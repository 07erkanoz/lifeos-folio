import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'uyap_case_links.dart';
import 'uyap_case_store.dart';
import 'uyap_web_service.dart';

/// What the UYAP panel beside a document works with: the case the document
/// is written for, as it was last fetched and kept, and what can be done
/// with it now. Everything that needs UYAP asks for a session first; what
/// was kept works without one.
class UyapCasePanelController extends ChangeNotifier {
  UyapCasePanelController({
    this._web,
    this._store,
    this._links,
    this.pause = const Duration(milliseconds: 300),
  });

  final UyapWebService? _web;
  final UyapCaseStore? _store;
  final UyapCaseLinks? _links;
  UyapWebService get web => _web ?? UyapWebService.instance;
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
    final kept = path == null ? null : await links.of(path);
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
    _changed();
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
    _record = record;
    _live = null;
    _liveDocuments = const {};
    selected.clear();
    _changed();
  }

  /// Ties the document to [link], a case kept on this computer, without
  /// asking UYAP: what was fetched of it before is there already.
  Future<void> attach(UyapCaseLink link) async {
    _link = link;
    _record = await store.load(link.court, link.number);
    _live = null;
    _liveDocuments = const {};
    selected.clear();
    if (_path != null) await links.link(_path!, link);
    _changed();
  }

  /// Whether the case can be looked for in UYAP: a case kept by an earlier
  /// Folio may not know where it is.
  bool get findable =>
      _link != null && _link!.courtId.isNotEmpty && _link!.courtType.isNotEmpty;

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

  /// Fetches the case's particulars, parties and documents, and keeps them.
  Future<void> refresh() async {
    if (_link == null || !web.connected) return;
    await _doing('Dosya UYAP’ta aranıyor', () async {
      final live = await _liveCase();
      busy = 'Dosya bilgileri çekiliyor';
      _changed();
      final details = await web.caseDetails(live);
      final parties = await web.parties(live);
      final documents = await web.caseDocuments(
        live,
        onPage: (page, pages) {
          busy = pages > 1
              ? 'Evrak listesi çekiliyor · $page/$pages'
              : 'Evrak listesi çekiliyor';
          _changed();
        },
      );
      _liveDocuments = {
        for (final d in documents.documents) ...{
          d.key: d,
          for (final a in d.attachments) a.key: a,
        },
      };
      _record = await store.keep(
        target: live,
        details: details,
        parties: parties,
        documents: documents,
        link: _link,
      );
    });
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
    if (!web.connected) {
      throw StateError('Evrakı indirmek için UYAP’a bağlanın.');
    }
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
