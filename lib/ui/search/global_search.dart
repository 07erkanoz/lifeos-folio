import 'dart:async';
import 'dart:io' show Platform;

import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_hearing.dart';
import '../../services/search/search_models.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../portfolio/portfolio_rows.dart';
import 'search_worker.dart';

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

/// A group of what was found: the first [shown] of [items], the first
/// [SearchWorker.limit] of [total].
class FoundGroup<T extends Found> {
  const FoundGroup(this.items, {int? total, this.shown = GlobalSearch.perGroup})
    : _counted = total;
  final List<T> items;
  final int? _counted;
  final int shown;
  List<T> get first => items.length <= shown ? items : items.sublist(0, shown);

  /// All it holds, the list's "tümünü göster" pressed.
  FoundGroup<T> get opened =>
      FoundGroup(items, total: total, shown: items.length);
  bool get more => items.length > shown;

  /// Opened, and still not all of [total]: the rest asks for more words.
  bool get cut => !more && total > items.length;
  int get total => _counted ?? items.length;
  bool get isEmpty => items.isEmpty;
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

  List<FoundGroup<Found>> get _groups => [
    cases,
    parties,
    documents,
    files,
    agenda,
  ];

  /// What the list shows, in its order: Enter opens the first, the arrows
  /// go through them.
  List<Found> get shown => [for (final g in _groups) ...g.first];

  /// How many [shown] holds, and its [i]th, without making it: an opened
  /// group holds a hundred, and an arrow pressed asked for them all.
  int get shownCount => _groups.fold(0, (n, g) => n + g.first.length);
  Found shownAt(int i) {
    final at = i;
    for (final g in _groups) {
      final first = g.first;
      if (i < first.length) return first[i];
      i -= first.length;
    }
    throw RangeError.index(at, shown);
  }
}

/// The home page's search: the UYAP cases, their parties and documents,
/// the archive and the agenda at once, a few of each.
class GlobalSearch {
  GlobalSearch({
    required this.lawyer,
    this.database,
    this.store,
    this.archive,
    bool? inline,
    DateTime Function()? now,
  }) : _inline = inline ?? Platform.environment.containsKey('FLUTTER_TEST'),
       _now = now ?? DateTime.now;

  final String lawyer;
  final PortalDatabase? database;
  final UyapCaseStore? store;

  /// The archive's search; null where there is none.
  final Future<SearchPage?> Function(String text, int limit)? archive;

  /// Searched on this isolate, not a worker's: under a widget test, whose
  /// clock no other isolate's answer reaches.
  final bool _inline;
  final DateTime Function() _now;

  static const perGroup = 5;

  Future<SearchWorker>? _worker;
  Future<SearchWorker> get _started => _disposed
      ? Future.error(StateError('arama kapandı'))
      : _worker ??= _inline
            ? Future.value(SearchWorker.inline())
            : SearchWorker.start().catchError((Object e) {
                _worker = null;
                throw e;
              });

  /// The portfolio loaded into the worker, kept until a case's record
  /// changes (or ten minutes pass): folding a box's tens of thousands of
  /// documents at every letter typed held the window for seconds.
  _Index? _index;
  Future<_Index>? _making;

  /// The agenda as last read, with its words folded; read again when the
  /// database has changed since.
  _Agenda? _agendaKept;

  /// The search asked for last: one asked before it is no longer wanted.
  int _asked = 0;
  bool _disposed = false;

  /// Made ahead, as the field is entered: the first letter finds it ready.
  Future<void> prepare() => _indexed();

  /// What the portfolio is made of now: the UYAP records kept, the cases
  /// the portals listed.
  Future<(int, int)> _version() async {
    final db = database ?? await PortalDatabase.shared();
    return (UyapCaseStore.changes.value, db.casesRevision);
  }

  Future<_Index> _indexed() async {
    final version = await _version();
    final kept = _index;
    if (kept != null &&
        kept.version == version &&
        _now().difference(kept.at) < const Duration(minutes: 10)) {
      return Future.value(kept);
    }
    return _making ??= _make(version).whenComplete(() => _making = null);
  }

