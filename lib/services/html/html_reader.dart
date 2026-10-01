import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../models/document_model.dart';

/// Reads HTML into a document model, as a browser would lay it out.
///
/// What lands on the clipboard as HTML is written by very different hands,
/// and each says the same thing its own way:
///
/// - Word puts its paragraph styles in a stylesheet wrapped in comments,
///   writes a tab as a span with `mso-tab-count`, a list item as a paragraph
///   with `mso-list` and its bullet as text between `<![if !supportLists]>`
///   markers, and its tab stops as `tab-stops`.
/// - Google Docs writes every run's style inline, a tab as a tab in a span
///   that keeps white space, and a list item as a paragraph inside the `li`.
/// - Chrome copies a web page with each element's computed style inline.
/// - LibreOffice writes `<font>` and `align`, and its tabs as plain tab
///   characters that HTML would otherwise collapse.
/// - Folio writes everything inline, as Google Docs does (see [HtmlWriter]).
///
/// So the reader follows CSS where it can: inherited properties inherit,
/// white space collapses unless it is kept, margins nest, a negative first
/// line indent is a hanging one, and the browser's own defaults apply where
/// nothing is said.
abstract final class HtmlReader {
  static DocModel read(String source, {bool clipboard = false}) {
    final document = html.parse(source);
    final sheet = _Sheet.parse(
      document.querySelectorAll('style').map((e) => e.text).join('\n'),
    );
    final generator =
        document
            .querySelector('meta[name="generator"]')
            ?.attributes['content'] ??
        document
            .querySelector('meta[name="Generator"]')
            ?.attributes['content'] ??
        '';
    final producer = source.contains('docs-internal-guid')
        ? _Producer.googleDocs
        : generator.contains('Microsoft') ||
              source.contains('urn:schemas-microsoft-com:office') ||
              source.contains('class=MsoNormal') ||
              source.contains('class="MsoNormal"')
        ? _Producer.word
        : generator.contains('LibreOffice') || generator.contains('OpenOffice')
        ? _Producer.libreOffice
        : generator.contains('Folio')
        ? _Producer.folio
        : _Producer.web;
    for (final e in document.querySelectorAll(
      'script,style,iframe,object,embed,link,meta,noscript,title,template',
    )) {
      e.remove();
    }
    bool? openEnd;
    if (clipboard &&
        source.contains('<!--StartFragment-->') &&
        source.contains('<!--EndFragment-->')) {
      openEnd = _openEnd(document);
      _trimToFragment(document);
    }
    final body = document.body;
    final reader = _Reader(sheet, producer);
    if (body != null) {
      final root = reader.computed(body, _Style.root);
      reader.children(body, root, _Block.root(root));
      reader.flush();
    }
    return DocModel(
      blocks: reader.blocks,
      metadata: {
        // HTML's tabs are the browser's: every half inch from the margin, as
        // in Word and Google Docs; a line break inside a paragraph is one,
        // not a new paragraph.
        'tabRules': 'word',
        'defaultTabStop': 36.0,
        'openEnd': ?openEnd,
      },
    );
  }

  /// Whether the copied fragment stops inside its last paragraph.
  ///
  /// Word marks what was copied with StartFragment and EndFragment comments:
  /// a selection that stops inside a paragraph ends inside that paragraph's
  /// element, one that took the whole paragraph ends after it. A fragment of
  /// runs with no paragraph around them — what a browser gives for part of a
  /// line — stops inside one too.
  static bool _openEnd(dom.Document document) {
    dom.Comment? end;
    void find(dom.Node node) {
      for (final child in node.nodes) {
        if (end != null) return;
        if (child is dom.Comment && child.data?.trim() == 'EndFragment') {
          end = child;
          return;
        }
        find(child);
      }
    }

    find(document);
    final marker = end;
    if (marker == null) return true;
    for (var parent = marker.parentNode; parent is dom.Element;) {
      final tag = parent.localName;
      if (tag == 'body' || tag == 'html') break;
      if (_blockTags.contains(tag)) return true;
      parent = parent.parentNode;
    }
    // Directly in the body: open if what precedes it is text or inline.
    final siblings = marker.parentNode?.nodes ?? const <dom.Node>[];
    for (var i = siblings.indexOf(marker) - 1; i >= 0; i--) {
      final node = siblings[i];
      if (node is dom.Comment) continue;
      if (node is dom.Text && node.text.trim().isEmpty) continue;
      return node is dom.Text ||
          (node is dom.Element && !_blockTags.contains(node.localName));
    }
    return true;
  }

  /// Keeps what lies between the fragment markers, and the elements around
  /// it for the styles they hand down.
  static void _trimToFragment(dom.Document document) {
    var selected = false;
    void trim(dom.Node parent) {
      for (final child in parent.nodes.toList()) {
        if (child is dom.Comment) {
          final data = child.data?.trim();
          if (data == 'StartFragment') selected = true;
          if (data == 'EndFragment') selected = false;
          if (data == 'StartFragment' || data == 'EndFragment') child.remove();
        } else if (child is dom.Element) {
          final startsSelected = selected;
          trim(child);
          // Outside the fragment: nothing selected is left in it.
          if (!startsSelected && !selected && !_holdsText(child)) {
            child.remove();
          }
        } else if (!selected) {
          child.remove();
        }
      }
    }

    trim(document);
  }

  static bool _holdsText(dom.Element element) =>
      element.text.trim().isNotEmpty ||
      element.querySelector('img,table,br') != null;
}

