import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:xml/xml.dart';

import '../../models/document_model.dart';
import '../../models/evrak_file.dart';
import '../html/html_reader.dart';

/// Offline content preview. No scripts, CSS execution, remote resources or links.
class StructuredReader {
  static DocModel read(({Uint8List bytes, EvrakFormat format}) request) {
    if (request.format == EvrakFormat.odt) return _odt(request.bytes);
    var source = utf8.decode(request.bytes);
    if (request.format == EvrakFormat.markdown) {
      source = md.markdownToHtml(
        source,
        extensionSet: md.ExtensionSet.gitHubFlavored,
      );
    }
    return _html(source);
  }

  /// Clipboard context can contain unselected text and ancestor style rules.
  /// Keep the ancestor elements and stylesheet, but only the selected content.
  static DocModel clipboardHtml(String source) =>
      HtmlReader.read(source, clipboard: true);

  static DocModel _html(String source) {
    final model = HtmlReader.read(source);
    return DocModel(
      blocks: model.blocks,
      metadata: {
        ...model.metadata,
        'previewNote': 'İçerik önizlemesi • Harici kaynaklar yüklenmez; özgün web sayfası düzeni uygulanmaz.',
      },
    );
  }

  static DocModel _odt(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.findFile('content.xml');
    if (file == null) {
      throw const FormatException('ODT content.xml bulunamadı.');
    }
    final doc = XmlDocument.parse(utf8.decode(file.content));
    final textRoot = doc.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.qualified == 'office:text')
        .firstOrNull;
    if (textRoot == null) {
      throw const FormatException('ODT metin gövdesi bulunamadı.');
    }
    final styles = <String, Map<String, String>>{};
    final roots = [doc];
    final styleFile = archive.findFile('styles.xml');
    if (styleFile != null) {
      roots.add(XmlDocument.parse(utf8.decode(styleFile.content)));
    }
    for (final root in roots) {
      for (final e in root.descendants.whereType<XmlElement>().where(
        (e) => e.name.qualified == 'style:style',
      )) {
        styles[e.getAttribute('style:name') ?? ''] = {
          for (final p in e.childElements)
            for (final a in p.attributes) a.name.qualified: a.value,
          'parent': e.getAttribute('style:parent-style-name') ?? '',
        };
      }
    }
    Map<String, String> resolve(String? name, [Set<String>? seen]) {
      if (name == null || !styles.containsKey(name)) return {};
      final visited = {...?seen};
      if (!visited.add(name)) return {};
      final attrs = styles[name]!;
      return {...resolve(attrs['parent'], visited), ...attrs};
    }

    DocBlock paragraph(XmlElement el) {
      final text = StringBuffer();
      final spans = <DocSpan>[];
      void walk(XmlNode node, Map<String, String> style) {
        if (node is XmlText) {
          final start = text.length;
          text.write(node.value);
          spans.add(
            DocSpan(
              startOffset: start,
              length: node.value.length,
              bold: style['fo:font-weight'] == 'bold',
              italic: style['fo:font-style'] == 'italic',
              underline: style['style:text-underline-style'] == 'solid',
              fontFamily:
                  style['fo:font-family']?.replaceAll("'", '') ??
                  style['style:font-name'],
              fontSize: double.tryParse(
                (style['fo:font-size'] ?? '').replaceAll('pt', ''),
              ),
              color: style['fo:color'],
            ),
          );
        } else if (node is XmlElement) {
          if (node.name.qualified == 'text:s') {
            text.write(
              ' ' *
                  (int.tryParse(node.getAttribute('text:c') ?? '') ?? 1).clamp(
                    1,
                    10000,
                  ),
            );
            return;
          }
          if (node.name.qualified == 'text:tab') {
            text.write('\t');
            return;
          }
          if (node.name.qualified == 'text:line-break') {
            text.write('\n');
            return;
          }
          final merged = {
            ...style,
            ...resolve(node.getAttribute('text:style-name')),
          };
          for (final child in node.children) {
            walk(child, merged);
          }
        }
      }

      walk(el, {});
      return DocBlock(plainText: text.toString(), spans: spans);
    }

    final blocks = <DocBlock>[];
    void visit(XmlElement el) {
      if (['text:p', 'text:h'].contains(el.name.qualified)) {
        blocks.add(paragraph(el));
        return;
      }
      if (el.name.qualified == 'table:table') {
        blocks.add(
          DocBlock(
            type: DocBlockType.table,
            plainText: '',
            table: DocTable(
              rows: [
                for (final row in el.childElements.where(
                  (e) => e.name.local == 'table-row',
                ))
                  DocTableRow(
                    cells: [
                      for (final cell in row.childElements.where(
                        (e) => e.name.local == 'table-cell',
                      ))
                        DocTableCell(
                          blocks: [
                            for (final p in cell.childElements.where(
                              (e) => ['p', 'h'].contains(e.name.local),
                            ))
                              paragraph(p),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
        return;
      }
      for (final child in el.childElements) {
        visit(child);
      }
    }

    visit(textRoot);
    return DocModel(
      blocks: blocks,
      metadata: {
        'previewNote': 'ODT içerik önizlemesi • Temel metin, biçim ve tablolar; gelişmiş sayfa düzeni ve gömülü nesneler desteklenmez.',
      },
    );
  }
}
