import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/platform/document_intents.dart';

/// The Download folder chosen, and Android's all-files access not given.
class DownloadsAccessRefused implements Exception {
  const DownloadsAccessRefused();

  @override
  String toString() =>
      'Android ayarlarında LifeOS Folio için "Tüm dosyalara erişim" izni '
      'verilmedi.';
}

/// A folder to index on a phone; null when none was chosen.
///
/// On Android the Download folder is offered first: Android 11 and later
/// keep it out of the system's folder picker, so it is read directly once
/// all-files access is given (android MainActivity.kt, downloadsFolder).
/// Throws [DownloadsAccessRefused] when that access is not given. On an
/// iPhone the system's folder picker opens as before.
Future<String?> pickPhoneFolder(
  BuildContext context, {
  @visibleForTesting bool? android,
}) async {
  if (!(android ?? Platform.isAndroid)) return DocumentIntents.pickFolder();
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('folder-downloads'),
            leading: const Icon(Icons.download_rounded),
            title: const Text('İndirilenler'),
            subtitle: const Text(
              'İlk seferde Android ayarlarından "Tüm dosyalara erişim" '
              'izni istenir',
            ),
            onTap: () => Navigator.pop(sheet, 'downloads'),
          ),
          ListTile(
            key: const ValueKey('folder-other'),
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('Başka bir klasör seç'),
            onTap: () => Navigator.pop(sheet, 'other'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  switch (choice) {
    case 'downloads':
      return await DocumentIntents.downloadsFolder() ??
          (throw const DownloadsAccessRefused());
    case 'other':
      return DocumentIntents.pickFolder();
    default:
      return null;
  }
}
