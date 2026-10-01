import 'package:flutter/material.dart';

import '../../models/evrak_file.dart';

class MobileDocumentHome extends StatelessWidget {
  final List<EvrakFile> recent;
  final VoidCallback onOpen, onNew, onArchive, onRecovery;

  /// The phone's photographs. On a desktop the gallery is a place in the
  /// sidebar; a phone has no sidebar, so it needs a door of its own here.
  final VoidCallback onGallery;

  /// Camera to PDF; null where there is no scanner (off Android).
  final VoidCallback? onScan;
  final ValueChanged<EvrakFile> onRecent, onShare;
  final int recoveryCount;
  const MobileDocumentHome({
    super.key,
    required this.recent,
    required this.onOpen,
    required this.onNew,
    required this.onArchive,
    required this.onGallery,
    this.onScan,
    required this.onRecovery,
    required this.onRecent,
    required this.onShare,
    required this.recoveryCount,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Text(
          'Belgeniz, elinizin altında.',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.6),
        ),
        const SizedBox(height: 8),
        Text(
          'Açın, inceleyin, düzenleyin ve paylaşın.',
          style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onOpen,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Belge aç'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        if (onScan != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('mobile-scan'),
            onPressed: onScan,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Kameradan PDF tara'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onNew,
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('Yeni belge oluştur'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onGallery,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Galeri'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'PDF · UDF · Word · RTF · metin · görseller',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
        ),
        if (recoveryCount > 0) ...[
          const SizedBox(height: 20),
          Material(
            color: colors.primaryContainer.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              leading: Icon(Icons.restore_rounded, color: colors.primary),
              title: Text('$recoveryCount taslak kurtarılabilir'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onRecovery,
            ),
          ),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Son açılanlar',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            TextButton.icon(
              onPressed: onArchive,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Arşivde ara'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 32,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Açtığınız belgeler burada görünür.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Dosyalar veya başka bir uygulamadaki “Birlikte aç” seçeneğiyle de Folio’ya gelebilirsiniz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        for (final file in recent)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                contentPadding: const EdgeInsets.only(left: 14, right: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Container(
                  width: 38,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    file.format.isVisual
                        ? Icons.image_outlined
                        : Icons.description_outlined,
                    size: 22,
                    color: colors.primary,
                  ),
                ),
                title: Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  file.format.label,
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: IconButton(
                  tooltip: 'Belgeyi paylaş',
                  onPressed: () => onShare(file),
                  icon: const Icon(Icons.ios_share_rounded, size: 20),
                ),
                onTap: () => onRecent(file),
              ),
            ),
          ),
      ],
    );
  }
}
