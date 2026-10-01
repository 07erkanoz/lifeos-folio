import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import 'case_law_search.dart';
import 'constitutional_court.dart';
import 'decision.dart';
import 'html_text.dart';
import 'rich_text.dart';
import 'uyap_emsal.dart';

/// Where a decision's text came from, named so a reader can weigh it.
enum DecisionSource {
  bedesten('Bedesten · Adalet Bakanlığı', 'https://mevzuat.adalet.gov.tr/'),
  uyapEmsal('UYAP Emsal', UyapEmsal.site),
  constitutional(
    'Anayasa Mahkemesi Kararlar Bilgi Bankası',
    'https://normkararlarbilgibankasi.anayasa.gov.tr/',
  );

  const DecisionSource(this.label, this.site);

  final String label;

  /// The bank's own search, for a decision it could not be asked about.
  final String site;

  static DecisionSource of(String? name) => values.firstWhere(
    (source) => source.name == name,
    orElse: () => DecisionSource.bedesten,
  );
}

/// A decision as the case bank has it.
@immutable
class Decision {
  const Decision({
    required this.court,
    required this.esas,
    required this.karar,
    required this.date,
    required this.text,
    this.html,
    this.source = DecisionSource.bedesten,
    this.url = '',
    this.bankKind = '',
    this.officialReference = '',
    this.details = const [],
  });

  /// The chamber as the bank names it, which is not always how the document
  /// named it — a filing may write "15. HD" where the bank says "15. Hukuk
  /// Dairesi", and it may write the wrong chamber altogether.
  final String court;
  final String esas, karar;

  /// As printed, "21.09.2017"; empty when the bank gave none.
  final String date;

  /// The decision verbatim. Not a summary: a lawyer reading this is reading
  /// the decision, and a paraphrase would be worse than nothing.
  final String text;

  /// The same, with the formatting the bank carried — the bold that marks
  /// the headnote and the holding. Null for a copy kept before the app began
  /// keeping it.
  final String? html;

  final DecisionSource source;

  /// The decision's page at its source; empty where the source has none.
  final String url;

  /// Which of the bank's collections it came from, "YARGITAYKARARI".
  final String bankKind;

  /// The reference the court itself asks for, where it asks for one: the
  /// Constitutional Court's "AYM, E.2020/95, K.2022/3, 26/1/2022".
  final String officialReference;

  /// Further lines of its heading — the Official Gazette, the outcome, the
  /// applicant — as the source gave them.
  final List<(String, String)> details;

  /// An individual application to the Constitutional Court.
  bool get isApplication => bankKind == ConstitutionalKind.individual.code;

  String get title => isApplication
      ? [court, 'B. No: $esas', if (date.isNotEmpty) date].join(' ')
      : [court, 'E.$esas', 'K.$karar', if (date.isNotEmpty) date].join(' ');

  /// "Yargıtay 15. Hukuk Dairesi, 2016/1531 E., 2017/3344 K., 21.09.2017 T."
  String get reference => officialReference.isNotEmpty
      ? officialReference
      : decisionReference(court: court, esas: esas, karar: karar, date: date);

  /// The decision as paragraphs, bold where the bank marked it.
  List<RichParagraph> get paragraphs {
    final page = html;
    if (page != null && page.trim().isNotEmpty) {
      final read = richParagraphsOf(page);
      if (read.isNotEmpty) return read;
    }
    return plainParagraphsOf(text);
  }
}

/// What asking about a citation came to.
enum LookupOutcome {
  found,

  /// Asked, and the bank has not published it. Banks publish a selection
  /// of what is decided, not all of it.
  absent,

  /// Could not ask: no network, a refusal, a shape the bank changed. Not
  /// the same thing as absent, and never told the reader as if it were.
  unreachable,

  /// A court whose decisions no bank publishes.
  unpublished,
}

@immutable
class DecisionLookup {
  const DecisionLookup(
    this.outcome, {
    this.decision,
    this.chamberDiffers = false,
  });

