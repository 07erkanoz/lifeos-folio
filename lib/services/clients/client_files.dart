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

  /// [source] copied into [clientId]'s folder, under a name of its own.
  Future<ClientFile> keep(String clientId, String source) async {
    final folder = Directory(p.join((await _root()).path, clientId));
    await folder.create(recursive: true);
    final name = p.basename(source);
    var target = File(p.join(folder.path, name));
    for (var i = 2; await target.exists(); i++) {
      target = File(
        p.join(
          folder.path,
          '${p.basenameWithoutExtension(name)} ($i)${p.extension(name)}',
        ),
      );
    }
    await File(source).copy(target.path);
    final digest = sha256.convert(await target.readAsBytes()).toString();
    // Under the clients' folder, as every device has it.
    return (
      name: name,
      path: p.join(clientId, p.basename(target.path)),
      sha256: digest,
    );
  }

  /// Where [f] is on this device, in the client's folder; null when it is
  /// not here (yet: it comes from the device it was kept on).
  Future<File?> locate(String clientId, ClientFile f) async {
    final here = await placeFor(clientId, f);
    return await here.exists() ? here : null;
  }

  /// Where [f] is put when brought from another device.
  Future<File> placeFor(String clientId, ClientFile f) async =>
      File(p.join((await _root()).path, clientId, p.basename(f.path)));

  /// [bytes] kept as [name] in [clientId]'s folder.
  Future<ClientFile> keepBytes(
    String clientId,
    String name,
    Uint8List bytes,
  ) async {
    final folder = Directory(p.join((await _root()).path, clientId));
    await folder.create(recursive: true);
    final target = File(p.join(folder.path, name));
    await target.writeAsBytes(bytes, flush: true);
    return (
      name: name,
      path: p.join(clientId, name),
      sha256: sha256.convert(bytes).toString(),
    );
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
