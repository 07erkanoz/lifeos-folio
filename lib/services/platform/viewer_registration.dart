import 'dart:io';
import 'dart:convert';

import 'atomic_file.dart';
import 'viewer_file_types.dart';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'app_directories.dart';

class ViewerRegistration {
  static const linuxApplicationId = 'com.erkanoz.evrak_convert';
  static const mimeTypes =
      'application/pdf;application/x-uyap-udf;application/udf;application/x-udf;application/vnd.openxmlformats-officedocument.wordprocessingml.document;application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;application/vnd.oasis.opendocument.text;text/plain;text/html;text/markdown;text/csv;text/tab-separated-values;application/json;application/xml;text/xml;image/png;image/jpeg;image/gif;image/webp;image/bmp;image/tiff;image/svg+xml;';
  // UYAP's Linux package registers application/udf. A competing higher-weight
  // glob hides UYAP from GNOME's Open With list even though it remains installed.
  static const udfMime = '''<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
<mime-type type="application/udf">
<comment>UYAP UDF belgesi</comment>
<glob pattern="*.udf"/>
<alias type="application/x-uyap-udf"/>
<alias type="application/x-udf"/>
</mime-type>
</mime-info>''';
  static String desktopEntry(String executable, String icon) =>
      '''[Desktop Entry]
Type=Application
Name=LifeOS Folio
Comment=Evrak arama, önizleme ve dönüştürme
Exec=${quoteExec(executable)} %F
Icon=$icon
Terminal=false
Categories=Office;Viewer;
StartupNotify=true
StartupWMClass=$linuxApplicationId
MimeType=$mimeTypes
''';

  /// Desktop Exec has its own escaping rules (not shell quoting).
  static String quoteExec(String value) =>
      '"${value.replaceAll('\\', '\\\\\\\\').replaceAll('"', '\\\\"').replaceAll('`', '\\\\`').replaceAll(r'$', r'\\$').replaceAll('%', '%%')}"';
  static Future<String>? _pending;

  static Future<String> register({required List<ViewerFileType> types}) {
    if (types.isEmpty ||
        types.any((t) => !ViewerFileType.supported.contains(t))) {
      return Future.error(
        ArgumentError('En az bir desteklenen dosya türü seçin.'),
      );
    }
    return _pending ??= _register(List.unmodifiable(types))
        .whenComplete(() => _pending = null);
  }

  static Future<ProcessResult> runCommand(
    String command,
    List<String> args,
  ) async {
    final process = await Process.start(command, args);
    final output = process.stdout.transform(utf8.decoder).join();
    final error = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw ProcessException(command, args, 'İşlem zaman aşımına uğradı.');
      },
    );
    return ProcessResult(process.pid, code, await output, await error);
  }

  static Future<String> _register(List<ViewerFileType> types) async {
    if (Platform.isLinux) {
      final base =
          Platform.environment['XDG_DATA_HOME'] ??
          p.join(Platform.environment['HOME']!, '.local', 'share');
      final asset = await rootBundle.load('assets/branding/lifeos_folio.png');
      return registerLinux(
        base: base,
        executable: Platform.resolvedExecutable,
        icon: asset.buffer.asUint8List(
          asset.offsetInBytes,
          asset.lengthInBytes,
        ),
        types: types,
      );
    }
    if (Platform.isWindows) {
      final directory = await folioSupportDirectory();
      await directory.create(recursive: true);
      final script = File(p.join(directory.path, 'register-viewer.ps1'));
      await script.writeAsString(
        '\uFEFF${await rootBundle.loadString('packaging/windows/register-viewer.ps1')}',
      );
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
        '-Executable',
        Platform.resolvedExecutable,
        '-SelectedExtensions',
        types.expand((t) => t.extensions).join(','),
      ]);
      if (result.exitCode != 0) {
        throw StateError('Uygulama kaydedilemedi: ${result.stderr}');
      }
      await Process.start('explorer.exe', ['ms-settings:defaultapps']);
      return 'Seçilen türler: ${types.map((t) => t.extensions.map((e) => ".$e").join(", ")).join(", ")}. Windows ayarlarında LifeOS Folio’yu seçip bu türleri onaylayın. Son seçimi Windows ekranında yaparsınız.';
    }
    if (Platform.isAndroid) {
      return configureAndroidDefaultViewer();
    }
    return 'Bu platformda varsayılan önizleyici kaydı desteklenmiyor.';
  }

  static Future<String> configureAndroidDefaultViewer() async =>
      await const MethodChannel('lifeos_evrak/documents')
          .invokeMethod<String>('configureDefaultViewer') ??
      'Belge seçimi iptal edildi; varsayılan değiştirilmedi.';

  /// The injectable data root and process runner keep tests away from the live desktop.
  static Future<String> registerLinux({
    required String base,
    required String executable,
    required List<int> icon,
    required List<ViewerFileType> types,
    Future<ProcessResult> Function(String, List<String>) run = runCommand,
  }) async {
    final applications = p.join(base, 'applications');
    // Publish dependencies first; publish the complete desktop entry last.
    await replaceFileIfChanged(
      File(
        p.join(
          base,
          'icons',
          'hicolor',
          '256x256',
          'apps',
          '$linuxApplicationId.png',
        ),
      ),
      icon,
    );
    final mimeChanged = await replaceFileIfChanged(
      File(p.join(base, 'mime', 'packages', 'lifeos-evrakci.xml')),
      utf8.encode(udfMime),
    );
    if (mimeChanged) {
      final result = await run('update-mime-database', [p.join(base, 'mime')]);
      if (result.exitCode != 0) {
        throw StateError('UDF dosya türü kaydedilemedi: ${result.stderr}');
      }
    }
    final entryChanged = await replaceFileIfChanged(
      File(p.join(applications, '$linuxApplicationId.desktop')),
      utf8.encode(desktopEntry(executable, linuxApplicationId)),
    );
    if (entryChanged) {
      final result = await run('update-desktop-database', [applications]);
      if (result.exitCode != 0) {
        throw StateError('Uygulama kaydı güncellenemedi: ${result.stderr}');
      }
    }
    // GNOME observes complete files itself. Do not force a shared icon cache reload.
    final failed = <String>[];
    for (final mime in types.expand((t) => t.mimeTypes).toSet()) {
      final current = await run('xdg-mime', ['query', 'default', mime]);
      if (current.exitCode == 0 &&
          current.stdout.toString().trim() == '$linuxApplicationId.desktop') {
        continue;
      }
      final result = await run('xdg-mime', [
        'default',
        '$linuxApplicationId.desktop',
        mime,
      ]);
      final check = await run('xdg-mime', ['query', 'default', mime]);
      if (result.exitCode != 0 ||
          check.exitCode != 0 ||
          check.stdout.toString().trim() != '$linuxApplicationId.desktop') {
        failed.add(mime);
      }
    }
    if (failed.isNotEmpty) {
      throw StateError(
        'Bazı türler atanamadı: ${failed.join(', ')}. Diğer türler için işlem tamamlanmış olabilir.',
      );
    }
    return 'LifeOS Folio şu türler için varsayılan oldu: ${types.expand((t) => t.extensions).map((e) => ".$e").join(", ")}. Belgeler doğrudan geniş önizlemede açılır.';
  }
}