  final LookupOutcome outcome;
  final Decision? decision;

  /// The document named another chamber than the one the bank filed these
  /// numbers under: the same numbers can belong to two chambers, and the
  /// reader must not take one for the other.
  final bool chamberDiffers;
}

/// Lets one caller through at a time, and not too often.
///
/// These government services refuse a caller who asks too quickly — the
/// sister site answers about seventeen requests a second apart and then
/// shuts for three seconds. Fetching one decision costs two requests, so a
/// document with a dozen citations would trip it in a moment if the presses
/// were allowed to pile up. They are queued instead, a breath apart, and a
/// refusal is waited out rather than shown to the reader.
class _Gate {
  _Gate({required this.between});

  final Duration between;
  Future<void> _queue = Future.value();
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  Future<T> run<T>(Future<T> Function() body) {
    final next = _queue.then((_) async {
      final since = DateTime.now().difference(_last);
      if (since < between) await Future<void>.delayed(between - since);
      try {
        return await body();
      } finally {
        _last = DateTime.now();
      }
    });
    // The queue must survive a failure, or one error stops every later call.
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }
}

/// Court decisions, fetched from the official banks and then kept.
///
/// Turkish court decisions are free to reproduce (FSEK m. 31). The Ministry
/// publishes the Court of Cassation, the Council of State and the regional
/// courts through Bedesten, and more of the regional courts through UYAP
/// Emsal; the Constitutional Court publishes its own. A decision is found by
/// its case numbers, fetched once and written to disk; pressing the same
/// citation again costs nothing.
///
/// No bank holds everything. Measured against a working archive of
/// seventeen hundred filings, about a third of the higher court decisions
/// cited in them could be found. An underline therefore promises only that
/// this is a decision worth asking about — the answer may be that the bank
/// has not got it, and that answer is kept for a while too, so it is not
/// asked twice.
///
/// Only a court that publishes is ever asked about. A first instance case
/// number in a filing is almost always the writer's own file rather than a
/// precedent, so those are left alone even though the bank holds some.
class CaseLaw {
  CaseLaw({
    @visibleForTesting Future<String> Function(String path, String? body)? send,
    @visibleForTesting Directory? cache,
    @visibleForTesting UyapEmsal? emsal,
    @visibleForTesting ConstitutionalCourt? constitutional,
    // Measured: about a dozen requests go through together before the bank
    // shuts for a few seconds. Six hundred milliseconds keeps well under
    // that while a page of ten settles in a handful of seconds.
    @visibleForTesting Duration between = const Duration(milliseconds: 600),
    // `this._send` is what the analyser would rather see, but a named
    // argument may not begin with an underscore, so it cannot be called.
    // ignore: prefer_initializing_formals
  }) : _send = send,
       _kept = cache,
       _emsal = emsal ?? UyapEmsal(),
       _constitutional = constitutional ?? ConstitutionalCourt(),
       _gate = _Gate(between: between);

  /// How the bank is reached. A test hands its own in, and must: flutter_test
  /// answers every real request with an empty 400.
  final Future<String> Function(String path, String? body)? _send;

  Directory? _kept;
  final UyapEmsal _emsal;
  final ConstitutionalCourt _constitutional;
  final _Gate _gate;

  /// Batches already fetched, by the body that fetched them, with the
  /// bank's count of everything that matched. Paging inside a batch never
  /// reaches the bank again.
  final _batches = <String, (List<CaseLawHit>, int)>{};

  static const _host = 'bedesten.adalet.gov.tr';

  /// A decision's page on the Ministry's own site.
  static String pageOf(String documentId) =>
      'https://mevzuat.adalet.gov.tr/ictihat/$documentId';

  /// Which benches to look through. The first instance collection is left
  /// out on purpose; see the note on this class.
  static const _kinds = [
    'YARGITAYKARARI',
    'ISTINAFHUKUK',
    'DANISTAYKARAR',
    'KYB',
  ];

