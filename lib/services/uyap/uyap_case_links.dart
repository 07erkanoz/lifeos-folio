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

  Future<File> _file() async => File(
    p.join(
      (_directory ?? await folioSharedDirectory()).path,
      'uyap',
      'baglar.json',
    ),
  );

  Future<Map<String, Object?>> _read() async {
    if (_all != null) return _all!;
    try {
      final json = jsonDecode(await (await _file()).readAsString());
      _all = json is Map ? json.cast<String, Object?>() : {};
    } catch (_) {
      _all = {};
    }
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

  /// Ties [path] to [link]; null unties it.
  Future<void> link(String path, UyapCaseLink? link) async {
    final all = await _read();
    final key = DocumentHistory.documentKey(path);
    if (link == null) {
      all.remove(key);
    } else {
      all[key] = link.toJson();
    }
    await replaceFileIfChanged(await _file(), utf8.encode(jsonEncode(all)));
  }
}

extension UyapCaseFinding on UyapWebService {
  /// [link]'s case in this session, with this session's id: open cases
  /// first, then closed ones.
  Future<UyapCase> findCase(UyapCaseLink link) async {
    final number = RegExp(r'(\d{4})\s*/\s*(\d+)').firstMatch(link.number);
    final wanted = UyapCase('', link.number, link.courtId, link.court);
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
