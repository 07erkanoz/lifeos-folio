import 'package:flutter/material.dart';

import '../../services/search/library_controller.dart';
import '../../services/search/search_models.dart';

/// Both the library and the desktop palette expose this exact set of filters.
class SearchControls extends StatelessWidget {
  final LibraryController library;
  const SearchControls({super.key, required this.library});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final group in const <(String, List<String>)>[
                ('Tümü', []),
                ('UDF', ['udf']),
                ('PDF', ['pdf']),
                ('Word', ['docx', 'doc', 'rtf']),
                ('Excel', ['xlsx']),
                (
                  'Metin',
                  [
                    'txt',
                    'md',
                    'markdown',
                    'html',
                    'htm',
                    'odt',
                    'csv',
                    'tsv',
                    'json',
                    'xml',
                    'log',
                  ],
                ),
                (
                  'Görseller',
                  [
                    'png',
                    'jpg',
                    'jpeg',
                    'webp',
                    'gif',
                    'bmp',
                    'tif',
                    'tiff',
                    'svg',
                    'heic',
                    'heif',
                  ],
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(group.$1),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    selected:
                        !library.ocrOnly &&
                        library.extensions.join(',') == group.$2.join(','),
                    onSelected: (_) =>
                        library.filter(types: group.$2, onlyOcr: false),
                  ),
                ),
              // Only offered once OCR has actually produced something: an
              // archive that never ran it would get a chip that can only ever
              // come back empty. Its text may contain recognition mistakes, so
              // being able to list exactly those documents matters.
              if (library.ocrCount > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    avatar: Icon(
                      Icons.document_scanner_outlined,
                      size: 16,
                      color: library.ocrOnly
                          ? Theme.of(context).colorScheme.onSecondaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    // Not "image with text": two thirds of these are scanned
                    // PDFs, not picture files. What they share is that the text
                    // was read off a picture of the page rather than carried by
                    // the document.
                    label: Text('Görüntüden okunan · ${library.ocrCount}'),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    selected: library.ocrOnly,
                    onSelected: (_) =>
                        library.filter(types: const [], onlyOcr: true),
                  ),
                ),
            ],
          ),
        ),
      ),
      SearchOptionsButton(library: library),
    ],
  );
}

class SearchOptionsButton extends StatelessWidget {
  final LibraryController library;
  const SearchOptionsButton({super.key, required this.library});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Arama seçenekleri',
    icon: const Icon(Icons.tune_rounded, size: 20),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => ListenableBuilder(
        listenable: library,
        builder: (context, _) => AlertDialog(
          title: const Text('Arama seçenekleri'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Eşleşme biçimi',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final option in [
                        (SearchMatch.all, 'Tüm sözcükler'),
                        (SearchMatch.phrase, 'Tam ifade'),
                        (SearchMatch.any, 'Herhangi biri'),
                      ])
                        ChoiceChip(
                          label: Text(option.$2),
                          selected: library.match == option.$1,
                          onSelected: (_) =>
                              library.filter(matching: option.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Uzun bir cümle yapıştırabilirsiniz. Tırnak içindeki sözcükler birlikte ve aynı sırayla aranır.',
                    style: TextStyle(fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<bool>(
                    isExpanded: true,
                    initialValue: library.namesOnly,
                    decoration: const InputDecoration(labelText: 'Arama alanı'),
                    items: const [
                      DropdownMenuItem(
                        value: false,
                        child: Text('Dosya adı ve tüm içerik'),
                      ),
                      DropdownMenuItem(
                        value: true,
                        child: Text('Yalnız dosya adı'),
                      ),
                    ],
                    onChanged: (value) => library.filter(byName: value),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: library.sourceId ?? -1,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Klasör / kaynak',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: -1,
                        child: Text('Tüm kaynaklar'),
                      ),
                      for (final source in library.sources)
                        DropdownMenuItem(
                          value: source.id,
                          child: Text(
                            source.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => library.filter(
                      folder: value == -1 ? null : value,
                      clearFolder: value == -1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: library.sort,
                    decoration: const InputDecoration(labelText: 'Sıralama'),
                    items: const [
                      DropdownMenuItem(
                        value: 'relevance',
                        child: Text('En ilgili'),
                      ),
                      DropdownMenuItem(
                        value: 'added',
                        child: Text('Yeni eklenenler'),
                      ),
                      DropdownMenuItem(
                        value: 'newest',
                        child: Text('Son değiştirilen'),
                      ),
                      DropdownMenuItem(value: 'oldest', child: Text('En eski')),
                      DropdownMenuItem(value: 'name', child: Text('Dosya adı')),
                    ],
                    onChanged: (value) => library.filter(ordering: value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => library.filter(
                byName: false,
                matching: SearchMatch.all,
                types: [],
                clearFolder: true,
                ordering: 'relevance',
              ),
              child: const Text('Sıfırla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam'),
            ),
          ],
        ),
      ),
    ),
  );
}
