import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/speech/speech_models.dart';

/// The voice models come from Folio's own site, once, and only as they
/// were put there.
void main() {
  late HttpServer server;
  late Directory root;
  final served = <String, List<int>>{};
  final ranges = <String?>[];
  var breakAfter = -1;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('folio-ses-');
    served.clear();
    ranges.clear();
    breakAfter = -1;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = served[request.uri.path];
      final response = request.response;
      if (body == null) {
        response.statusCode = 404;
        await response.close();
        return;
      }
      final range = request.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      var from = 0;
      if (range != null) {
        from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!);
        response.statusCode = HttpStatus.partialContent;
      }
      final rest = body.sublist(from);
      response.contentLength = rest.length;
      if (breakAfter >= 0) {
        // The connection drops part of the way through.
        final socket = await response.detachSocket();
        socket.add(rest.sublist(0, breakAfter));
        await socket.flush();
        socket.destroy();
        return;
      }
      response.add(rest);
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await root.delete(recursive: true);
  });

  /// A model of [files], each served gzipped as the site serves them.
  SpeechModel model(
    Map<String, List<int>> files, {
    String? wrongHash,
    List<String> replaces = const [],
  }) {
    for (final e in files.entries) {
      served['/ses/deneme-1/${e.key}.gz'] = gzip.encode(e.value);
    }
    return SpeechModel(
      folder: 'deneme-1',
      title: 'Deneme',
      need: 'Deneme gerekiyor',
      offline: 'Çevrimdışı.',
      license: 'MIT',
      replaces: replaces,
      files: [
        for (final e in files.entries)
          SpeechFile(
            e.key,
            e.value.length,
            e.key == wrongHash ? '0' * 64 : sha256.convert(e.value).toString(),
            served['/ses/deneme-1/${e.key}.gz']!.length,
          ),
      ],
    );
  }

  /// Bytes gzip cannot shrink, so that a download has a middle to break in.
  List<int> noise(int length) {
    final random = Random(7);
    return List.generate(length, (_) => random.nextInt(256));
  }

  SpeechModelStore store() => SpeechModelStore(
    root: () async => root,
    server: Uri.parse('http://${server.address.host}:${server.port}/ses/'),
  );

  test(
    'a model is fetched once, whole, and then found where it was put',
    () async {
      final m = model({
        'a.onnx': List.generate(5000, (i) => i % 251),
        'b.txt': 'merhaba'.codeUnits,
      });
      expect(await store().installed(m), isNull);
      final seen = <int>[];
      final path = await store().download(
        m,
        progress: (received, total) {
          expect(total, m.size);
          seen.add(received);
        },
      );
      // What is counted is what is fetched: the gzipped files.
      expect(m.size, lessThan(5007));
      expect(seen.last, m.size);
      expect(
        File('$path/a.onnx').readAsBytesSync(),
        List.generate(5000, (i) => i % 251),
      );
      expect(
        Directory(path)
            .listSync()
            .map((e) => e.path)
            .where((p) => p.endsWith('.part') || p.endsWith('.gz')),
        isEmpty,
      );
      expect(await store().installed(m), path);
      expect(File('$path/b.txt').readAsStringSync(), 'merhaba');
      // Nothing is fetched a second time.
      ranges.clear();
      await store().download(m);
      expect(ranges, isEmpty);
    },
  );

  test('an interrupted file is carried on from where it stopped', () async {
    final body = noise(4000);
    final m = model({'a.onnx': body});
    breakAfter = 1500;
    await expectLater(store().download(m), throwsA(anything));
    expect(await store().installed(m), isNull);
    breakAfter = -1;
    await store().download(m);
    expect(ranges.last, 'bytes=1500-');
    expect(await store().installed(m), isNotNull);
    expect(File('${root.path}/deneme-1/a.onnx').readAsBytesSync(), body);
  });

  test('a file that does not hash to what it should is thrown away', () async {
    final m = model({
      'a.onnx': [1, 2, 3],
    }, wrongHash: 'a.onnx');
    await expectLater(store().download(m), throwsA(isA<HttpException>()));
    expect(await store().installed(m), isNull);
    expect(File('${root.path}/deneme-1/a.onnx').existsSync(), isFalse);
    expect(File('${root.path}/deneme-1/a.onnx.part').existsSync(), isFalse);
  });

  test('an earlier model for the same work is taken off the disk once the '
      'new one has arrived', () async {
    final earlier = Directory('${root.path}/eski-1')..createSync();
    File('${earlier.path}/model.onnx').writeAsStringSync('eski');
    final m = model({'a.onnx': noise(100)}, replaces: ['eski-1']);
    await store().download(m);
    expect(earlier.existsSync(), isFalse);
  });

  test('a download can be stopped', () async {
    final m = model({'a.onnx': List.filled(1000, 1)});
    final cancel = DownloadCancel()..cancel();
    await expectLater(
      store().download(m, cancel: cancel),
      throwsA(isA<DownloadCancelled>()),
    );
  });

  test('the models Folio uses add up to what the question says', () {
    expect(SpeechModel.reading.size, closeTo(124e6, 1e6));
    expect(SpeechModel.dictation.size, closeTo(608e6, 1e6));
  });
}
