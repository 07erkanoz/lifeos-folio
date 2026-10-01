import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';

/// One file of a model. On lifeos.com.tr it is kept gzipped, as
/// `[name].gz` of [packed] bytes: smaller to fetch, and of a kind Cloudflare
/// keeps in its cache, so that it is Cloudflare that hands it out rather
/// than the server. [size] and [sha256] are the file's as it is used.
class SpeechFile {
  const SpeechFile(this.name, this.size, this.sha256, this.packed);
  final String name;
  final int size;
  final String sha256;
  final int packed;
}

/// A voice model Folio fetches the first time it is used rather than
/// carrying in every copy of itself: hundreds of megabytes that most people
/// never need. The files are served from Folio's own site, pinned here by
/// size and SHA-256, so what arrives is exactly what was put there.
class SpeechModel {
  const SpeechModel({
    required this.folder,
    required this.title,
    required this.need,
    required this.offline,
    required this.license,
    required this.files,
    this.replaces = const [],
  });

  /// The folder on the server and on disk. A new version is a new folder,
  /// never a changed file in the old one.
  final String folder;
  final String title;

  /// What the download question says: what is needed, and that the work
  /// is done on the computer.
  final String need, offline;
  final String license;
  final List<SpeechFile> files;

  /// Folders of earlier models for the same work, taken off the disk once
  /// this one has arrived.
  final List<String> replaces;

  /// What is fetched: the gzipped files.
  int get size => files.fold(0, (sum, f) => sum + f.packed);

  /// Supertonic 3, the Turkish voice read out with.
  static const reading = SpeechModel(
    folder: 'okuma-supertonic3-1',
    title: 'Sesli okuma',
    need: 'Sesli okuma için ses modelinin indirilmesi gerekiyor',
    offline:
        'Okuma internet bağlantısı olmadan yapılır; belgeleriniz '
        'bilgisayarınızdan çıkmaz.',
    license: 'Supertonic 3 · Supertone · OpenRAIL-M',
    files: [
      SpeechFile(
        'duration_predictor.int8.onnx',
        3700147,
        'c3eb91414d5ff8a7a239b7fe9e34e7e2bf8a8140d8375ffb14718b1c639325db',
        3224716,
      ),
      SpeechFile(
        'text_encoder.int8.onnx',
        36416150,
        'c7befd5ea8c3119769e8a6c1486c4edc6a3bc8365c67621c881bbb774b9902ff',
        33536047,
      ),
      SpeechFile(
        'vector_estimator.int8.onnx',
        78400833,
        '20cd86fa5c6effedfda0e7cffe5b0569ca401c440a0c3a1d72bf39286c0db3fd',
        66639512,
      ),
      SpeechFile(
        'vocoder.int8.onnx',
        25991073,
        'e923d60f53f95eb1ce235f1dc33ec56d9c057823c96fa6f8acf98f32b0da6152',
        19971443,
      ),
      SpeechFile(
        'tts.json',
        8253,
        '42078d3aef1cd43ab43021f3c54f47d2d75ceb4e75f627f118890128b06a0d09',
        1124,
      ),
      SpeechFile(
        'unicode_indexer.bin',
        262144,
        '8402ca48e5189a8950138580b0fff64db6f072f24ac07cd54ba8b2fbb9883b30',
        21104,
      ),
      SpeechFile(
        'voice.bin',
        517168,
        '67d5209b0ee8ce6c74105ffbe12fe6a7628aea3b4ba2fcb308a4a67938a93ce8',
        485303,
      ),
      SpeechFile(
        'LICENSE',
        15007,
        '0d944a9110fed9a9602d60e0423a272903e7bd21ab060490774efc77c2275e9f',
        5695,
      ),
    ],
  );

  /// Whisper large-v3 turbo, which writes down what is said, and Silero,
  /// which hears where speech starts and stops. Turbo, not small: on a
  /// lawyer's own dictation small got one word in four wrong, turbo one in
  /// seventeen.
  static const dictation = SpeechModel(
    folder: 'yazma-whisper-turbo-1',
    title: 'Sesli yazma',
    need: 'Sesli yazma için konuşma tanıma modelinin indirilmesi gerekiyor',
    offline:
        'Yazıya dökme internet bağlantısı olmadan yapılır; sesiniz ve '
        'belgeleriniz bilgisayarınızdan çıkmaz.',
    license: 'Whisper large-v3 turbo · OpenAI · MIT; Silero VAD · MIT',
    replaces: ['yazma-whisper-small-1'],
    files: [
      SpeechFile(
        'turbo-encoder.int8.onnx',
        674716297,
        'b02dcdf54f348741e93fe732b67d933c8dcb6735655f710640143081db38878b',
        391675088,
      ),
      SpeechFile(
        'turbo-decoder.int8.onnx',
        361080764,
        '20accd02388482eb3a46bd615631adfdc85e1eb2c7db9ea3f02a40ffe6b81547',
        215824316,
      ),
      SpeechFile(
        'turbo-tokens.txt',
        816730,
        'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
        370469,
      ),
      SpeechFile(
        'silero_vad.onnx',
        643854,
        '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
        508030,
      ),
      SpeechFile(
        'LICENSE',
        1063,
        'b5d65a59060e68c4ff940e1eddfa6f94b2d68fdf58ed7f4dd57721c997e35e9d',
        642,
      ),
    ],
  );
}