  /// Which collection each branch of the court table is filed in.
  static const _collections = {
    'yargitay': {'YARGITAYKARARI', 'KYB'},
    'danistay': {'DANISTAYKARAR'},
    'bam': {'ISTINAFHUKUK'},
  };

  /// How long "not published" is believed. Banks add decisions, and a
  /// search that went wrong once should not be believed for ever.
  static const absentFor = Duration(days: 7);

  /// Decisions do not change, so a kept copy never goes stale. It is
  /// re-fetched only if the file is lost or damaged.
  final _inMemory = <String, Decision>{};

  /// Numbers the banks answered for and had nothing. Two thirds of the
  /// citations in a working archive are in here, so remembering them is
  /// what keeps a reader from paying the wait twice for the same nothing.
  final _absent = <String>{};

  static String _keyFor(DecisionCitation citation) {
    final key = citation.application
        ? 'b_${citation.esas}'
        : '${citation.esas}_${citation.karar}';
    return (citation.constitutional ? 'aym_$key' : key).replaceAll('/', '-');
  }

  /// Whether this decision is already on disk, so the caller can say whether
  /// a press will answer at once or reach for the network.
  Future<bool> isKept(DecisionCitation citation) async {
    if (_inMemory.containsKey(_keyFor(citation))) return true;
    final kept = await _read(citation);
    return kept != null && kept.text.isNotEmpty;
  }

  /// The decision a citation points at, or null when it cannot be had.
  Future<Decision?> decision(DecisionCitation citation) async =>
      (await lookup(citation)).decision;

  /// The decision a citation points at, and if there is none, why.
  Future<DecisionLookup> lookup(DecisionCitation citation) async {
    if (!citation.fetchable) {
      return const DecisionLookup(LookupOutcome.unpublished);
    }
    final key = _keyFor(citation);
    final held = _inMemory[key];
    if (held != null) return _found(citation, held);
    if (_absent.contains(key)) {
      return const DecisionLookup(LookupOutcome.absent);
    }

    final kept = await _read(citation);
    if (kept != null) {
      if (kept.text.isEmpty) {
        _absent.add(key);
        return const DecisionLookup(LookupOutcome.absent);
      }
      _inMemory[key] = kept;
      return _found(citation, kept);
    }

    final Decision? found;
    try {
      found = citation.constitutional
          ? await _fromConstitutionalCourt(citation)
          : await _fromBanks(citation);
    } on Object {
      // No network, a refusal, a shape the bank changed: none of it is the
      // reader's doing, and none of it means the decision does not exist.
      return const DecisionLookup(LookupOutcome.unreachable);
    }
    if (found == null) {
      _absent.add(key);
      await _writeAbsent(citation);
      return const DecisionLookup(LookupOutcome.absent);
    }
    _inMemory[key] = found;
    await _write(citation, found);
    return _found(citation, found);
  }

  static DecisionLookup _found(DecisionCitation citation, Decision decision) =>
      DecisionLookup(
        LookupOutcome.found,
        decision: decision,
        chamberDiffers: chamberDiffers(citation, decision),
      );

  /// Whether the document named a chamber other than the one found.
  @visibleForTesting
  static bool chamberDiffers(DecisionCitation citation, Decision decision) {
    if (citation.constitutional) return false;
    final written = citation.courtLabel;
    if (written.isEmpty || decision.court.isEmpty) return false;
    if (!sameBench(written, decision.court)) return true;
    // A document that said which court, and the bank filing the numbers
    // under another: "Yargıtay 22. HD" found as a regional court's chamber.
    final kinds = _collections[citation.court?.kind];
    final said = RegExp(
      'Yargıtay|Danıştay|Bölge|BAM',
      caseSensitive: false,
    ).hasMatch(citation.courtWritten);
    return said &&
        kinds != null &&
        decision.bankKind.isNotEmpty &&
        !kinds.contains(decision.bankKind);
  }