enum _Producer { word, googleDocs, libreOffice, folio, web }

const _blockTags = {
  'p',
  'div',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'li',
  'ul',
  'ol',
  'dl',
  'dt',
  'dd',
  'pre',
  'blockquote',
  'table',
  'section',
  'article',
  'header',
  'footer',
  'main',
  'nav',
  'aside',
  'address',
  'figure',
  'figcaption',
  'center',
  'form',
  'fieldset',
  'details',
  'summary',
  'hr',
  'body',
};

/// Properties a child takes from its parent in CSS.
const _inherited = {
  'font-family',
  'font-size',
  'font-weight',
  'font-style',
  'color',
  'text-align',
  'line-height',
  'text-indent',
  'white-space',
  'list-style-type',
  'visibility',
  'tab-stops',
};

/// An element's computed style: CSS property names to values.
class _Style {
  const _Style(this.values, this.decorations, this.background, this.script);

  final Map<String, String> values;

  /// Text decoration is not inherited, but it is drawn through everything
  /// inside the element that has it.
  final Set<String> decorations;

  /// An inline element's background shows behind its text, and behind the
  /// text of everything inside it.
  final String? background;
  final String? script;

  static const root = _Style({'font-size': '12pt'}, {}, null, null);

  String? operator [](String key) => values[key];

  double get fontSize => _length(values['font-size'], 12) ?? 12;
}

/// Where a paragraph's layout comes from: the block element around its text,
/// with the indents of every block around that.
class _Block {
  _Block({
    required this.style,
    required this.left,
    required this.right,
    this.before = 0,
    this.after = 0,
    this.heading,
    this.list,
    this.explicit = false,
    this.cellOf,
  });

  factory _Block.root(_Style style) => _Block(style: style, left: 0, right: 0);

  final _Style style;
  final double left, right, before, after;
  final int? heading;
  final _ListItem? list;

  /// An element that is a paragraph even when empty: `<p></p>` is a line.
  final bool explicit;
  final Object? cellOf;
}

class _ListItem {
  _ListItem(this.type, this.level);
  final DocListType type;
  final int level;

  /// The first paragraph of an item carries its bullet; any after it in the
  /// same item continue under it.
  bool used = false;
}

class _Reader {
  _Reader(this.sheet, this.producer);

  final _Sheet sheet;
  final _Producer producer;
  final blocks = <DocBlock>[];

  _Buffer? _buffer;

  /// Inside Word's `<![if !supportLists]>`: the bullet, written as text.
  bool _marker = false;
  final _markerText = StringBuffer();

  _Style computed(dom.Element element, _Style parent) {
    final tag = element.localName ?? '';
    final declared = <String, String>{
      // LibreOffice centres a paragraph with `align` beside a stylesheet
      // that says `p { text-align: start }`, and means the attribute.
      ..._defaults(tag, parent),
      ...sheet.match(element),
      ..._attributes(element),
      ..._Sheet.declarations(element.attributes['style']),
    };
    _expand(declared);
    final values = <String, String>{
      for (final key in _inherited) key: ?parent.values[key],
    };
    for (final entry in declared.entries) {
      values[entry.key] = entry.value;
    }
    // Relative sizes are relative to the parent's.
    final size = declared['font-size'];
    if (size != null) {
      final resolved = _fontSize(size, parent.fontSize);
      if (resolved != null) values['font-size'] = '${resolved}pt';
    }
    final decorations = {...parent.decorations};
    final decoration =
        declared['text-decoration-line'] ?? declared['text-decoration'];
    if (decoration != null) {
      if (decoration.contains('underline')) decorations.add('underline');
      if (decoration.contains('line-through')) decorations.add('line-through');
    }
    var background = parent.background;
    final paint = _color(declared['background-color']);
    if (declared.containsKey('background-color')) {
      // A white box is the page, not a highlight.
      background = paint == null || paint == '#ffffff' ? background : paint;
      if (declared['background-color']!.contains('transparent')) {
        background = parent.background;
      }
    }
    final align = declared['vertical-align'];
    final script = align == 'super' || align == 'sub'
        ? align
        : align == 'baseline'
        ? null
        : parent.script;
    return _Style(values, decorations, background, script);
  }

  /// What a browser draws an element with before any stylesheet.
  Map<String, String> _defaults(String tag, _Style parent) => switch (tag) {
    'b' || 'strong' || 'th' => {'font-weight': 'bold'},
    'i' ||
    'em' ||
    'cite' ||
    'var' ||
    'dfn' ||
    'address' => {'font-style': 'italic'},
    'u' || 'ins' => {'text-decoration': 'underline'},
    's' || 'strike' || 'del' => {'text-decoration': 'line-through'},
    'sup' => {'vertical-align': 'super'},
    'sub' => {'vertical-align': 'sub'},
    'mark' => {'background-color': '#ffff00'},
    'small' => {'font-size': 'smaller'},
    'big' => {'font-size': 'larger'},
    'code' || 'kbd' || 'samp' || 'tt' => {'font-family': 'monospace'},
    'pre' => {'font-family': 'monospace', 'white-space': 'pre'},
    'center' => {'text-align': 'center'},
    'h1' => {'font-size': '2em', 'font-weight': 'bold'},
    'h2' => {'font-size': '1.5em', 'font-weight': 'bold'},
    'h3' => {'font-size': '1.17em', 'font-weight': 'bold'},
    'h4' => {'font-weight': 'bold'},
    'h5' => {'font-size': '.83em', 'font-weight': 'bold'},
    'h6' => {'font-size': '.67em', 'font-weight': 'bold'},
    _ => const {},
  };

