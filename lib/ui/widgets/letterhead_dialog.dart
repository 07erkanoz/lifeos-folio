import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../models/document_model.dart';
import '../../services/editor/doc_delta_map.dart';
import '../../services/editor/letterheads.dart';
import '../../services/fonts/document_fonts.dart';
import 'editor_image_embed.dart';
import 'editor_line_layout.dart';
import 'editor_tab_spans.dart';

/// What the lawyer chose in [LetterheadDialog]: a letterhead to head the
/// document with, on every page or only the first.
typedef LetterheadChoice = ({Letterhead letterhead, bool firstPageOnly});

/// The letterheads: put one on the document, keep the document's header as
/// one, name them, and pick the one new documents get.
///
/// A letterhead is designed where it prints, in the document's header, with
/// the editor's own tools: type, alignment, a logo from a file. Kept here, it
/// heads any document in one step.
class LetterheadDialog extends StatefulWidget {
  const LetterheadDialog({
    super.key,
    required this.store,
    required this.header,
    required this.pageWidth,
  });

  final LetterheadStore store;

  /// The document's header as it is now, to keep as a letterhead; null or
  /// empty when it has none.
  final List<DocBlock>? header;

  /// The text area's width, which a letterhead is shown at.
  final double pageWidth;

  static Future<LetterheadChoice?> show(
    BuildContext context, {
    required LetterheadStore store,
    required List<DocBlock>? header,
    required double pageWidth,
  }) => showDialog<LetterheadChoice>(
    context: context,
    builder: (_) =>
        LetterheadDialog(store: store, header: header, pageWidth: pageWidth),
  );

  @override
  State<LetterheadDialog> createState() => _LetterheadDialogState();
}

class _LetterheadDialogState extends State<LetterheadDialog> {
  bool _firstPageOnly = false;