  /// Whether two names of a bench are the same bench: "Yargıtay 3. Hukuk
  /// Dairesi" and "3. HUKUK DAİRESİ" are; "3." and "13." are not, though one
  /// is written inside the other.
  @visibleForTesting
  static bool sameBench(String a, String b) {
    String plain(String value) {
      final folded = value
          .replaceAll('İ', 'i')
          .replaceAll('I', 'ı')
          .toLowerCase()
          .replaceAll('ı', 'i')
          .replaceAll('ç', 'c')
          .replaceAll('ğ', 'g')
          .replaceAll('ö', 'o')
          .replaceAll('ş', 's')
          .replaceAll('ü', 'u')
          .replaceAll(RegExp(r'\byargitay\b|\bdanistay\b|\bt\.c\.'), ' ');
      return folded.replaceAll(RegExp('[^0-9a-z]+'), '');
    }

    final x = plain(a), y = plain(b);
    if (x.isEmpty || y.isEmpty) return true;
    final nx = RegExp(r'\d{1,2}').firstMatch(x)?.group(0);
    final ny = RegExp(r'\d{1,2}').firstMatch(y)?.group(0);
    if (nx != null && ny != null && nx != ny) return false;
    final tx = x.replaceAll(RegExp(r'\d'), '');
    final ty = y.replaceAll(RegExp(r'\d'), '');
    return tx.contains(ty) || ty.contains(tx);
  }

  // -- the banks ------------------------------------------------------------

  Future<Decision?> _fromBanks(DecisionCitation citation) async {
    final search = jsonEncode({
      'data': {
        'pageSize': 5,
        'pageNumber': 1,
        'itemTypeList': _kinds,
        'esasNoYil': citation.esasYear,
        'esasNoSira': citation.esasNumber,
        'kararNoYil': citation.kararYear,
        'kararNoSira': citation.kararNumber,
      },
      'applicationName': 'UyapMevzuat',
    });
    final found = _rowsIn(await _call('/emsal-karar/searchDocuments', search));
    if (found.isNotEmpty) {
      // The same numbers can belong to more than one bench. The one the
      // document named is preferred; failing that the first is taken, and
      // the bank's own name for it is shown, so a reader can see at once
      // when it is not the decision they meant.
      final row = _matching(found, citation) ?? found.first;
      final id = '${row['documentId']}';
      if (id.isNotEmpty && id != 'null') {
        final html = await _textOf(id, throwing: true);
        if (html != null) {
          final type = row['itemType'];
          final esas = '${row['esasNo'] ?? citation.bankEsas}';
          return Decision(
            court: '${row['birimAdi'] ?? citation.court?.name ?? ''}',
            esas: esasWrittenIn(html, esas),
            karar: '${row['kararNo'] ?? citation.karar}',
            date: '${row['kararTarihiStr'] ?? ''}',
            text: plainTextOf(html),
            html: html,
            url: pageOf(id),
            bankKind: type is Map ? '${type['name'] ?? ''}' : '',
          );
        }
      }
    }
    if (!_mayBeRegional(citation)) return null;
    return _fromEmsal(citation);
  }

  /// Whether UYAP Emsal is worth asking: it carries the regional courts of
  /// appeal and the courts beneath them, and nothing of the Court of
  /// Cassation or the Council of State.
  static bool _mayBeRegional(DecisionCitation citation) {
    final kind = citation.court?.kind;
    if (kind == 'bam') return true;
    if (kind != 'yargitay' || citation.chamber == null) return false;
    // "İstanbul 22. Hukuk Dairesi" may be either; "Yargıtay 22. HD" is not.
    return !RegExp(
      r'Yargıtay|^Y\s*\.',
      caseSensitive: false,
    ).hasMatch(citation.courtWritten);
  }

