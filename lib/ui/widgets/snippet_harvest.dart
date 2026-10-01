import 'package:flutter/material.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../services/editor/snippets.dart';

/// The passages the archive already repeats, offered one by one.
///
/// This is what a first run should show. Telling a reader with an empty
/// library to go and select a paragraph is asking them to do by hand what
/// their own files already answer: measured on a real archive, 309 passages
/// appeared word for word in five or more filings.
///
/// Nothing is kept without being chosen. What repeats is not always a
/// passage worth keeping — a party's address repeats too — and only the
/// reader can tell which is which.
class SnippetHarvest extends StatefulWidget {
  const SnippetHarvest({super.key, required this.found, required this.store});

  /// What the archive repeats, most repeated first.
  final List<({String text, int documents})> found;

  final SnippetStore store;

  static Future<int?> show(
    BuildContext context, {
    required List<({String text, int documents})> found,
    required SnippetStore store,
  }) => showDialog<int>(
    context: context,
    builder: (_) => SnippetHarvest(found: found, store: store),
  );

  /// What a passage carries that belongs to one case rather than to the
  /// passage: a date, a case number, an identity number, a sum. Turned into
  /// blanks so the passage can serve the next file too.
  static final _particular = <(RegExp, String)>[
    (RegExp(r'\b\d{4}\s*/\s*\d{1,6}\b'), 'ESAS'),
    (RegExp(r'\b[1-9][0-9]{10}\b'), 'TC'),
    (RegExp(r'\b\d{1,2}[./]\d{1,2}[./]\d{4}\b'), 'TARİH'),
    (RegExp(r'\b\d[\d.]*,\d{2}\s*(?:TL|₺)'), 'TUTAR'),
  ];

  @visibleForTesting
  static String blanked(String text) {
    var out = text;
    for (final (pattern, name) in _particular) {
      out = out.replaceAll(pattern, '[$name]');
    }
    return out;
  }

  /// A name from the opening words, which is what the reader would call it.
  @visibleForTesting
  static String nameFor(String text) {
    final words = text.split(RegExp(r'\s+')).take(6).join(' ');
    return words.length > 52 ? '${words.substring(0, 52)}…' : words;
  }

  @override
  State<SnippetHarvest> createState() => _SnippetHarvestState();
}

class _SnippetHarvestState extends State<SnippetHarvest> {
  final _taken = <int>{};
  var _blank = true;
  var _busy = false;

  Future<void> _keep() async {
    setState(() => _busy = true);
    var kept = 0;
    for (final at in _taken.toList()..sort()) {
      final text = _blank
          ? SnippetHarvest.blanked(widget.found[at].text)
          : widget.found[at].text;
      await widget.store.add(
        SnippetHarvest.nameFor(text),
        Delta()..insert('$text\n'),
      );
      kept++;
    }
    if (mounted) Navigator.pop(context, kept);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Arşivinizde tekrar eden paragraflar',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.found.isEmpty
                        ? 'Beş ya da daha fazla belgede aynen geçen bir '
                              'paragraf bulunamadı. Arşiv henüz taranıyor '
                              'olabilir.'
                        : '${widget.found.length} paragraf bulundu. '
                              'Kalıba almak istediklerinizi işaretleyin.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.found.isNotEmpty)
              CheckboxListTile(
                key: const ValueKey('harvest-blank'),
                dense: true,
                value: _blank,
                onChanged: (on) => setState(() => _blank = on ?? true),
                title: const Text(
                  'Tarih, esas numarası, kimlik ve tutarları boş bırak',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'Bir dosyaya ait olan kısımlar [TARİH] gibi doldurulacak '
                  'yerlere çevrilir.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: widget.found.length,
                itemBuilder: (context, i) {
                  final one = widget.found[i];
                  final shown = _blank
                      ? SnippetHarvest.blanked(one.text)
                      : one.text;
                  return CheckboxListTile(
                    key: ValueKey('harvest-$i'),
                    value: _taken.contains(i),
                    onChanged: (on) => setState(
                      () => on ?? false ? _taken.add(i) : _taken.remove(i),
                    ),
                    isThreeLine: true,
                    title: Text(
                      '${one.documents} belgede',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    subtitle: Text(
                      shown,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('Vazgeç'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('harvest-keep'),
                    onPressed: _taken.isEmpty || _busy ? null : _keep,
                    child: Text(
                      _taken.isEmpty
                          ? 'Kalıba al'
                          : '${_taken.length} kalıbı al',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
