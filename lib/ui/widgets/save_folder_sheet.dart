import 'package:flutter/material.dart';

import '../../services/platform/phone_document_save.dart';

/// The folder a phone saves into, asked for once (21 Ekim 2026, approved
/// mockup): what it is for, then the system's folder screen. Null when none
/// is chosen; the one chosen before when there is one.
Future<PhoneSaveFolder?> ensureSaveFolder(BuildContext context) async {
  final folder = PhoneSaveFolder.instance;
  if (await folder.current() != null) return folder;
  if (!context.mounted) return null;
  final go = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Belgeler nereye kaydedilsin?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Bir kez seçersiniz; sonra Kaydet doğrudan oraya yazar. '
              'İmzaladığınız belgeler de oraya kaydedilir.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('save-folder-choose'),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.folder_outlined),
              label: const Text('Klasör seç'),
            ),
          ],
        ),
      ),
    ),
  );
  if (go != true) return null;
  return await folder.choose() == null ? null : folder;
}
