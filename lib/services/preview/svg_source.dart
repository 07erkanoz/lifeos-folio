import 'dart:io';

import 'package:xml/xml.dart';

class SvgSource {
  static Future<String> load(String path) async {
    final file = File(path);
    if (await file.length() > 8 * 1024 * 1024) {
      throw const FormatException('SVG önizleme sınırı 8 MB.');
    }
    final source = await file.readAsString();
    final doc = XmlDocument.parse(source);
    if (doc.rootElement.name.local != 'svg') {
      throw const FormatException('Geçerli SVG değil.');
    }
    for (final el in doc.descendants.whereType<XmlElement>().toList()) {
      if (['script', 'foreignObject'].contains(el.name.local)) {
        el.parent?.children.remove(el);
        continue;
      }
      for (final attr in el.attributes.toList()) {
        if (attr.name.local.toLowerCase().startsWith('on')) {
          el.attributes.remove(attr);
        }
        if (attr.name.local == 'href' &&
            !attr.value.startsWith('#') &&
            !attr.value.startsWith('data:image/')) {
          throw const FormatException(
            'Harici dosya/ağ kaynağı kullanan SVG desteklenmiyor.',
          );
        }
      }
    }
    final urls = RegExp(
      r'url\(\s*[\x22\x27]?([^\)\x22\x27]+)[\x22\x27]?\s*\)',
      caseSensitive: false,
    );
    // Inspect decoded attribute values: XML may encode CSS quotes as &quot;.
    final css = doc.descendants
        .whereType<XmlElement>()
        .expand(
          (el) => [
            ...el.attributes.map((attr) => attr.value),
            if (el.name.local == 'style') el.innerText,
          ],
        )
        .join('\n');
    if (css.toLowerCase().contains('@import') ||
        urls.allMatches(css).any((m) => !m.group(1)!.trim().startsWith('#'))) {
      throw const FormatException(
        'Harici CSS kaynağı kullanan SVG desteklenmiyor.',
      );
    }
    return doc.toXmlString();
  }
}
