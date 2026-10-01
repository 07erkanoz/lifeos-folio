import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Synthetic OOXML with cross-sheet formulas, styles, a drawing and date cells.
Uint8List xlsxFixture({bool protected = false, bool signed = false}) {
  const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const rel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  final parts = <String, String>{
    '[Content_Types].xml': '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/xl/calcChain.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.calcChain+xml"/></Types>',
    'xl/workbook.xml':
        '<workbook xmlns="$ns" xmlns:r="$rel"><sheets><sheet name="Hesaplar" sheetId="1" r:id="r1"/><sheet name="Notlar" sheetId="2" r:id="r2"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels':
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="r1" Type="$rel/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="r2" Type="$rel/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="r3" Type="$rel/calcChain" Target="calcChain.xml"/></Relationships>',
    'xl/sharedStrings.xml':
        '<sst xmlns="$ns"><si><r><t>Erkan </t></r><r><t>ÖZ</t></r></si></sst>',
    'xl/styles.xml':
        '<styleSheet xmlns="$ns"><fonts count="2"><font/><font><b/><color rgb="FF103020"/></font></fonts><fills count="2"><fill/><fill><patternFill patternType="solid"><fgColor rgb="FFE1F0E8"/></patternFill></fill></fills><cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0"/><xf numFmtId="0" fontId="1" fillId="1"/><xf numFmtId="14" fontId="0" fillId="0"/><xf numFmtId="10" fontId="0" fillId="0"/></cellXfs></styleSheet>',
    'xl/worksheets/sheet1.xml':
        '<worksheet xmlns="$ns"><dimension ref="A1:D4"/><sheetData><row r="1"><c r="A1" t="s" s="1"><v>0</v></c><c r="B1"><v>12</v></c><c r="C1"><f>B1*2</f><v>24</v></c></row><row r="2"><c r="A2" s="2"><v>46023</v></c><c r="B2" s="3"><v>0.125</v></c></row><row r="3"><c r="A3"><f t="array" ref="A3:A4">B1:B2*2</f><v>24</v></c></row></sheetData>${protected ? '<sheetProtection sheet="1"/>' : ''}<mergeCells><mergeCell ref="C3:D3"/></mergeCells><drawing xmlns:r="$rel" r:id="drawing1"/></worksheet>',
    'xl/worksheets/sheet2.xml':
        '<worksheet xmlns="$ns"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>İhtiyati haciz değerlendirmesi</t></is></c><c r="B1"><f>Hesaplar!B1+1</f><v>13</v></c></row></sheetData></worksheet>',
    'xl/calcChain.xml': '<calcChain xmlns="$ns"><c r="C1" i="1"/></calcChain>',
    'xl/drawings/drawing1.xml':
        '<drawing>Preserve original drawing content</drawing>',
    'docProps/custom.xml': '<properties>Original metadata</properties>',
    if (signed) '_xmlsignatures/sig1.xml': '<Signature/>',
  };
  final archive = Archive();
  for (final part in parts.entries) {
    final data = utf8.encode(part.value);
    archive.addFile(ArchiveFile(part.key, data.length, data));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
