import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

/// An AI program's answer as it wrote it, Markdown drawn: headings,
/// paragraphs, bold and italic, lists, tables, quotes and code. Selectable
/// as one text. Links are shown, not followed.
class AiMarkdown extends StatelessWidget {
  const AiMarkdown(this.text, {super.key, this.size = 13.5});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parseLines(text.replaceAll('\r\n', '\n').split('\n'));
    final scheme = Theme.of(context).colorScheme;
    final base = TextStyle(
      fontSize: size,
      height: 1.5,
      color: scheme.onSurface,
    );
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final n in nodes) ..._block(n, base, scheme, 0)],
      ),
    );
  }

  List<Widget> _block(
    md.Node node,
    TextStyle base,
    ColorScheme scheme,
    int depth,
  ) {
    if (node is md.Text) {
      return [_para(Text.rich(TextSpan(text: node.text, style: base)))];
    }
    if (node is! md.Element) return const [];
    final e = node;
    switch (e.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final step = {'h1': 4.0, 'h2': 3.0, 'h3': 2.0}[e.tag] ?? 1.0;
        return [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text.rich(
              _inline(
                e.children,
                base.copyWith(
                  fontSize: size + step,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ];
      case 'p':
        return [_para(Text.rich(_inline(e.children, base)))];
      case 'ul' || 'ol':
        final ordered = e.tag == 'ol';
        final start = int.tryParse(e.attributes['start'] ?? '') ?? 1;
        var i = 0;
        return [
          Padding(
            padding: EdgeInsets.only(left: depth == 0 ? 2 : 14, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in e.children ?? const <md.Node>[])
                  if (item is md.Element && item.tag == 'li')
                    _item(
                      ordered ? '${start + i++}.' : '•',
                      item,
                      base,
                      scheme,
                      depth,
                    ),
              ],
            ),
          ),
        ];
      case 'blockquote':
        return [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: scheme.outlineVariant, width: 3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in e.children ?? const <md.Node>[])
                  ..._block(
                    c,
                    base.copyWith(color: scheme.onSurfaceVariant),
                    scheme,
                    depth,
                  ),
              ],
            ),
          ),
        ];
      case 'pre':
        return [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              e.textContent.trimRight(),
              style: base.copyWith(fontFamily: 'monospace', fontSize: size - 1),
            ),
          ),
        ];
      case 'hr':
        return [Divider(color: scheme.outlineVariant)];
      case 'table':
        return [_table(e, base, scheme)];
      default:
        return [_para(Text.rich(_inline(e.children, base)))];
    }
  }

  Widget _para(Widget child) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: child);

  Widget _item(
    String mark,
    md.Element item,
    TextStyle base,
    ColorScheme scheme,
    int depth,
  ) {
    final children = item.children ?? const <md.Node>[];
    final inline = <md.Node>[];
    final blocks = <Widget>[];
    for (final c in children) {
      if (c is md.Element &&
          const {
            'ul',
            'ol',
            'p',
            'pre',
            'blockquote',
            'table',
          }.contains(c.tag)) {
        if (c.tag == 'p') {
          blocks.add(Text.rich(_inline(c.children, base)));
        } else {
          blocks.addAll(_block(c, base, scheme, depth + 1));
        }
      } else {
        inline.add(c);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: mark.length > 2 ? 26 : 16,
            child: Text(mark, style: base),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (inline.isNotEmpty) Text.rich(_inline(inline, base)),
                ...blocks,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(md.Element table, TextStyle base, ColorScheme scheme) {
    final rows = <(bool, List<md.Element>)>[];
    for (final part in table.children ?? const <md.Node>[]) {
      if (part is! md.Element) continue;
      for (final row in part.children ?? const <md.Node>[]) {
        if (row is! md.Element || row.tag != 'tr') continue;
        rows.add((
          part.tag == 'thead',
          [
            for (final cell in row.children ?? const <md.Node>[])
              if (cell is md.Element) cell,
          ],
        ));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final columns = rows
        .map((r) => r.$2.length)
        .reduce((a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: scheme.outlineVariant),
          children: [
            for (final (head, cells) in rows)
              TableRow(
                decoration: head
                    ? BoxDecoration(color: scheme.surfaceContainerHighest)
                    : null,
                children: [
                  for (var i = 0; i < columns; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Text.rich(
                          i < cells.length
                              ? _inline(
                                  cells[i].children,
                                  head
                                      ? base.copyWith(
                                          fontWeight: FontWeight.w700,
                                        )
                                      : base,
                                )
                              : const TextSpan(),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  TextSpan _inline(List<md.Node>? nodes, TextStyle style) => TextSpan(
    style: style,
    children: [for (final n in nodes ?? const <md.Node>[]) _span(n, style)],
  );

  InlineSpan _span(md.Node node, TextStyle style) {
    if (node is md.Text) return TextSpan(text: _unescape(node.text));
    if (node is! md.Element) return const TextSpan();
    final e = node;
    switch (e.tag) {
      case 'strong':
        return _inline(e.children, style.copyWith(fontWeight: FontWeight.w700));
      case 'em':
        return _inline(e.children, style.copyWith(fontStyle: FontStyle.italic));
      case 'del':
        return _inline(
          e.children,
          style.copyWith(decoration: TextDecoration.lineThrough),
        );
      case 'code':
        return TextSpan(
          text: e.textContent,
          style: style.copyWith(fontFamily: 'monospace', fontSize: size - 1),
        );
      case 'br':
        return const TextSpan(text: '\n');
      case 'a':
        return _inline(
          e.children,
          style.copyWith(decoration: TextDecoration.underline),
        );
      default:
        return _inline(e.children, style);
    }
  }

  static String _unescape(String text) => text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}