/// Asked to stop a download; the part already fetched stays, and the next
/// attempt goes on from it.
class DownloadCancel {
  bool _cancelled = false;
  HttpClient? _client;
  bool get cancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

/// Where the models are kept, and how they get there.
class SpeechModelStore {
  SpeechModelStore({
    Future<Directory> Function()? root,
    Uri? server,
    HttpClient Function()? client,
  }) : _root = root ?? _defaultRoot,
       _server = server ?? Uri.parse('https://lifeos.com.tr/ses/'),
       _client = client ?? HttpClient.new;

  static SpeechModelStore instance = SpeechModelStore();

  final Future<Directory> Function() _root;
  final Uri _server;
  final HttpClient Function() _client;

  static Future<Directory> _defaultRoot() async =>
      Directory(p.join((await folioSharedDirectory()).path, 'ses'));

  static const _done = '.tamam';

  Future<Directory> directoryOf(SpeechModel model) async =>
      Directory(p.join((await _root()).path, model.folder));

  /// The folder [model] is in, once the whole of it has arrived; null
  /// before. Checked by size: the hash was checked as each file came.
  Future<String?> installed(SpeechModel model) async {
    final dir = await directoryOf(model);
    if (!await File(p.join(dir.path, _done)).exists()) return null;
    for (final f in model.files) {
      final file = File(p.join(dir.path, f.name));
      if (!await file.exists() || await file.length() != f.size) return null;
    }
    return dir.path;
  }

  /// Fetches whatever of [model] is not here yet, telling [progress] the
  /// bytes in hand out of the whole. A file that does not hash to what it
  /// should is thrown away and the download fails; a part left by an
  /// interrupted one is carried on from where it stopped.
  Future<String> download(
    SpeechModel model, {
    void Function(int received, int total)? progress,
    DownloadCancel? cancel,
  }) async {
    final dir = await directoryOf(model);
    await dir.create(recursive: true);
    var before = 0;
    for (final f in model.files) {
      final file = File(p.join(dir.path, f.name));
      if (!(await file.exists() && await file.length() == f.size)) {
        await _fetch(
          model,
          f,
          file,
          (n) => progress?.call(before + n, model.size),
          cancel,
        );
      }
      before += f.packed;
      progress?.call(before, model.size);
    }
    await File(p.join(dir.path, _done)).writeAsString(model.folder);
    for (final old in model.replaces) {
      final earlier = Directory(p.join((await _root()).path, old));
      if (await earlier.exists()) await earlier.delete(recursive: true);
    }
    return dir.path;
  }

  Future<void> _fetch(
    SpeechModel model,
    SpeechFile f,
    File target,
    void Function(int) progress,
    DownloadCancel? cancel,
  ) async {
    // The gzipped file is fetched whole first, so that an interrupted
    // download can go on from where it stopped, and only then opened.
    final packed = File('${target.path}.gz.part');
    var have = await packed.exists() ? await packed.length() : 0;
    if (have > f.packed) {
      await packed.delete();
      have = 0;
    }
    if (cancel?.cancelled ?? false) throw const DownloadCancelled();
    final client = _client()
      ..connectionTimeout = const Duration(seconds: 15)
      // What arrives is opened here, never on the way.
      ..autoUncompress = false;
    cancel?._client = client;
    try {
      if (have < f.packed) {
        final request = await client.getUrl(
          _server.resolve('${model.folder}/${f.name}.gz'),
        );
        if (have > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
        }
        final response = await request.close();
        final resumed = response.statusCode == HttpStatus.partialContent;
        if (response.statusCode != HttpStatus.ok && !resumed) {
          await response.drain<void>();
          throw HttpException('Sunucu ${response.statusCode} döndü: ${f.name}');
        }
        // A server that ignores the range sends the whole file again.
        if (!resumed) have = 0;
        final sink = packed.openWrite(
          mode: resumed ? FileMode.append : FileMode.write,
        );
        try {
          await for (final chunk in response) {
            sink.add(chunk);
            have += chunk.length;
            progress(have);
          }
        } finally {
          await sink.close();
        }
      }
      if (cancel?.cancelled ?? false) throw const DownloadCancelled();
      if (await packed.length() != f.packed) {
        throw HttpException('${f.name} eksik indi.');
      }
      final part = File('${target.path}.part');
      try {
        await packed.openRead().transform(gzip.decoder).pipe(part.openWrite());
      } on FormatException {
        await packed.delete();
        throw HttpException('${f.name} bozuk indi; yeniden deneyin.');
      }
      final digest = await sha256.bind(part.openRead()).first;
      if (await part.length() != f.size || digest.toString() != f.sha256) {
        await part.delete();
        await packed.delete();
        throw HttpException('${f.name} bozuk indi; yeniden deneyin.');
      }
      await part.rename(target.path);
      await packed.delete();
    } on SocketException {
      if (cancel?.cancelled ?? false) throw const DownloadCancelled();
      rethrow;
    } on HttpException {
      if (cancel?.cancelled ?? false) throw const DownloadCancelled();
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Takes [model] off the disk.
  Future<void> remove(SpeechModel model) async {
    final dir = await directoryOf(model);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
