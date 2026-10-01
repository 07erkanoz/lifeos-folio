import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../platform/app_directories.dart';
import '../platform/atomic_file.dart';

/// One index owner per user. Subsequent file launches are forwarded over a
/// loopback-only socket authenticated with a per-run random token.
class DesktopInstance {
  final RandomAccessFile _lock;
  final ServerSocket _server;
  final String _token;
  final _requests = StreamController<List<String>>();
  Stream<List<String>> get requests => _requests.stream;
  DesktopInstance._(this._lock, this._server, this._token) {
    _server.listen((socket) async {
      try {
        var bytes = 0;
        final line = await socket
            .timeout(const Duration(seconds: 3))
            .map((chunk) {
              bytes += chunk.length;
              if (bytes > 65536) {
                throw const FormatException('İstek çok büyük.');
              }
              return chunk;
            })
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first;
        final request = jsonDecode(line) as Map;
        if (request['token'] != _token) return;
        final args = (request['arguments'] as List).cast<String>();
        if (!_requests.isClosed) _requests.add(args);
        socket.write('ok\n');
        await socket.flush();
      } catch (_) {
        /* Ignore stale or unrelated local clients. */
      } finally {
        socket.destroy();
      }
    });
  }
  static Future<DesktopInstance?> acquire(
    List<String> arguments, {
    Directory? directory,
  }) async {
    final dir = directory ?? await folioSupportDirectory();
    await dir.create(recursive: true);
    final lock = await File('${dir.path}/desktop.lock')
        .open(mode: FileMode.append);
    final info = File('${dir.path}/desktop-instance.json');
    try {
      await lock.lock(FileLock.exclusive);
    } on FileSystemException {
      await lock.close();
      // Owner may still be starting. Retry only transport, never document work.
      for (var attempt = 0; attempt < 20; attempt++) {
        try {
          final data = jsonDecode(await info.readAsString()) as Map;
          final socket = await Socket.connect(
            InternetAddress.loopbackIPv4,
            data['port'] as int,
            timeout: const Duration(seconds: 1),
          );
          try {
            socket.write(
              '${jsonEncode({'token': data['token'], 'arguments': arguments})}\n',
            );
            await socket.flush();
            final reply = await socket
                .cast<List<int>>()
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .first
                .timeout(const Duration(seconds: 2));
            if (reply == 'ok') return null;
          } finally {
            socket.destroy();
          }
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw StateError(
        'LifeOS Folio arka planda çalışıyor ancak yanıt vermiyor.',
      );
    }
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final token = List.generate(
        32,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await replaceFileIfChanged(
        info,
        utf8.encode(jsonEncode({'port': server.port, 'token': token})),
      );
      if (!Platform.isWindows) await Process.run('chmod', ['600', info.path]);
      return DesktopInstance._(lock, server, token);
    } catch (_) {
      await lock.close();
      rethrow;
    }
  }

  Future<void> close() async {
    await _server.close();
    await _requests.close();
    await _lock.unlock();
    await _lock.close();
  }
}
