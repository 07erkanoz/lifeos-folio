import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../fonts/document_fonts.dart';
import '../platform/app_directories.dart';
import 'client.dart';

/// A file kept with a client's record: a power of attorney's scan, the
/// signed minutes. Its digest is kept with it: the same file is the same
/// evidence, wherever it is copied.
typedef ClientFile = ({String name, String path, String sha256});

Map<String, Object?> clientFileJson(ClientFile f) => {
  'ad': f.name,
  'yol': f.path,
  'sha256': f.sha256,
};

List<ClientFile> clientFilesOf(ClientRecord r) => [
  for (final f in r.data['ekler'] is List ? r.data['ekler'] as List : const [])
    if (f is Map && f['yol'] is String)
      (name: '${f['ad']}', path: f['yol'] as String, sha256: '${f['sha256']}'),
];

class ClientFiles {
  ClientFiles({Future<Directory> Function()? root})
    : _root = root ?? _defaultRoot;

  static Future<Directory> _defaultRoot() async =>
      Directory(p.join((await folioSharedDirectory()).path, 'muvekkil'));

  final Future<Directory> Function() _root;

  /// The clients' folder, each client's files in a folder of its id.
  Future<Directory> root() => _root();

  /// A client's id as a folder's name: what another device sends is not
  /// let name a path (no separators, no "..").
  static bool safeId(String id) =>
      RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id);

  /// A file's name as kept: the start of its digest, then its own name, so
  /// that two files of one name are two (content-addressed).
  static String storedName(String sha, String name) {
    final clean = p.basename(name).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    // The whole digest: a part of one could be another file's.
    return '$sha-$clean';
  }

  Future<Directory> _folderOf(String clientId) async {
    if (!safeId(clientId)) throw ArgumentError('müvekkil kimliği: $clientId');
    final root = (await _root()).absolute;
    final folder = Directory(p.join(root.path, clientId));
    if (!p.isWithin(root.path, folder.path)) throw ArgumentError(clientId);
    // A link in place of the client's folder would lead out of the root.
    if (FileSystemEntity.isLinkSync(folder.path)) throw ArgumentError(clientId);
    if (await root.exists() && await folder.exists()) {
      final realRoot = await root.resolveSymbolicLinks();
      final real = await folder.resolveSymbolicLinks();
      if (!p.isWithin(realRoot, real)) throw ArgumentError(clientId);
    }
    return folder;
  }

  /// Where an earlier Folio kept [f] (its own name, no digest), when it is
  /// inside the client's folder.
  Future<File?> _legacy(String clientId, ClientFile f) async {
    try {
      final folder = await _folderOf(clientId);
      final file = File(p.join(folder.path, p.basename(f.path)));
      if (!p.isWithin(folder.path, file.path)) return null;
      return file;
    } catch (_) {
      return null;
    }
  }

  /// [source] copied into [clientId]'s folder, under its digest's name.
  Future<ClientFile> keep(String clientId, String source) async =>
      keepBytes(clientId, p.basename(source), await File(source).readAsBytes());

  /// Where [f] is on this device, in the client's folder, its content its
  /// digest's; null when it is not here (yet: it comes from the device it
  /// was kept on).
  Future<File?> locate(String clientId, ClientFile f) async {
    final File here;
    try {
      here = await placeFor(clientId, f);
    } catch (_) {
      return null;
    }
    for (final file in [here, ?await _legacy(clientId, f)]) {
      if (!await file.exists() || FileSystemEntity.isLinkSync(file.path)) {
        continue;
      }
      final digest = sha256.convert(await file.readAsBytes()).toString();
      if (digest != f.sha256) continue;
      // An earlier Folio's file, moved to where it is kept now.
      if (file.path != here.path) {
        try {
          return await file.rename(here.path);
        } catch (_) {
          return file;
        }
      }
      return file;
    }
    return null;
  }

  /// Where [f] is put when brought from another device.
  Future<File> placeFor(String clientId, ClientFile f) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(f.sha256)) {
      throw ArgumentError('özet: ${f.sha256}');
    }
    final folder = await _folderOf(clientId);
    final file = File(p.join(folder.path, storedName(f.sha256, f.name)));
    if (!p.isWithin(folder.path, file.path)) throw ArgumentError(f.name);
    return file;
  }

  /// [bytes] kept as [name] in [clientId]'s folder.
  Future<ClientFile> keepBytes(
    String clientId,
    String name,
    Uint8List bytes,
  ) async {
    final digest = sha256.convert(bytes).toString();
    final f = (name: p.basename(name), path: '', sha256: digest);
    final target = await placeFor(clientId, f);
    await target.parent.create(recursive: true);
    if (!await target.exists()) await target.writeAsBytes(bytes, flush: true);
    return (
      name: f.name,
      path: p.join(clientId, p.basename(target.path)),
      sha256: digest,
    );
  }

  /// [f] taken off this device, its folder's file alone.
  Future<void> forget(String clientId, ClientFile f) async {
    try {
      // Only a file of this content goes, wherever it lies.
      Future<bool> mine(File file) async =>
          await file.exists() &&
          !FileSystemEntity.isLinkSync(file.path) &&
          sha256.convert(await file.readAsBytes()).toString() == f.sha256;
      final here = await placeFor(clientId, f);
      if (await mine(here)) await here.delete();
      // An earlier Folio's file goes only when it is this one's content: a
      // name another device sent cannot take another record's file.
      final old = await _legacy(clientId, f);
      if (old != null &&
          await old.exists() &&
          !FileSystemEntity.isLinkSync(old.path) &&
          sha256.convert(await old.readAsBytes()).toString() == f.sha256) {
        await old.delete();
      }
    } catch (_) {}
  }
}

