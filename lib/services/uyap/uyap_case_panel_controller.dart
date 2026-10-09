import 'uyap_enforcement.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../portal/observed.dart' show caseKey;
import '../portal/portal_sync.dart';
import 'uyap_case_links.dart';
import 'uyap_case_store.dart';
import 'uyap_mobile_api.dart';
import 'uyap_web_service.dart';

/// What the UYAP panel beside a document works with: the case the document
/// is written for, as it was last fetched and kept, and what can be done
/// with it now. Everything that needs UYAP asks for a session first; what
/// was kept works without one. The web portal gives everything and is
/// asked first; without it the UYAP mobile API gives the parties, the
/// documents and the documents' files (UYGULAMAPLANI §9.2).
class UyapCasePanelController extends ChangeNotifier {
  UyapCasePanelController({
    this._web,
    this._mobile,
    this._sync,
    this._store,
    this._links,
    this.pause = const Duration(milliseconds: 300),
    this.background = false,
  });

  /// Fetching for the sync, not for a lawyer looking at the case: it gives
  /// way to one who is ([lawyerWaiting]).
  final bool background;

  /// How many cases a lawyer has asked to be fetched and is waiting for.
  static int _waiting = 0;

  /// Whether a lawyer is waiting for a case: the sync's next case waits
  /// for it, UYAP taking one request at a time.
  static bool get lawyerWaiting => _waiting > 0;

  final UyapWebService? _web;
  final UyapMobileApi? _mobile;
  final PortalSync? _sync;
  final UyapCaseStore? _store;
  final UyapCaseLinks? _links;
  UyapWebService get web => _web ?? UyapWebService.instance;
  UyapMobileApi get mobile => _mobile ?? UyapMobileApi.instance;
  PortalSync get sync => _sync ?? PortalSync.instance;

  /// Whether either portal can be asked now.
  bool get connected => web.connected || mobile.connected;

  /// Whether the web portal is the one asked: connected, and the case's
  /// place on it known. Otherwise the mobile API, when connected.
  bool get _useWeb => web.connected && (findable || !mobile.connected);

  /// The mobile session [_liveDocuments] came from, when they did.
  MobileSession? _liveMobile;
  String? _mobileCaseId;
  UyapCaseStore get store => _store ?? UyapCaseStore.instance;
  UyapCaseLinks get links => _links ?? UyapCaseLinks.instance;

  /// Between one download and the next: UYAP takes one request at a time
  /// from a lawyer, and a burst is answered with errors.
  final Duration pause;

  /// Told where a document was saved, so that Folio can search the folder.
  void Function(File file)? onSaved;

  String? _path;
  UyapCaseLink? _link;
  UyapCaseRecord? _record;
  UyapCase? _live;
  UyapSession? _liveSession;
  Map<String, UyapCaseDocument> _liveDocuments = const {};
  String _query = '';
  final selected = <String>{};
  String? busy;
  String? error;
  bool _disposed = false;

  UyapCaseLink? get link => _link;
  UyapCaseRecord? get record => _record;
  String get query => _query;