  /// Presentational attributes, which CSS in the same element overrides.
  Map<String, String> _attributes(dom.Element element) {
    final a = element.attributes;
    return {
      if (a['align'] case final align?) 'text-align': align.toLowerCase(),
      'font-family': ?a['face'],
      'color': ?a['color'],
      'background-color': ?a['bgcolor'],
      if (element.localName == 'font' && a['size'] != null)
        'font-size':
            const {
              '1': '8pt',
              '2': '10pt',
              '3': '12pt',
              '4': '14pt',
              '5': '18pt',
              '6': '24pt',
              '7': '36pt',
            }[a['size']!.trim()] ??
            '12pt',
    };
  }

  /// Shorthands, as the longhands they stand for.
  void _expand(Map<String, String> css) {
    final margin = css.remove('margin');
    if (margin != null) {
      final parts = margin.split(RegExp(r'\s+'));
      final (top, right, bottom, left) = switch (parts.length) {
        1 => (parts[0], parts[0], parts[0], parts[0]),
        2 => (parts[0], parts[1], parts[0], parts[1]),
        3 => (parts[0], parts[1], parts[2], parts[1]),
        _ => (parts[0], parts[1], parts[2], parts[3]),
      };
      css.putIfAbsent('margin-top', () => top);
      css.putIfAbsent('margin-right', () => right);
      css.putIfAbsent('margin-bottom', () => bottom);
      css.putIfAbsent('margin-left', () => left);
    }
    final padding = css.remove('padding');
    if (padding != null) {
      final parts = padding.split(RegExp(r'\s+'));
      css.putIfAbsent(
        'padding-left',
        () => parts.length == 4
            ? parts[3]
            : parts.length > 1
            ? parts[1]
            : parts[0],
      );
      css.putIfAbsent(
        'padding-right',
        () => parts.length > 1 ? parts[1] : parts[0],
      );
    }
    for (final (logical, physical) in const [
      ('margin-inline-start', 'margin-left'),
      ('margin-inline-end', 'margin-right'),
      ('margin-block-start', 'margin-top'),
      ('margin-block-end', 'margin-bottom'),
      ('padding-inline-start', 'padding-left'),
    ]) {
      final value = css.remove(logical);
      if (value != null) css.putIfAbsent(physical, () => value);
    }
    final background = css.remove('background');
    if (background != null) {
      final color =
          RegExp(
                r'(#[0-9a-fA-F]{3,8}|rgba?\([^)]*\)|hsla?\([^)]*\)|\b[a-zA-Z]+\b)',
              )
              .allMatches(background)
              .map((m) => m.group(0)!)
              .firstWhere(
                (c) => _color(c) != null || c == 'transparent',
                orElse: () => '',
              );
      if (color.isNotEmpty) css.putIfAbsent('background-color', () => color);
    }
    final font = css.remove('font');
    if (font != null) {
      // [style] [weight] size[/line-height] family, family…
      final match = RegExp(
        r'''^(.*?)(\d*\.?\d+(?:pt|px|em|rem|%|in|cm|mm)|xx-small|x-small|small|medium|large|x-large|xx-large|smaller|larger)(?:\s*/\s*(\S+))?\s+(.+)$''',
      ).firstMatch(font.trim());
      if (match != null) {
        final lead = match.group(1)!.toLowerCase();
        if (lead.contains('italic') || lead.contains('oblique')) {
          css.putIfAbsent('font-style', () => 'italic');
        }
        if (lead.contains('bold') || RegExp(r'\b[6-9]00\b').hasMatch(lead)) {
          css.putIfAbsent('font-weight', () => 'bold');
        }
        css.putIfAbsent('font-size', () => match.group(2)!);
        if (match.group(3) case final line?) {
          css.putIfAbsent('line-height', () => line);
        }
        css.putIfAbsent('font-family', () => match.group(4)!);
      }
    }
    // Word's own name for a highlight.
    final highlight = css.remove('mso-highlight');
    if (highlight != null) css.putIfAbsent('background-color', () => highlight);
  }

  _Block _blockOf(dom.Element element, _Style style, _Block parent) {
    final tag = element.localName ?? '';
    double length(String key) => _length(style[key], style.fontSize) ?? 0;
    // Browsers put space around paragraphs, headings and quotations unless
    // told otherwise; the office suites always say.
    final declared = {
      ...sheet.match(element),
      ..._Sheet.declarations(element.attributes['style']),
    };
    _expand(declared);
    final defaults =
        producer == _Producer.web &&
        !declared.containsKey('margin-top') &&
        !declared.containsKey('margin-bottom');
    final vertical = defaults
        ? switch (tag) {
            'p' || 'blockquote' || 'dl' || 'pre' => style.fontSize,
            'h1' => style.fontSize * .67,
            'h2' => style.fontSize * .83,
            'h3' || 'h4' => style.fontSize,
            'h5' => style.fontSize * 1.67,
            'h6' => style.fontSize * 2.33,
            _ => 0.0,
          }
        : 0.0;
    final quote = tag == 'blockquote' && !declared.containsKey('margin-left')
        ? 30.0
        : 0.0;
    final ownLeft = tag == 'ul' || tag == 'ol'
        ? 0.0
        : (_length(declared['margin-left'], style.fontSize) ?? 0) +
              (_length(declared['padding-left'], style.fontSize) ?? 0);
    final ownRight = _length(declared['margin-right'], style.fontSize) ?? 0;
    final heading = RegExp(r'^h([1-6])$').firstMatch(tag);
    return _Block(
      style: style,
      left: parent.left + quote + (ownLeft < 0 ? 0 : ownLeft),
      right: parent.right + quote + (ownRight < 0 ? 0 : ownRight),
      before: declared.containsKey('margin-top')
          ? length('margin-top')
          : vertical,
      after: declared.containsKey('margin-bottom')
          ? length('margin-bottom')
          : vertical,
      heading: heading == null ? null : int.parse(heading.group(1)!),
      list: _listOf(element, style, parent),
      explicit: tag != 'div' && tag != 'body' && tag != 'ul' && tag != 'ol',
      cellOf: parent.cellOf,
    );
  }

