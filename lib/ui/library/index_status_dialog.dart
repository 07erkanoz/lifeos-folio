import 'package:flutter/material.dart';

import '../../services/search/library_controller.dart';

class IndexStatusDialog extends StatelessWidget {
  final LibraryController library;
  const IndexStatusDialog({super.key, required this.library});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: const Text('Arşiv ve indeks durumu'),
        content: SizedBox(
          width: 620,
          height: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${library.total} evrak · ${library.searchable} içerik hazır · ${library.namesOnlyCount} yalnız ad · ${library.failures} okunamadı',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 16),
              if (library.active) ...[
                LinearProgressIndicator(
                  value: library.toProcess == 0
                      ? null
                      : library.processed / library.toProcess,
                ),
                const SizedBox(height: 8),
                Text(
                  '${library.phase} · ${library.processed}/${library.toProcess}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  library.currentPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (library.error != null)
                Text(
                  library.error!,
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              Expanded(
                child: ListView.separated(
                  itemCount: library.sources.length,
                  separatorBuilder: (_, i) => const Divider(height: 16),
                  itemBuilder: (context, i) {
                    final source = library.sources[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        source.folder
                            ? Icons.folder_outlined
                            : Icons.description_outlined,
                      ),
                      title: Text(
                        source.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${source.path}\n${source.count} evrak${source.folder
                            ? source.recursive
                                  ? ' · Alt klasörler dahil'
                                  : ' · Tek klasör'
                            : ''}${source.error == null ? '' : '\n${source.error}'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Kaynağı güncelle',
                            onPressed: () => library.refresh(ids: [source.id]),
                            icon: const Icon(Icons.refresh, size: 19),
                          ),
                          IconButton(
                            tooltip: 'Arşivden çıkar; kaynak dosyalar korunur',
                            onPressed: () => library.removeSource(source.id),
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              size: 19,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'İndeks bu cihazda saklanır. Kaynağı arşivden çıkarmak dosyalarınızı silmez. Görseller ve metin katmanı olmayan PDF’ler dosya adıyla aranabilir.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (library.active)
            TextButton(
              onPressed: library.cancel,
              child: const Text('İndekslemeyi durdur'),
            ),
          if (!library.active)
            TextButton(
              onPressed: () => library.refresh(force: true),
              child: const Text('İçerikleri yeniden indeksle'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      );
    },
  );
}
