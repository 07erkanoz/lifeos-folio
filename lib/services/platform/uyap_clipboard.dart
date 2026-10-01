import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../../models/document_model.dart';
import '../udf/udf_reader.dart';

/// UYAP exports styled selections as a Java serialization stream, not HTML.
/// This decoder reads data only: no JVM, class loading or readObject execution.
///
/// The stream is Swing's own description of the selection: a list of element
/// specs opening and closing the same elements a UDF file stores — paragraph,
/// table, row, cell — with runs of text between them, each carrying the
/// attribute set UYAP holds for it. Measured on whole documents copied out of
/// UYAP's own editor, it has everything the file has: tab stops on a third
/// of the paragraphs, hanging indents, lists, tables and the e-signature
/// image. So the specs are laid out as a UDF's `<elements>` and read by
/// [UdfReader]; a paste from UYAP and the same document opened as a file come
/// out the same.
abstract final class UyapClipboard {
  static DocModel read(Uint8List bytes) {
    final root = _Stream(bytes).read();
    if (root is! _Object || !root.name.endsWith('.EditorDataFlavor')) {
      throw const FormatException('UYAP pano biçimi tanınmadı.');
    }
    final list = root.fields['elementSpecList'];
    if (list is! _Object) {
      throw const FormatException('UYAP metin parçaları yok.');
    }
    final resolved = <_Object, Map<String, Object?>>{};
    Map<String, Object?> attributes(Object? value) => value is _Object
        ? resolved.putIfAbsent(value, () => _attributes(value))
        : const {};

    final text = StringBuffer();
    final elements = XmlElement(XmlName.qualified('elements'));
    // What is open, innermost last, with the attributes each was opened with:
    // Swing looks up whatever a run does not say in the paragraph around it.
    final open = <(XmlElement, Map<String, Object?>)>[(elements, const {})];
    // The selection began inside a paragraph, so the list does not open it;
    // its attributes travel beside the list.
    Map<String, Object?>? implied = attributes(root.fields['startParAttr']);

    void start(String name, Map<String, Object?> attrs) {
      // A row or a cell whose table began before the selection still needs
      // one around it, or nothing reads what is in it.
      final parent = open.last.$1.name.local;
      if (name == 'row' && parent != 'table') start('table', const {});
      if (name == 'cell' && open.last.$1.name.local != 'row') {
        start('row', const {});
      }
      if (name == 'paragraph' && parent == 'row') start('cell', const {});
      final element = _element(name, attrs);
      open.last.$1.children.add(element);
      open.add((element, attrs));
    }

    void run(String name, Map<String, Object?> attrs, String value) {
      if (open.last.$1.name.local != 'paragraph') {
        start('paragraph', implied ?? const {});
      }
      implied = null;
      final paragraph = open.last.$2;
      final leaf = _element(name, {
        for (final entry in paragraph.entries)
          if (_character.contains(entry.key)) entry.key: entry.value,
        ...attrs,
      });
      leaf
        ..setAttribute('startOffset', '${text.length}')
        ..setAttribute('length', '${value.length}');
      text.write(value);
      open.last.$1.children.add(leaf);
    }

    for (final spec in list.annotations.expand((a) => a).whereType<_Object>()) {
      if (!spec.name.endsWith(r'$SerializableElementSpec')) continue;
      // Swing's JoinPreviousDirection. UYAP ends a selection that stops in or
      // after a table with a paragraph holding one space in this direction,
      // telling its own paste to join it to what precedes; the space is not
      // part of what was selected. It is the only place the direction occurs
      // across 125 whole documents copied out of UYAP.
      if (spec.fields['direction'] == 4) continue;
      final attrs = attributes(spec.fields['attrs']);
      final name = attrs[r'$ename'];
      switch (spec.fields['type']) {
        case 1:
          implied = null;
          start(name is String ? name : 'paragraph', attrs);
        case 2:
          // An end tag for something opened before the selection began.
          implied = null;
          if (open.length > 1) open.removeLast();
        case 3:
          final chars = spec.fields['text'];
          if (chars is! List) continue;
          final offset = spec.fields['offset'] as int? ?? 0;
          final length = spec.fields['length'] as int? ?? 0;
          if (offset < 0 || length < 0 || offset + length > chars.length) {
            throw const FormatException('Geçersiz UYAP metin aralığı.');
          }
          final value = String.fromCharCodes(
            chars.cast<int>(),
            offset,
            offset + length,
          ).replaceAll('\r\n', '\n');
          run(name is String ? name : 'content', attrs, value);
      }
    }
    final content = text.toString();
    final blocks = UdfReader.readElements(elements, content);
    if (blocks.isEmpty) {
      throw const FormatException('UYAP panosunda metin yok.');
    }
    return DocModel(
      blocks: blocks,
      metadata: {
        // A line break inside a paragraph is drawn as nothing by UYAP, and
        // the editor draws a UDF's the same way (see [DocDeltaMap]); what is
        // pasted from UYAP is read as the file would be.
        'formatId': 'uyap',
        // Whether the copy stopped before the last paragraph's end: the
        // paragraph it stopped in then carries on into the one it is pasted
        // into, as it would in UYAP.
        'openEnd': !content.endsWith('\n'),
      },
    );
  }

