import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/platform/atomic_file.dart';
import 'package:evrak_convert/services/platform/viewer_file_types.dart';
import 'package:evrak_convert/services/platform/viewer_registration.dart';
import 'package:evrak_convert/ui/widgets/default_viewer_dialog.dart';

void main() {
  test('Linux MIME registration keeps UYAP available in Open With', () async {
    for (final tool in [
      'update-mime-database',
      'update-desktop-database',
      'gio',
    ]) {
      if ((await Process.run('which', [tool])).exitCode != 0) {
        markTestSkipped('$tool is required for the Linux integration check');
        return;
      }
    }
    final root = await Directory.systemTemp.createTemp('folio-uyap-mime-');
    addTearDown(() => root.delete(recursive: true));
    for (final dir in [
      'data/mime/packages',
      'data/applications',
      'config',
      'system',
    ]) {
      await Directory('${root.path}/$dir').create(recursive: true);
    }
    final environment = {
      'XDG_DATA_HOME': '${root.path}/data',
      'XDG_DATA_DIRS': '${root.path}/system',
      'XDG_CONFIG_HOME': '${root.path}/config',
      'XDG_CONFIG_DIRS': '${root.path}/system',
      'LC_ALL': 'C',
    };
    Future<String> run(String command, List<String> args) async {
      final result = await Process.run(command, args, environment: environment);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return result.stdout.toString();
    }

    const uyapEntry =
        '[Desktop Entry]\nType=Application\nName=UYAP\n'
        'Exec=/bin/cat %f\nMimeType=application/udf;\n';
    final uyap = File('${root.path}/data/applications/uyap.desktop');
    await uyap.writeAsString(uyapEntry);
    await File('${root.path}/data/applications/folio.desktop')
        .writeAsString(ViewerRegistration.desktopEntry('/bin/true', 'folio'));
    const defaults = '[Default Applications]\napplication/udf=uyap.desktop\n';
    final preferences = File('${root.path}/config/mimeapps.list');
    await preferences.writeAsString(defaults);
    await run('update-desktop-database', ['${root.path}/data/applications']);
    final mimeFile = File('${root.path}/data/mime/packages/lifeos-evrakci.xml');
    await mimeFile.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
<mime-type type="application/x-uyap-udf"><glob pattern="*.udf" weight="80"/></mime-type>
</mime-info>''');
    await run('update-mime-database', ['${root.path}/data/mime']);
    expect(
      await run('gio', ['mime', 'application/x-uyap-udf']),
      isNot(contains('uyap.desktop')),
    );

    await replaceFileIfChanged(
      mimeFile,
      utf8.encode(ViewerRegistration.udfMime),
    );
    await run('update-mime-database', ['${root.path}/data/mime']);
    final document = File('${root.path}/sample.udf');
    await document.writeAsString('sample');
    expect(
      await run('gio', ['info', '-a', 'standard::content-type', document.path]),
      contains('standard::content-type: application/udf'),
    );
    for (final type in [
      'application/udf',
      'application/x-uyap-udf',
      'application/x-udf',
    ]) {
      final apps = await run('gio', ['mime', type]);
      expect(apps, contains('uyap.desktop'));
      expect(apps, contains('folio.desktop'));
    }
    expect(
      await run('gio', ['mime', 'application/udf']),
      contains('Default application for “application/udf”: uyap.desktop'),
    );
    expect(await preferences.readAsString(), defaults);
    expect(await uyap.readAsString(), uyapEntry);
  }, skip: !Platform.isLinux);

  test('registration is idempotent and changes only selected defaults', () async {
    final root = await Directory.systemTemp.createTemp('folio-register-');
    addTearDown(() => root.delete(recursive: true));
    final commands = <String>[];
    final defaults = {
      'application/pdf': 'other-reader.desktop',
      'image/png': 'image-viewer.desktop',
    };
    Future<ProcessResult> run(String executable, List<String> args) async {
      commands.add('$executable ${args.join(' ')}');
      if (executable == 'xdg-mime') {
        if (args.first == 'default') defaults[args.last] = args[1];
        return ProcessResult(
          1,
          0,
          args.first == 'query' ? defaults[args.last] ?? '' : '',
          '',
        );
      }
      return ProcessResult(1, 0, '', '');
    }

    Future<void> register() => ViewerRegistration.registerLinux(
      base: root.path,
      executable: '/opt/Folio App/evrak_convert',
      icon: [1, 2, 3],
      types: [ViewerFileType.supported.first],
      run: run,
    );
    await register();
    final desktop = File(
      '${root.path}/applications/${ViewerRegistration.linuxApplicationId}.desktop',
    );
    final before = await desktop.stat();
    expect(
      await desktop.readAsString(),
      contains('Exec="/opt/Folio App/evrak_convert" %F'),
    );
    expect(defaults['application/pdf'], 'other-reader.desktop');
    expect(defaults['image/png'], 'image-viewer.desktop');
    expect(
      defaults['application/x-uyap-udf'],
      '${ViewerRegistration.linuxApplicationId}.desktop',
    );
    expect(commands.any((c) => c.startsWith('gtk-update-icon-cache')), isFalse);
    commands.clear();
    await register();
    expect((await desktop.stat()).modified, before.modified);
    expect(
      commands.every((c) => c.startsWith('xdg-mime query default ')),
      isTrue,
    );
  });

  test(
    'atomic replacement never truncates the published desktop entry',
    () async {
      final root = await Directory.systemTemp.createTemp('folio-atomic-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/folio.desktop');
      final original = utf8.encode('[Desktop Entry]\nName=Old\n');
      final replacement = utf8.encode('[Desktop Entry]\nName=LifeOS Folio\n');
      await file.writeAsBytes(original);
      final events = <FileSystemEvent>[];
      final watch = root.watch().listen(events.add);
      expect(await replaceFileIfChanged(file, replacement), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await watch.cancel();
      expect(await file.readAsBytes(), replacement);
      // No open/truncate/write operation happened on the published path.
      expect(
        events.whereType<FileSystemModifyEvent>().where(
          (e) => e.path == file.path,
        ),
        isEmpty,
      );
      expect(await root.list().length, 1);
      expect(await replaceFileIfChanged(file, replacement), isFalse);
    },
    skip: !Platform.isLinux,
  );

  testWidgets('file type choices reach registration once while busy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final result = Completer<String>();
    var calls = 0;
    List<ViewerFileType>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DefaultViewerDialog(
            register: (types) {
              calls++;
              selected = types;
              return result.future;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('PDF · .pdf'));
    await tester.pump();
    // Found by its role, not its wording: the label names the integration the
    // running system offers, so it follows Platform rather than the platform
    // this test declares, and reads differently on each host. What is being
    // checked here is that one tap registers once, whatever it is called.
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(calls, 1);
    expect(selected!.map((t) => t.label), ['UYAP UDF', 'PDF']);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    result.complete('İşlem tamamlandı');
    await tester.pumpAndSettle();
    expect(find.text('İşlem tamamlandı'), findsOneWidget);
  }, variant: TargetPlatformVariant({TargetPlatform.linux}));
}
