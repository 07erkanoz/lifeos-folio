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
  });

  @override
  State<DropZoneOverlay> createState() => _DropZoneOverlayState();
}

class _DropZoneOverlayState extends State<DropZoneOverlay> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
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
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.file_download_outlined,
                          size: 48,
                          color: AppColors.primary,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Evrakları Buraya Bırakın',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Dosya veya klasör ekleyin; desteklenen evraklar arşivlensin',
                          style: TextStyle(
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