  Future<Decision?> _fromEmsal(DecisionCitation citation) async {
    final rows = await _gate.run(
      () => _emsal.find(
        esasYear: citation.esasYear,
        esasNumber: citation.esasNumber,
        kararYear: citation.kararYear,
        kararNumber: citation.kararNumber,
      ),
    );
    if (rows.isEmpty) return null;
    final row = rows.firstWhere(
      (one) =>
          citation.courtLabel.isEmpty ||
          sameBench(citation.courtLabel, one.court),
      orElse: () => rows.first,
    );
    final html = await _gate.run(() => _emsal.page(row.id));
    if (html == null) return null;
    return Decision(
      court: row.court,
      esas: row.esas,
      karar: row.karar,
      date: row.date,
      text: plainTextOf(html),
      html: html,
      source: DecisionSource.uyapEmsal,
      url: UyapEmsal.site,
      bankKind: 'ISTINAFHUKUK',
      details: [if (row.state.isNotEmpty) ('Durum', _titled(row.state))],
    );
  }

  Future<Decision?> _fromConstitutionalCourt(DecisionCitation citation) async {
    final rows = await _gate.run(
      () => citation.application
          ? _constitutional.find(application: citation.esas)
          : _constitutional.find(
              esas: citation.bankEsas,
              karar: citation.karar,
            ),
    );
    if (rows.isEmpty) return null;
    final full = await _gate.run(
      () => _constitutional.byId(rows.first.kind, rows.first.id),
    );
    if (full == null) return null;
    return decisionOfConstitutional(full);
  }

  /// A decision of the Constitutional Court as the rest of the app shows one.
  static Decision decisionOfConstitutional(ConstitutionalRecord record) {
    final html = record.html ?? '';
    final individual = record.kind == ConstitutionalKind.individual;
    return Decision(
      court: individual && record.body.isNotEmpty
          ? 'Anayasa Mahkemesi ${record.body}'
          : 'Anayasa Mahkemesi',
      esas: individual ? record.application : record.esas,
      karar: record.karar,
      date: record.date,
      text: plainTextOf(html),
      html: html,
      source: DecisionSource.constitutional,
      url: record.url,
      bankKind: record.kind.code,
      officialReference: record.reference,
      details: [
        if (individual && record.applicant.isNotEmpty)
          ('Başvurucu', record.applicant),
        if (individual) ('Başvuru No', record.application),
        if (record.outcome.isNotEmpty) ('Sonuç', record.outcome),
        if (record.gazetteDate.isNotEmpty || record.gazetteNumber.isNotEmpty)
          (
            'Resmî Gazete',
            [
              record.gazetteDate,
              record.gazetteNumber,
            ].where((part) => part.isNotEmpty).join(' – '),
          ),
      ],
    );
  }

  /// The esas as the decision's own first line writes it, where the bank
  /// files it shorter: a General Assembly's "2011/7-695" is filed as
  /// 2011/695, and it is the longer one a reference is written with.
  @visibleForTesting
  static String esasWrittenIn(String html, String filed) {
    final head = plainTextOf(
      html.length > 3000 ? html.substring(0, 3000) : html,
    ).split('\n').first;
    final written = RegExp(r'(\d{4})\s*/\s*(\d{1,2})\s*-\s*(\d{1,6})\s*E\.')
        .firstMatch(head);
    if (written == null) return filed;
    final year = written.group(1)!, number = written.group(3)!;
    return filed == '$year/$number'
        ? '$year/${written.group(2)}-$number'
        : filed;
  }

  static String _titled(String value) => value.isEmpty
      ? value
      : '${value.substring(0, 1)}${value.substring(1).toLowerCase()}';

