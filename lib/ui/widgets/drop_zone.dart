import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class DropZoneOverlay extends StatefulWidget {
  final Widget child;
  final Function(List<String> paths) onFilesDropped;

  const DropZoneOverlay({
    super.key,
    required this.child,
    required this.onFilesDropped,
    this.enabled = true,
    this.title = 'Evrakları Buraya Bırakın',
    this.subtitle =
        'Dosya veya klasör ekleyin; desteklenen evraklar arşivlensin',
  });

  /// Off where a page of its own takes what is dropped.
  final bool enabled;
  final String title, subtitle;

  @override
  State<DropZoneOverlay> createState() => _DropZoneOverlayState();
}

class _DropZoneOverlayState extends State<DropZoneOverlay> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        final paths = details.files.map((f) => f.path).toList();
        if (paths.isNotEmpty) {
          widget.onFilesDropped(paths);
        }
      },
      child: Stack(
        children: [
          widget.child,
          if (_isDragging)
            Positioned.fill(
              child: Container(
                color: AppColors.primary.withValues(alpha: 0.15),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primary, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.file_download_outlined,
                          size: 48,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.darkTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The files among [paths], a folder's own and its folders' too, at most
/// [limit]: what is dropped to be sent.
List<String> droppedFiles(List<String> paths, {int limit = 500}) {
  final out = <String>[];
  for (final path in paths) {
    if (out.length >= limit) break;
    if (FileSystemEntity.isDirectorySync(path)) {
      try {
        for (final e in Directory(path).listSync(recursive: true)) {
          if (out.length >= limit) break;
          final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (e is File && !name.startsWith('.')) out.add(e.path);
        }
      } catch (_) {}
    } else if (FileSystemEntity.isFileSync(path)) {
      out.add(path);
    }
  }
  return out;
}
