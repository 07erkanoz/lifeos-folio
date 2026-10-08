import 'dart:async';

import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_hearing.dart';
import '../../services/search/search_models.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../portfolio/portfolio_rows.dart';

/// One thing the home page's search found; each opens one place.
sealed class Found {
  const Found();
}

/// A UYAP case: its page.
class FoundCase extends Found {
  const FoundCase(this.row);
  final PortfolioRow row;
}

/// A party, with the cases it is in: one case opens its parties, more open
/// UYAP Dosyalarım searched for the name.
class FoundParty extends Found {
  const FoundParty(this.name, this.role, this.cases);
  final String name, role;
  final List<PortfolioRow> cases;
}

/// A document of a UYAP case: its preview, in the case.
class FoundDocument extends Found {
  const FoundDocument(this.row, this.document);
  final PortfolioRow row;
  final UyapCaseDocument document;
}

/// A document of the archive, found by its name or its text.
class FoundFile extends Found {
  const FoundFile(this.hit);
  final SearchHit hit;
}

/// A note, task or deadline of the agenda, or a hearing: its day.
class FoundAgenda extends Found {
  const FoundAgenda({this.item, this.hearing, required this.day});
  final AgendaItem? item;
  final PortalHearing? hearing;

  /// Null for a note without a date.
  final DateTime? day;
}

/// A group of what was found: the first [shown] of [all].
class FoundGroup<T extends Found> {
  const FoundGroup(this.all, {this.shown = GlobalSearch.perGroup});
  final List<T> all;
  final int shown;
  List<T> get first => all.length <= shown ? all : all.sublist(0, shown);

  /// All of it, the list's "tümünü göster" pressed.
  FoundGroup<T> get opened => FoundGroup(all, shown: all.length);
  bool get more => all.length > shown;
  int get total => all.length;
  bool get isEmpty => all.isEmpty;
}

class GlobalSearchResults {
  const GlobalSearchResults({
    required this.query,
    this.cases = const FoundGroup([]),
    this.parties = const FoundGroup([]),
    this.documents = const FoundGroup([]),
    this.files = const FoundGroup([]),
    this.filesTotal = 0,
    this.agenda = const FoundGroup([]),
  });

  final String query;
  final FoundGroup<FoundCase> cases;
  final FoundGroup<FoundParty> parties;
  final FoundGroup<FoundDocument> documents;

  /// The archive's first few, and how many it has in all.
  final FoundGroup<FoundFile> files;
  final int filesTotal;
  final FoundGroup<FoundAgenda> agenda;

  /// The same, with the documents' or the agenda's group shown whole.
  GlobalSearchResults open({bool documents = false, bool agenda = false}) =>
      GlobalSearchResults(
        query: query,
        cases: cases,
        parties: parties,
        documents: documents ? this.documents.opened : this.documents,
        files: files,
        filesTotal: filesTotal,
        agenda: agenda ? this.agenda.opened : this.agenda,
      );

  bool get isEmpty =>
      cases.isEmpty &&
      parties.isEmpty &&
      documents.isEmpty &&
      files.isEmpty &&
      agenda.isEmpty;

  /// What the list shows, in its order: Enter opens the first, the arrows
  /// go through them.
  List<Found> get shown => [
    ...cases.first,
    ...parties.first,
    ...documents.first,
    ...files.first,
    ...agenda.first,
  ];
}

