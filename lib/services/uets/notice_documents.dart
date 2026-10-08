import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../pdf/pdf_pages.dart';
import '../portal/portal_database.dart';
import '../search/text_extractor.dart';

/// The reader's version: raised whenever how a document is read changes,
/// so that every package kept is read again (the audit's B21).
const noticeReaderVersion = 1;

/// A document of a notice's package as Folio read it (the audit's B01,
/// B02, B24, B25): what it is, where, its digest and how its text came.
class NoticeDocument {
  final String noticeId;

  /// Its place in the package, from 0.
  final int seq;
  final String name;
  final String path;

  /// The notice's list's part it is, when its name tells; null otherwise.
  final String? partId;

  /// SHA-256 of its bytes; empty when it could not be read.
  final String digest;

  /// 'okundu' (its text layer), 'ocr' (read from its pictures), 'kismi'
  /// (part of it), 'metinYok' (no text in it), 'okunamadi' (it would not
  /// open), 'kayip' (the file is gone) or 'ustveri' (the package's own
  /// description of the case, read as data: see [NoticeCaseFile]).
  final String state;

  /// Its text; for 'ustveri', the [NoticeCaseFile] as JSON.
  final String text;

  /// Why it is as it is, for the lawyer.
  final String? note;
  final int reader;
  final DateTime readAt;

  const NoticeDocument({
    required this.noticeId,
    required this.seq,
    required this.name,
    required this.path,
    this.partId,
    required this.digest,
    required this.state,
    this.text = '',
    this.note,
    required this.reader,
    required this.readAt,
  });

  /// Its text was read, whole or by OCR, or it is the case's description.
  bool get read => state == 'okundu' || state == 'ocr' || state == 'ustveri';

  /// A document whose text is there to look in for deadlines.
  bool get hasText =>
      (state == 'okundu' || state == 'ocr' || state == 'kismi') &&
      text.trim().isNotEmpty;

  NoticeCaseFile? get caseFile =>
      state == 'ustveri' ? NoticeCaseFile.fromJson(text) : null;
}

/// `dosyaBilgileriV1.xml`, which every UETS package carries: the unit the
/// notice comes from with UYAP's own ids, the case's number and kind, and
/// its parties by name and role (no lawyers).
class NoticeCaseFile {
  final String unitId;
  final String unitName;
  final String province;
  final String district;
  final String detsis;
  final String number;
  final String kind;
  final List<({String name, String role, bool institution})> parties;

  const NoticeCaseFile({
    this.unitId = '',
    this.unitName = '',
    this.province = '',
    this.district = '',
    this.detsis = '',
    this.number = '',
    this.kind = '',
    this.parties = const [],
  });

