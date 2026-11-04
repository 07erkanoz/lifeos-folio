import 'package:flutter/foundation.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../services/platform/app_language.dart';
import '../../services/platform/file_actions.dart';

class ShareDocumentDialog extends StatefulWidget {
  final String path;
  const ShareDocumentDialog({super.key, required this.path});
  @override
  State<ShareDocumentDialog> createState() => _ShareDocumentDialogState();
}

class _ShareDocumentDialogState extends State<ShareDocumentDialog> {
  bool _busy = false;
  String? _error;
  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await action();
      if (mounted && message != null) Navigator.pop(context, message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is PlatformException ? e.message : '$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l.tbShareSend),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.basename(widget.path),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              context.l.tbSavedCopyUsed,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: Text(context.l.tbCopyFile),
              subtitle: Text(context.l.tbCopyFileHelp),
              enabled: !_busy,
              onTap: () => _run(() async {
                final copied = context.l.tbFileCopied;
                await FileActions.invoke('copyFile', widget.path);
                return copied;
              }),
            ),
            // The system's own share: Windows's, and a Mac's (AirDrop,
            // Mesajlar, Notlar…; macos/Runner FileActions "share").
            if (defaultTargetPlatform == TargetPlatform.windows ||
                defaultTargetPlatform == TargetPlatform.macOS)
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: Text(
                  defaultTargetPlatform == TargetPlatform.macOS
                      ? context.l.tbShare
                      : context.l.tbShareWithWindows,
                ),
                subtitle: Text(
                  defaultTargetPlatform == TargetPlatform.macOS
                      ? context.l.tbShareMacHelp
                      : context.l.tbShareWindowsHelp,
                ),
                enabled: !_busy,
                onTap: () => _run(() async {
                  await FileActions.invoke('share', widget.path);
                  return '';
                }),
              ),
            // Linux by xdg-email; a Mac by Mail's compose ("email").
            if (defaultTargetPlatform == TargetPlatform.linux ||
                defaultTargetPlatform == TargetPlatform.macOS)
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: Text(context.l.tbAttachToEmail),
                subtitle: Text(context.l.tbAttachToEmailHelp),
                enabled: !_busy,
                onTap: () => _run(() async {
                  await FileActions.composeEmail(widget.path);
                  return '';
                }),
              ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: Text(context.l.tbCopyToFolder),
              subtitle: Text(context.l.tbCopyToFolderHelp),
              enabled: !_busy,
              onTap: () => _run(() async {
                final l = context.l;
                final directory = await FilePicker.getDirectoryPath(
                  dialogTitle: l.tbChooseTargetFolder,
                );
                if (directory == null) return null;
                final target = await FileActions.copyToDirectory(
                  widget.path,
                  directory,
                );
                return l.tbCopiedTo(target);
              }),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: Text(context.l.tbClose),
      ),
    ],
  );
}
