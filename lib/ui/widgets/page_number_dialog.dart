import 'package:flutter/material.dart';

import '../../services/layout/page_numbers.dart';
import 'folio_select.dart';

/// Where the page numbers go, and how they read: what UYAP's own page
/// number dialog offers, so a number set here is one UYAP draws the same
/// way. [region] is null for no numbers at all.
typedef PageNumberChoice = ({String? region, PageNumbering numbering});

class PageNumberDialog extends StatefulWidget {
  const PageNumberDialog({super.key, this.region, this.numbering});

  /// `header` or `footer`, where the numbers are now; null for none.
  final String? region;
  final PageNumbering? numbering;

  static Future<PageNumberChoice?> show(
    BuildContext context, {
    String? region,
    PageNumbering? numbering,
  }) => showDialog<PageNumberChoice>(
    context: context,
    builder: (_) => PageNumberDialog(region: region, numbering: numbering),
  );

  @override
  State<PageNumberDialog> createState() => _PageNumberDialogState();
}

class _PageNumberDialogState extends State<PageNumberDialog> {
  late String? _region = widget.region ?? 'footer';
  late bool _top = widget.numbering?.top ?? false;
  late PageNumberAlign _align =
      widget.numbering?.align ?? PageNumberAlign.center;
  late bool _total = widget.numbering?.withTotal ?? false;
  late String _separator = widget.numbering?.separator ?? '/';
  late bool _skipFirst = widget.numbering?.skipFirst ?? false;
  late bool _skipSingle = widget.numbering?.skipSingle ?? false;
  late String _face = widget.numbering?.fontFace ?? 'Arial';
  late double _size = widget.numbering?.fontSize ?? 11;
  late bool _bold = widget.numbering?.bold ?? false;
  late final _prefix = TextEditingController(
    text: widget.numbering?.prefix ?? '',
  );
  late final _start = TextEditingController(
    text: widget.numbering?.startNumber?.toString() ?? '',
  );

  /// UYAP's own lists.
  static const _separators = ['/', '-', '\\', '.', ','];
  static const _sizes = <double>[8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24];

  @override
  void dispose() {
    _prefix.dispose();
    _start.dispose();
    super.dispose();
  }

  PageNumbering get _numbering => PageNumbering(
    top: _top,
    align: _align,
    withTotal: _total,
    separator: _separator,
    skipFirst: _skipFirst,
    skipSingle: _skipSingle,
    prefix: _prefix.text,
    fontFace: _face,
    fontSize: _size,
    bold: _bold,
    startNumber: int.tryParse(_start.text.trim()),
  );

  @override
  Widget build(BuildContext context) {
    final off = _region == null;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
    return AlertDialog(
      title: const Text('Sayfa numarası'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                key: const ValueKey('page-number-region'),
                segments: const [
                  ButtonSegment(value: 'none', label: Text('Yok')),
                  ButtonSegment(value: 'header', label: Text('Üst bilgide')),
                  ButtonSegment(value: 'footer', label: Text('Alt bilgide')),
                ],
                selected: {_region ?? 'none'},
                onSelectionChanged: (v) => setState(() {
                  _region = v.first == 'none' ? null : v.first;
                  // Where the number sits in its region follows the region
                  // until it is set by hand: the top of a header, the
                  // bottom of a footer.
                  if (widget.numbering == null) _top = _region == 'header';
                }),
              ),
              if (!off) ...[
                label('Yeri'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Üstte')),
                        ButtonSegment(value: false, label: Text('Altta')),
                      ],
                      selected: {_top},
                      onSelectionChanged: (v) => setState(() => _top = v.first),
                    ),
                    SegmentedButton<PageNumberAlign>(
                      key: const ValueKey('page-number-align'),
                      segments: const [
                        ButtonSegment(
                          value: PageNumberAlign.left,
                          label: Text('Sol'),
                        ),
                        ButtonSegment(
                          value: PageNumberAlign.center,
                          label: Text('Orta'),
                        ),
                        ButtonSegment(
                          value: PageNumberAlign.right,
                          label: Text('Sağ'),
                        ),
                      ],
                      selected: {_align},
                      onSelectionChanged: (v) =>
                          setState(() => _align = v.first),
                    ),
                  ],
                ),
                label('Biçimi'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _prefix,
                        decoration: const InputDecoration(
                          labelText: 'Ön metin',
                          hintText: 'Sayfa ',
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _start,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'İlk numara',
                          hintText: '1',
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Checkbox(
                      value: _total,
                      onChanged: (v) => setState(() => _total = v ?? false),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _total = !_total),
                      child: const Text('Toplam sayfayla'),
                    ),
                    const SizedBox(width: 12),
                    if (_total)
                      FolioSelect<String>(
                        value: _separator,
                        items: [
                          for (final s in _separators)
                            DropdownMenuItem(value: s, child: Text(' $s ')),
                        ],
                        onChanged: (v) => setState(() => _separator = v ?? '/'),
                      ),
                  ],
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _skipFirst,
                  title: const Text('İlk sayfada gösterme'),
                  onChanged: (v) => setState(() => _skipFirst = v ?? false),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _skipSingle,
                  title: const Text('Tek sayfaysa gösterme'),
                  onChanged: (v) => setState(() => _skipSingle = v ?? false),
                ),
                label('Yazı'),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FolioSelect<String>(
                      value: _face,
                      items: const [
                        DropdownMenuItem(value: 'Arial', child: Text('Arial')),
                        DropdownMenuItem(
                          value: 'Times New Roman',
                          child: Text('Times New Roman'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _face = v ?? 'Arial'),
                    ),
                    const SizedBox(width: 12),
                    FolioSelect<double>(
                      value: _sizes.contains(_size) ? _size : 11,
                      items: [
                        for (final s in _sizes)
                          DropdownMenuItem(
                            value: s,
                            child: Text('${s.round()}'),
                          ),
                      ],
                      onChanged: (v) => setState(() => _size = v ?? 11),
                    ),
                    const SizedBox(width: 12),
                    FilterChip(
                      label: const Text('Kalın'),
                      selected: _bold,
                      onSelected: (v) => setState(() => _bold = v),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Örnek: ${_numbering.label(1, 5)}',
                  key: const ValueKey('page-number-sample'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop<PageNumberChoice>(context, (
            region: _region,
            numbering: _numbering,
          )),
          child: const Text('Tamam'),
        ),
      ],
    );
  }
}