  /// Run attributes Swing resolves through the paragraph when the run has no
  /// value of its own.
  static const _character = {
    'family',
    'size',
    'bold',
    'italic',
    'underline',
    'strikethrough',
    'superscript',
    'subscript',
    'foreground',
    'background',
  };

  static final _name = RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$');

  /// An element as a UDF writes it: every attribute as text, colours as
  /// Swing's packed integer and tab stops as `position:alignment:leader`.
  static XmlElement _element(String name, Map<String, Object?> attrs) {
    final element = XmlElement(XmlName.qualified(name));
    for (final MapEntry(:key, :value) in attrs.entries) {
      if (!_name.hasMatch(key)) continue;
      final text = switch (value) {
        bool() || int() || double() || String() => '$value',
        _Object(name: 'java.awt.Color') => '${value.fields['value']}',
        _Object(name: 'javax.swing.text.TabSet') => _tabSet(value),
        _ => null,
      };
      if (text != null) element.setAttribute(key, text);
    }
    return element;
  }

  static String? _tabSet(_Object value) {
    final tabs = value.fields['tabs'];
    if (tabs is! List) return null;
    return [
      for (final tab in tabs.whereType<_Object>())
        '${tab.fields['position']}:${tab.fields['alignment']}:'
            '${tab.fields['leader']}',
    ].join(',');
  }

  static Map<String, Object?> _attributes(Object? value, [Set<_Object>? seen]) {
    if (value is! _Object) return {};
    seen ??= {};
    if (!seen.add(value)) return {};
    final result = <String, Object?>{};
    for (final data in value.annotations) {
      // StyleContext writes an attribute count as block data followed by pairs.
      final objects = data.where((v) => v is! Uint8List).toList();
      for (var i = 0; i + 1 < objects.length; i += 2) {
        final key = objects[i];
        if (key is! String) continue;
        final name = key.startsWith('javax.swing.text.')
            ? key.split('.').last
            : key;
        var item = objects[i + 1];
        if (name == 'resolver') {
          // A named style: what it sets applies where the set says nothing,
          // and its name is what a UDF writes as the paragraph's resolver.
          final parent = _attributes(item, seen);
          for (final entry in parent.entries) {
            if (entry.key == 'name' || entry.key == 'resolver') continue;
            result.putIfAbsent(entry.key, () => entry.value);
          }
          if (parent['name'] case final String style) {
            result['resolver'] = style;
          }
        } else {
          if (item is _Object && _boxed.contains(item.name)) {
            item = item.fields['value'];
          }
          result[name] = item;
        }
      }
    }
    return result;
  }

  static const _boxed = {
    'java.lang.Integer',
    'java.lang.Long',
    'java.lang.Short',
    'java.lang.Byte',
    'java.lang.Float',
    'java.lang.Double',
    'java.lang.Boolean',
  };

  /// The shortest decimal that reads back as the same 32-bit float, which is
  /// what Java writes for it: UYAP stores a first line indent as 33.57143,
  /// and the float behind it is 33.57143020629883 as a double.
  static double _float(double value) {
    if (!value.isFinite) return value;
    final box = Float32List(1);
    for (var digits = 1; digits <= 9; digits++) {
      final shortest = double.parse(value.toStringAsPrecision(digits));
      box[0] = shortest;
      if (box[0] == value) return shortest;
    }
    return value;
  }
}

class _Object {
  _Object(this.name);
  final String name;
  final fields = <String, Object?>{};
  final annotations = <List<Object?>>[];
}

class _Class {
  _Class(this.name);
  final String name;
  int flags = 0;
  final fields = <(String, String)>[];
  _Class? parent;
}