  set query(String value) {
    _query = value;
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// The document at [path] is the one being written now: its case, if it
  /// has one, and that case as it was kept. [carry] is for the same
  /// document under a new name — saved for the first time, saved as
  /// another, signed into a copy — which keeps the case it had; another
  /// document opened in its place does not.
  Future<void> bind(String? path, {bool carry = false}) async {
    if (path == _path && (_link != null || path == null)) return;
    final kept = path == null
        ? null
        : await links.of(path) ?? await _caseOfFolder(path);
    final had = _link;
    _path = path;
    if (kept == null && had != null && path != null && carry) {
      await links.link(path, had);
      return _changed();
    }
    if (kept?.title != had?.title || (kept == null && !carry)) {
      _link = kept;
      _record = null;
      _live = null;
      _liveDocuments = const {};
      selected.clear();
    }
    if (_link != null) {
      _record = await store.load(_link!.court, _link!.number);
    }
    // A tie an earlier Folio made kept no path: written again with it, the
    // petition shows on its case's page.
    if (kept != null && path != null) await links.link(path, kept);
    _changed();
  }

  /// The case whose folder [path] is in: a document UYAP gave, or one
  /// saved beside it, is that case's without being tied by hand.
  Future<UyapCaseLink?> _caseOfFolder(String path) async {
    try {
      final folder = p.normalize(p.dirname(path)).toLowerCase();
      for (final (record, _) in await store.cases()) {
        if (p.normalize(store.folderOf(record)).toLowerCase() != folder) {
          continue;
        }
        return record.link ??
            UyapCaseLink(
              jurisdiction: '',
              courtType: '',
              courtId: '',
              court: record.court,
              number: record.number,
            );
      }
    } catch (_) {}
    return null;
  }

  /// Ties the document to [link], found as [live] in this session, and
  /// fetches what UYAP has on it.
  Future<void> choose(UyapCaseLink link, UyapCase live) async {
    _link = link;
    _record = await store.load(link.court, link.number);
    _live = live;
    _liveSession = web.session.value;
    _liveDocuments = const {};
    selected.clear();
    if (_path != null) await links.link(_path!, link);
    _changed();
    await refresh();
  }

  /// The case kept as [record], with no document: the case's own page.
  /// Its place in UYAP comes from the record, or for one an earlier Folio
  /// kept, from a document tied to it.
  Future<void> show(UyapCaseRecord record) async {
    _path = null;
    _link =
        record.link ??
        await links.findFor(record.court, record.number) ??
        UyapCaseLink(
          jurisdiction: '',
          courtType: '',
          courtId: '',
          court: record.court,
          number: record.number,
        );
    _record = await store.dropSameContent(record);
    _live = null;
    _liveDocuments = const {};
    selected.clear();
    _changed();
  }

  /// Ties the document to [link], a case kept on this computer, without
  /// asking UYAP: what was fetched of it before is there already.
  Future<void> attach(UyapCaseLink link) async {
    _link = link;
    final kept = await store.load(link.court, link.number);
    // The web's place of it, found once and kept with the record.
    final known = kept?.link;
    if (link.courtId.isEmpty &&
        known != null &&
        known.courtId.isNotEmpty &&
        known.courtType.isNotEmpty) {
      _link = known;
    }
    _record = kept == null ? null : await store.dropSameContent(kept);
    _live = null;
    _liveDocuments = const {};
    selected.clear();
    if (_path != null) await links.link(_path!, _link);
    _changed();
  }

  /// Whether the case can be looked for in UYAP: a case kept by an earlier
  /// Folio may not know where it is.
  bool get findable =>
      _link != null &&
      _link!.courtId.isNotEmpty &&
      (_link!.courtType.isNotEmpty ||
          UyapWebService.isHighCourt(_link!.jurisdiction));

  /// The courts the web portal lists, asked once a session for each kind:
  /// a sync places many cases of one court kind one after another.
  static final _courts = <String, List<UyapOption>>{};
  static Object? _courtsSession;

  Future<List<UyapOption>> _courtsOf(
    String jurisdiction,
    String type,
    bool closed,
  ) async {
    final session = web.session.value;
    if (!identical(session, _courtsSession)) {
      _courts.clear();
      _courtsSession = session;
    }
    return _courts['$jurisdiction|$type|$closed'] ??= await web.courts(
      jurisdiction,
      type,
      closed: closed,
    );
  }

  /// A case the mobile API brought knows its court by name, not by the web
  /// portal's id; with the web connected, the id is looked up by the name
  /// and kept, so that the case is fetched from the web: the account, the
  /// money and the debtors are there, not in the mobile API.
  Future<void> _placeOnWeb() async {
    final link = _link;
    if (link == null ||
        findable ||
        !web.connected ||
        link.court.isEmpty ||
        link.jurisdiction.isEmpty ||
        UyapWebService.isHighCourt(link.jurisdiction)) {
      return;
    }
    final name = UyapWebService.fold(link.court);
    final types = link.courtType.isNotEmpty
        ? [link.courtType]
        : [for (final t in await web.courtTypes(link.jurisdiction)) t.id];
    for (final type in types) {
      for (final closed in [link.closed, !link.closed]) {
        for (final c in await _courtsOf(link.jurisdiction, type, closed)) {
          if (UyapWebService.fold(c.label) != name) continue;
          _link = UyapCaseLink(
            jurisdiction: link.jurisdiction,
            courtType: type,
            courtId: c.id,
            court: link.court,
            number: link.number,
            closed: link.closed,
          );
          if (_path != null) await links.link(_path!, _link);
          return;
        }
      }
    }
  }

  Future<void> unlink() async {
    if (_path != null) await links.link(_path!, null);
    _link = null;
    _record = null;
    _live = null;
    _liveDocuments = const {};
    selected.clear();
    _changed();
  }

  /// The case in this session: its ids are the session's, so a new login
  /// finds it again by court and number.
  Future<UyapCase> _liveCase() async {
    if (!findable) {
      throw StateError(
        'Bu dosyanın UYAP’taki yeri kayıtlı değil. Dosyayı UYAP’tan yeniden '
        'ekleyin.',
      );
    }
    final session = web.session.value;
    if (_live != null && identical(session, _liveSession)) return _live!;
    _live = await web.findCase(_link!);
    _liveSession = session;
    _liveDocuments = const {};
    return _live!;
  }

  Future<T?> _doing<T>(String what, Future<T> Function() work) async {
    busy = what;
    error = null;
    _changed();
    try {
      return await work();
    } catch (e) {
      error = '$e'.replaceFirst('Bad state: ', '');
      return null;
    } finally {
      busy = null;
      _changed();
    }
  }

  /// What UYAP shows of a case of a kind it does not show it for.
  static const hiddenNotes = {
    'ayrinti_bilgileri': 'UYAP bu dosya türünde dosya bilgilerini göstermiyor.',
    'taraf_bilgileri': 'UYAP bu dosya türünde tarafları göstermiyor.',
    'evrak_bilgileri': 'UYAP bu dosya türünde evrak listesini göstermiyor.',
  };

  /// Fetches the case's particulars, parties, documents and money, and
  /// keeps them. UYAP is asked first what it shows of a case of this kind,
  /// and only that is asked for. Without the web portal the mobile API is
  /// asked for the parties and the documents.
  Future<void> refresh() async {
    if (_link == null || !connected) return;
    if (!background) _waiting++;
    try {
      await _refresh();
    } finally {
      if (!background) _waiting--;
    }
  }

  Future<void> _refresh() async {
    try {
      await _placeOnWeb();
    } catch (_) {
      // Not found on the web: the mobile API, as before.
    }
    if (!_useWeb) return _refreshMobile();
    await _doing('Dosya UYAP’ta aranıyor', () async {
      final live = await _liveCase();
      busy = 'Dosya bilgileri çekiliyor';
      _changed();
      UyapCasePermissions permissions;
      try {
        permissions = await web.permissions(live);
      } catch (_) {
        // Not answered: everything is asked for, as before.
        permissions = const UyapCasePermissions(null, null);
      }
      final hidden = {
        for (final what in hiddenNotes.keys)
          if (!permissions.allows(what)) what,
      };
      // A high court's particulars come with its list; the court cases'
      // particulars call is not known to answer for it.
      final details =
          hidden.contains('ayrinti_bilgileri') ||
              UyapWebService.isHighCourt(_link!.jurisdiction)
          ? const UyapCaseDetails()
          : await web.caseDetails(live);
      final parties = hidden.contains('taraf_bilgileri')
          ? const <UyapParty>[]
          : await web.parties(live);
      final documents = hidden.contains('evrak_bilgileri')
          ? const UyapCaseDocuments([])
          : await web.caseDocuments(
              live,
              onPage: (page, pages) {
                busy = pages > 1
                    ? 'Evrak listesi çekiliyor · $page/$pages'
                    : 'Evrak listesi çekiliyor';
                _changed();
              },
            );
      final typeCode = permissions.typeCode ?? live.listing?.typeCode;
      UyapCaseMoney? money;
      if (typeCode != null &&
          permissions.allows('tahsilat_reddiyat_bilgileri')) {
        busy = 'Harç ve tahsilat bilgileri çekiliyor';
        _changed();
        try {
          money = await web.caseMoney(live, typeCode);
        } catch (_) {
          // The rest of the case stands without it.
        }
      }
      // An enforcement file's account and debtors: asked only where UYAP
      // says it shows them, neither asks a quota.
      UyapEnforcement? enforcement;
      final account = permissions.allowed?.contains('hesap_bilgileri') ?? false;
      final debtorsShown =
          permissions.allowed?.contains('borclu_bilgileri') ?? false;
      if (account || debtorsShown) {
        busy = 'Borç hesabı ve borçlular çekiliyor';
        _changed();
        var lines = const <UyapAccountLine>[];
        var debtors = const <UyapDebtor>[];
        try {
          if (account) lines = await web.accountLines(live);
        } catch (_) {}
        try {
          if (debtorsShown) debtors = await web.debtors(live);
        } catch (_) {}
        if (lines.isNotEmpty || debtors.isNotEmpty) {
          enforcement = UyapEnforcement(lines: lines, debtors: debtors);
        }
      }
      _liveDocuments = {
        for (final d in documents.documents) ...{
          d.key: d,
          for (final a in d.attachments) a.key: a,
        },
      };
      _record = await store.keep(
        target: live,
        details: details.withListing(live.listing),
        parties: parties,
        documents: documents,
        link: _link,
        money: money,
        enforcement: enforcement,
        hidden: hidden,
      );
    });
  }

  /// The case's id in this mobile session, the portfolio read for it first
  /// when need be.
  Future<String> _mobileId() async {
    final session = mobile.session.value;
    if (_mobileCaseId != null && identical(session, _liveMobile)) {
      return _mobileCaseId!;
    }
    busy = 'UYAP Mobil’de dosya aranıyor';
    _changed();
    final id = await sync.mobileCaseId(
      court: _link!.court,
      number: _link!.number,
      jurisdiction: _link!.jurisdiction,
      unitKind: _link!.courtType,
    );
    if (id == null || id.isEmpty) {
      throw StateError(
        '${_link!.title} UYAP Mobil’de bulunamadı. Yargıtay ve Cumhuriyet '
        'Başsavcılığı dosyaları yalnız UYAP Web’den alınır.',
      );
    }
    _liveMobile = session;
    _liveDocuments = const {};
    return _mobileCaseId = id;
  }

  Future<void> _refreshMobile() => _doing(
    'Dosya UYAP Mobil’den çekiliyor',
    () async {
      final id = await _mobileId();
      final kept = await sync.portalCase(caseKey(_link!.number, _link!.court));
      final details = kept?.details?.value ?? const <String, Object?>{};
      busy = 'Taraflar çekiliyor';
      _changed();
      List<UyapParty> parties;
      try {
        parties = [
          for (final p in await mobile.parties(
            id,
            caseType: '${details['dosyaTurKod'] ?? ''}',
          ))
            UyapParty.fromMap(p),
        ];
      } catch (_) {
        parties = const [];
      }
      busy = 'Evrak listesi çekiliyor';
      _changed();
      final raw = Map<String, Object?>.from(await mobile.caseDocuments(id));
      // The mobile API may give the full list as a list rather than grouped.
      if (raw['tumEvraklar'] is List) {
        raw['tumEvraklar'] = {'': raw['tumEvraklar']};
      }
      final aligned = alignKeys(
        keyDocuments([UyapDocumentPage.fromJson(raw)]),
        _record?.documents ?? const [],
      );
      final fetched = aligned.docs;
      _liveDocuments = {
        for (final d in fetched) ...{
          d.key: d,
          for (final a in d.attachments) a.key: a,
        },
      };
      final before = _record;
      final documents = enrichDocuments(fetched, [
        for (final d in before?.documents ?? const <UyapCaseDocument>[])
          if (!aligned.retired.contains(d.key)) d,
      ]);
      String text(String key) => '${details[key] ?? ''}'.trim();
      // What the web gave before stays: the mobile API knows less of a case.
      final d = before?.details;
      final hasWeb =
          d != null &&
          (d.kind.isNotEmpty ||
              d.opening.isNotEmpty ||
              d.status.isNotEmpty ||
              d.hearing != null ||
              d.decision.isNotEmpty);
      _record = await store.keep(
        target: UyapCase(id, _link!.number, _link!.courtId, _link!.court),
        details: hasWeb
            ? d
            : UyapCaseDetails(
                kind: text('davaTuru'),
                fileType: text('tur'),
                state: kept?.status?.value ?? '',
                hearing: before?.details.hearing,
              ),
        parties: parties.isEmpty ? before?.parties ?? const [] : parties,
        documents: UyapCaseDocuments(documents),
        link: _link,
        money: before?.money,
        hidden: before?.hidden ?? const {},
      );
    },
  );

  /// [fetched] with the keys the kept list knows its documents by. The
  /// web and the mobile API key one document alike most of the time, by
  /// its unit's number; where they do not (a number in two groups, a group
  /// named another way, a date written another way), a kept document with
  /// the same number, else the same kind, day and description, is taken
  /// for it when it is the only one. Its attachments follow it; a kept
  /// document is claimed once. A copy an earlier mobile refresh kept under
  /// its own key beside the web's is [retired]: the web's key stays.
  @visibleForTesting
  static ({List<UyapCaseDocument> docs, Set<String> retired}) alignKeys(
    List<UyapCaseDocument> fetched,
    List<UyapCaseDocument> kept,
  ) {
    if (kept.isEmpty) return (docs: fetched, retired: const {});
    String fold(String v) => UyapWebService.fold(v).trim();
    String day(UyapCaseDocument d) {
      final t = d.date;
      return t == null ? '' : '${t.year}-${t.month}-${t.day}';
    }

    String look(UyapCaseDocument d) =>
        '${fold(d.type)}|${day(d)}|${fold(d.description)}';
    bool numbered(UyapCaseDocument d) => d.number.isNotEmpty && d.number != '0';
    final keptKeys = {for (final d in kept) d.key};
    final fetchedKeys = {for (final d in fetched) d.key};
    // Only kept documents the fetched list does not name are candidates.
    final open = [
      for (final d in kept)
        if (!fetchedKeys.contains(d.key)) d,
    ];
    final claimed = <String>{};
    final retired = <String>{};
    UyapCaseDocument? only(Iterable<UyapCaseDocument> found) {
      final left = found.where((d) => !claimed.contains(d.key)).toList();
      return left.length == 1 ? left.single : null;
    }

    UyapCaseDocument? twin(UyapCaseDocument d) {
      if (numbered(d)) {
        final same = open.where((k) => k.number == d.number).toList();
        return only(same) ??
            only(same.where((k) => fold(k.source) == fold(d.source)));
      }
      return only(open.where((k) => look(k) == look(d)));
    }

    UyapCaseDocument rekey(UyapCaseDocument d, String key) => UyapCaseDocument(
      key: key,
      documentId: d.documentId,
      caseId: d.caseId,
      type: d.type,
      number: d.number,
      approved: d.approved,
      sender: d.sender,
      description: d.description,
      source: d.source,
      sentToSystem: d.sentToSystem,
      parentKey: d.parentKey,
      attachments: [
        for (final a in d.attachments)
          a.withKey(
            a.key.startsWith('${d.key}:')
                ? '$key${a.key.substring(d.key.length)}'
                : a.key,
            parentKey: key,
          ),
      ],
    );

    final docs = [
      for (final d in fetched)
        () {
          final match = twin(d);
          if (match == null) return d;
          claimed.add(match.key);
          // The copy kept under the mobile API's key gives way to the web's.
          if (keptKeys.contains(d.key)) retired.add(d.key);
          return rekey(d, match.key);
        }(),
    ];
    return (docs: docs, retired: retired);
  }

  /// The mobile API's list [fetched] merged into the list kept: it adds
  /// and fills, it never takes away (UYGULAMAPLANI §9.4). A document the
  /// web listed and the mobile API does not (a tied case's group, often)
  /// stays; a field the mobile API leaves empty keeps what the web gave;
  /// the session's ids are the mobile API's. Newest first.

  @visibleForTesting
  static List<UyapCaseDocument> enrichDocuments(
    List<UyapCaseDocument> fetched,
    List<UyapCaseDocument> kept,
  ) {
    String pick(String a, String b) => a.isNotEmpty ? a : b;
    UyapCaseDocument fill(UyapCaseDocument fresh, UyapCaseDocument? old) {
      if (old == null) return fresh;
      final oldAttachments = {for (final a in old.attachments) a.key: a};
      final freshKeys = {for (final a in fresh.attachments) a.key};
      return UyapCaseDocument(
        key: fresh.key,
        documentId: fresh.documentId,
        caseId: fresh.caseId,
        type: pick(fresh.type, old.type),
        number: pick(fresh.number, old.number),
        approved: pick(fresh.approved, old.approved),
        sender: pick(fresh.sender, old.sender),
        description: pick(fresh.description, old.description),
        // The group it is listed under stays as it was named.
        source: pick(old.source, fresh.source),
        sentToSystem: pick(fresh.sentToSystem, old.sentToSystem),
        parentKey: fresh.parentKey ?? old.parentKey,
        attachments: [
          for (final a in fresh.attachments) fill(a, oldAttachments[a.key]),
          for (final a in old.attachments)
            if (!freshKeys.contains(a.key)) a,
        ],
      );
    }

    final byKey = {for (final d in kept) d.key: d};
    final freshKeys = {for (final d in fetched) d.key};
    final out = [
      for (final d in fetched) fill(d, byKey[d.key]),
      for (final d in kept)
        if (!freshKeys.contains(d.key)) d,
    ];
    final far = DateTime(1900);
    out.sort((a, b) => (b.date ?? far).compareTo(a.date ?? far));
    return out;
  }

  /// The documents the list shows, as the search narrows them.
  List<UyapCaseDocument> get documents {
    final all = _record?.documents ?? const <UyapCaseDocument>[];
    final words = fold(_query).split(' ').where((w) => w.isNotEmpty);
    if (words.isEmpty) return all;
    bool matches(UyapCaseDocument d) {
      final text = fold(
        '${d.title} ${d.sender} ${d.number} ${d.source} ${d.approved}',
      );
      return words.every(text.contains);
    }

    return [
      for (final d in all)
        if (matches(d) || d.attachments.any(matches)) d,
    ];
  }

  bool isNew(String key) => _record?.fresh.contains(key) ?? false;
  bool isSaved(String key) =>
      _record != null && store.fileOf(_record!, key) != null;

  void toggle(String key) {
    if (!selected.remove(key)) selected.add(key);
    _changed();
  }

  /// The file of [document]: from disk when it is there, fetched and kept
  /// when not. Looking at it takes it off the new ones.
  Future<File?> open(UyapCaseDocument document) async {
    final record = _record;
    if (record == null) return null;
    final kept = store.fileOf(record, document.key);
    if (kept != null) {
      _record = await store.seen(record, document.key);
      _changed();
      return kept;
    }
    return _doing('Evrak indiriliyor', () => _fetch(document));
  }

  Future<File> _fetch(UyapCaseDocument document) async {
    if (!connected) {
      throw StateError(
        'Evrakı indirmek için UYAP Web’e ya da UYAP Mobil’e bağlanın.',
      );
    }
    if (!_useWeb) return _fetchMobile(document);
    await _liveCase();
    var live = _liveDocuments[document.key];
    if (live == null) {
      // A list kept from an earlier session: its ids are gone, so the list
      // is fetched again first.
      await refresh();
      live = _liveDocuments[document.key];
      if (live == null) {
        throw StateError('${document.title} UYAP’taki listede bulunamadı.');
      }
    }
    final bytes = await web.caseDocumentBytes(
      live,
      caseId: (await _liveCase()).id,
    );
    final (record, file) = await store.save(_record!, document, bytes);
    _record = await store.seen(record, document.key);
    onSaved?.call(file);
    return file;
  }

  Future<File> _fetchMobile(UyapCaseDocument document) async {
    final id = await _mobileId();
    var live = _liveDocuments[document.key];
    if (live == null) {
      await _refreshMobile();
      live = _liveDocuments[document.key];
      if (live == null) {
        throw StateError('${document.title} UYAP Mobil’deki listede yok.');
      }
    }
    // The document's id goes with the case's id this session resolved,
    // never with the dosyaId its row carries: a tied case's row names that
    // case, and UYAP then answers with another document (Banaozel's
    // `evrak_indir`, the contract of the working KararArama app).
    Uint8List bytes;
    try {
      bytes = _checked(await mobile.documentBytes(live.documentId, id));
    } catch (_) {
      // Both ids are the session's: looked up again, once.
      _mobileCaseId = null;
      await _refreshMobile();
      final again = _liveDocuments[document.key];
      if (again == null || _mobileCaseId == null) rethrow;
      bytes = _checked(
        await mobile.documentBytes(again.documentId, _mobileCaseId!),
      );
    }
    if (store.sameAsAnother(_record!, document.key, bytes)) {
      throw StateError(
        '${document.title}: UYAP Mobil başka bir evrakın içeriğini döndürdü; '
        'kaydedilmedi. UYAP Web ile deneyin.',
      );
    }
    final (record, file) = await store.save(_record!, document, bytes);
    _record = await store.seen(record, document.key);
    onSaved?.call(file);
    return file;
  }

  /// UYAP's document store's own failure, sent as a document's content
  /// (Banaozel's `_DSS_HATA_ISARETLERI`), is not a document.
  static Uint8List _checked(Uint8List bytes) {
    final head = String.fromCharCodes(bytes.take(400).where((b) => b < 128))
        .toLowerCase();
    const marks = [
      'dssreadexception',
      'dokuman saklama sistemine ulasirken hata olustu',
      'belge alma isleminde hata olustu',
    ];
    if (bytes.isEmpty || marks.any(head.contains)) {
      throw StateError('UYAP belge saklama servisi geçici hata verdi.');
    }
    return bytes;
  }

  /// Downloads [keys], or every document when none are given, one after
  /// another. What is on disk already is not fetched again.
  Future<int> download([Iterable<String>? keys]) async {
    final record = _record;
    if (record == null) return 0;
    final wanted = {
      ...keys ??
          [
            for (final d in record.documents) ...[
              d.key,
              for (final a in d.attachments) a.key,
            ],
          ],
    };
    final byKey = {
      for (final d in record.documents) ...{
        d.key: d,
        for (final a in d.attachments) a.key: a,
      },
    };
    final todo = [
      for (final key in wanted)
        if (byKey[key] != null && store.fileOf(_record!, key) == null)
          byKey[key]!,
    ];
    var done = 0;
    await _doing('Evraklar indiriliyor', () async {
      for (final document in todo) {
        busy = 'Evraklar indiriliyor · ${done + 1}/${todo.length}';
        _changed();
        await _fetch(document);
        done++;
        if (done < todo.length) await Future<void>.delayed(pause);
      }
    });
    selected.clear();
    _changed();
    return done;
  }

  /// Turkish without its accents and case, for searching.
  static String fold(String value) => value
      .replaceAll('İ', 'i')
      .replaceAll('I', 'ı')
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'\s+'), ' ');
}