  /// Searches the bank.
  ///
  /// A hundred are asked for and ten are shown. The two used to be the
  /// same number, which was the mistake that made this search nearly
  /// useless: a hundred costs the same single request as ten — 0.4
  /// seconds either way — and taking only ten meant taking whatever one
  /// chamber happened to produce in one sitting. What comes back is spread
  /// by [CaseLawSpread] before any of it is shown, and the rest of the
  /// batch is kept so that paging through it costs the bank nothing.
  ///
  /// The order a reader actually wants needs the text of each decision,
  /// which is a request apiece; doing that first meant staring at a
  /// spinner for half a minute before seeing anything. It is done
  /// afterwards instead, by [rank], and the list settles as it comes.
  Future<CaseLawResults> search(CaseLawQuery query) async {
    if (query.isEmpty) return const CaseLawResults.empty();
    if (query.constitutional != null) return _searchConstitutional(query);
    // The body already carries everything that decides the batch, and the
    // reader's own page is not part of it, so it is the batch's name.
    final asked = CaseLawQueryBuilder.body(query);
    var batch = _batches[asked];
    if (batch == null) {
      final String body;
      try {
        body = await _call('/emsal-karar/searchDocuments', asked);
      } on Object {
        return const CaseLawResults.empty();
      }

      final json = jsonDecode(body);
      if (json is! Map) return const CaseLawResults.empty();
      if ((json['metadata'] as Map?)?['FMTY'] == 'ERROR') {
        return const CaseLawResults.empty();
      }
      final data = json['data'];
      if (data is! Map) return const CaseLawResults.empty();
      final rows = data['emsalKararList'];
      final hits = <CaseLawHit>[
        if (rows is List)
          for (final row in rows)
            if (row is Map) ?CaseLawHit.fromJson(row.cast<String, Object?>()),
      ];
      // Oldest out first. A reader paging back and forth through one
      // search is the case worth keeping; a dozen searches ago is not.
      if (_batches.length >= 8) _batches.remove(_batches.keys.first);
      batch = _batches[asked] = (
        CaseLawSpread.of(hits),
        (data['total'] as num?)?.toInt() ?? hits.length,
      );
    }

    final (rows, total) = batch;
    final from = query.offsetInBatch;
    if (from >= rows.length) {
      return CaseLawResults(hits: const [], total: total, page: query.page);
    }
    return CaseLawResults(
      hits: rows.sublist(
        from,
        (from + query.pageSize).clamp(from, rows.length),
      ),
      total: total,
      page: query.page,
    );
  }

  /// The Constitutional Court's bank, searched its own way: its words go in
  /// as they were typed, and the case numbers as "2020/95".
  Future<CaseLawResults> _searchConstitutional(CaseLawQuery query) async {
    final kind = query.constitutional!;
    String? number(int? year, int? sequence) =>
        year != null && sequence != null ? '$year/$sequence' : null;
    final esas = number(query.esasYear, query.esasNumber);
    final ConstitutionalPage page;
    try {
      page = await _gate.run(
        () => _constitutional.search(
          kind,
          words: query.words,
          esas: kind == ConstitutionalKind.norm ? esas : null,
          karar: kind == ConstitutionalKind.norm
              ? number(query.kararYear, query.kararNumber)
              : null,
          application: kind == ConstitutionalKind.individual ? esas : null,
          page: query.page,
          size: query.pageSize,
        ),
      );
    } on Object {
      return const CaseLawResults.empty();
    }
    return CaseLawResults(
      hits: [
        for (final record in page.records)
          CaseLawHit.fromConstitutional(record),
      ],
      total: page.total,
      page: query.page,
    );
  }

  /// Reads the decisions of a page and puts them in order as it goes.
  ///
  /// [onSettled] is called each time another text has arrived and the page
  /// has been reordered, so the reader watches it settle rather than
  /// waiting for it. Stopped by [wanted] answering false, which is how a
  /// reader who searches again is not made to wait for the last search.
  ///
  /// The bank allows about a dozen requests together and then shuts for a
  /// few seconds, so these go one at a time through the same gate as
  /// everything else. The Constitutional Court's bank orders its own.
  Future<void> rank(
    CaseLawQuery query,
    CaseLawResults results,
    void Function(CaseLawResults ordered) onSettled, {
    bool Function()? wanted,
  }) async {
    if (results.hits.isEmpty || !query.hasWords) return;
    if (query.constitutional != null) return;
    final texts = <String, String>{};
    for (final hit in results.hits) {
      if (wanted != null && !wanted()) return;
      final page = await _textOf(hit.documentId);
      if (page == null) continue;
      if (wanted != null && !wanted()) return;
      texts[hit.documentId] = plainTextOf(page);
      onSettled(
        CaseLawResults(
          hits: CaseLawRanking.of(query.words, results.hits, texts),
          total: results.total,
          page: results.page,
        ),
      );
    }
  }

