import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../pdf/pdf_pages.dart';
import '../portal/portal_database.dart';
import '../portal/portal_deadline.dart';
import 'eyp_package.dart';
import 'notice_matcher.dart';
import 'uets_api.dart';

/// The notices whose packages come down by themselves: those of the last
/// forty days, as Banaozel's server does; an older one's when the lawyer
/// asks for it ([only]), not to load the computer with years of a box.
const autoPackageWindow = Duration(days: 40);

/// Fetches the package of every notice that has none yet, newest first
/// (the lawyer chose every notice, read or not: UETS then shows it read;
/// its service day does not move): the envelope and the documents are
/// written under [root], each notice in a folder of its own that Folio
/// made, and the envelope's text is read for its directives. [onKept] is
/// told each notice as it is kept, so that its deadlines are made again
/// at once, not after the whole box. A package UETS would not give is
/// asked again a day later; UETS's "ask less often" is waited out.
Future<void> fetchNoticePackages(
  UetsApi api,
  PortalDatabase db, {
  required String root,
  Future<String?> Function(String path)? readText,
  void Function(int done, int total)? progress,
  void Function(String noticeId)? onKept,
  Duration gap = const Duration(seconds: 3),
  DateTime? now,
  Duration? recent = autoPackageWindow,
  Set<String>? only,
}) async {
  final at = now ?? DateTime.now();
  final kept = db.envelopes();
  final since = recent == null ? null : at.subtract(recent);
  final due = [
    for (final n in db.notices())
      if ((only == null || only.contains(n.message.id)) &&
          (only != null ||
              since == null ||
              (n.message.sent != null && !n.message.sent!.isBefore(since))) &&
          switch (kept[n.message.id]) {
            null => true,
            final e when e.state == 'hata' =>
              e.fetchedAt == null ||
                  at.difference(e.fetchedAt!) > const Duration(days: 1),
            _ => false,
          })
        n,
  ];
  final read = readText ?? _pdfText;
  for (var i = 0; i < due.length; i++) {
    if (!api.connected) return;
    progress?.call(i, due.length);
    final n = due[i];
    try {
      final bytes = await _withRetry(() => api.package(n.message.id));
      db.saveEnvelope(
        await _keep(n, bytes, db, root: root, read: read, now: at),
      );
    } catch (e) {
      if (!api.connected) return;
      db.saveEnvelope(
        NoticeEnvelope(
          noticeId: n.message.id,
          state: 'hata',
          fetchedAt: at,
          error: e is StateError ? e.message : '$e',
        ),
      );
    }
    onKept?.call(n.message.id);
    if (i < due.length - 1 && gap > Duration.zero) {
      await Future<void>.delayed(gap);
    }
  }
  progress?.call(due.length, due.length);
}

/// [ask] again after UETS's own wait when it says it is busy, twice.
Future<T> _withRetry<T>(Future<T> Function() ask) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await ask();
    } on UetsBusy catch (busy) {
      if (attempt >= 2) rethrow;
      await Future<void>.delayed(busy.retryAfter);
    }
  }
}