  bool get _headerWritten =>
      widget.header?.any(
        (b) => b.plainText.trim().isNotEmpty || b.type == DocBlockType.image,
      ) ??
      false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_changed);
  }

  @override
  void dispose() {
    widget.store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<String?> _askName(String title, String initial) => showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, initial: initial),
  );

  Future<void> _keepHeader() async {
    final name = await _askName(
      'Üst bilgiyi antet olarak kaydet',
      widget.store.all.isEmpty ? 'Antetim' : '',
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final taken = widget.store.byName(name);
    if (taken != null) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('"${taken.name}" değiştirilsin mi?'),
          content: const Text(
            'Bu adla kayıtlı antet, belgenin üst bilgisiyle değiştirilecek.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Değiştir'),
            ),
          ],
        ),
      );
      if (replace != true) return;
    }
    await widget.store.save(name, widget.header!);
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.store.all;
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Antetler'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Henüz antet yok. Anteti belgenin üst bilgisinde '
                  'tasarlayın: yazı, hizalama ve Ekle › Görsel ile logo. '
                  'Sonra aşağıdan antet olarak kaydedin; her belgeye tek '
                  'tıkla eklenir.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final one in all)
                      _LetterheadTile(
                        key: ValueKey('letterhead-${one.id}'),
                        letterhead: one,
                        pageWidth: widget.pageWidth,
                        onApply: () => Navigator.pop<LetterheadChoice>(
                          context,
                          (letterhead: one, firstPageOnly: _firstPageOnly),
                        ),
                        onRename: () async {
                          final name = await _askName(
                            'Anteti yeniden adlandır',
                            one.name,
                          );
                          if (name != null) {
                            await widget.store.rename(one.id, name);
                          }
                        },
                        onDelete: () => widget.store.remove(one.id),
                        onDefault: () => widget.store.makeDefault(
                          one.isDefault ? null : one.id,
                        ),
                      ),
                  ],
                ),
              ),
            if (all.isNotEmpty)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _firstPageOnly,
                title: const Text('Yalnız ilk sayfada'),
                subtitle: const Text(
                  'Kapalıyken antet her sayfanın başında basılır.',
                ),
                onChanged: (v) => setState(() => _firstPageOnly = v ?? false),
              ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _headerWritten ? _keepHeader : null,
          icon: const Icon(Icons.bookmark_add_outlined, size: 18),
          label: const Text('Üst bilgiyi antet olarak kaydet…'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

/// One letterhead, drawn small as it prints, with what can be done to it.
class _LetterheadTile extends StatefulWidget {
  const _LetterheadTile({
    super.key,
    required this.letterhead,
    required this.pageWidth,
    required this.onApply,
    required this.onRename,
    required this.onDelete,
    required this.onDefault,
  });

  final Letterhead letterhead;
  final double pageWidth;
  final VoidCallback onApply, onRename, onDelete, onDefault;

  @override
  State<_LetterheadTile> createState() => _LetterheadTileState();
}

class _LetterheadTileState extends State<_LetterheadTile> {
  late QuillController _preview = _controller();

  QuillController _controller() => QuillController(
    document: Document.fromDelta(
      DocDeltaMap.modeldenDelta(DocModel(blocks: widget.letterhead.blocks))
          .delta,
    ),
    selection: const TextSelection.collapsed(offset: 0),
    readOnly: true,
  );

  @override
  void didUpdateWidget(covariant _LetterheadTile old) {
    super.didUpdateWidget(old);
    if (!identical(old.letterhead.blocks, widget.letterhead.blocks)) {
      _preview.dispose();
      _preview = _controller();
    }
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final one = widget.letterhead;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(one.name, style: theme.textTheme.titleSmall),
                ),
                if (one.isDefault)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: const Text('Yeni belgelerde'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                FilledButton.tonal(
                  onPressed: widget.onApply,
                  child: const Text('Uygula'),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Diğer',
                  onSelected: (v) => switch (v) {
                    'rename' => widget.onRename(),
                    'delete' => widget.onDelete(),
                    _ => widget.onDefault(),
                  },
                  itemBuilder: (_) => [
                    CheckedPopupMenuItem(
                      value: 'default',
                      checked: one.isDefault,
                      child: const Text('Yeni belgelerde kullan'),
                    ),
                    const PopupMenuItem(
                      value: 'rename',
                      child: Text('Yeniden adlandır'),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('Sil')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // As it prints, shrunk to the list's width.
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFDCE0E8)),
              ),
              child: IgnorePointer(
                child: FittedBox(
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: widget.pageWidth,
                    child: QuillEditor.basic(
                      controller: _preview,
                      config: QuillEditorConfig(
                        embedBuilders: [EditorImageEmbed()],
                        lineLayoutBuilder: EditorLineLayout.builder(
                          pageWidth: widget.pageWidth,
                        ),
                        textSpanBuilder: EditorTabSpans.builder(
                          pageWidth: widget.pageWidth,
                        ),
                        customStyles: DefaultStyles(
                          paragraph: DefaultTextBlockStyle(
                            TextStyle(
                              color: Colors.black,
                              fontFamily: DocumentFonts.family(
                                'Times New Roman',
                              ),
                              fontSize: 12,
                              height: 1.15,
                            ),
                            const HorizontalSpacing(0, 0),
                            const VerticalSpacing(0, 0),
                            const VerticalSpacing(0, 0),
                            null,
                          ),
                        ),
                        customStyleBuilder: (attribute) =>
                            attribute.key == 'font'
                            ? TextStyle(
                                fontFamily: DocumentFonts.family(
                                  attribute.value as String?,
                                ),
                              )
                            : const TextStyle(),
                        scrollable: false,
                        expands: false,
                        padding: EdgeInsets.zero,
                        showCursor: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a name. Its own widget, so the field's controller lives as long
/// as the dialog does, closing animation and all.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _field,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Adı'),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _field.text),
        child: const Text('Tamam'),
      ),
    ],
  );
}
