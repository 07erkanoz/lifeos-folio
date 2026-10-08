import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/update/update_check.dart';
import '../../services/update/update_manifest.dart';
import 'update_dialog.dart';

/// A newer Folio, told as a card: its version, what is new in it, and the
/// way to install it now, later or never. The same card stands at the top
/// of the settings until it is installed or skipped.
class UpdateCard extends StatelessWidget {
  const UpdateCard({
    super.key,
    required this.update,
    this.onLater,
    this.floating = false,
  });

  final UpdateManifest update;

  /// "Sonra": the card goes; the settings keep it. Null in the settings.
  final VoidCallback? onLater;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notes = (update.notes['tr'] ?? update.notes['en'] ?? '').trim();
    return Material(
      key: const ValueKey('update-card'),
      elevation: floating ? 12 : 0,
      shadowColor: const Color(0x55000000),
      borderRadius: BorderRadius.circular(16),
      color: scheme.surface,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.primary.withValues(alpha: .35)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary.withValues(alpha: .08), scheme.surface],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.system_update_alt_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LifeOS Folio ${update.version} hazır',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Yeni sürüm indirilmeye hazır; kurmak bir dakika sürer.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onLater != null)
                  IconButton(
                    tooltip: 'Kapat',
                    visualDensity: VisualDensity.compact,
                    onPressed: onLater,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
              ],
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                notes,
                maxLines: floating ? 3 : 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 4,
              children: [
                TextButton(
                  key: const ValueKey('update-skip'),
                  onPressed: () {
                    unawaited(UpdateCheck.instance.skip(update));
                    onLater?.call();
                  },
                  child: const Text('Bu sürümü atla'),
                ),
                if (onLater != null)
                  TextButton(
                    key: const ValueKey('update-later'),
                    onPressed: onLater,
                    child: const Text('Sonra'),
                  ),
                FilledButton.icon(
                  key: const ValueKey('update-open'),
                  onPressed: () {
                    onLater?.call();
                    unawaited(UpdateDialog.show(context, update));
                  },
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Şimdi güncelle'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