Future<NoticeEnvelope> _keep(
  KeptNotice n,
  Uint8List bytes,
  PortalDatabase db, {
  required String root,
  required Future<String?> Function(String path) read,
  required DateTime now,
}) async {
  final m = n.message;
  NoticeEnvelope failed(String why, {String? folder}) => NoticeEnvelope(
    noticeId: m.id,
    state: 'hata',
    folder: folder,
    fetchedAt: now,
    error: why,
  );
  if (bytes.length > EypPackage.maxPackageBytes) {
    return failed('Tebligat paketi çok büyük.');
  }
  // Opened off the window's isolate: a large package would hold it.
  final EypPackage package;
  try {
    package = await Isolate.run(() => EypPackage.read(bytes));
  } on FormatException catch (e) {
    return failed(e.message);
  }
  final parsed = NoticeSubject.parse(m.subject);
  final Directory folder;
  try {
    folder = await _ownFolder(
      root,
      safeFileName(
        parsed == null
            ? 'Diğer'
            : '${parsed.unit} ${parsed.number.replaceAll('/', '-')}',
      ),
      // The notice's own id in the name: one folder a notice, Folio's.
      safeFileName(
        '${m.barcode.isEmpty ? 'Tebligat' : m.barcode} '
        '${m.id.length > 8 ? m.id.substring(0, 8) : m.id}',
      ),
    );
  } on FileSystemException catch (e) {
    return failed(e.message);
  }
  final taken = <String>{};
  final packageFile = await _writeNew(
    folder,
    'Tebligat paketi.eyp',
    bytes,
    taken,
  );
  // The documents under the names the notice's list gives them, when the
  // list and the package count alike; else the package's own (EK-1…).
  final listed = [
    for (final part in db.manifest(m.id).parts)
      if (!part.name.toLowerCase().endsWith('.xml')) part.name,
  ];
  final attachments = <({String name, String path})>[];
  for (var i = 0; i < package.attachments.length; i++) {
    final a = package.attachments[i];
    var name = listed.length == package.attachments.length ? listed[i] : a.name;
    name = safeFileName(name.replaceFirst(RegExp(r'^\(\d+\)\s*'), ''));
    if (name.isEmpty) name = 'Ek ${i + 1}';
    if (p.extension(name).isEmpty) name = '$name${p.extension(a.name)}';
    final file = await _writeNew(folder, name, a.bytes, taken);
    attachments.add((name: p.basename(file.path), path: file.path));
  }
  String? envelopePath, text;
  if (package.envelope != null) {
    final file = await _writeNew(
      folder,
      'Tebligat zarfı.pdf',
      package.envelope!.bytes,
      taken,
    );
    envelopePath = file.path;
    text = (await read(file.path))?.trim();
  }
  return NoticeEnvelope(
    noticeId: m.id,
    state: envelopePath == null
        ? 'zarfYok'
        : (text == null || text.isEmpty)
        ? 'metinYok'
        : 'indirildi',
    folder: folder.path,
    packagePath: packageFile.path,
    envelopePath: envelopePath,
    envelopeText: text,
    attachments: attachments,
    fetchedAt: now,
  );
}

/// [root]/[court]/[notice], made by Folio, and inside [root] for certain:
/// no step of it is a link that would lead elsewhere.
Future<Directory> _ownFolder(String root, String court, String notice) async {
  final base = Directory(root);
  await base.create(recursive: true);
  final real = await base.resolveSymbolicLinks();
  var at = real;
  for (final step in [court, notice]) {
    final next = p.join(at, step);
    if (await FileSystemEntity.isLink(next)) {
      throw FileSystemException('UETS klasöründe bir bağlantı var', next);
    }
    await Directory(next).create();
    at = next;
  }
  final resolved = await Directory(at).resolveSymbolicLinks();
  if (!p.isWithin(real, resolved)) {
    throw FileSystemException('UETS klasörünün dışına yazılmadı', resolved);
  }
  return Directory(resolved);
}

/// [bytes] as [name] in [folder], never over anything there, and never
/// half: written whole to a hidden file first, then moved to a name taken
/// by creating it anew (which fails on whatever is already there, a file
/// or a link); a name taken gets " (2)", " (3)"…. What fails leaves
/// nothing behind.
Future<File> _writeNew(
  Directory folder,
  String name,
  List<int> bytes,
  Set<String> taken,
) async {
  final stem = p.basenameWithoutExtension(name);
  final ext = p.extension(name);
  final part = File(
    p.join(
      folder.path,
      '.$stem.${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 32)}.part',
    ),
  );
  await part.create(exclusive: true);
  try {
    await part.writeAsBytes(bytes, flush: true);
    for (var i = 1; i < 1000; i++) {
      final file = File(p.join(folder.path, i == 1 ? name : '$stem ($i)$ext'));
      if (!taken.add(p.basename(file.path).toLowerCase())) continue;
      try {
        await file.create(exclusive: true);
      } on FileSystemException {
        continue;
      }
      // The name is ours now: the whole file takes its place.
      return await part.rename(file.path);
    }
    throw FileSystemException(
      'Dosya için ad bulunamadı',
      p.join(folder.path, name),
    );
  } finally {
    if (await part.exists()) await part.delete();
  }
}

Future<String?> _pdfText(String path) async =>
    (await PdfPages.text(path, 200000))?.$1;

/// [value] as a file or folder name on every system.
String safeFileName(String value) => value
    .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .replaceAll(RegExp(r'[. ]+$'), '');
