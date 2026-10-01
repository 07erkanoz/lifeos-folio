import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'services/platform/editor_window.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/theme_controller.dart';
import 'ui/widgets/desktop_frame.dart';
import 'ui/widgets/file_preview.dart';
import 'ui/widgets/folio_about_dialog.dart';

/// A document on its own, only to be read, in a window of its own: a UYAP
/// document taken out beside the page being written, or onto a second
/// screen. Like LifeOS Editör it takes no lock and keeps no archive.
Future<void> runPreviewApp(List<String> arguments) async {
  final path = arguments.where(FileSystemEntity.isFileSync).firstOrNull;
  var chrome = false;
  WindowOptions? options;
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    try {
      await windowManager.ensureInitialized();
      chrome = Platform.isLinux || Platform.isWindows;
      options = WindowOptions(
        titleBarStyle: chrome ? TitleBarStyle.hidden : TitleBarStyle.normal,
        windowButtonVisibility: !chrome,
        size: const Size(860, 980),
        minimumSize: const Size(480, 420),
        center: true,
        title: path == null
            ? 'Folio önizleme'
            : '${p.basename(path)} — Folio önizleme',
      );
    } catch (_) {
      chrome = false;
      options = null;
    }
  }
  runApp(PreviewApp(path: path, desktopChrome: chrome));
  if (options != null) {
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}

class PreviewApp extends StatefulWidget {
  const PreviewApp({super.key, required this.path, this.desktopChrome = false});
  final String? path;
  final bool desktopChrome;

  @override
  State<PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<PreviewApp> {
  final _appearance = ThemeController();
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    unawaited(_appearance.load());
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    final name = path == null ? 'Folio önizleme' : p.basename(path);
    return ListenableBuilder(
      listenable: _appearance,
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigator,
        title: name,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _appearance.mode,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
        locale: const Locale('tr', 'TR'),
        builder: (context, child) => widget.desktopChrome
            ? DesktopFrame(
                title: name,
                titleIcon: Icons.visibility_outlined,
                onAbout: () {
                  final context = _navigator.currentState?.overlay?.context;
                  if (context != null) showFolioAbout(context);
                },
                child: child ?? const SizedBox.shrink(),
              )
            : child ?? const SizedBox.shrink(),
        home: Scaffold(
          body: path == null
              ? const Center(child: Text('Gösterilecek belge yok.'))
              : FilePreview(path: path),
        ),
      ),
    );
  }
}

/// [path] in a preview window of its own.
Future<void> openPreviewWindow(String path) async {
  if (!EditorWindow.available) return;
  await Process.start(Platform.resolvedExecutable, [
    previewFlag,
    path,
  ], mode: ProcessStartMode.detached);
}
