import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../editor/document_history.dart';
import '../platform/app_directories.dart';
import '../platform/atomic_file.dart';
import 'uyap_web_service.dart';

/// The UYAP case a document is written for, as it can be found again in
/// any session: by where it is and its number, never by UYAP's ids, which
/// change with every login.
class UyapCaseLink {
  const UyapCaseLink({
    required this.jurisdiction,
    required this.courtType,
    required this.courtId,
    required this.court,
    required this.number,
    this.closed = false,
  });

  /// Hukuk 1, Ceza 0, İcra 2, İdari 6: the portal's yargı türü.
  final String jurisdiction;

  /// The kind of court, the portal's yargı birimi.
  final String courtType;
  final String courtId, court, number;
  final bool closed;

  String get title => '$court $number';

  Map<String, Object?> toJson() => {
    'yargiTuru': jurisdiction,
    'yargiBirimi': courtType,
    'birimId': courtId,
    'mahkeme': court,
    'esas': number,
    'kapali': closed,
  };

  static UyapCaseLink? fromJson(Object? json) {
    if (json is! Map) return null;
    String s(String k) => '${json[k] ?? ''}';
    if (s('esas').isEmpty || s('mahkeme').isEmpty) return null;
    return UyapCaseLink(
      jurisdiction: s('yargiTuru'),
      courtType: s('yargiBirimi'),
      courtId: s('birimId'),
      court: s('mahkeme'),
      number: s('esas'),
      closed: json['kapali'] == true,
    );
  }
}

/// Which document is written for which case: kept beside the documents,
/// in Folio's own folder, not inside them. A UDF carries nothing but what
/// UYAP reads, and its signature covers its content.
class UyapCaseLinks {
  UyapCaseLinks({this._directory});

  static UyapCaseLinks instance = UyapCaseLinks();

  final Directory? _directory;
  Map<String, Object?>? _all;

  /// The file as [_all] was read from it: Folio and each editor window are
  /// processes of their own, and each writes ties here. Read once and kept,
  /// a window wrote its own old copy over another's new tie.
  (DateTime, int)? _stamp;

  /// This process's writes, one after another.
  Future<void> _writing = Future.value();

  Future<File> _file() async => File(
    p.join(
      (_directory ?? await folioSharedDirectory()).path,
      'uyap',
      'baglar.json',
    ),
  );

  static Future<(DateTime, int)?> _stampOf(File file) async {
    try {
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.notFound) return null;
      return (stat.modified, stat.size);
    } catch (_) {
      return null;
    }
  }

  /// The ties, read again when another window changed the file since.
  Future<Map<String, Object?>> _read({bool fresh = false}) async {
    // No folder to keep them in: none are kept, as before.
    final File file;
    try {
      file = await _file();
    } catch (_) {
      return _all ??= {};
    }
    final stamp = await _stampOf(file);
    if (!fresh && _all != null && stamp == _stamp) return _all!;
    try {
      final json = jsonDecode(await file.readAsString());
      _all = json is Map ? json.cast<String, Object?>() : {};
    } catch (_) {
      _all = {};
    }
    _stamp = stamp;
    return _all!;
  }

  Future<UyapCaseLink?> of(String path) async =>
      UyapCaseLink.fromJson((await _read())[DocumentHistory.documentKey(path)]);

  /// The place in UYAP of the case kept as [court] [number], from any
  /// document tied to it: for a case an earlier Folio kept without it.
  Future<UyapCaseLink?> findFor(String court, String number) async {
    for (final value in (await _read()).values) {
      final link = UyapCaseLink.fromJson(value);
      if (link != null &&
          UyapWebService.fold(link.court) == UyapWebService.fold(court) &&
          UyapWebService.fold(link.number) == UyapWebService.fold(number)) {
        return link;
      }
    }
    return null;
  }

  /// The documents tied to the case kept as [court] [number] that are
  /// still where they were: the petitions written for it. A tie made by an
  /// earlier Folio, which kept no path, is listed once its document is
  /// opened again.
  Future<List<String>> documentsOf(String court, String number) async {
    final out = <String>[];
    for (final value in (await _read()).values) {
      final link = UyapCaseLink.fromJson(value);
      final path = value is Map ? value['yol'] : null;
      if (link == null || path is! String) continue;
      if (UyapWebService.fold(link.court) == UyapWebService.fold(court) &&
          UyapWebService.fold(link.number) == UyapWebService.fold(number) &&
          await File(path).exists()) {
        out.add(path);
      }
    }
    return out..sort();
  }

  /// Ties [path] to [link]; null unties it. The file as it is now, read
  /// under a claim the other windows wait on, with this one tie changed in
  /// it: what another window tied meanwhile stays.
  Future<void> link(String path, UyapCaseLink? link) {
    final run = _writing.then((_) => _link(path, link));
    _writing = run.catchError((Object _) {});
    return run;
  }

  Future<void> _link(String path, UyapCaseLink? link) async {
    final claim = await lockBeside(await _file());
    try {
      final all = await _read(fresh: true);
      final key = DocumentHistory.documentKey(path);
      if (link == null) {
        all.remove(key);
      } else {
        // The path beside the tie: the key is a hash of it, and a case's
        // page lists the petitions written for it by where they are.
        all[key] = {...link.toJson(), 'yol': p.absolute(path)};
      }
      final file = await _file();
      await replaceFileIfChanged(file, utf8.encode(jsonEncode(all)));
      _stamp = await _stampOf(file);
    } finally {
      try {
        await claim?.close();
      } catch (_) {}
    }
  }
}

extension UyapCaseFinding on UyapWebService {
  /// [link]'s case in this session, with this session's id: open cases
  /// first, then closed ones.
  Future<UyapCase> findCase(UyapCaseLink link) async {
    if (UyapWebService.isHighCourt(link.jurisdiction)) {
      // A high court lists the whole chamber; the case is found in it by
      // its number.
      final found = await chamberCases(
        link.jurisdiction,
        UyapOption(link.courtId, link.court),
      );
      for (final c in found) {
        if (UyapWebService.fold(c.number) == UyapWebService.fold(link.number)) {
          return c;
        }
      }
      throw StateError('${link.title} UYAP’ta bulunamadı.');
    }
    final wanted = UyapCase('', link.number, link.courtId, link.court);
    if (link.jurisdiction == UyapWebService.prosecution) {
      // A prosecutor's office lists by page only, open and closed apart.
      for (final closed in [link.closed, !link.closed]) {
        for (var page = 1; page <= 40; page++) {
          final got = await prosecutorCases(
            UyapOption(link.courtId, link.court),
            closed: closed,
            pageNumber: page,
          );
          for (final c in got.cases) {
            if (c.sameCase(wanted)) return c;
          }
          if (got.rows < UyapWebService.pageSize) break;
        }
      }
      throw StateError('${link.title} UYAP’ta bulunamadı.');
    }
    final number = RegExp(r'(\d{4})\s*/\s*(\d+)').firstMatch(link.number);
    for (final closed in [link.closed, !link.closed]) {
      final found = await cases(
        jurisdiction: link.jurisdiction,
        courtType: link.courtType,
        court: UyapOption(link.courtId, link.court),
        year: number == null ? null : int.parse(number[1]!),
        number: number == null ? null : int.parse(number[2]!),
        closed: closed,
      );
      for (final c in found) {
        if (c.sameCase(wanted)) return c;
      }
    }
    throw StateError('${link.title} UYAP’ta bulunamadı.');
  }
}
