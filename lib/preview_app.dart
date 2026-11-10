import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/platform/app_language.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'models/evrak_file.dart';
import 'services/convert/converter_service.dart';
import 'services/desktop/screen_fit.dart';
import 'services/pdf/pdf_service.dart';
import 'services/pdf/pdf_tools.dart';
import 'services/platform/app_edition.dart';
import 'services/platform/file_actions.dart';
import 'services/tiff/tiff_service.dart';
import 'ui/widgets/notice.dart';
import 'ui/widgets/pdf_tools_dialogs.dart';
import 'ui/widgets/print_screen.dart';
import 'ui/widgets/viewer_bar.dart';
import 'services/platform/editor_window.dart';
import 'services/preview/pdf_fonts.dart';
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
      // A Mac too, its traffic lights kept (lib/main.dart).
      chrome = true;
      options = WindowOptions(
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: Platform.isMacOS,
        // As tall as the screen lets it be: a page is read whole.
        size: await fitToPrimaryScreen(const Size(900, 1100)),
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
  // The fonts unembedded papers name, before the document is drawn.
  unawaited(preloadPdfFonts());
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
          AppLocalizations.delegate,
        ],
        // Ofis's language (the system's or the one chosen); Turkish in
        // Folio.
        supportedLocales: AppLanguage.supported,
        locale: AppLanguage.instance.locale,
        localeResolutionCallback: AppLanguage.resolve,
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
              : Stack(
                  children: [
                    Positioned.fill(child: FilePreview(path: path)),
                    // At the right end of the viewer's row of tools.
                    Positioned(
                      top: (ViewerToolbar.height - 36) / 2,
                      right: 8,
                      child: PreviewFileMenu(path: path),
                    ),
                  ],
                ),
          // Opened from the file manager to be read; written in Folio itself
          // with one press, as the file manager's "Folio ile düzenle" does.
          floatingActionButton: path != null && _editable(path)
              // Above the viewer's status line, not over it.
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: FloatingActionButton.extended(
                    key: const ValueKey('preview-window-edit'),
                    onPressed: () => unawaited(_edit(path)),
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('Düzenle'),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

bool _editable(String path) {
  if (!EditorWindow.available) return false;
  try {
    return EvrakFile.fromPath(path).format.canEdit;
  } catch (_) {
    return false;
  }
}

/// [path] handed to Folio to be edited (the open Folio takes it if there is
/// one), and this window closed.
Future<void> _edit(String path) async {
  await Process.start(Platform.resolvedExecutable, [
    '--edit',
    '--',
    path,
  ], mode: ProcessStartMode.detached);
  try {
    await windowManager.close();
  } catch (_) {}
}

/// [path] in a preview window of its own.
Future<void> openPreviewWindow(String path) => PreviewWindow.open(path);

/// What is done with the document a preview window shows: printed, kept
/// as a copy or as a PDF, taken to Folio's own window, found in its folder.
class PreviewFileMenu extends StatelessWidget {
  const PreviewFileMenu({super.key, required this.path});

  final String path;

  /// The document as the PDF that is printed or kept: a PDF as it is, a
  /// scan or a picture as pages, anything else laid out as it prints.
  static Future<Uint8List?> pdfOf(String path) async {
    final file = EvrakFile.fromPath(path);
    final bytes = await File(path).readAsBytes();
    switch (file.format) {
      case EvrakFormat.pdf:
        return bytes;
      case EvrakFormat.tif:
        return TiffService.tiffToPdf(bytes);
      case EvrakFormat.image:
        return PdfTools.fromImages([path], title: file.baseName);
      default:
        final model = await ConverterService.extractDocModel(
          bytes,
          file.format,
        );
        return model == null
            ? null
            : PdfService.modelToPdfBytes(model, title: file.baseName);
    }
  }

  Future<void> _run(BuildContext context, String action) async {
    try {
      switch (action) {
        case 'print':
          final pdf = await pdfOf(path);
          if (pdf != null && context.mounted) {
            await PrintScreen.show(context, pdf: pdf, name: p.basename(path));
          }
        case 'pdf':
          final pdf = await pdfOf(path);
          if (pdf == null || !context.mounted) return;
          final saved = await savePdfAs(
            context,
            pdf,
            '${p.basenameWithoutExtension(path)}.pdf',
          );
          if (saved != null && context.mounted) pdfMade(context, saved);
        case 'copy':
          final where = await FilePicker.saveFile(
            dialogTitle: context.l.viewSaveCopy,
            fileName: p.basename(path),
          );
          if (where == null) return;
          await File(path).copy(where);
          if (context.mounted) {
            showNotice(
              context,
              context.l.viewCopySaved,
              kind: NoticeKind.success,
            );
          }
        case 'folio':
          await PreviewWindow.inFolio(path);
          try {
            await windowManager.close();
          } catch (_) {}
        case 'folder':
          await FileActions.invoke('showFolder', path);
      }
    } catch (e) {
      if (context.mounted) {
        showNotice(context, '$e', kind: NoticeKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPdf = p.extension(path).toLowerCase() == '.pdf';
    PopupMenuItem<String> item(String value, IconData icon, String label) =>
        PopupMenuItem(
          value: value,
          child: Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 12),
              Text(label),
            ],
          ),
        );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
            unawaited(_run(context, 'print')),
      },
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: PopupMenuButton<String>(
          key: const ValueKey('preview-file-menu'),
          tooltip: context.l.viewMore,
          position: PopupMenuPosition.under,
          onSelected: (action) => unawaited(_run(context, action)),
          itemBuilder: (context) => [
            item('print', Icons.print_outlined, context.l.viewPrintKey),
            if (!isPdf)
              item(
                'pdf',
                Icons.picture_as_pdf_outlined,
                context.l.viewSaveAsPdf,
              ),
            item('copy', Icons.save_alt_rounded, context.l.viewSaveCopy),
            const PopupMenuDivider(),
            if (!AppEdition.isOfis)
              item(
                'folio',
                Icons.open_in_new_rounded,
                context.l.viewOpenInFolio,
              ),
            item(
              'folder',
              Icons.folder_open_outlined,
              context.l.viewShowInFolder,
            ),
          ],
          child: const SizedBox(
            width: 36,
            height: 36,
            child: Icon(Icons.more_horiz_rounded, size: 20),
          ),
        ),
      ),
    );
  }
}