  /// A decision found by searching rather than by its citation.
  Future<Decision?> byId(CaseLawHit hit) async {
    final kind = ConstitutionalKind.of(hit.kind);
    if (kind != null) {
      try {
        final record = await _gate.run(
          () => _constitutional.byId(kind, hit.documentId),
        );
        return record == null ? null : decisionOfConstitutional(record);
      } on Object {
        return null;
      }
    }
    final text = await _textOf(hit.documentId);
    if (text == null) return null;
    return Decision(
      court: hit.court,
      esas: hit.esas,
      karar: hit.karar,
      date: hit.date,
      text: plainTextOf(text),
      html: text,
      url: pageOf(hit.documentId),
      bankKind: hit.kind,
    );
  }

  /// The page a decision is written on, kept so a second look is free.
  final _pages = <String, String>{};

  /// With [throwing] a failure to reach the bank is let through, so that
  /// the caller can tell it from a decision without a page.
  Future<String?> _textOf(String documentId, {bool throwing = false}) async {
    final held = _pages[documentId];
    if (held != null) return held;
    try {
      final body = await _call(
        '/emsal-karar/getDocumentContent',
        jsonEncode({
          'data': {'documentId': documentId},
          'applicationName': 'UyapMevzuat',
        }),
      );
      final content = (jsonDecode(body) as Map<String, Object?>)['data'];
      if (content is! Map) return null;
      final encoded = content['content'];
      if (encoded is! String || encoded.isEmpty) return null;
      final html = utf8.decode(base64.decode(encoded));
      _pages[documentId] = html;
      return html;
    } on Object {
      if (throwing) rethrow;
      return null;
    }
  }

