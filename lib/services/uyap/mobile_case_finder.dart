import 'uyap_mobile_api.dart';
import 'uyap_web_service.dart';

/// Finds one case's id in this UYAP mobile session, as Banaozel does it
/// (MobilUYAP.md): the id is the session's and is never kept, so it is
/// looked up each time, narrowly: the kind of unit (`yargibirimleri`), the
/// court by its name (`mahkeme`, its id encrypted and the session's), then
/// the case by its year and sequence (`dosya`). The portfolio is not read.
class MobileCaseFinder {
  MobileCaseFinder(this.api);

  final UyapMobileApi api;

  /// This session's courts, by "t3|t2|closed"; and the kinds of unit of a
  /// jurisdiction. Emptied when the session changes.
  final _courts = <String, List<Map<String, Object?>>>{};
  final _units = <int, List<String>>{};
  MobileSession? _of;

  void _session() {
    final now = api.session.value;
    if (!identical(now, _of)) {
      _of = now;
      _courts.clear();
      _units.clear();
    }
  }

  /// Hukuk 1, Ceza 0, İcra 2, İdari 6, read from the court's name.
  static int guessJurisdiction(String court) => court.contains('Ceza')
      ? 0
      : court.contains('İcra')
      ? 2
      : court.contains('İdare') || court.contains('Vergi')
      ? 6
      : 1;

  static String _first(String number) => number.split(' - ').first.trim();

  /// The id of [number] at [court] in this session, or null when the
  /// mobile API does not list it (a Yargıtay or prosecution case is the
  /// web's alone). [jurisdiction] and [unitKind] are the codes when known
  /// (the web's yargı türü and yargı birimi are the same); they spare the
  /// search. Several cases matching is no match: no guess is made.
  Future<String?> find({
    required String court,
    required String number,
    String? jurisdiction,
    String? unitKind,
    bool closedFirst = false,
  }) async {
    if (!api.connected) return null;
    _session();
    final m = RegExp(r'(\d{4})\s*/\s*(\d+)').firstMatch(number);
    if (m == null) return null;
    final name = UyapWebService.fold(court);
    final wanted = '${m[1]}/${m[2]}';
    bool same(Map<String, Object?> row) =>
        _first('${row['dosyaNo'] ?? ''}').replaceAll(' ', '') == wanted &&
        UyapWebService.fold('${row['birimAdi'] ?? ''}') == name;
    String? single(Iterable<Map<String, Object?>> rows) {
      final ids = {
        for (final r in rows)
          if (same(r) && '${r['dosyaId'] ?? ''}'.isNotEmpty) '${r['dosyaId']}',
      };
      return ids.length == 1 ? ids.single : null;
    }

    if (court.contains('Danıştay')) {
      for (final chamber in await api.danistayChambers()) {
        if (UyapWebService.fold('${chamber['birimAdi'] ?? ''}') != name) {
          continue;
        }
        return single(await api.danistayCases('${chamber['birimId']}'));
      }
      return null;
    }

    final t3 = int.tryParse(jurisdiction ?? '') ?? guessJurisdiction(court);
    final kinds = (unitKind ?? '').isNotEmpty
        ? [unitKind!]
        : _units[t3] ??= [
            for (final u in await api.unitTypes(t3))
              if ('${u['tablo'] ?? ''}'.trim().isNotEmpty)
                '${u['tablo']}'.trim(),
          ];
    for (final kind in kinds) {
      for (final closed in [closedFirst, !closedFirst]) {
        final courts = _courts['$t3|$kind|$closed'] ??= await api.courts(
          t3,
          kind,
          closed: closed,
        );
        for (final c in courts) {
          if (UyapWebService.fold('${c['birimAdi'] ?? ''}') != name) continue;
          final id = single(
            await api.findCase(
              t3,
              kind,
              '${c['birimId']}',
              year: m[1]!,
              sequence: m[2]!,
              closed: closed,
            ),
          );
          if (id != null) return id;
        }
      }
    }
    return null;
  }
}