class _Stream {
  _Stream(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;
  final handles = <Object?>[];
  int at = 0, depth = 0;
  Never bad() => throw const FormatException('Geçersiz UYAP pano verisi.');
  int take(int count) {
    if (count < 0 || at + count > bytes.length) bad();
    final start = at;
    at += count;
    return start;
  }

  int u8() => data.getUint8(take(1));
  int u16() => data.getUint16(take(2));
  int i32() => data.getInt32(take(4));
  T remember<T>(T value) {
    // Every new handle takes at least one byte of the stream, so the stream
    // bounds them; a whole court decision copied out of UYAP has well over
    // a hundred thousand.
    if (handles.length > bytes.length) bad();
    handles.add(value);
    return value;
  }

  String utf(int length) {
    final end = take(length) + length;
    var pos = end - length;
    final units = <int>[];
    while (pos < end) {
      final b = bytes[pos++];
      if (b < 128) {
        units.add(b);
      } else if ((b & 0xe0) == 0xc0 && pos < end) {
        units.add(((b & 31) << 6) | (bytes[pos++] & 63));
      } else if ((b & 0xf0) == 0xe0 && pos + 1 < end) {
        units.add(
          ((b & 15) << 12) | ((bytes[pos++] & 63) << 6) | (bytes[pos++] & 63),
        );
      } else {
        bad();
      }
    }
    return String.fromCharCodes(units);
  }

  Object? read() {
    if (bytes.length > 32 * 1024 * 1024 || u16() != 0xaced || u16() != 5) bad();
    return value();
  }

  Object? primitive(String kind) => switch (kind) {
    'Z' => u8() != 0,
    'B' => data.getInt8(take(1)),
    'C' => u16(),
    'S' => data.getInt16(take(2)),
    'I' => i32(),
    'J' => data.getInt64(take(8)),
    'F' => UyapClipboard._float(data.getFloat32(take(4))),
    'D' => data.getFloat64(take(8)),
    'L' || '[' => value(),
    _ => bad(),
  };
  List<Object?> annotation() {
    final result = <Object?>[];
    while (at < bytes.length && bytes[at] != 0x78) {
      result.add(value());
    }
    if (u8() != 0x78) bad();
    return result;
  }

  Object? value() {
    if (++depth > 128) bad();
    try {
      switch (u8()) {
        case 0x70:
          return null;
        case 0x71:
          final index = i32() - 0x7e0000;
          if (index < 0 || index >= handles.length) bad();
          return handles[index];
        case 0x74:
          return remember(utf(u16()));
        case 0x7c:
          return remember(utf(data.getInt64(take(8))));
        case 0x72:
          final name = utf(u16());
          take(8);
          final type = remember(_Class(name))..flags = u8();
          final count = u16();
          for (var i = 0; i < count; i++) {
            final kind = String.fromCharCode(u8());
            final field = utf(u16());
            if (kind == 'L' || kind == '[') value();
            type.fields.add((kind, field));
          }
          annotation();
          type.parent = value() as _Class?;
          return type;
        case 0x73:
          final type = value();
          if (type is! _Class) bad();
          final object = remember(_Object(type.name));
          final hierarchy = <_Class>[];
          for (_Class? t = type; t != null; t = t.parent) {
            hierarchy.add(t);
          }
          for (final t in hierarchy.reversed) {
            if (t.flags & 4 != 0) bad(); // Externalizable is not supported.
            for (final (kind, field) in t.fields) {
              object.fields[field] = primitive(kind);
            }
            if (t.flags & 1 != 0) object.annotations.add(annotation());
          }
          return object;
        case 0x75:
          final type = value();
          if (type is! _Class || !type.name.startsWith('[')) bad();
          final list = remember(<Object?>[]);
          final count = i32();
          if (count < 0 || count > bytes.length) bad();
          for (var i = 0; i < count; i++) {
            list.add(primitive(type.name[1]));
          }
          return list;
        case 0x77:
          final count = u8();
          final start = take(count);
          return Uint8List.sublistView(bytes, start, start + count);
        case 0x7a:
          final count = i32();
          final start = take(count);
          return Uint8List.sublistView(bytes, start, start + count);
        case 0x76:
          return remember(value());
        case 0x7e:
          final type = value();
          if (type is! _Class) bad();
          final object = remember(_Object(type.name));
          object.fields['name'] = value();
          return object;
        default:
          bad();
      }
    } finally {
      depth--;
    }
  }
}