  _ListItem? _listOf(dom.Element element, _Style style, _Block parent) {
    final tag = element.localName;
    if (tag == 'li') {
      final container = element.parent?.localName;
      final type =
          _listType(style['list-style-type']) ??
          (container == 'ol' ? DocListType.ordered : DocListType.unordered);
      var depth = 0;
      for (var p = element.parent; p != null; p = p.parent) {
        if (p.localName == 'ul' || p.localName == 'ol') depth++;
      }
      final aria = int.tryParse(element.attributes['aria-level'] ?? '');
      return _ListItem(type, ((aria ?? depth) - 1).clamp(0, 8));
    }
    // Word's list paragraphs: the level is in mso-list, the kind in the
    // bullet it writes as text (see _markerText).
    final mso = RegExp(r'level(\d+)').firstMatch(
      _Sheet.declarations(element.attributes['style'])['mso-list'] ?? '',
    );
    if (mso != null) {
      return _ListItem(DocListType.unordered, int.parse(mso.group(1)!) - 1);
    }
    return parent.list;
  }

  static DocListType? _listType(String? value) => switch (value?.trim()) {
    'disc' || 'circle' || 'square' => DocListType.unordered,
    'decimal' ||
    'decimal-leading-zero' ||
    'lower-alpha' ||
    'upper-alpha' ||
    'lower-latin' ||
    'upper-latin' ||
    'lower-roman' ||
    'upper-roman' => DocListType.ordered,
    _ => null,
  };

  void children(dom.Node node, _Style style, _Block block) {
    for (final child in node.nodes) {
      visit(child, style, block);
    }
  }