  /// Made while the portfolio changes, it is kept under the version it
  /// began with: the next search makes it again.
  Future<_Index> _make((int, int) version) async {
    final worker = await _started;
    final rows = await loadPortfolio(
      lawyer: lawyer,
      database: database,
      store: store,
    );
    // The words gathered here, folded there; a few milliseconds at a time,
    // the window let draw between them.
    final caseWords = <String>[], partyNames = <String>[];
    final partyRoles = <String>[], documentWords = <String>[];
    final approved = <String>[], sent = <String>[];
    final caseLasts = <int>[], partyCases = <int>[], documentCases = <int>[];
    final documents = <(PortfolioRow, UyapCaseDocument)>[];
    final watch = Stopwatch()..start();
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final parties = [...r.ours, ...r.others];
      caseWords.add(
        [
          r.kase.number,
          r.kase.court,
          r.type,
          for (final p in parties) p.name,
        ].join(' '),
      );
      caseLasts.add(r.lastChange.millisecondsSinceEpoch);
      for (final party in parties) {
        partyCases.add(i);
        partyNames.add(party.name);
        partyRoles.add(party.role);
      }
      for (final d in r.record?.documents ?? const <UyapCaseDocument>[]) {
        for (final x in [d, ...d.attachments]) {
          documents.add((r, x));
          documentCases.add(i);
          documentWords.add('${x.type} ${x.description}');
          approved.add(x.approved);
          sent.add(x.sentToSystem);
          // A case of thousands of documents let breathe in the middle.
          if (watch.elapsedMilliseconds >= 4) {
            await Future<void>.delayed(Duration.zero);
            watch.reset();
          }
        }
      }
      if (watch.elapsedMilliseconds >= 4) {
        await Future<void>.delayed(Duration.zero);
        watch.reset();
      }
    }
    final id = await worker.load(
      caseWords: caseWords,
      caseLasts: caseLasts,
      partyCases: partyCases,
      partyNames: partyNames,
      partyRoles: partyRoles,
      documentCases: documentCases,
      documentWords: documentWords,
      documentApproved: approved,
      documentSent: sent,
    );
    return _index = _Index(
      version: version,
      at: _now(),
      id: id,
      rows: rows,
      documents: documents,
    );
  }

  /// The words of [text], folded; none when it is shorter than two letters.
  static List<String> words(String text) {
    final q = UyapWebService.fold(text.trim());
    return q.length < 2 ? const [] : q.split(RegExp(r'\s+'));
  }

  /// What [text] finds. Asked again before it answers, it gives up and
  /// answers nothing: the field has moved on, and its answer is not shown.
  Future<GlobalSearchResults> find(String text) async {
    final query = text.trim();
    final ws = words(query);
    final none = GlobalSearchResults(query: query);
    if (ws.isEmpty) return none;
    final asked = ++_asked;

    final filesSoon = _files(query);
    var index = await _indexed();
    if (asked != _asked || _disposed) return none;
    final worker = await _started;
    var hits = await worker.find(index.id, ws);
    if (hits == null) {
      // The worker took a newer portfolio in the meantime.
      index = await _indexed();
      hits = await worker.find(index.id, ws);
    }
    if (hits == null || asked != _asked) return none;
    final rows = index.rows;
    final cases = [for (final i in hits.cases) FoundCase(rows[i])];
    final parties = [
      for (final p in hits.parties)
        FoundParty(p.name, p.role, [for (final i in p.cases) rows[i]]),
    ];
    final documents = [
      for (final i in hits.documents)
        FoundDocument(index.documents[i].$1, index.documents[i].$2),
    ];

    final agenda = await _agenda(ws, {
      for (final i in hits.allCases) rows[i].key,
    });
    final (files, filesTotal) = await filesSoon;
    return GlobalSearchResults(
      query: query,
      cases: FoundGroup(cases, total: hits.casesTotal),
      parties: FoundGroup(parties, total: hits.partiesTotal),
      documents: FoundGroup(documents, total: hits.documentsTotal),
      files: FoundGroup(files),
      filesTotal: filesTotal,
      agenda: FoundGroup(agenda.$1, total: agenda.$2),
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
  /// hearings still to come of the cases found ([keys]).
  Future<(List<FoundAgenda>, int)> _agenda(
    List<String> ws,
    Set<String> keys,
  ) async {
    bool has(String folded) => ws.every(folded.contains);
    final db = database ?? await PortalDatabase.shared();
    final today = DateTime(_now().year, _now().month, _now().day);
    final revision = db.revision;
    var kept = _agendaKept;
    // A note just written is found at once: the database says it changed.
    if (kept == null || kept.revision != revision || kept.day != today) {
      kept = _agendaKept = _Agenda(
        revision: revision,
        day: today,
        items: [
          for (final i in db.agenda())
            (i, UyapWebService.fold('${i.title} ${i.body}')),
        ],
      );
    }
    final agenda = kept;
    final items = [
      for (final (i, folded) in agenda.items)
        if (has(folded)) FoundAgenda(item: i, day: i.at),
    ];
    // The hearings to come read once a case is found.
    final hearings = [
      if (keys.isNotEmpty)
        for (final h in agenda.hearings ??= db.hearings(
          from: today,
          to: today.add(const Duration(days: 400)),
        ))
          if (keys.contains(h.caseKey)) FoundAgenda(hearing: h, day: h.at),
    ];
    // What is to come first, nearest first; then what has passed, latest
    // first; the notes without a date last.
    int rank(FoundAgenda a) =>
        a.day == null ? 2 : (a.day!.isBefore(today) ? 1 : 0);
    final all = [...hearings, ...items]
      ..sort((a, b) {
        final ra = rank(a), rb = rank(b);
        if (ra != rb) return ra.compareTo(rb);
        if (ra == 2) return 0;
        return ra == 0 ? a.day!.compareTo(b.day!) : b.day!.compareTo(a.day!);
      });
    return (
      all.length <= SearchWorker.limit
          ? all
          : all.sublist(0, SearchWorker.limit),
      all.length,
    );
  }

  void dispose() {
    _disposed = true;
    _asked++;
    unawaited(_worker?.then((w) => w.stop(), onError: (Object _) {}));
    _worker = null;
  }
}

/// The portfolio as loaded into the worker: [id] its load, the rows and
/// documents its answers point to.
class _Index {
  const _Index({
    required this.version,
    required this.at,
    required this.id,
    required this.rows,
    required this.documents,
  });
  final (int, int) version;
  final DateTime at;
  final int id;
  final List<PortfolioRow> rows;
  final List<(PortfolioRow, UyapCaseDocument)> documents;
}

class _Agenda {
  _Agenda({required this.revision, required this.day, required this.items});
  final (int, int) revision;
  final DateTime day;
  final List<(AgendaItem, String)> items;
  List<PortalHearing>? hearings;
}