/// The home page's search: the UYAP cases, their parties and documents,
/// the archive and the agenda at once, a few of each.
class GlobalSearch {
  GlobalSearch({
    required this.lawyer,
    this.database,
    this.store,
    this.archive,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String lawyer;
  final PortalDatabase? database;
  final UyapCaseStore? store;

  /// The archive's search; null where there is none.
  final Future<SearchPage?> Function(String text, int limit)? archive;
  final DateTime Function() _now;

  static const perGroup = 5;

  /// The portfolio, read once for a run of searches: each letter typed
  /// does not read every case again.
  List<PortfolioRow>? _rows;
  DateTime? _rowsAt;
  int _rowsVersion = -1;

  Future<List<PortfolioRow>> _portfolio() async {
    final version = UyapCaseStore.changes.value;
    final at = _rowsAt;
    if (_rows != null &&
        version == _rowsVersion &&
        at != null &&
        _now().difference(at) < const Duration(seconds: 30)) {
      return _rows!;
    }
    final rows = await loadPortfolio(
      lawyer: lawyer,
      database: database,
      store: store,
    );
    _rows = rows;
    _rowsAt = _now();
    _rowsVersion = version;
    return rows;
  }

  /// The words of [text], folded; none when it is shorter than two letters.
  static List<String> words(String text) {
    final q = UyapWebService.fold(text.trim());
    return q.length < 2 ? const [] : q.split(RegExp(r'\s+'));
  }

  Future<GlobalSearchResults> find(String text) async {
    final query = text.trim();
    final ws = words(query);
    if (ws.isEmpty) return GlobalSearchResults(query: query);
    bool has(String folded) => ws.every(folded.contains);

    final filesSoon = _files(query);
    final rows = await _portfolio();
    final cases = [
      for (final r in rows)
        if (has(r.haystack)) FoundCase(r),
    ]..sort((a, b) => b.row.lastChange.compareTo(a.row.lastChange));

    // A party by its name, once for all its cases.
    final parties = <String, (UyapParty, List<PortfolioRow>)>{};
    for (final r in rows) {
      for (final party in [...r.ours, ...r.others]) {
        final name = UyapWebService.fold(party.name);
        if (name.isEmpty || !has(name)) continue;
        final seen = parties.putIfAbsent(name, () => (party, []));
        if (!seen.$2.contains(r)) seen.$2.add(r);
      }
    }
    final found = [
      for (final (party, cases) in parties.values)
        FoundParty(party.name, party.role, cases),
    ]..sort((a, b) => b.cases.length.compareTo(a.cases.length));

    final documents = <FoundDocument>[];
    for (final r in rows) {
      for (final d in [
        for (final d in r.record?.documents ?? const <UyapCaseDocument>[]) ...[
          d,
          ...d.attachments,
        ],
      ]) {
        if (has(UyapWebService.fold('${d.type} ${d.description}'))) {
          documents.add(FoundDocument(r, d));
        }
      }
    }
    final far = DateTime(1900);
    documents.sort(
      (a, b) => (b.document.date ?? far).compareTo(a.document.date ?? far),
    );

    final agenda = await _agenda(has, cases);
    final (files, filesTotal) = await filesSoon;
    return GlobalSearchResults(
      query: query,
      cases: FoundGroup(cases),
      parties: FoundGroup(found),
      documents: FoundGroup(documents),
      files: FoundGroup(files),
      filesTotal: filesTotal,
      agenda: FoundGroup(agenda),
    );
  }

  Future<(List<FoundFile>, int)> _files(String query) async {
    final search = archive;
    if (search == null) return (const <FoundFile>[], 0);
    try {
      final page = await search(query, perGroup);
      if (page == null) return (const <FoundFile>[], 0);
      return ([for (final h in page.hits) FoundFile(h)], page.total);
    } catch (_) {
      return (const <FoundFile>[], 0);
    }
  }

  /// The agenda's notes, tasks and deadlines by their words, and the
  /// hearings still to come of the cases found.
  Future<List<FoundAgenda>> _agenda(
    bool Function(String) has,
    List<FoundCase> cases,
  ) async {
    final db = database ?? await PortalDatabase.shared();
    final items = [
      for (final i in db.agenda())
        if (has(UyapWebService.fold('${i.title} ${i.body}')))
          FoundAgenda(item: i, day: i.at),
    ];
    final today = DateTime(_now().year, _now().month, _now().day);
    final keys = {for (final c in cases) c.row.key};
    final hearings = keys.isEmpty
        ? const <FoundAgenda>[]
        : [
            for (final h in db.hearings(
              from: today,
              to: today.add(const Duration(days: 400)),
            ))
              if (keys.contains(h.caseKey)) FoundAgenda(hearing: h, day: h.at),
          ];
    // What is to come first, nearest first; then what has passed, latest
    // first; the notes without a date last.
    int rank(FoundAgenda a) =>
        a.day == null ? 2 : (a.day!.isBefore(today) ? 1 : 0);
    return [...hearings, ...items]..sort((a, b) {
      final ra = rank(a), rb = rank(b);
      if (ra != rb) return ra.compareTo(rb);
      if (ra == 2) return 0;
      return ra == 0 ? a.day!.compareTo(b.day!) : b.day!.compareTo(a.day!);
    });
  }
}