  void visit(dom.Node node, _Style style, _Block block) {
    if (node is dom.Comment) {
      final data = node.data?.trim() ?? '';
      if (data.startsWith('[if !supportLists]')) {
        _marker = true;
        _markerText.clear();
      } else if (data.startsWith('[endif]') && _marker) {
        _marker = false;
        final marker = _markerText.toString().trim();
        if (RegExp(r'^[\(\[]?([0-9]+|[a-zA-Z]|[ivxlcdmIVXLCDM]+)[\.\)\]]')
            .hasMatch(marker)) {
          _buffer?.listType = DocListType.ordered;
        }
      }
      return;
    }
    if (node is dom.Text) {
      if (_marker) {
        _markerText.write(node.text);
        return;
      }
      text(node.text, style, block);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    if (_marker) {
      _markerText.write(node.text);
      return;
    }
    final s = computed(node, style);
    final msoList = s['mso-list'] ?? '';
    if (s['display'] == 'none' ||
        s['visibility'] == 'hidden' ||
        msoList.contains('Ignore') ||
        tag == 'head') {
      return;
    }
    switch (tag) {
      case 'br':
        // Chrome ends a copy that stops at a paragraph's end with this; it
        // is not a line of the document.
        if (node.classes.contains('Apple-interchange-newline')) return;
        lineBreak(style, block);
        return;
      case 'img':
        image(node, s, block);
        return;
      case 'table':
        flush(interrupted: true);
        final table = _table(node, s, block);
        if (table != null) blocks.add(table);
        return;
      case 'hr':
        flush(interrupted: true);
        return;
    }
    // Word's tab: a span of spaces that counts tabs.
    final tabs = int.tryParse(
      RegExp(r'\d+').stringMatch(s['mso-tab-count'] ?? '') ?? '',
    );
    if (tabs != null && tag == 'span') {
      append('\t' * tabs.clamp(1, 100), s, block);
      return;
    }
    if (_blockTags.contains(tag) || _isBlockDisplay(s['display'])) {
      flush(interrupted: true);
      final inner = _blockOf(node, s, block);
      if (inner.explicit) _buffer = _Buffer(inner, explicit: true);
      children(node, s, inner);
      flush();
      return;
    }
    children(node, s, block);
  }

  static bool _isBlockDisplay(String? display) =>
      display == 'block' || display == 'list-item';

  /// Appends text as a browser would draw it: white space collapses unless
  /// the element keeps it, a non-breaking space is always a space.
  void text(String value, _Style style, _Block block) {
    final mode = style['white-space'] ?? 'normal';
    final keep = mode.startsWith('pre') || mode == 'break-spaces';
    var out = value;
    if (!keep) {
      // A tab LibreOffice writes into HTML is a tab it means, unless it
      // follows a line break in the source, where LibreOffice indents its
      // own markup; every other HTML writer puts only indentation there.
      out = producer == _Producer.libreOffice
          ? out
                .replaceAll(RegExp(r'[\r\n\f][ \t\r\n\f]*'), ' ')
                .replaceAll(RegExp(r' +'), ' ')
          : out.replaceAll(RegExp(r'[ \t\r\n\f]+'), ' ');
      out = out.replaceAll(RegExp(r' ?\t ?'), '\t');
      // A space after a space, or at the start of a line, is not drawn.
      final written = _buffer?.text.toString() ?? '';
      if ((written.isEmpty ||
              written.endsWith(' ') ||
              written.endsWith('\n')) &&
          out.startsWith(' ')) {
        out = out.substring(1);
      }
    } else if (mode == 'pre-line') {
      out = out.replaceAll(RegExp(r'[ \t]+'), ' ');
    }
    if (keep || mode == 'pre-line') {
      out = out.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    }
    if (out.isEmpty) return;
    append(out, style, block);
  }

  /// `<br>`: a new line in the same paragraph. The model writes it '\n';
  /// the editor draws it as Word does (see [DocDeltaMap]).
  void lineBreak(_Style style, _Block block) {
    _ensure(block);
    _buffer!.text.write('\n');
  }

  void _ensure(_Block block) {
    final buffer = _buffer;
    if (buffer == null || (buffer.block != block && buffer.text.isEmpty)) {
      _buffer = _Buffer(block, explicit: buffer?.explicit ?? false);
      if (buffer != null && buffer.listType != null) {
        _buffer!.listType = buffer.listType;
      }
    }
  }

  void append(String value, _Style style, _Block block) {
    _ensure(block);
    final buffer = _buffer!;
    final start = buffer.text.length;
    buffer.text.write(value);
    buffer.spans.add(
      DocSpan(
        startOffset: start,
        length: value.length,
        bold: _isBold(style['font-weight']),
        italic:
            style['font-style'] == 'italic' || style['font-style'] == 'oblique',
        underline: style.decorations.contains('underline'),
        strikethrough: style.decorations.contains('line-through'),
        fontFamily: _family(style['font-family']),
        fontSize: _length(style['font-size'], 12),
        color: _color(style['color']),
        background: style.background,
        superscript: style.script == 'super',
        subscript: style.script == 'sub',
      ),
    );
  }

  void image(dom.Element element, _Style style, _Block block) {
    final source = element.attributes['src'] ?? '';
    final match = RegExp(
      r'^data:(image/(?:png|jpe?g|gif|bmp|webp));base64,(.+)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(source.trim());
    // Only pictures the HTML carries: nothing is fetched or read from disk.
    if (match == null) return;
    final data = match.group(2)!.replaceAll(RegExp(r'\s'), '');
    try {
      base64Decode(data);
    } on FormatException {
      return;
    }
    double? size(String attribute, String property) {
      final css = _length(style[property], style.fontSize);
      if (css != null) return css;
      final value = double.tryParse(element.attributes[attribute] ?? '');
      return value == null ? null : value * .75;
    }

    flush(interrupted: true);
    blocks.add(
      DocBlock(
        type: DocBlockType.image,
        plainText: '',
        alignment: _alignment(block.style['text-align']),
        imageBase64: data,
        imageMime: match.group(1)!.toLowerCase().replaceAll('jpg', 'jpeg'),
        imageWidth: size('width', 'width'),
        imageHeight: size('height', 'height'),
      ),
    );
  }

  /// Ends the paragraph being filled. [interrupted] when a block starts
  /// inside the element it belongs to: `<li><p>…</p></li>` is one paragraph,
  /// not an empty one for the `li` and another for the `p`.
  void flush({bool interrupted = false}) {
    final buffer = _buffer;
    _buffer = null;
    if (buffer == null) return;
    var value = buffer.text.toString();
    final hasText = value.trim().isNotEmpty;
    if (!hasText) {
      if (interrupted) return;
      // An empty paragraph, or `<div><br></div>`, which an editor in a
      // browser writes for an empty line.
      if (!buffer.explicit && !value.contains('\n')) return;
    }
    // A line's trailing space is not drawn, nor a line break ending a
    // paragraph, nor Word's lone non-breaking space in an empty paragraph.
    final trimmed = value.replaceFirst(RegExp(r'[ \n]+$'), '');
    // A non-breaking space is kept where a plain one would not be drawn;
    // past that it is a space like any other.
    // A line of tabs is kept: it holds the place of a column.
    final blank =
        !trimmed.contains('\t') &&
        trimmed.replaceAll('\u00a0', ' ').trim().isEmpty;
    value = blank ? '' : trimmed.replaceAll('\u00a0', ' ');
    final block = buffer.block;
    final style = block.style;
    final list = block.list;
    final listType = list == null || list.used
        ? DocListType.none
        : buffer.listType ?? list.type;
    if (list != null && hasText) list.used = true;
    final first = _length(style['text-indent'], style.fontSize) ?? 0;
    // A negative first line indent is a hanging one: the other rows start
    // further in, as a Word paragraph with a hanging indent is written.
    final hanging = first < 0 ? (-first).clamp(0.0, block.left) : 0.0;
    blocks.add(
      DocBlock(
        type: listType == DocListType.none
            ? DocBlockType.paragraph
            : DocBlockType.listItem,
        plainText: value,
        spans: [
          for (final s in buffer.spans)
            if (s.startOffset < value.length)
              DocSpan(
                startOffset: s.startOffset,
                length: s.length.clamp(0, value.length - s.startOffset),
                bold: s.bold,
                italic: s.italic,
                underline: s.underline,
                strikethrough: s.strikethrough,
                superscript: s.superscript,
                subscript: s.subscript,
                fontFamily: s.fontFamily,
                fontSize: s.fontSize,
                color: s.color,
                background: s.background,
              ),
        ],
        alignment: _alignment(style['text-align']),
        listType: listType,
        listLevel: list?.level ?? 0,
        styleName: block.heading == null ? null : 'Başlık ${block.heading}',
        // A list item's own paragraph is set by the list; a paragraph after
        // it in the same item continues under its text.
        leftIndent: list != null && listType == DocListType.none
            ? (list.level + 1) * 36.0
            : block.left - hanging,
        rightIndent: block.right,
        firstLineIndent: first < 0 ? 0 : first,
        hanging: hanging,
        spacingBefore: block.before < 0 ? 0 : block.before,
        spacingAfter: block.after < 0 ? 0 : block.after,
        lineSpacing: _lineSpacing(style),
        tabSet: _tabStops(style['tab-stops']),
      ),
    );
  }

  double? _lineSpacing(_Style style) {
    final value = style['line-height']?.trim();
    if (value == null || value == 'normal' || value.isEmpty) return null;
    double? multiple;
    final factor = value.endsWith('%')
        ? double.tryParse(value.substring(0, value.length - 1)) == null
              ? null
              : double.parse(value.substring(0, value.length - 1)) / 100
        : double.tryParse(value);
    if (factor != null) {
      multiple = switch (producer) {
        // Google Docs writes its single spacing as 1.2 and its 1.15 as 1.38.
        _Producer.googleDocs => factor / 1.2,
        // To CSS a factor multiplies the font size, and a single line is
        // about 1.15 of it; Word, LibreOffice and Folio write the number of
        // lines, as their own spacing counts.
        _Producer.web => factor / 1.15,
        _ => factor,
      };
    } else {
      final length = _length(value, style.fontSize);
      // A height in points: against the font's own line, about 1.15 of it.
      if (length != null) multiple = length / (style.fontSize * 1.15);
    }
    if (multiple == null || !multiple.isFinite) return null;
    if ((multiple - 1).abs() < .04 || multiple < 1) return null;
    return (multiple.clamp(1, 4) * 100).round() / 100;
  }

  /// Word's `tab-stops`: lengths from the margin, each after its alignment.
  static String? _tabStops(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final stops = <String>[];
    var align = '0';
    for (final token in value.trim().split(RegExp(r'\s+'))) {
      switch (token.toLowerCase()) {
        case 'left':
          align = '0';
        case 'right':
          align = '1';
        case 'center':
          align = '2';
        case 'decimal':
          align = '4';
        case 'bar':
          align = '5';
        default:
          final position = _length(token, 12);
          if (position != null && position > 0) {
            stops.add('$position:$align:0');
            align = '0';
          }
      }
    }
    return stops.isEmpty ? null : stops.join(',');
  }

  DocBlock? _table(dom.Element element, _Style style, _Block block) {
    final rows = <dom.Element>[
      for (final child in element.children)
        if (child.localName == 'tr')
          child
        else if (const {'thead', 'tbody', 'tfoot'}.contains(child.localName))
          ...child.children.where((r) => r.localName == 'tr'),
    ];
    if (rows.isEmpty) return null;
    var bordered =
        int.tryParse(element.attributes['border'] ?? '') != null &&
        int.parse(element.attributes['border']!) > 0;
    bool visible(String? border) =>
        border != null &&
        !RegExp(r'\b(none|hidden)\b|^0(px|pt)?\b').hasMatch(border.trim()) &&
        border.trim().isNotEmpty;
    final tableStyle = computed(element, style);
    if (visible(tableStyle['border'])) bordered = true;
    List<double>? widths;
    final columns = element.querySelectorAll('col');
    if (columns.isNotEmpty) {
      widths = [
        for (final col in columns)
          _length(
                _Sheet.declarations(col.attributes['style'])['width'] ??
                    col.attributes['width'],
                12,
              ) ??
              0,
      ];
    }
    final docRows = <DocTableRow>[];
    for (final row in rows) {
      final rowStyle = computed(row, tableStyle);
      final cells = <DocTableCell>[];
      final rowWidths = <double>[];
      for (final cell in row.children.where(
        (c) => c.localName == 'td' || c.localName == 'th',
      )) {
        final cellStyle = computed(cell, rowStyle);
        if (visible(cellStyle['border']) ||
            visible(cellStyle['border-top']) ||
            visible(cellStyle['border-bottom']) ||
            visible(cellStyle['border-left'])) {
          bordered = true;
        }
        final inner = _Reader(sheet, producer);
        // The cell's shade is the cell's, not a highlight on its text.
        final contents = _Style(
          cellStyle.values,
          cellStyle.decorations,
          null,
          cellStyle.script,
        );
        final cellBlock = _Block(
          style: contents,
          left: 0,
          right: 0,
          cellOf: cell,
        );
        inner.children(cell, contents, cellBlock);
        inner.flush();
        final width =
            _length(cellStyle['width'], 12) ??
            (double.tryParse(cell.attributes['width'] ?? '') == null
                ? null
                : double.parse(cell.attributes['width']!) * .75);
        rowWidths.add(width ?? 0);
        cells.add(
          DocTableCell(
            blocks: inner.blocks.isEmpty
                ? [DocBlock(plainText: '')]
                : inner.blocks,
            colspan: (int.tryParse(cell.attributes['colspan'] ?? '') ?? 1)
                .clamp(1, 1000),
            rowspan: (int.tryParse(cell.attributes['rowspan'] ?? '') ?? 1)
                .clamp(1, 1000),
            backgroundColor:
                cellStyle.background ?? _color(cellStyle['background-color']),
          ),
        );
      }
      if (widths == null &&
          rowWidths.isNotEmpty &&
          rowWidths.every((w) => w > 0) &&
          cells.every((c) => c.colspan == 1)) {
        widths = rowWidths;
      }
      docRows.add(
        DocTableRow(
          cells: cells,
          isHeader:
              row.children.isNotEmpty &&
              row.children.every((c) => c.localName == 'th'),
        ),
      );
    }
    return DocBlock(
      type: DocBlockType.table,
      plainText: '',
      alignment: _alignment(element.attributes['align'] ?? style['text-align']),
      table: DocTable(
        rows: docRows,
        columnWidths: widths != null && widths.every((w) => w > 0)
            ? widths
            : null,
        bordered: bordered,
      ),
    );
  }

  static DocAlignment _alignment(String? value) => switch (value?.trim()) {
    'center' || 'middle' => DocAlignment.center,
    'right' || 'end' => DocAlignment.right,
    'justify' => DocAlignment.justify,
    _ => DocAlignment.left,
  };
}

class _Buffer {
  _Buffer(this.block, {this.explicit = false});
  final _Block block;
  final bool explicit;
  final text = StringBuffer();
  final spans = <DocSpan>[];

  /// Set from a Word bullet that turned out to be a number.
  DocListType? listType;
}

/// The simple selectors of a stylesheet: `p`, `.class`, `p.class` — what
/// Word, LibreOffice and a copied web page put in theirs.
class _Sheet {
  _Sheet(this.rules);
  final Map<String, Map<String, String>> rules;

  static _Sheet parse(String source) {
    final rules = <String, Map<String, String>>{};
    final clean = source
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll('<!--', '')
        .replaceAll('-->', '');
    // At-rules describe no element: @import and @charset, and those with a
    // block of their own (@font-face, @page, Word's @list, @media).
    final flat = clean
        .replaceAll(RegExp(r'@[a-zA-Z-]+[^{;]*;'), '')
        .replaceAll(
          RegExp(r'@[a-zA-Z-]+[^{;]*\{(?:[^{}]*\{[^{}]*\})*[^{}]*\}'),
          '',
        );
    for (final rule in RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(flat)) {
      final declarations = Map.of(declarationsOf(rule.group(2)));
      for (final selector in rule.group(1)!.split(',')) {
        final key = selector.trim().toLowerCase();
        if (key.isEmpty || key.contains(RegExp(r'[ >+~:\[#*@]'))) continue;
        rules[key] = {...?rules[key], ...declarations};
      }
    }
    return _Sheet(rules);
  }

  Map<String, String> match(dom.Element element) {
    if (rules.isEmpty) return const {};
    final tag = (element.localName ?? '').toLowerCase();
    return {
      ...?rules[tag],
      for (final name in element.classes) ...?rules['.${name.toLowerCase()}'],
      for (final name in element.classes)
        ...?rules['$tag.${name.toLowerCase()}'],
    };
  }

  static final _cache = <String, Map<String, String>>{};

  static Map<String, String> declarations(String? source) {
    if (source == null || source.isEmpty) return const {};
    return _cache.putIfAbsent(source, () => declarationsOf(source));
  }

  static Map<String, String> declarationsOf(String? source) {
    if (source == null || source.isEmpty) return const {};
    final result = <String, String>{};
    for (final part in source.split(';')) {
      final colon = part.indexOf(':');
      if (colon <= 0) continue;
      final key = part.substring(0, colon).trim().toLowerCase();
      final value = part
          .substring(colon + 1)
          .replaceAll(RegExp(r'\s*!important\s*$', caseSensitive: false), '')
          .trim();
      if (key.isNotEmpty && value.isNotEmpty) result[key] = value;
    }
    return result;
  }
}

/// A CSS length in points; [em] is the font size an `em` is against.
double? _length(String? value, double em) {
  if (value == null) return null;
  final match = RegExp(
    r'^\s*(-?\d*\.?\d+)\s*(pt|px|in|cm|mm|pc|em|rem|%|ex|ch)?\s*$',
  ).firstMatch(value.trim().toLowerCase());
  if (match == null) return null;
  final n = double.tryParse(match.group(1)!);
  if (n == null || !n.isFinite) return null;
  return switch (match.group(2)) {
    'pt' => n,
    'px' || null => n * .75,
    'in' => n * 72,
    'cm' => n * 72 / 2.54,
    'mm' => n * 72 / 25.4,
    'pc' => n * 12,
    'em' || 'ch' => n * em,
    'rem' => n * 12,
    'ex' => n * em / 2,
    '%' => n * em / 100,
    _ => null,
  };
}

/// A font size in points, against the parent's for relative ones.
double? _fontSize(String value, double parent) {
  final v = value.trim().toLowerCase();
  final keyword = const {
    'xx-small': 7.0,
    'x-small': 7.5,
    'small': 10.0,
    'medium': 12.0,
    'large': 13.5,
    'x-large': 18.0,
    'xx-large': 24.0,
    'xxx-large': 36.0,
  }[v];
  if (keyword != null) return keyword;
  if (v == 'smaller') return parent / 1.2;
  if (v == 'larger') return parent * 1.2;
  final size = _length(v, parent);
  if (size == null || size <= 0) return null;
  return (size * 100).round() / 100;
}

bool _isBold(String? value) {
  if (value == null) return false;
  final v = value.trim().toLowerCase();
  if (v == 'bold' || v == 'bolder') return true;
  return (int.tryParse(v) ?? 0) >= 600;
}

/// The first family a document can use: CSS lists fallbacks, and a web page
/// starts with names no document font has, like `-apple-system`.
String? _family(String? value) {
  if (value == null) return null;
  const generic = {
    'serif': 'Times New Roman',
    'sans-serif': 'Arial',
    'monospace': 'Courier New',
    'cursive': null,
    'fantasy': null,
    'system-ui': 'Arial',
    'ui-sans-serif': 'Arial',
    'ui-serif': 'Times New Roman',
    'ui-monospace': 'Courier New',
  };
  String? fallback;
  for (final raw in value.split(',')) {
    final name = raw.trim().replaceAll(RegExp(r'''^["']|["']$'''), '').trim();
    if (name.isEmpty) continue;
    final lower = name.toLowerCase();
    if (generic.containsKey(lower)) {
      fallback ??= generic[lower];
      continue;
    }
    if (lower.startsWith('-') ||
        lower == 'blinkmacsystemfont' ||
        lower.contains('emoji') ||
        lower == 'inherit' ||
        lower == 'initial') {
      continue;
    }
    return name;
  }
  return fallback;
}

/// A colour as the editor stores it, `#rrggbb`; null for no colour.
String? _color(String? value) {
  if (value == null) return null;
  final color = value.trim().toLowerCase();
  if (RegExp(r'^#[0-9a-f]{6}$').hasMatch(color)) return color;
  if (RegExp(r'^#[0-9a-f]{8}$').hasMatch(color)) {
    return color.endsWith('00') ? null : color.substring(0, 7);
  }
  if (RegExp(r'^#[0-9a-f]{3,4}$').hasMatch(color)) {
    if (color.length == 5 && color.endsWith('0')) return null;
    return '#${color.substring(1, 4).split('').map((c) => '$c$c').join()}';
  }
  final function = RegExp(r'^(rgba?|hsla?)\(([^)]+)\)$').firstMatch(color);
  if (function != null) {
    final parts = function
        .group(2)!
        .split(RegExp(r'[,\s/]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length < 3 || parts.length > 4) return null;
    if (parts.length == 4) {
      final alpha = parts[3].endsWith('%')
          ? (double.tryParse(parts[3].replaceAll('%', '')) ?? 100) / 100
          : double.tryParse(parts[3]) ?? 1;
      if (alpha == 0) return null;
    }
    List<int>? rgb;
    if (function.group(1)!.startsWith('rgb')) {
      rgb = [];
      for (final part in parts.take(3)) {
        final n = double.tryParse(part.replaceAll('%', ''));
        if (n == null || !n.isFinite) return null;
        rgb.add((part.endsWith('%') ? n * 2.55 : n).round().clamp(0, 255));
      }
    } else {
      final h = (double.tryParse(parts[0].replaceAll('deg', '')) ?? 0) % 360;
      final s = (double.tryParse(parts[1].replaceAll('%', '')) ?? 0) / 100;
      final l = (double.tryParse(parts[2].replaceAll('%', '')) ?? 0) / 100;
      final c = (1 - (2 * l - 1).abs()) * s;
      final x = c * (1 - ((h / 60) % 2 - 1).abs());
      final m = l - c / 2;
      final (r, g, b) = h < 60
          ? (c, x, 0.0)
          : h < 120
          ? (x, c, 0.0)
          : h < 180
          ? (0.0, c, x)
          : h < 240
          ? (0.0, x, c)
          : h < 300
          ? (x, 0.0, c)
          : (c, 0.0, x);
      rgb = [
        for (final v in [r, g, b]) ((v + m) * 255).round().clamp(0, 255),
      ];
    }
    return '#${rgb.map((c) => c.toRadixString(16).padLeft(2, '0')).join()}';
  }
  return _named[color];
}

const _named = {
  'black': '#000000',
  'white': '#ffffff',
  'red': '#ff0000',
  'green': '#008000',
  'blue': '#0000ff',
  'yellow': '#ffff00',
  'gray': '#808080',
  'grey': '#808080',
  'silver': '#c0c0c0',
  'maroon': '#800000',
  'purple': '#800080',
  'fuchsia': '#ff00ff',
  'magenta': '#ff00ff',
  'lime': '#00ff00',
  'olive': '#808000',
  'navy': '#000080',
  'teal': '#008080',
  'aqua': '#00ffff',
  'cyan': '#00ffff',
  'orange': '#ffa500',
  'darkred': '#8b0000',
  'darkblue': '#00008b',
  'darkgreen': '#006400',
  'darkgray': '#a9a9a9',
  'darkgrey': '#a9a9a9',
  'lightgray': '#d3d3d3',
  'lightgrey': '#d3d3d3',
  'brown': '#a52a2a',
  'pink': '#ffc0cb',
  'gold': '#ffd700',
  'violet': '#ee82ee',
  'indigo': '#4b0082',
  'crimson': '#dc143c',
  'darkorange': '#ff8c00',
  'lightblue': '#add8e6',
  'lightgreen': '#90ee90',
  'lightyellow': '#ffffe0',
  'rebeccapurple': '#663399',
  // Word's highlight names.
  'darkcyan': '#008b8b',
  'darkmagenta': '#8b008b',
  'darkyellow': '#808000',
};