/// The minutes of a meeting with a client, to be printed and signed by
/// both (docs/design/muvekkil-taslak): who met when and where, what was
/// talked of, and what was decided, told or allowed, so that none of it
/// is denied later. Its code, the digest of what it says, is printed at
/// its foot.
Future<Uint8List> meetingMinutesPdf({
  required Client client,
  required ClientRecord meeting,
  required String lawyer,
  String caseTitle = '',
  ByteData? regular,
  ByteData? bold,
}) async {
  final font = pw.Font.ttf(
    regular ?? await DocumentFonts.loadFace('Times New Roman', 'Regular'),
  );
  final strong = pw.Font.ttf(
    bold ?? await DocumentFonts.loadFace('Times New Roman', 'Bold'),
  );
  String two(int v) => v.toString().padLeft(2, '0');
  String day(DateTime t) => '${two(t.day)}.${two(t.month)}.${t.year}';
  String time(DateTime t) => '${two(t.hour)}:${two(t.minute)}';
  final start = DateTime.tryParse(meeting.text('baslangic')) ?? meeting.created;
  final end = DateTime.tryParse(meeting.text('bitis'));
  final code = sha256
      .convert(utf8.encode(jsonEncode(meeting.data)))
      .toString()
      .substring(0, 16)
      .toUpperCase();
  final base = pw.TextStyle(font: font, fontSize: 11.5, lineSpacing: 2);
  final head = pw.TextStyle(font: strong, fontSize: 11.5);

  pw.Widget field(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(text: '$label: ', style: head),
          pw.TextSpan(text: value, style: base),
        ],
      ),
    ),
  );

  pw.Widget section(String title, String body) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(height: 10),
      pw.Text(title, style: head),
      pw.SizedBox(height: 4),
      pw.Text(body.trim().isEmpty ? '—' : body.trim(), style: base),
    ],
  );

  pw.Widget signature(String who, String name) => pw.Expanded(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(who, style: head),
        pw.SizedBox(height: 2),
        pw.Text(name, style: base),
        pw.SizedBox(height: 46),
        pw.Container(height: .6, width: 150, color: PdfColors.grey700),
        pw.Text('İmza', style: base.copyWith(fontSize: 9.5)),
      ],
    ),
  );

  final doc = pw.Document(title: 'Müvekkil görüşme tutanağı');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(56, 56, 56, 48),
      footer: (context) => pw.Text(
        'Tutanak kodu $code · yazıldı ${day(meeting.created)} '
        '${time(meeting.created)}:${two(meeting.created.second)} · '
        'sayfa ${context.pageNumber}/${context.pagesCount}',
        style: base.copyWith(fontSize: 8.5, color: PdfColors.grey700),
      ),
      build: (context) => [
        pw.Center(
          child: pw.Text(
            'MÜVEKKİL GÖRÜŞME TUTANAĞI',
            style: head.copyWith(fontSize: 14),
          ),
        ),
        pw.SizedBox(height: 16),
        field(
          'Tarih ve saat',
          '${day(start)} ${time(start)}'
              '${end == null ? '' : ' – ${time(end)}'}',
        ),
        if (meeting.text('yer').isNotEmpty) field('Yer', meeting.text('yer')),
        if (meeting.text('kanal').isNotEmpty)
          field('Görüşme', meeting.text('kanal')),
        field('Müvekkil', client.name),
        field(
          'Katılanlar',
          meeting.text('katilanlar').isEmpty
              ? '${client.name}, $lawyer'
              : meeting.text('katilanlar'),
        ),
        if (caseTitle.isNotEmpty) field('Dosya', caseTitle),
        section('Konuşulanlar', meeting.text('konusulanlar')),
        section(
          'Kararlar, talimatlar ve verilen yetkiler',
          meeting.text('kararlar'),
        ),
        pw.SizedBox(height: 14),
        pw.Text(
          'Yukarıdaki hususlar taraflarca okunmuş, doğruluğu kabul edilerek '
          'birlikte imza altına alınmıştır.',
          style: base,
        ),
        pw.SizedBox(height: 28),
        pw.Row(
          children: [
            signature('Müvekkil', client.name),
            signature('Avukat', lawyer),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}
