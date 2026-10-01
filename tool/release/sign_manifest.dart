// Writes the signed update manifest for one platform's package, the file
// Folio reads from https://lifeos.com.tr/surum/stable/<platform>.json.
//
//   UPDATE_SIGNING_KEY=<base64 seed> dart run tool/release/sign_manifest.dart \
//     --platform linux-x64 --file build/LifeOS-Folio-1.2.0-linux-x64.tar.gz \
//     --notes-tr "..." --notes-en "..." > linux-x64.json
//
// Version and build come from pubspec.yaml; the file's SHA-256 and size are
// measured here, and the download address is lifeos.com.tr/downloads/ plus
// the file's name. The manifest is checked against Folio's public key before
// it is written, so a wrong key fails here rather than on every reader's
// machine.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:evrak_convert/services/update/update_manifest.dart';

Future<void> main(List<String> args) async {
  String option(String name) {
    final at = args.indexOf('--$name');
    if (at < 0 || at + 1 >= args.length) {
      stderr.writeln('--$name gerekli.');
      exit(64);
    }
    return args[at + 1];
  }

  final seedText = Platform.environment['UPDATE_SIGNING_KEY'];
  if (seedText == null || seedText.trim().isEmpty) {
    stderr.writeln('UPDATE_SIGNING_KEY tanımlı değil.');
    exit(64);
  }
  final platform = option('platform');
  if (!UpdateManifest.platforms.contains(platform)) {
    stderr.writeln('Bilinmeyen platform: $platform');
    exit(64);
  }
  final file = File(option('file'));
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final version = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (version == null) {
    stderr.writeln('pubspec.yaml sürümü okunamadı.');
    exit(65);
  }
  final bytes = file.readAsBytesSync();
  final name = file.uri.pathSegments.last;
  final body = <String, dynamic>{
    'schema': UpdateManifest.schema,
    'product': 'folio',
    'channel': UpdateManifest.channel,
    'platform': platform,
    'version': version.group(1),
    'build': int.parse(version.group(2)!),
    'url': 'https://lifeos.com.tr/downloads/${Uri.encodeComponent(name)}',
    'sha256': sha256.convert(bytes).toString(),
    'size': bytes.length,
    'notes': {'tr': option('notes-tr'), 'en': option('notes-en')},
    'published': DateTime.now().toUtc().toIso8601String(),
  };
  final signed = await UpdateManifest.sign(
    body,
    base64Decode(seedText.trim()),
  );
  final text = const JsonEncoder.withIndent('  ').convert(signed);
  // The same check every copy of Folio will make.
  await UpdateManifest.verify(text, platform: platform);
  stdout.writeln(text);
}