  /// [xml] read; null when it is not such a file.
  static NoticeCaseFile? parse(String xml) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } on XmlException {
      return null;
    }
    String first(XmlElement? at, String name) =>
        at?.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local.toLowerCase() == name.toLowerCase())
            .firstOrNull
            ?.innerText
            .trim() ??
        '';
    final root = doc.rootElement;
    if (root.name.local.toLowerCase() != 'dosyabilgileri' &&
        root.descendants.whereType<XmlElement>().every(
          (e) => e.name.local.toLowerCase() != 'dosyabilgileri',
        )) {
      return null;
    }
    final unit = root.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'birim')
        .firstOrNull;
    return NoticeCaseFile(
      unitId: first(unit, 'id'),
      unitName: first(unit, 'adi'),
      province: first(unit, 'il'),
      district: first(unit, 'ilce'),
      detsis: first(unit, 'detsisNo'),
      number: first(root, 'dosyano'),
      kind: first(root, 'dosyatur'),
      parties: [
        for (final t in root.descendants.whereType<XmlElement>().where(
          (e) => e.name.local.toLowerCase() == 'taraf',
        ))
          (
            name: first(t, 'tarafadi'),
            role: first(t, 'tarafrolu'),
            institution: first(
              t,
              'kisiMiKurummu',
            ).toLowerCase().contains('kurum'),
          ),
      ],
    );
  }

  String toJson() => jsonEncode({
    'birimId': unitId,
    'birim': unitName,
    'il': province,
    'ilce': district,
    'detsis': detsis,
    'dosyaNo': number,
    'tur': kind,
    'taraflar': [
      for (final t in parties)
        {'ad': t.name, 'rol': t.role, 'kurum': t.institution},
    ],
  });

  static NoticeCaseFile? fromJson(String json) {
    try {
      final m = jsonDecode(json) as Map;
      return NoticeCaseFile(
        unitId: '${m['birimId'] ?? ''}',
        unitName: '${m['birim'] ?? ''}',
        province: '${m['il'] ?? ''}',
        district: '${m['ilce'] ?? ''}',
        detsis: '${m['detsis'] ?? ''}',
        number: '${m['dosyaNo'] ?? ''}',
        kind: '${m['tur'] ?? ''}',
        parties: [
          for (final t in (m['taraflar'] as List? ?? const []))
            if (t is Map)
              (
                name: '${t['ad'] ?? ''}',
                role: '${t['rol'] ?? ''}',
                institution: t['kurum'] == true,
              ),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// What reading one file gave.
typedef DocumentReading = ({
  String digest,
  String state,
  String text,
  String? note,
});

/// Reads the documents of every notice's package kept on this computer
/// that are not yet read by this [noticeReaderVersion], one at a time,
/// and tells [onRead] of each notice done, for its deadlines to be made
/// again. Packages downloaded before documents were read are read where
/// they are: nothing is fetched again. [read] stands in for the reader in
/// the tests.
Future<void> readNoticeDocuments(
  PortalDatabase db, {
  Future<DocumentReading> Function(String path)? read,
  void Function(String noticeId)? onRead,
  Set<String>? only,
  DateTime? now,
}) async {
  final reader = read ?? readDocumentApart;
  for (final e in db.envelopes().values) {
    if (e.state == 'hata' || e.attachments.isEmpty) continue;
    if (only != null && !only.contains(e.noticeId)) continue;
    final kept = db.noticeDocuments(e.noticeId);
    if (kept.length == e.attachments.length &&
        kept.every((d) => d.reader == noticeReaderVersion) &&
        [for (final d in kept) d.path].join('\n') ==
            [for (final a in e.attachments) a.path].join('\n')) {
      continue;
    }
    final parts = db.manifest(e.noticeId).parts;
    final docs = <NoticeDocument>[];
    for (var i = 0; i < e.attachments.length; i++) {
      final a = e.attachments[i];
      final at = now ?? DateTime.now();
      DocumentReading r;
      if (!await File(a.path).exists()) {
        r = (
          digest: '',
          state: 'kayip',
          text: '',
          note: 'Dosya bu bilgisayarda bulunamadı.',
        );
      } else if (p.extension(a.path).toLowerCase() == '.xml') {
        r = await _readCaseFile(a.path);
      } else {
        r = await reader(a.path);
      }
      docs.add(
        NoticeDocument(
          noticeId: e.noticeId,
          seq: i,
          name: a.name,
          path: a.path,
          partId: _partOf(a.name, parts),
          digest: r.digest,
          state: r.state,
          text: r.text,
          note: r.note,
          reader: noticeReaderVersion,
          readAt: at,
        ),
      );
      // The window breathes between documents.
      await Future<void>.delayed(Duration.zero);
    }
    db.saveNoticeDocuments(e.noticeId, docs);
    onRead?.call(e.noticeId);
  }
}

/// The part of the notice's list a document saved as [name] is: the same
/// name, its "(1)" and its extension aside. Null when none or several.
String? _partOf(String name, List<({String id, String name})> parts) {
  String plain(String s) => p
      .basenameWithoutExtension(s.replaceFirst(RegExp(r'^\(\d+\)\s*'), ''))
      .toLowerCase()
      .trim();
  final want = plain(name);
  final found = [
    for (final part in parts)
      if (plain(part.name) == want) part.id,
  ];
  return found.length == 1 ? found.single : null;
}

Future<DocumentReading> _readCaseFile(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final digest = sha256.convert(bytes).toString();
    final file = NoticeCaseFile.parse(utf8.decode(bytes, allowMalformed: true));
    if (file == null) {
      return (
        digest: digest,
        state: 'metinYok',
        text: '',
        note: 'Paketin XML dosyası tanınmadı.',
      );
    }
    return (digest: digest, state: 'ustveri', text: file.toJson(), note: null);
  } catch (e) {
    return (digest: '', state: 'okunamadi', text: '', note: '$e');
  }
}

/// [path] read off the window's isolate: its digest, and its text as the
/// archive reads it (a PDF's text layer, a UDF's paragraphs, a picture or
/// a scan by OCR). PDFium stays with the window's isolate, asked through
/// its host, as the archive's indexer does.
Future<DocumentReading> readDocumentApart(String path) =>
    compute(_readApart, (path: path, pdfium: PdfPagesHost.start()));

Future<DocumentReading> _readApart(
  ({String path, SendPort pdfium}) request,
) async {
  PdfPages.host = request.pdfium;
  final String digest;
  try {
    digest = sha256.convert(await File(request.path).readAsBytes()).toString();
  } catch (e) {
    return (digest: '', state: 'okunamadi', text: '', note: '$e');
  }
  final got = await IndexTextExtractor.extract(request.path, ocr: true);
  final text = '${got['text'] ?? ''}';
  final note = got['note'] as String?;
  final state = switch (got['state']) {
    'ready' when got['ocr'] == true => 'ocr',
    'ready' => 'okundu',
    'partial' => 'kismi',
    'no_text' || 'image' => 'metinYok',
    _ => 'okunamadi',
  };
  return (digest: digest, state: state, text: text, note: note);
}
