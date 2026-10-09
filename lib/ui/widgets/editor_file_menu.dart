import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../models/evrak_file.dart';

/// What the program around an editor adds to its Dosya menu: a new document,
/// opening one, the recently opened documents and unsaved drafts. Folio and
/// LifeOS Editör each answer these their own way; the editor only asks.
class EditorFileHost {
  const EditorFileHost({
    this.onNew,
    this.onOpen,
    this.recent,
    this.onOpenRecent,
    this.onRecovery,
  });

  final VoidCallback? onNew;
  final VoidCallback? onOpen;

  /// Read each time the menu opens, so it is never a stale list.
  final List<EvrakFile> Function()? recent;
  final ValueChanged<EvrakFile>? onOpenRecent;
  final VoidCallback? onRecovery;
}

/// The editor's Dosya menu: the host's commands, then the editor's own —
/// saving in each format, PDF, printing, versions, signing and UYAP.
class EditorFileMenu extends StatelessWidget {
  const EditorFileMenu({
    super.key,
    required this.host,
    required this.currentPath,
    this.controller,
    required this.busy,
    required this.onSave,
    required this.onSaveAs,
    required this.onSaveIn,
    required this.onPrint,
    required this.onHistory,
    this.onSign,
    this.onSendUyap,
    this.onUyapOperations,
    this.onNewWindow,
    this.onLiveShare,
    this.compact = false,
  });

  final EditorFileHost? host;
  final String? currentPath;

  /// Lets the editor open the menu from the keyboard.
  final MenuController? controller;
  final bool busy;
  final VoidCallback onSave;

  /// Save under a new name in the document's own format.
  final VoidCallback onSaveAs;
  final ValueChanged<EvrakFormat> onSaveIn;
  final VoidCallback onPrint;
  final VoidCallback onHistory;
  final VoidCallback? onSign;
  final VoidCallback? onSendUyap;
  final VoidCallback? onUyapOperations;

  /// A new document in an editor window of its own.
  final VoidCallback? onNewWindow;

  /// The document shown live on other devices; null where it cannot be.
  final VoidCallback? onLiveShare;

  /// An icon alone, for a narrow window.
  final bool compact;

  /// How many recent documents the menu lists.
  static const recentLimit = 12;

  static String _key(String key, {bool shift = false}) =>
      '${Platform.isMacOS ? '⌘' : 'Ctrl+'}${shift ? 'Shift+' : ''}$key';

  static IconData _icon(EvrakFormat format) => switch (format) {
    EvrakFormat.udf => Icons.edit_note_rounded,
    EvrakFormat.pdf => Icons.picture_as_pdf_rounded,
    EvrakFormat.docx || EvrakFormat.doc => Icons.description_rounded,
    _ => Icons.article_outlined,
  };

  Widget _item(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    String? keys,
    Key? key,
  }) => MenuItemButton(
    key: key,
    leadingIcon: Icon(icon, size: 19),
    trailingIcon: keys == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(keys, style: const TextStyle(fontSize: 12)),
          ),
    onPressed: onPressed,
    child: Text(label),
  );

  List<Widget> _recent(BuildContext context) {
    final files = [
      for (final file in host?.recent?.call() ?? const <EvrakFile>[])
        if (file.path != currentPath) file,
    ].take(recentLimit).toList();
    if (files.isEmpty) {
      return [
        const MenuItemButton(
          onPressed: null,
          child: Text('Henüz açılmış belge yok'),
        ),
      ];
    }
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return [
      for (final file in files)
        MenuItemButton(
          key: ValueKey('editor-recent-${file.path}'),
          leadingIcon: Icon(_icon(file.format), size: 19),
          onPressed: () => host!.onOpenRecent!(file),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  p.dirname(file.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final host = this.host;
    final save = busy ? null : onSave;
    return MenuAnchor(
      controller: controller,
      menuChildren: [
        if (host?.onNew != null)
          _item(
            'Yeni belge',
            Icons.note_add_outlined,
            host!.onNew,
            keys: _key('N'),
          ),
        if (onNewWindow != null)
          _item('Yeni pencere', Icons.open_in_new_rounded, onNewWindow),
        if (host?.onOpen != null)
          _item(
            'Aç…',
            Icons.folder_open_outlined,
            host!.onOpen,
            keys: _key('O'),
          ),
        if (host?.recent != null && host?.onOpenRecent != null)
          SubmenuButton(
            key: const ValueKey('editor-recent-menu'),
            leadingIcon: const Icon(Icons.history_rounded, size: 19),
            menuChildren: _recent(context),
            child: const Text('Son açılanlar'),
          ),
        if (host?.onNew != null ||
            host?.onOpen != null ||
            host?.recent != null ||
            onNewWindow != null)
          const Divider(height: 8),
        _item('Kaydet', Icons.save_outlined, save, keys: _key('S')),
        if (onLiveShare != null)
          _item('Canlı paylaş…', Icons.cast_outlined, onLiveShare),
        _item('Farklı kaydet…', Icons.save_as_outlined, busy ? null : onSaveAs),
        _item(
          'UYAP UDF Olarak Kaydet',
          Icons.edit_note_rounded,
          busy ? null : () => onSaveIn(EvrakFormat.udf),
        ),
        _item(
          'Word (DOCX) Olarak Kaydet',
          Icons.description_outlined,
          busy ? null : () => onSaveIn(EvrakFormat.docx),
        ),
        _item(
          'Zengin Metin (RTF) Olarak Kaydet',
          Icons.article_outlined,
          busy ? null : () => onSaveIn(EvrakFormat.rtf),
        ),
        _item(
          'PDF’e dönüştür',
          Icons.picture_as_pdf_outlined,
          busy ? null : () => onSaveIn(EvrakFormat.pdf),
        ),
        const Divider(height: 8),
        _item('Yazdır', Icons.print_outlined, onPrint, keys: _key('P')),
        _item('Belge geçmişi', Icons.restore_outlined, onHistory),
        if (host?.onRecovery != null)
          _item(
            'Kurtarılabilir taslaklar',
            Icons.settings_backup_restore_rounded,
            host!.onRecovery,
          ),
        if (onSign != null || onSendUyap != null || onUyapOperations != null)
          const Divider(height: 8),
        if (onSign != null)
          _item('UDF e-imzala', Icons.draw_outlined, busy ? null : onSign),
        if (onSendUyap != null)
          _item(
            'UYAP’a gönder',
            Icons.upload_file_outlined,
            busy ? null : onSendUyap,
          ),
        if (onUyapOperations != null)
          _item(
            'UYAP devam eden işlemler',
            Icons.pending_actions_outlined,
            onUyapOperations,
          ),
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        if (compact) {
          return IconButton(
            key: const ValueKey('editor-file-menu'),
            tooltip: 'Dosya',
            onPressed: toggle,
            icon: const Icon(Icons.folder_outlined, size: 20),
          );
        }
        // Stacked like the toolbar's own groups, so it costs a narrow column
        // rather than squeezing the groups beside it.
        final colors = Theme.of(context).colorScheme;
        return Tooltip(
          message: 'Dosya menüsü',
          child: InkWell(
            key: const ValueKey('editor-file-menu'),
            onTap: toggle,
            borderRadius: BorderRadius.circular(8),
            // As wide as the save-as arrow it replaced: the toolbar keeps
            // the width it had, so nothing on it moves out of view.
            child: SizedBox(
              width: 40,
              height: 72,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_outlined, size: 24, color: colors.primary),
                  const SizedBox(height: 4),
                  // One line whatever the text scale: at 150% the word is
                  // wider than the column and would wrap into the page.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Dosya',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