  static List<Map<String, Object?>> _rowsIn(String body) {
    final json = jsonDecode(body);
    if (json is! Map) return const [];
    if ((json['metadata'] as Map?)?['FMTY'] == 'ERROR') {
      throw const FormatException('Bedesten hata döndürdü');
    }
    final data = json['data'];
    if (data is! Map) return const [];
    final rows = data['emsalKararList'];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map) row.cast<String, Object?>(),
    ];
  }

  /// The row whose bench the document named, if one of them is.
  ///
  /// The chamber number decides first — "15. HD" and "15. Hukuk Dairesi" are
  /// the same court written two ways, and the number is what they share —
  /// and then the branch: the same numbers in the Court of Cassation and in
  /// a regional court, or in a civil and a criminal chamber, are told apart
  /// by what the document said.
  static Map<String, Object?>? _matching(
    List<Map<String, Object?>> rows,
    DecisionCitation citation,
  ) {
    if (rows.length == 1) return rows.first;
    final written = citation.courtLabel;
    final kinds = _collections[citation.court?.kind];
    Map<String, Object?>? best;
    var bestScore = 0;
    for (final row in rows) {
      final bench = '${row['birimAdi'] ?? ''}';
      final type = row['itemType'];
      final kind = type is Map ? '${type['name'] ?? ''}' : '';
      var score = 0;
      final number = RegExp(r'\d{1,2}').firstMatch(bench)?.group(0);
      if (citation.chamber != null && number != null) {
        score += int.parse(number) == citation.chamber ? 4 : -4;
      }
      if (written.isNotEmpty && sameBench(written, bench)) score += 2;
      if (kinds != null && kinds.contains(kind)) score += 1;
      if (score > bestScore) {
        bestScore = score;
        best = row;
      }
    }
    return best;
  }

  Future<String> _call(String path, String? body) => _gate.run(() async {
    final send = _send ?? _http;
    final first = await send(path, body);
    if (!_isRefusal(first)) return first;
    // The bank's own refusal, which lifts after about three seconds. Waited
    // out here rather than shown to the reader as a failure.
    await Future<void>.delayed(const Duration(seconds: 4));
    return send(path, body);
  });

  /// The bank answers a caller who asked too quickly with a web page, not
  /// with JSON. Recognised in one place, so the real sender and the one a
  /// test hands in behave alike.
  static bool _isRefusal(String body) => body.trimLeft().startsWith('<');

  static Future<String> _http(String path, String? body) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.parse('https://$_host$path');
      final request = body == null
          ? await client.getUrl(uri)
          : await client.postUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'Folio');
      if (body != null) {
        request.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        request.write(body);
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode == 429) return '<refused/>';
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('${response.statusCode}', uri: uri);
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }

  // -- what is kept on disk ------------------------------------------------

  /// The shape of a kept file. A file without it was written before the
  /// app asked more than one bank: its decisions stand, its "not found"
  /// does not — the Constitutional Court's were asked of the wrong bank.
  static const _version = 2;

  Future<File> _file(DecisionCitation citation) async {
    final dir = _kept ??= Directory(
      p.join((await folioSupportDirectory()).path, 'ictihat'),
    );
    return File(p.join(dir.path, '${_keyFor(citation)}.json'));
  }

  Future<Decision?> _read(DecisionCitation citation) async {
    try {
      final file = await _file(citation);
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final text = json['metin'] as String?;
      if (text == null) return null;
      // An empty text is the remembered "the bank has not got this".
      if (text.isEmpty) {
        final at = DateTime.tryParse(json['alindi'] as String? ?? '');
        final current = (json['surum'] as num?)?.toInt() == _version;
        if (!current ||
            at == null ||
            DateTime.now().difference(at) > absentFor) {
          return null;
        }
        return const Decision(
          court: '',
          esas: '',
          karar: '',
          date: '',
          text: '',
        );
      }
      final details = json['kunye'];
      return Decision(
        court: json['daire'] as String? ?? '',
        esas: json['esas'] as String? ?? citation.esas,
        karar: json['karar'] as String? ?? citation.karar,
        date: json['tarih'] as String? ?? '',
        text: text,
        html: json['bicimli'] as String?,
        source: DecisionSource.of(json['kaynak'] as String?),
        url: json['adres'] as String? ?? '',
        bankKind: json['koleksiyon'] as String? ?? '',
        officialReference: json['atif'] as String? ?? '',
        details: [
          if (details is List)
            for (final pair in details)
              if (pair is List && pair.length == 2)
                ('${pair[0]}', '${pair[1]}'),
        ],
      );
    } on Object {
      // A half-written or hand-edited file is simply fetched again.
      return null;
    }
  }

  /// Remembers that the banks had nothing, so they are not asked again soon.
  Future<void> _writeAbsent(DecisionCitation citation) => _write(
    citation,
    Decision(
      court: citation.court?.name ?? '',
      esas: citation.esas,
      karar: citation.karar,
      date: '',
      text: '',
    ),
  );

  Future<void> _write(DecisionCitation citation, Decision decision) async {
    try {
      final file = await _file(citation);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'surum': _version,
          'kaynak': decision.source.name,
          'daire': decision.court,
          'esas': decision.esas,
          'karar': decision.karar,
          'tarih': decision.date,
          'alindi': DateTime.now().toUtc().toIso8601String(),
          'metin': decision.text,
          if (decision.html != null) 'bicimli': decision.html,
          if (decision.url.isNotEmpty) 'adres': decision.url,
          if (decision.bankKind.isNotEmpty) 'koleksiyon': decision.bankKind,
          if (decision.officialReference.isNotEmpty)
            'atif': decision.officialReference,
          if (decision.details.isNotEmpty)
            'kunye': [
              for (final (name, value) in decision.details) [name, value],
            ],
        }),
      );
    } on Object {
      // Keeping it is a kindness, not a requirement.
    }
  }
}
