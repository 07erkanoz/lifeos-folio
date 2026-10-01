import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// What a release says about itself: which build it is, where its file is
/// and what that file's SHA-256 is. Published per platform at
/// [UpdateManifest.addressFor] and signed with Folio's Ed25519 key, whose
/// public half is [publicKey]. A manifest that does not verify, or that
/// names anything but a file on lifeos.com.tr, is ignored.
class UpdateManifest {
  const UpdateManifest({
    required this.platform,
    required this.version,
    required this.build,
    required this.url,
    required this.sha256,
    required this.size,
    required this.notes,
    required this.published,
  });

  final String platform;

  /// What a person reads, "1.2.0".
  final String version;

  /// What decides whether it is newer: pubspec's `+N`, raised every release.
  final int build;
  final Uri url;
  final String sha256;
  final int size;

  /// Release notes by language code, "tr" and "en".
  final Map<String, String> notes;
  final DateTime published;

  static const schema = 1;
  static const channel = 'stable';
  static const platforms = {'windows-x64', 'linux-x64', 'android'};

  /// Folio's update-signing public key. The private half is only in the
  /// release workflow's secrets and in the owner's backup.
  static final publicKey = base64Decode(
    'uo8uTbTSKeMNBtitM6hL25KFShLiMnlZKA6gbTPcxgY=',
  );

  static const _host = 'lifeos.com.tr';
  static const _downloads = '/downloads/';

  static Uri addressFor(String platform) =>
      Uri.https(_host, '/surum/$channel/$platform.json');

  /// JSON with keys sorted at every level and no spaces: the bytes the
  /// signature covers, the same whoever writes them.
  static String canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k as String).toList()..sort();
      return '{${[for (final k in keys) '${jsonEncode(k)}:${canonical(value[k])}'].join(',')}}';
    }
    if (value is List) return '[${value.map(canonical).join(',')}]';
    return jsonEncode(value);
  }

  /// The manifest in [text] for [platform], or a [FormatException] saying
  /// why it was refused. The signature is checked before anything in it is
  /// believed.
  static Future<UpdateManifest> verify(
    String text, {
    required String platform,
    List<int>? key,
  }) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Sürüm bilgisi okunamadı.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Sürüm bilgisi okunamadı.');
    }
    final signature = decoded['signature'];
    if (signature is! String || !signature.startsWith('ed25519:')) {
      throw const FormatException('Sürüm bilgisi imzasız.');
    }
    final body = Map<String, dynamic>.of(decoded)..remove('signature');
    final List<int> bytes;
    try {
      bytes = base64Decode(signature.substring('ed25519:'.length));
    } on FormatException {
      throw const FormatException('Sürüm bilgisinin imzası bozuk.');
    }
    final good = await Ed25519().verify(
      utf8.encode(canonical(body)),
      signature: Signature(
        bytes,
        publicKey: SimplePublicKey(key ?? publicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!good) {
      throw const FormatException('Sürüm bilgisinin kaynağı doğrulanamadı.');
    }

    T field<T>(String name) {
      final value = body[name];
      if (value is! T) {
        throw FormatException('Sürüm bilgisinde "$name" eksik ya da hatalı.');
      }
      return value;
    }

    if (field<int>('schema') != schema ||
        field<String>('product') != 'folio' ||
        field<String>('channel') != channel ||
        field<String>('platform') != platform) {
      throw const FormatException('Sürüm bilgisi bu kurulum için değil.');
    }
    final url = Uri.tryParse(field<String>('url'));
    if (url == null ||
        url.scheme != 'https' ||
        url.host != _host ||
        !url.path.startsWith(_downloads)) {
      throw const FormatException(
        'Sürüm bilgisi tanınmayan bir adres veriyor.',
      );
    }
    final sha256 = field<String>('sha256');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw const FormatException('Sürüm bilgisindeki dosya özeti hatalı.');
    }
    final build = field<int>('build');
    final size = field<int>('size');
    final published = DateTime.tryParse(field<String>('published'));
    if (build < 1 || size < 1 || published == null) {
      throw const FormatException('Sürüm bilgisi eksik.');
    }
    final notes = field<Map<String, dynamic>>('notes');
    return UpdateManifest(
      platform: platform,
      version: field<String>('version'),
      build: build,
      url: url,
      sha256: sha256,
      size: size,
      notes: {
        for (final e in notes.entries)
          if (e.value is String) e.key: e.value as String,
      },
      published: published,
    );
  }

  /// [body] with its Ed25519 signature added, by the key whose 32-byte
  /// seed is [seed]. What the release tool publishes.
  static Future<Map<String, dynamic>> sign(
    Map<String, dynamic> body,
    List<int> seed,
  ) async {
    final pair = await Ed25519().newKeyPairFromSeed(seed);
    final signature = await Ed25519().sign(
      utf8.encode(canonical(body)),
      keyPair: pair,
    );
    return {...body, 'signature': 'ed25519:${base64Encode(signature.bytes)}'};
  }
}
