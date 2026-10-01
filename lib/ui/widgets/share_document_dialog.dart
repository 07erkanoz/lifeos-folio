import 'package:flutter/foundation.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

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
    title: const Text('Paylaş / Gönder'),
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
            const Text(
              'Diskte kayıtlı belge kullanılır.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('Dosyayı kopyala'),
              subtitle: const Text(
                'E-postaya, sohbete veya klasöre yapıştırın',
              ),
              enabled: !_busy,
              onTap: () => _run(() async {
                await FileActions.invoke('copyFile', widget.path);
                return 'Dosya kopyalandı. Hedef uygulamaya yapıştırabilirsiniz.';
              }),
            ),
            if (defaultTargetPlatform == TargetPlatform.windows)
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: const Text('Windows ile paylaş'),
                subtitle: const Text('Yüklü paylaşım uygulamalarından seçin'),
                enabled: !_busy,
                onTap: () => _run(() async {
                  await FileActions.invoke('share', widget.path);
                  return '';
                }),
              ),
            if (defaultTargetPlatform == TargetPlatform.linux)
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: const Text('E-postaya ekle'),
                subtitle: const Text('Ekli yeni ileti açılır'),
                enabled: !_busy,
                onTap: () => _run(() async {
                  await FileActions.composeEmail(widget.path);
                  return '';
                }),
              ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Klasöre kopyala'),
              subtitle: const Text('USB bellek veya başka bir klasör seçin'),
              enabled: !_busy,
              onTap: () => _run(() async {
                final directory = await FilePicker.getDirectoryPath(
                  dialogTitle: 'Gönderilecek klasörü seçin',
                );
                if (directory == null) return null;
                final target = await FileActions.copyToDirectory(
                  widget.path,
                  directory,
                );
                return 'Kopyalandı: $target';
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
        child: const Text('Kapat'),
      ),
    ],
  );
}
