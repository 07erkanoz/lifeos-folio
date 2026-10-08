import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../preview_app.dart' show openPreviewWindow;
import '../../services/platform/editor_window.dart';
import '../../services/office/office_network.dart';
import '../../services/portal/portal_case.dart';
import '../../services/portal/portal_channel.dart';
import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_hearing.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/portal/uyap_notice.dart';
import '../../services/uyap/uyap_case_links.dart';
import '../../services/uyap/uyap_case_panel_controller.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../../services/uyap/uyap_mobile_api.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../agenda/mobile_connect.dart';
import '../office/send_to_office.dart';
import '../office/task_give_dialog.dart';
import '../office/tasks_page.dart' show TaskDetail, dueOf;
import '../widgets/file_preview.dart';
import '../widgets/share_as.dart';
import 'portfolio_rows.dart';

/// A case's own page (docs/design/uyap-portfoy-taslak.png, the second
/// frame): its number, court and state; whose side is whose; its last
/// news, next hearing, nearest deadline and the petitions written for it;
/// and its documents, the new ones first and marked.
class CaseDetailPage extends StatefulWidget {
  const CaseDetailPage({
    super.key,
    required this.caseKey,
    required this.onBack,
    required this.onOpen,
    this.onNewPetition,
    this.onOpenPath,
    this.onSaved,
    this.lawyer = '',
    this.database,
    this.controller,
    this.links,
    this.showParties = false,
    this.showDocument,
  });

  /// The portal's key of the case.
  final String caseKey;

  /// Opened at its parties, from a search for one.
  final bool showParties;

  /// A document of it to open, by key, from a search for it.
  final String? showDocument;
  final VoidCallback onBack;
  final ValueChanged<File> onOpen;
  final ValueChanged<UyapCaseLink>? onNewPetition;
  final ValueChanged<String>? onOpenPath;
  final void Function(File file)? onSaved;
  final String lawyer;
  final PortalDatabase? database;

  /// For tests: the panel's controller to use, and the ties of documents
  /// to cases to read.
  final UyapCasePanelController? controller;
  final UyapCaseLinks? links;

  /// Closes the preview of the case page open, for Esc and the back
  /// button, which then leave the page only when it is closed; false when
  /// none is showing.
  static bool closePreview() =>
      _CaseDetailPageState._active?._closePreview() ?? false;

  @override
  State<CaseDetailPage> createState() => _CaseDetailPageState();
}

enum _Tab {
  documents,
  notices,
  hearings,
  deadlines,
  parties,
  facts,
  petitions,
  tasks,
}

enum _DocFilter { all, fresh, decisions, petitions, notDownloaded }

class _CaseDetailPageState extends State<CaseDetailPage> {
  late final UyapCasePanelController _c =
      widget.controller ?? UyapCasePanelController();
  PortalCase? _kase;
  CaseState _state = const CaseState();
  List<PortalHearing> _hearings = const [];
  List<AgendaItem> _items = const [];
  List<KeptNotice> _notices = const [];

  /// UYAP's notifications whose body names this case.
  List<UyapNotice> _uyapNotices = const [];
  List<String> _petitions = const [];
  bool _loaded = false;

  /// The documents new when the page opened, kept marked while it is open
  /// though they are no longer new once seen.
  final _fresh = <String>{};
  final _cleared = <String>{};
  _Tab _tab = _Tab.documents;
  _DocFilter _filter = _DocFilter.all;
  final _search = TextEditingController();

  /// The document shown beside the list; each case's last one is shown
  /// again when it is opened again, while Folio runs.
  static final _lastShown = <String, String>{};
  String? _shownKey;

  /// Whether the preview is beside the list: closed when the page opens,
  /// the list taking the width, and opened by choosing a document.
  bool _previewOpen = false;

  /// The document being fetched from UYAP to be shown.
  String? _fetchingKey;
  final _listFocus = FocusNode(debugLabel: 'case-documents');
  final _shownRow = GlobalKey();

  static _CaseDetailPageState? _active;

  /// Whether the last build put the preview beside the list.
  bool _previewShowing = false;

  /// The whole heading shown while a document is open beside the list:
  /// asked for with "Ayrıntılar", or the list scrolled up. Kept from case
  /// to case while Folio runs.
  static bool _detailsWanted = false;
  bool _scrolledUp = false;

  bool _closePreview() {
    if (!mounted || !_previewShowing) return false;
    setState(() => _previewOpen = false);
    _listFocus.requestFocus();
    return true;
  }

  @override
  void initState() {
    super.initState();
    _active = this;
    _c.onSaved = widget.onSaved;
    _c.addListener(_changed);
    unawaited(_load());
  }

  @override
  void dispose() {
    if (identical(_active, this)) _active = null;
    _c.removeListener(_changed);
    if (widget.controller == null) _c.dispose();
    _search.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  void _changed() {
    final record = _c.record;
    if (record != null && !_cleared.containsAll(record.fresh)) {
      // What a refresh brought while the page is open is new here too.
      _fresh.addAll(record.fresh);
      unawaited(_seen());
    }
    if (mounted) setState(() {});
  }

  Future<PortalDatabase> get _db async =>
      widget.database ?? await PortalDatabase.shared();

  Future<void> _load() async {
    final db = await _db;
    // This case alone: the whole portfolio and every notice are not read
    // to open one case's page.
    final kase = db.caseOf(widget.caseKey);
    if (!mounted) return;
    if (kase == null) {
      setState(() => _loaded = true);
      return;
    }
    final link = linkOf(kase);
    await _c.attach(link);
    _fresh.addAll(_c.record?.fresh ?? const {});
    final state = db.caseStates()[kase.key] ?? const CaseState();
    List<String> petitions = const [];
    try {
      petitions = await (widget.links ?? UyapCaseLinks.instance).documentsOf(
        kase.court,
        kase.number,
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _kase = kase;
      _state = state;
      _hearings = db.hearings(caseKey: kase.key)
        ..sort((a, b) => b.at.compareTo(a.at));
      _items = db.agenda(caseKey: kase.key);
      _notices = db.notices(caseKey: kase.key);
      _uyapNotices = db.uyapNotices(caseKey: kase.key);
      _petitions = petitions;
      _shownKey = _lastShown[kase.key];
      if (widget.showParties) _tab = _Tab.parties;
      _loaded = true;
    });
    _openAsked();
    await _seen();
    // Fetched again when it has not been for a while and a portal is
    // there to ask; the list shows what was kept meanwhile.
    // Not while UYAP Mobil's portfolio is being read: the two would ask
    // UYAP and write this case's record at once.
    final record = _c.record;
    final reading =
        PortalSync.started?.state(PortalChannel.uyapMobile).running ?? false;
    if (_c.connected &&
        !reading &&
        (record == null ||
            DateTime.now().difference(record.fetchedAt) >
                const Duration(minutes: 30))) {
      unawaited(_c.refresh());
    }
  }

  /// The document a search asked for, shown once the list is there: beside
  /// it on a wide window, on a page of its own on a phone.
  void _openAsked() {
    final key = widget.showDocument;
    final record = _c.record;
    if (key == null || record == null) return;
    final d = [
      for (final d in record.documents) ...[d, ...d.attachments],
    ].where((d) => d.key == key).firstOrNull;
    if (d == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.sizeOf(context).width >= 900) {
        _show(d);
      } else {
        unawaited(_openPreviewPage(d));
      }
    });
  }

  /// The case opened: no longer new, nor its documents.
  Future<void> _seen() async {
    final kase = _kase;
    if (kase == null) return;
    try {
      (await _db).markSeen(kase.key);
      final record = _c.record;
      // Each new document is taken off the new ones once.
      if (record != null && !_cleared.containsAll(record.fresh)) {
        _cleared.addAll(record.fresh);
        await _c.store.seenAll(record);
      }
    } catch (_) {}
  }

  Future<void> _refresh() async {
    if (!_c.connected) {
      PortalSync.begin();
      if (!await connectUyapMobile(context, api: UyapMobileApi.instance)) {
        return;
      }
    }
    await _c.refresh();
  }

  Future<void> _open(UyapCaseDocument d) async {
    if (!_c.connected && _c.store.fileOf(_c.record!, d.key) == null) {
      PortalSync.begin();
      if (!await connectUyapMobile(context, api: UyapMobileApi.instance)) {
        return;
      }
    }
    final file = await _c.open(d);
    if (file != null && mounted) widget.onOpen(file);
  }

  Future<void> _downloadFresh() async {
    if (!_c.connected) {
      PortalSync.begin();
      if (!await connectUyapMobile(context, api: UyapMobileApi.instance)) {
        return;
      }
    }
    final n = await _c.download(_fresh);
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('$n evrak indirildi')));
    }
  }

  // Building.

  @override
  Widget build(BuildContext context) {
    final kase = _kase;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final page = dark
        ? Theme.of(context).colorScheme.surface
        : AgendaColors.page;
    if (!_loaded) {
      return ColoredBox(
        color: page,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (kase == null) {
      return ColoredBox(
        color: page,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Dosya portföyde bulunamadı.'),
              TextButton(
                onPressed: widget.onBack,
                child: const Text('UYAP Dosyalarım’a dön'),
              ),
            ],
          ),
        ),
      );
    }
    return ColoredBox(
      color: page,
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 900;
          // Room for the list and a document beside it: the page fills the
          // window and only the list scrolls.
          final split = box.maxWidth >= 1100 && box.maxHeight >= 520;
          _previewShowing =
              split &&
              _previewOpen &&
              _tab == _Tab.documents &&
              _c.record != null;
          if (split) return _splitPage(context, kase);
          final pad = wide ? 28.0 : 12.0;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
                sliver: SliverList.list(
                  children: [
                    _header(context, kase, wide),
                    if (_c.busy != null || _c.error != null) ...[
                      const SizedBox(height: 8),
                      _status(context),
                    ],
                    const SizedBox(height: 12),
                    _partyCards(context, wide),
                    const SizedBox(height: 12),
                    _summaries(context, wide),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 16),
                sliver: _tab == _Tab.documents && _c.record != null
                    ? _documentsSliver(context, wide)
                    : SliverToBoxAdapter(child: _tabsCard(context, wide)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The tabs' card with the documents in it, its rows built as they come
  /// on the screen.
  Widget _documentsSliver(BuildContext context, bool wide) {
    final scheme = Theme.of(context).colorScheme;
    final entries = _documentEntries();
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(child: _tabsCard(context, wide, entries: entries)),
          SliverList.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) => _entryRow(context, entries[i]),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
      ),
    );
  }

  /// The page when the window has room: the case's heading with its facts
  /// in a line, and the tabs filling the rest; in Evraklar the list on the
  /// left, the document shown on the right (docs/design/
  /// evrak-onizleme-taslak.png).
  Widget _splitPage(BuildContext context, PortalCase kase) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A document open beside the list: the heading in a line, the
        // document given its room; the whole of it again when asked for
        // or when the list is scrolled up, as the app's other pages do.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: _previewShowing && !_detailsWanted && !_scrolledUp
              ? _foldedHeader(context, kase)
              : _header(context, kase, true, facts: true),
        ),
        if (_c.busy != null || _c.error != null) ...[
          const SizedBox(height: 8),
          _status(context),
        ],
        const SizedBox(height: 10),
        Expanded(
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (n) {
              if (!_previewShowing || n.metrics.axis != Axis.vertical) {
                return false;
              }
              final delta = n.scrollDelta ?? 0;
              final up = delta < -6 || n.metrics.pixels <= 0;
              final down = delta > 6 && n.metrics.pixels > 0;
              if (up && !_scrolledUp) {
                setState(() => _scrolledUp = true);
              } else if (down && _scrolledUp) {
                setState(() => _scrolledUp = false);
              }
              return false;
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _tabBar(context),
                    Expanded(
                      child: _tab == _Tab.documents && _c.record != null
                          ? _documentsSplit(context)
                          : SingleChildScrollView(
                              child: _tabBody(context, true),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  /// The heading in a line, a document open beside the list: the case,
  /// its court and kind, the next hearing, and the way to the rest.
  Widget _foldedHeader(BuildContext context, PortalCase kase) {
    final record = _c.record;
    final type = record?.details.kind.isNotEmpty == true
        ? record!.details.kind
        : '${kase.details?.value['tur'] ?? ''}';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final hearing = ([
      for (final h in _hearings)
        if (!h.at.isBefore(today)) h,
    ]..sort((a, b) => a.at.compareTo(b.at))).firstOrNull;
    return Container(
      key: const ValueKey('case-header-folded'),
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'UYAP Dosyalarım',
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Text(
            kase.number,
            style: const TextStyle(
              fontFamily: 'Consolas',
              fontFamilyFallback: ['Cascadia Mono', 'monospace'],
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: [
                      kase.court,
                      if (type.trim().isNotEmpty) type.trim(),
                    ].join(' · '),
                  ),
                  if (hearing != null) ...[
                    const TextSpan(text: ' · Duruşma '),
                    TextSpan(
                      text: '${dayText(hearing.at)} ${clockText(hearing.at)}',
                      style: const TextStyle(
                        color: AgendaColors.deadline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AgendaColors.muted),
            ),
          ),
          TextButton.icon(
            key: const ValueKey('case-header-details'),
            onPressed: () => setState(() => _detailsWanted = true),
            icon: const Icon(Icons.expand_more_rounded, size: 18),
            label: const Text('Ayrıntılar'),
          ),
          IconButton(
            tooltip: 'UYAP’tan tazele',
            onPressed: _c.busy != null ? null : () => unawaited(_refresh()),
            icon: const Icon(Icons.sync_rounded, size: 19),
          ),
        ],
      ),
    );
  }

  /// The parties, the next hearing and deadline, the last news.
  Widget _factsLine(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final hearing = ([
      for (final h in _hearings)
        if (!h.at.isBefore(today)) h,
    ]..sort((a, b) => a.at.compareTo(b.at))).firstOrNull;
    final deadline = ([
      for (final i in _items)
        if (i.kind == 'deadline' && !i.done && i.at != null) i,
    ]..sort((a, b) => a.at!.compareTo(b.at!))).firstOrNull;
    final change = _state.changeAt ?? _documents.firstOrNull?.date;
    bool soon(DateTime at, int days) =>
        DateTime(at.year, at.month, at.day).difference(today).inDays <= days;
    Widget fact(String label, String value, {bool warn = false}) => Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: warn
                  ? AgendaColors.deadline
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 12.5, color: AgendaColors.muted),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        key: const ValueKey('case-facts'),
        spacing: 18,
        runSpacing: 4,
        children: [
          fact(
            'Duruşma',
            hearing == null
                ? 'yok'
                : '${dayText(hearing.at)} ${clockText(hearing.at)}',
            warn: hearing != null && soon(hearing.at, 7),
          ),
          fact(
            'Açık süre',
            deadline == null
                ? 'yok'
                : '${deadline.title} · ${dayText(deadline.at!)}',
            warn: deadline != null && soon(deadline.at!, 3),
          ),
          fact('Son gelişme', change == null ? '—' : dayText(change)),
        ],
      ),
    );
  }

  /// The list, which keeps its place, and the document chosen in it.
  Widget _documentsSplit(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = _documentEntries();
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _documentsTab(context, !_previewOpen, entries: entries),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: Focus(
            focusNode: _listFocus,
            onKeyEvent: (_, e) => _listKey(e, entries),
            child: ListView.builder(
              key: const ValueKey('case-doc-list'),
              itemCount: entries.length,
              itemBuilder: (context, i) =>
                  _entryRow(context, entries[i], split: true),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 7, 14, 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '↑ ↓ evrak değiştirir · Enter ya da çift tık açar',
                  style: TextStyle(fontSize: 11, color: AgendaColors.muted),
                ),
              ),
              if (!_previewOpen)
                TextButton.icon(
                  key: const ValueKey('case-preview-show'),
                  onPressed: () => setState(() => _previewOpen = true),
                  icon: const Icon(Icons.vertical_split_outlined, size: 16),
                  label: const Text('Önizlemeyi göster'),
                ),
            ],
          ),
        ),
      ],
    );
    if (!_previewOpen) return list;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 440, child: list),
        VerticalDivider(width: 1, color: scheme.outlineVariant),
        Expanded(child: _previewPane(context, entries)),
      ],
    );
  }

  List<UyapCaseDocument> _shownDocuments(
    List<({String? bucket, UyapCaseDocument? doc, int? attachment})> entries,
  ) => [
    for (final e in entries)
      if (e.doc != null) e.doc!,
  ];

  /// ↑ and ↓ move through the list, the document shown with them; Enter
  /// opens it, or fetches it when it is not on this computer yet.
  KeyEventResult _listKey(
    KeyEvent e,
    List<({String? bucket, UyapCaseDocument? doc, int? attachment})> entries,
  ) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final docs = _shownDocuments(entries);
    final at = docs.indexWhere((d) => d.key == _shownKey);
    final down = e.logicalKey == LogicalKeyboardKey.arrowDown;
    if (down || e.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (docs.isEmpty) return KeyEventResult.handled;
      final next = (at < 0 ? 0 : at + (down ? 1 : -1)).clamp(
        0,
        docs.length - 1,
      );
      _show(docs[next]);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final row = _shownRow.currentContext;
        if (row != null && row.mounted) {
          Scrollable.ensureVisible(
            row,
            alignmentPolicy: down
                ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
                : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          );
        }
      });
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter && at >= 0) {
      final d = docs[at];
      unawaited(_downloaded(d) ? _open(d) : _fetchShown(d));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// A click shows [d] at once; a second on it soon after opens it. Not
  /// a double tap's recogniser, which holds every click back to wait for
  /// a second.
  void _tapped(UyapCaseDocument d) {
    final now = DateTime.now();
    final again =
        _lastTap?.key == d.key &&
        now.difference(_lastTap!.at) < const Duration(milliseconds: 400);
    _lastTap = again ? null : (key: d.key, at: now);
    if (again) {
      unawaited(_open(d));
      return;
    }
    _show(d);
    // A click is asking to see it: fetched at once when it is not here.
    // The arrows only show what is here, not to ask UYAP for every one.
    if (!_downloaded(d)) unawaited(_fetchShown(d));
  }

  ({String key, DateTime at})? _lastTap;

  void _show(UyapCaseDocument d) {
    setState(() {
      _shownKey = d.key;
      _previewOpen = true;
      // A document opened: the heading in its line again.
      _scrolledUp = false;
    });
    final kase = _kase;
    if (kase != null) _lastShown[kase.key] = d.key;
    _listFocus.requestFocus();
  }

  /// [d] fetched from UYAP to be shown; the list can be gone through
  /// meanwhile.
  Future<void> _fetchShown(UyapCaseDocument d) async {
    // One at a time; the last one asked for meanwhile comes after.
    if (_fetchingKey != null) {
      _fetchNext = d;
      return;
    }
    if (!_c.connected) {
      PortalSync.begin();
      if (!await connectUyapMobile(context, api: UyapMobileApi.instance)) {
        return;
      }
    }
    if (!mounted) return;
    setState(() => _fetchingKey = d.key);
    try {
      await _c.open(d);
    } finally {
      if (mounted) setState(() => _fetchingKey = null);
    }
    final next = _fetchNext;
    _fetchNext = null;
    if (mounted &&
        next != null &&
        next.key == _shownKey &&
        !_downloaded(next)) {
      await _fetchShown(next);
    }
  }

  UyapCaseDocument? _fetchNext;

  /// The document of [key], among the documents or their attachments.
  UyapCaseDocument? _documentOf(String? key) {
    if (key == null) return null;
    for (final d in _c.record?.documents ?? const <UyapCaseDocument>[]) {
      if (d.key == key) return d;
      for (final a in d.attachments) {
        if (a.key == key) return a;
      }
    }
    return null;
  }

  Widget _previewPane(
    BuildContext context,
    List<({String? bucket, UyapCaseDocument? doc, int? attachment})> entries,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final back = dark ? scheme.surfaceContainerLowest : const Color(0xFFE9ECF1);
    final docs = _shownDocuments(entries);
    final at = docs.indexWhere((d) => d.key == _shownKey);
    final d = at >= 0 ? docs[at] : _documentOf(_shownKey);
    if (d == null) {
      return ColoredBox(
        color: back,
        child: const Center(
          child: Text(
            'Önizlemek için soldan bir evrak seçin.',
            style: TextStyle(color: AgendaColors.muted),
          ),
        ),
      );
    }
    final record = _c.record;
    final file = record == null ? null : _c.store.fileOf(record, d.key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.type.isNotEmpty ? d.type : d.title,
                      key: const ValueKey('case-preview-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      [
                        if (d.date != null) dayText(d.date!),
                        if (d.sender.trim().isNotEmpty)
                          titleName(d.sender.trim()),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AgendaColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Önceki evrak',
                onPressed: at > 0 ? () => _show(docs[at - 1]) : null,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
              IconButton(
                tooltip: 'Sonraki evrak',
                onPressed: at >= 0 && at < docs.length - 1
                    ? () => _show(docs[at + 1])
                    : null,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
              if (file != null)
                SendToOfficeButton(
                  paths: () => [file.path],
                  text: _sentWith(_c, d),
                ),
              if (_mayGiveTask)
                IconButton(
                  key: const ValueKey('case-preview-task'),
                  tooltip: 'Bu evrakla görev ver',
                  onPressed: () => unawaited(_giveTaskWith(d)),
                  icon: const Icon(Icons.add_task_rounded, size: 19),
                ),
              if (file != null && EditorWindow.available)
                IconButton(
                  tooltip: 'Ayrı pencerede aç',
                  onPressed: () => unawaited(openPreviewWindow(file.path)),
                  icon: const Icon(Icons.open_in_new_rounded, size: 19),
                ),
              const SizedBox(width: 4),
              FilledButton.icon(
                key: const ValueKey('case-preview-open'),
                onPressed: () => unawaited(_open(d)),
                icon: Icon(
                  file != null ? Icons.open_in_full_rounded : Icons.download,
                  size: 17,
                ),
                label: Text(file != null ? 'Aç' : 'İndir ve aç'),
              ),
              IconButton(
                key: const ValueKey('case-preview-close'),
                tooltip: 'Önizlemeyi kapat',
                onPressed: () => setState(() => _previewOpen = false),
                icon: const Icon(Icons.close_rounded, size: 19),
              ),
            ],
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: back,
            child: file != null
                ? FilePreview(key: ValueKey(file.path), path: file.path)
                : _notHere(
                    context,
                    fetching: _fetchingKey == d.key,
                    onFetch: () => unawaited(_fetchShown(d)),
                  ),
          ),
        ),
      ],
    );
  }

  /// A document not on this computer yet: fetched when asked, not when
  /// the arrows pass over it, which would ask UYAP for every one.
  static Widget _notHere(
    BuildContext context, {
    required bool fetching,
    required VoidCallback onFetch,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 360,
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              fetching
                  ? Icons.hourglass_top_rounded
                  : Icons.cloud_download_outlined,
              size: 34,
              color: scheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              fetching ? 'UYAP’tan indiriliyor' : 'Bu evrak henüz indirilmedi',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            if (fetching) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text(
                'Bu sırada listede gezmeye devam edebilirsiniz; inince burada '
                'açılır.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AgendaColors.muted),
              ),
            ] else ...[
              const Text(
                'Göstermek için UYAP’tan indirilir ve dosyanın klasörüne '
                'kaydedilir.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AgendaColors.muted),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const ValueKey('case-preview-fetch'),
                onPressed: onFetch,
                icon: const Icon(Icons.download_rounded, size: 17),
                label: const Text('Göster (indir)'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// On a phone or a narrow window: the document on a page of its own,
  /// the next and the one before a swipe away; back finds the list where
  /// it was.
  Future<void> _openPreviewPage(UyapCaseDocument d) async {
    final docs = _shownDocuments(_documentEntries());
    final at = docs.indexWhere((x) => x.key == d.key);
    if (at < 0) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CasePreviewPage(
          controller: _c,
          documents: docs,
          initial: at,
          fetch: _fetchShown,
          open: _open,
          giveTask: _mayGiveTask ? _giveTaskWith : null,
        ),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding, Border? border}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: border ?? Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _chip(String text, Color fill, Color ink) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ink),
    ),
  );

  /// [facts]: the parties, hearing, deadline and last news in a line, in
  /// place of their cards, when the documents take the window.
  Widget _header(
    BuildContext context,
    PortalCase kase,
    bool wide, {
    bool facts = false,
  }) {
    final kind = CaseKind.of(kase);
    final record = _c.record;
    final status = shortStatus(
      (kase.status?.value ?? '').isNotEmpty
          ? kase.status!.value
          : record?.details.status ?? '',
    );
    final degree = UyapWebService.isHighCourt(linkOf(kase).jurisdiction)
        ? 'İSTİNAF / TEMYİZ'
        : 'İLK DERECE';
    final type = record?.details.kind.isNotEmpty == true
        ? record!.details.kind
        : '${kase.details?.value['tur'] ?? ''}';
    final opened =
        parseDay(kase.details?.value['acilis']) ??
        parseDay(record?.details.openedOn);
    final now = DateTime.now();
    final actions = [
      // The whole heading asked for beside an open document: back to its
      // line.
      if (facts && _previewShowing && (_detailsWanted || _scrolledUp))
        TextButton.icon(
          key: const ValueKey('case-header-fold'),
          onPressed: () => setState(() {
            _detailsWanted = false;
            _scrolledUp = false;
          }),
          icon: const Icon(Icons.expand_less_rounded, size: 18),
          label: const Text('Daralt'),
        ),
      if (widget.onNewPetition != null)
        FilledButton.icon(
          key: const ValueKey('case-petition'),
          onPressed: () => widget.onNewPetition!(_c.link ?? linkOf(kase)),
          icon: const Icon(Icons.edit_note_rounded, size: 18),
          label: const Text('Dilekçe yaz'),
        ),
      OutlinedButton.icon(
        key: const ValueKey('case-refresh'),
        onPressed: _c.busy != null ? null : () => unawaited(_refresh()),
        icon: const Icon(Icons.sync_rounded, size: 17),
        label: const Text('UYAP’tan tazele'),
      ),
      if (_fresh.isNotEmpty)
        OutlinedButton.icon(
          key: const ValueKey('case-download-fresh'),
          onPressed: _c.busy != null ? null : () => unawaited(_downloadFresh()),
          icon: const Icon(Icons.download_rounded, size: 17),
          label: const Text('Yeni evrakları indir'),
        ),
      PopupMenuButton<String>(
        tooltip: 'Diğer',
        icon: const Icon(Icons.more_horiz_rounded),
        onSelected: (v) async {
          if (v == 'all') {
            final n = await _c.download();
            if (mounted) {
              ScaffoldMessenger.maybeOf(this.context)
                  ?.showSnackBar(SnackBar(content: Text('$n evrak indirildi')));
            }
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'all', child: Text('Tüm evrakları indir')),
        ],
      ),
    ];
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'UYAP Dosyalarım',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
                recognizer: null,
              ),
              TextSpan(text: ' › ${kind.label}'),
            ],
          ),
          style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
        ),
        const SizedBox(height: 4),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 4,
          children: [
            Text(
              kase.number,
              key: const ValueKey('case-number'),
              style: TextStyle(
                fontFamily: 'Consolas',
                fontFamilyFallback: const ['Cascadia Mono', 'monospace'],
                fontSize: facts ? 21 : (wide ? 26 : 21),
                fontWeight: FontWeight.w600,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: kind.fill,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${kind.label.toUpperCase()} · $degree',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .4,
                  color: kind.ink,
                ),
              ),
            ),
            if (status.isNotEmpty)
              switch (toneOf(status)) {
                StatusTone.open => _chip(
                  status,
                  const Color(0xFFEAF7F1),
                  const Color(0xFF157A52),
                ),
                StatusTone.closed => _chip(
                  status,
                  const Color(0xFFEEF0F3),
                  const Color(0xFF5D6474),
                ),
                StatusTone.other => _chip(
                  status,
                  AgendaColors.taskFill,
                  AgendaColors.taskText,
                ),
              },
          ],
        ),
        const SizedBox(height: 4),
        Text(kase.court, style: const TextStyle(fontSize: 15)),
        const SizedBox(height: 3),
        // The kind of case first and dark: it is what the case is about.
        Text.rich(
          TextSpan(
            children: [
              if (type.trim().isNotEmpty) ...[
                TextSpan(
                  text: type.trim(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const TextSpan(text: ' · '),
              ],
              TextSpan(
                text: [
                  if (opened != null) 'açılış ${dayText(opened)}',
                  record == null
                      ? 'yalnız künye — evraklar UYAP’tan ilk tazelemede gelir'
                      : 'son senkron ${whenText(record.fetchedAt, now)}',
                ].join(' · '),
              ),
            ],
          ),
          key: const ValueKey('case-type'),
          style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
        ),
      ],
    );
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: wide
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      tooltip: 'UYAP Dosyalarım’a dön',
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: facts
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [info, _factsLine(context)],
                            )
                          : info,
                    ),
                    const SizedBox(width: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: actions),
                  ],
                ),
                if (facts) _partyStrip(context),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      tooltip: 'UYAP Dosyalarım’a dön',
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(child: info),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ),
    );
  }

  bool get _mayGiveTask {
    final net = OfficeNetwork.instance;
    return net.ledger.members.any((m) => net.mayGive(m.deviceId));
  }

  /// Görev ver from a document: its case and it, already chosen.
  Future<void> _giveTaskWith(UyapCaseDocument d) => showDialog<void>(
    context: context,
    builder: (_) => TaskGiveDialog(
      network: OfficeNetwork.instance,
      initialCaseKey: widget.caseKey,
      initialDocKey: d.key,
    ),
  );

  /// The sides in the heading when the page has no room for their cards:
  /// whom the lawyer stands for and against whom, with their roles and
  /// counsel; the rest a tap away in Taraflar.
  Widget _partyStrip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lawyer = widget.lawyer.isNotEmpty
        ? widget.lawyer
        : UyapMobileApi.instance.session.value?.user ?? '';
    final (ours, others) = splitParties(
      _c.record?.parties ?? const <UyapParty>[],
      lawyer,
    );
    if (ours.isEmpty && others.isEmpty) return const SizedBox.shrink();
    // Our side's counsel is the reader; the other side's is worth naming.
    Widget side(
      String label,
      Color color,
      List<UyapParty> list, {
      bool counsel = true,
    }) {
      final shown = list.take(2).toList();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .7,
                  color: color,
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: titleName(p.name),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                          if (p.role.trim().isNotEmpty)
                            TextSpan(text: '  ${titleName(p.role)}'),
                          if (counsel && p.lawyer.trim().isNotEmpty)
                            TextSpan(
                              text:
                                  ' · Vekil: ${titleName(p.lawyer.trim().replaceAll(RegExp(r'^\[|\]$'), ''))}',
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AgendaColors.muted,
                      ),
                    ),
                  ),
                if (list.length > 2)
                  InkWell(
                    onTap: () => setState(() => _tab = _Tab.parties),
                    child: Text(
                      '+${list.length - 2} taraf daha',
                      style: TextStyle(fontSize: 12, color: scheme.primary),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      key: const ValueKey('case-parties-strip'),
      margin: const EdgeInsets.only(top: 12, left: 54),
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ours.isEmpty
          ? side('TARAFLAR', AgendaColors.muted, others)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: side(
                    'MÜVEKKİL',
                    const Color(0xFF157A52),
                    ours,
                    counsel: false,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(child: side('KARŞI', const Color(0xFFB7791F), others)),
              ],
            ),
    );
  }

  Widget _status(BuildContext context) => _card(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: Row(
      children: [
        if (_c.busy != null) ...[
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            _c.busy ?? _c.error ?? '',
            style: TextStyle(
              fontSize: 12.5,
              color: _c.busy != null
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _partyCards(BuildContext context, bool wide) {
    final parties = _c.record?.parties ?? const <UyapParty>[];
    final lawyer = widget.lawyer.isNotEmpty
        ? widget.lawyer
        : UyapMobileApi.instance.session.value?.user ?? '';
    final (ours, others) = splitParties(parties, lawyer);
    Widget person(UyapParty party, {required bool mine}) {
      final name = titleName(party.name);
      final institution = party.kind.toLowerCase().contains('kurum');
      final initials = name
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .take(2)
          .map((w) => w.substring(0, 1))
          .join();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFEEF1F5),
                shape: BoxShape.circle,
              ),
              child: institution
                  ? const Icon(
                      Icons.apartment_rounded,
                      size: 16,
                      color: Color(0xFF4B5465),
                    )
                  : Text(
                      initials,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF4B5465),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    party.lawyer.trim().isEmpty
                        ? 'vekili yok'
                        : 'Vekil: ${titleName(party.lawyer.trim())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AgendaColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF1F5),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                '${titleName(party.role)}${mine ? ' · müvekkil' : ''}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF4B5465)),
              ),
            ),
          ],
        ),
      );
    }

    Widget side(String title, Color top, List<UyapParty> list, bool mine) =>
        _card(
          // The side's colour as a band along the top, inside the rounded card:
          // a border of two colours cannot be rounded.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(height: 3, color: top),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
                  child: _sideBody(title, list, mine, person),
                ),
              ],
            ),
          ),
        );
    final mine = side(
      ours.isEmpty ? 'TARAFLAR' : 'BİZİM TARAF',
      const Color(0xFF157A52),
      ours.isEmpty ? others : ours,
      ours.isNotEmpty,
    );
    if (ours.isEmpty) return mine;
    final theirs = side('KARŞI TARAF', const Color(0xFFE0A23B), others, false);
    return wide
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: mine),
                const SizedBox(width: 12),
                Expanded(child: theirs),
              ],
            ),
          )
        : Column(children: [mine, const SizedBox(height: 12), theirs]);
  }

  Widget _sideBody(
    String title,
    List<UyapParty> list,
    bool mine,
    Widget Function(UyapParty party, {required bool mine}) person,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '$title · ${list.length}',
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: .8,
          color: AgendaColors.muted,
        ),
      ),
      const SizedBox(height: 4),
      if (list.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'Taraf bilgisi UYAP’tan tazelenince gelir.',
            style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
          ),
        ),
      for (final party in list.take(4)) person(party, mine: mine),
      if (list.length > 4)
        Text(
          '+${list.length - 4} taraf daha',
          style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
        ),
    ],
  );

  /// The documents newest first, sorted once a record, not at each frame.
  List<UyapCaseDocument> get _documents {
    final record = _c.record;
    if (!identical(record, _sortedFor)) {
      _sortedFor = record;
      final none = DateTime(1900);
      _sorted = [...?record?.documents]
        ..sort((a, b) => (b.date ?? none).compareTo(a.date ?? none));
    }
    return _sorted;
  }

  UyapCaseRecord? _sortedFor;
  List<UyapCaseDocument> _sorted = const [];

  Widget _summaries(BuildContext context, bool wide) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final docs = _documents;
    final newest = docs.isEmpty ? null : docs.first;
    final upcoming = [
      for (final h in _hearings)
        if (!h.at.isBefore(today)) h,
    ]..sort((a, b) => a.at.compareTo(b.at));
    final hearing = upcoming.firstOrNull;
    final deadlines = [
      for (final i in _items)
        if (i.kind == 'deadline' && !i.done && i.at != null) i,
    ]..sort((a, b) => a.at!.compareTo(b.at!));
    final deadline = deadlines.firstOrNull;
    // On a phone, smaller and on two lines: a case's newest document's
    // name is read whole, with the phone's own larger letters too.
    final phone = MediaQuery.sizeOf(context).width < 600;
    Widget box(
      String title,
      String value,
      String sub, {
      Color? valueColor,
      bool warn = false,
    }) => _card(
      padding: phone
          ? const EdgeInsets.fromLTRB(12, 9, 12, 9)
          : const EdgeInsets.fromLTRB(14, 11, 14, 11),
      border: Border.all(
        color: warn
            ? const Color(0xFFF0B4AF)
            : Theme.of(context).colorScheme.outlineVariant,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: phone ? 9.5 : 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: phone ? .5 : .8,
              color: AgendaColors.muted,
            ),
          ),
          SizedBox(height: phone ? 3 : 4),
          Text(
            value,
            maxLines: phone ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: phone ? 13.5 : 15,
              height: phone ? 1.2 : null,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: phone ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: phone ? 11 : 12,
              height: phone ? 1.2 : null,
              color: AgendaColors.muted,
            ),
          ),
        ],
      ),
    );
    final hearingDays = hearing == null
        ? null
        : DateTime(
            hearing.at.year,
            hearing.at.month,
            hearing.at.day,
          ).difference(today).inDays;
    final deadlineDays = deadline == null
        ? null
        : DateTime(
            deadline.at!.year,
            deadline.at!.month,
            deadline.at!.day,
          ).difference(today).inDays;
    final boxes = [
      box(
        'SON GELİŞME',
        _state.change ??
            (newest == null
                ? 'Henüz evrak yok'
                : (newest.type.isNotEmpty ? newest.type : newest.title)),
        _state.changeAt != null
            ? whenText(_state.changeAt!, now)
            : newest?.date == null
            ? '—'
            : '${dayText(newest!.date!)}${_fresh.contains(newest.key) ? ' · yeni' : ''}',
      ),
      box(
        'DURUŞMA',
        hearing == null
            ? 'Yaklaşan duruşma yok'
            : hearingDays == 0
            ? 'Bugün ${clockText(hearing.at)}'
            : '$hearingDays gün · ${dayText(hearing.at)}',
        hearing == null
            ? 'Ajanda UYAP’tan güncellenir'
            : [
                hearing.isEHearing ? 'E-duruşma' : 'Duruşma',
                if ((hearing.kind?.value ?? '').trim().isNotEmpty)
                  hearing.kind!.value.trim(),
                clockText(hearing.at),
              ].join(' · '),
        valueColor: hearingDays != null && hearingDays <= 1
            ? AgendaColors.deadline
            : null,
        warn: hearingDays != null && hearingDays <= 7,
      ),
      box(
        'SÜRE',
        deadline == null
            ? 'Açık süre yok'
            : '${deadline.title} · ${deadlineDays! <= 0 ? 'bugün' : '$deadlineDays gün'}',
        deadline == null
            ? 'Ajandadan eklenir'
            : '${dayText(deadline.at!)} son gün',
        warn: deadlineDays != null && deadlineDays <= 3,
      ),
      box(
        'DİLEKÇELERİM',
        '${_petitions.length} belge',
        _petitions.isEmpty
            ? 'Dilekçe yaz ile başlayın'
            : p.basenameWithoutExtension(_petitions.last),
      ),
    ];
    return wide
        ? Row(
            children: [
              for (final (i, b) in boxes.indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: b),
              ],
            ],
          )
        // Two by two, as tall as their words: a set height cut them.
        : Column(
            children: [
              for (var i = 0; i < boxes.length; i += 2) ...[
                if (i > 0) const SizedBox(height: 10),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: boxes[i]),
                      const SizedBox(width: 10),
                      Expanded(
                        child: i + 1 < boxes.length
                            ? boxes[i + 1]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
  }

  /// [entries]: the documents' rows, without the card: they follow it
  /// row by row in the page's own scroll (see [_documentEntries]).
  Widget _tabsCard(
    BuildContext context,
    bool wide, {
    List<({String? bucket, UyapCaseDocument? doc, int? attachment})>? entries,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tabBar(context),
        _tabBody(context, wide, entries: entries),
      ],
    );
    return entries != null ? content : _card(child: content);
  }

  Widget _tabBody(
    BuildContext context,
    bool wide, {
    List<({String? bucket, UyapCaseDocument? doc, int? attachment})>? entries,
  }) => switch (_tab) {
    _Tab.documents => _documentsTab(context, wide, entries: entries),
    _Tab.hearings => _hearingsTab(context),
    _Tab.deadlines => _deadlinesTab(context),
    _Tab.parties => _partiesTab(context),
    _Tab.notices => _noticesTab(context),
    _Tab.facts => _factsTab(context),
    _Tab.petitions => _petitionsTab(context),
    _Tab.tasks => _tasksTab(context),
  };

  /// The office's tasks over this case: given here, followed here.
  Widget _tasksTab(BuildContext context) => ListenableBuilder(
    listenable: OfficeNetwork.instance,
    builder: (context, _) {
      final net = OfficeNetwork.instance;
      final now = DateTime.now();
      final tasks = [
        for (final t in net.tasks.all)
          if (t.cases.any((c) => c.caseKey == widget.caseKey)) t,
      ];
      final canGive = net.ledger.members.any((m) => net.mayGive(m.deviceId));
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canGive)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const ValueKey('case-give-task'),
                  onPressed: () => unawaited(
                    showDialog<void>(
                      context: context,
                      builder: (_) => TaskGiveDialog(
                        network: net,
                        initialCaseKey: widget.caseKey,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add_task_rounded, size: 18),
                  label: const Text('Bu dosya için görev ver'),
                ),
              ),
            if (tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Bu dosyaya bağlı görev yok.',
                  style: TextStyle(color: AgendaColors.muted),
                ),
              ),
            for (final t in tasks)
              ListTile(
                key: ValueKey('case-task-${t.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(t.title),
                subtitle: Text(
                  '${t.stage.label} · %${t.percent} · ${dueOf(t, now).$1} · '
                  '${t.byName} → ${t.assignees.values.join(', ')}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => unawaited(TaskDetail.show(context, net, t)),
              ),
          ],
        ),
      );
    },
  );

  Widget _tabBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final docs = _c.record?.documents ?? const <UyapCaseDocument>[];
    final docCount = docs.fold<int>(0, (s, d) => s + 1 + d.attachments.length);
    final deadlines = _items.where((i) => !i.done).length + _notices.length;
    final parties = _c.record?.parties.length ?? 0;
    Widget tab(_Tab t, String label, int? count, {int fresh = 0}) => InkWell(
      key: ValueKey('case-tab-${t.name}'),
      onTap: () => setState(() => _tab = t),
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 10),
        margin: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: _tab == t ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: _tab == t ? FontWeight.w600 : FontWeight.w400,
                color: _tab == t ? null : AgendaColors.muted,
              ),
            ),
            if (count != null && count > 0)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AgendaColors.muted,
                  ),
                ),
              ),
            if (fresh > 0)
              Container(
                margin: const EdgeInsets.only(left: 5),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$fresh yeni',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            tab(_Tab.documents, 'Evraklar', docCount, fresh: _fresh.length),
            tab(
              _Tab.notices,
              'Bildirimler',
              _uyapNotices.length,
              fresh: _uyapNotices.where((n) => !n.read).length,
            ),
            tab(_Tab.hearings, 'Duruşmalar', _hearings.length),
            tab(_Tab.deadlines, 'Süreler & Tebligat', deadlines),
            tab(_Tab.parties, 'Taraflar', parties),
            tab(_Tab.facts, 'Künye', null),
            tab(_Tab.petitions, 'Dilekçelerim', _petitions.length),
            tab(
              _Tab.tasks,
              'Görevler',
              OfficeNetwork.instance.tasks.all
                  .where((t) => t.cases.any((c) => c.caseKey == widget.caseKey))
                  .length,
            ),
          ],
        ),
      ),
    );
  }

  // Documents.

  bool _isDecision(UyapCaseDocument d) => _folded(d).kind.contains('karar');
  bool _isPetition(UyapCaseDocument d) => _folded(d).kind.contains('dilekce');

  /// Which documents are on disk, looked at once a record, not at every
  /// row of every frame: a list of hundreds stuttered as it scrolled.
  bool _downloaded(UyapCaseDocument d) {
    final record = _c.record;
    if (record == null) return false;
    if (!identical(record, _onDiskFor)) {
      _onDiskFor = record;
      _onDisk = {
        for (final key in record.files.keys)
          if (_c.store.fileOf(record, key) != null) key,
      };
    }
    return _onDisk.contains(d.key);
  }

  UyapCaseRecord? _onDiskFor;
  Set<String> _onDisk = const {};

  /// A document's words folded, once a record: what the search looks in,
  /// and its kind.
  ({String search, String kind}) _folded(UyapCaseDocument d) {
    final record = _c.record;
    if (!identical(record, _foldedFor)) {
      _foldedFor = record;
      _foldedText.clear();
    }
    return _foldedText[d.key] ??= (
      search: UyapWebService.fold('${d.title} ${d.sender} ${d.approved}'),
      kind: UyapWebService.fold('${d.type} ${d.description}'),
    );
  }

  UyapCaseRecord? _foldedFor;
  final _foldedText = <String, ({String search, String kind})>{};

  /// [q]: the search, folded once for the whole list.
  bool _shows(UyapCaseDocument d, String q) {
    if (q.isNotEmpty && !_folded(d).search.contains(q)) return false;
    return switch (_filter) {
      _DocFilter.all => true,
      _DocFilter.fresh => _fresh.contains(d.key),
      _DocFilter.decisions => _isDecision(d),
      _DocFilter.petitions => _isPetition(d),
      _DocFilter.notDownloaded => !_downloaded(d),
    };
  }

  static const _months = [
    'OCAK', 'ŞUBAT', 'MART', 'NİSAN', 'MAYIS', 'HAZİRAN', //
    'TEMMUZ', 'AĞUSTOS', 'EYLÜL', 'EKİM', 'KASIM', 'ARALIK',
  ];

  String _bucket(DateTime? d) {
    if (d == null) return 'TARİHİ BİLİNMİYOR';
    final now = DateTime.now();
    if (now.difference(d).inDays < 7) return 'BU HAFTA';
    return '${_months[d.month - 1]} ${d.year}';
  }

  /// [entries]: the rows, made already, which then follow the tab in the
  /// page's own scroll rather than in it.
  Widget _documentsTab(
    BuildContext context,
    bool wide, {
    List<({String? bucket, UyapCaseDocument? doc, int? attachment})>? entries,
  }) {
    final head = entries != null;
    final scheme = Theme.of(context).colorScheme;
    final record = _c.record;
    if (record == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              'Bu dosyanın evrak listesi henüz alınmadı.',
              style: TextStyle(color: AgendaColors.muted),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _c.busy != null ? null : () => unawaited(_refresh()),
              icon: const Icon(Icons.sync_rounded, size: 17),
              label: const Text('UYAP’tan getir'),
            ),
          ],
        ),
      );
    }
    final docs = _documents;
    Widget filter(_DocFilter f, String label) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        key: ValueKey('case-filter-${f.name}'),
        label: Text(label),
        selected: _filter == f,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _filter = f),
      ),
    );
    final shown = entries ?? _documentEntries();
    final rows = head
        ? const <Widget>[]
        : [for (final e in shown) _entryRow(context, e)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: wide ? 340 : double.infinity,
                child: TextField(
                  key: const ValueKey('case-doc-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    hintText: 'Evrak ara: bilirkişi, gerekçeli karar, 2025',
                  ),
                ),
              ),
              filter(_DocFilter.all, 'Tümü'),
              if (_fresh.isNotEmpty)
                filter(_DocFilter.fresh, 'Yeni gelenler · ${_fresh.length}'),
              filter(_DocFilter.decisions, 'Kararlar'),
              filter(_DocFilter.petitions, 'Dilekçeler'),
              filter(_DocFilter.notDownloaded, 'İndirilmemiş'),
              Text(
                'Evrak listesi ${whenText(record.fetchedAt, DateTime.now())}’de tazelendi',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AgendaColors.muted,
                ),
              ),
            ],
          ),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              docs.isEmpty
                  ? (record.withheld ?? 'UYAP bu dosyada evrak listelemedi.')
                  : 'Bu süzgece uyan evrak yok.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AgendaColors.muted),
            ),
          ),
        ...rows,
        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0)),
        const SizedBox(height: 8),
      ],
    );
  }

  /// The documents' list as it shows: a month's heading, a document, an
  /// attachment, in order. Light to make; each row is built only when it
  /// is on the screen (a case of seven hundred documents built them all at
  /// every change, and stuttered as it scrolled).
  /// Made again only when the record, the search, the filter or the new
  /// ones change: a sync's progress, told often, leaves it as it was.
  List<({String? bucket, UyapCaseDocument? doc, int? attachment})>
  _documentEntries() {
    final q = UyapWebService.fold(_search.text.trim());
    final record = _c.record;
    final key = (_filter, q, _fresh.length);
    if (identical(record, _entriesFor) && key == _entriesKey) return _entries;
    final out = <({String? bucket, UyapCaseDocument? doc, int? attachment})>[];
    String? bucket;
    for (final d in _documents) {
      final children = [
        for (final a in d.attachments)
          if (_shows(a, q)) a,
      ];
      if (!_shows(d, q) && children.isEmpty) continue;
      final b = _bucket(d.date);
      if (b != bucket) {
        bucket = b;
        out.add((bucket: b, doc: null, attachment: null));
      }
      out.add((bucket: null, doc: d, attachment: null));
      for (final (i, a) in children.indexed) {
        out.add((bucket: null, doc: a, attachment: i + 1));
      }
    }
    _entriesFor = record;
    _entriesKey = key;
    return _entries = out;
  }

  UyapCaseRecord? _entriesFor;
  (_DocFilter, String, int)? _entriesKey;
  List<({String? bucket, UyapCaseDocument? doc, int? attachment})> _entries =
      const [];

  Widget _entryRow(
    BuildContext context,
    ({String? bucket, UyapCaseDocument? doc, int? attachment}) e, {
    bool split = false,
  }) => e.doc == null
      ? Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
          child: Text(
            e.bucket!,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: .9,
              color: AgendaColors.muted,
            ),
          ),
        )
      : _docRow(context, e.doc!, attachment: e.attachment, split: split);

  /// [split]: beside the preview, where a click shows the document and a
  /// double click opens it; elsewhere a tap shows it on a page of its own.
  Widget _docRow(
    BuildContext context,
    UyapCaseDocument d, {
    int? attachment,
    bool split = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final fresh = _fresh.contains(d.key);
    final downloaded = _downloaded(d);
    final shown = split && d.key == _shownKey;
    final folded = _folded(d).kind;
    final (icon, ink) = _isDecision(d)
        ? (Icons.gavel_rounded, AgendaColors.deadline)
        : _isPetition(d)
        ? (Icons.edit_note_rounded, scheme.primary)
        : folded.contains('zabt') ||
              folded.contains('zapt') ||
              folded.contains('tutanak')
        ? (Icons.receipt_long_outlined, const Color(0xFF4B5465))
        : folded.contains('teblig') || folded.contains('muzekkere')
        ? (Icons.mail_outline_rounded, const Color(0xFF4B5465))
        : (Icons.description_outlined, const Color(0xFF4B5465));
    final title = d.type.isNotEmpty ? d.type : d.title;
    final meta = [
      if (attachment != null) 'Ek $attachment',
      if (d.date != null) dayText(d.date!),
      if (d.sender.trim().isNotEmpty) titleName(d.sender.trim()),
      if (d.description.isNotEmpty && d.description != d.type) d.description,
    ].join(' · ');
    final row = InkWell(
      key: ValueKey('case-doc-${d.key}'),
      onTap: split ? () => _tapped(d) : () => unawaited(_openPreviewPage(d)),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          attachment == null ? (split ? 15 : 18) : (split ? 44 : 58),
          8,
          split ? 12 : 18,
          8,
        ),
        decoration: BoxDecoration(
          color: shown
              ? scheme.primary.withValues(alpha: .1)
              : fresh
              ? const Color(0xFFF6F9FE)
              : null,
          border: split
              ? Border(
                  left: BorderSide(
                    color: shown ? scheme.primary : Colors.transparent,
                    width: 3,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F7),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, size: 16, color: ink),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (fresh)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'YENİ',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .4,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AgendaColors.muted,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (split)
              _fetchingKey == d.key
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Tooltip(
                      message: downloaded ? 'İndirildi' : 'İndirilmedi',
                      child: Icon(
                        downloaded
                            ? Icons.check_circle_outline_rounded
                            : Icons.download_rounded,
                        size: 17,
                        color: downloaded
                            ? const Color(0xFF157A52)
                            : scheme.primary,
                      ),
                    )
            else ...[
              Text(
                downloaded ? 'indirildi' : (fresh ? 'okunmadı' : ''),
                style: TextStyle(
                  fontSize: 11.5,
                  color: downloaded
                      ? const Color(0xFF157A52)
                      : AgendaColors.taskText,
                ),
              ),
              IconButton(
                tooltip: downloaded ? 'Aç' : 'İndir ve aç',
                onPressed: () => unawaited(_open(d)),
                icon: Icon(
                  downloaded
                      ? Icons.folder_open_outlined
                      : Icons.download_rounded,
                  size: 18,
                  color: downloaded ? const Color(0xFF9AA2B1) : scheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return shown ? KeyedSubtree(key: _shownRow, child: row) : row;
  }

  // The other tabs.

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AgendaColors.muted),
    ),
  );

  Widget _line(
    String title,
    String sub, {
    Widget? leading,
    Widget? trailing,
    bool dim = false,
    Color? accent,
  }) => Opacity(
    opacity: dim ? .55 : 1,
    child: Container(
      padding: const EdgeInsets.fromLTRB(18, 9, 18, 9),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: accent ?? Colors.transparent, width: 3),
          top: const BorderSide(color: Color(0xFFF0F2F6)),
        ),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AgendaColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );

  Widget _hearingsTab(BuildContext context) {
    if (_hearings.isEmpty) {
      return _empty('Bu dosyanın ajandada duruşması yok.');
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final next = ([
      for (final h in _hearings)
        if (!h.at.isBefore(today)) h,
    ]..sort((a, b) => a.at.compareTo(b.at))).firstOrNull;
    return Column(
      children: [
        for (final h in _hearings)
          () {
            final days = DateTime(
              h.at.year,
              h.at.month,
              h.at.day,
            ).difference(today).inDays;
            return _line(
              '${h.isEHearing ? 'E-duruşma' : 'Duruşma'}'
              '${(h.kind?.value ?? '').trim().isEmpty ? '' : ' · ${h.kind!.value.trim()}'}',
              [
                dayText(h.at),
                clockText(h.at),
                days == 0
                    ? 'bugün'
                    : days > 0
                    ? '$days gün kaldı'
                    : '${-days} gün önce',
                if ((h.result?.value ?? '').trim().isNotEmpty)
                  h.result!.value.trim(),
              ].join(' · '),
              leading: SizedBox(
                width: 40,
                child: Text(
                  '${h.at.day}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              dim: days < 0,
              accent: identical(h, next) ? AgendaColors.hearing : null,
            );
          }(),
      ],
    );
  }

  Widget _deadlinesTab(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final items = [..._items]
      ..sort(
        (a, b) => (a.at ?? DateTime(2999)).compareTo(b.at ?? DateTime(2999)),
      );
    if (items.isEmpty && _notices.isEmpty) {
      return _empty(
        'Bu dosyaya bağlı süre ya da tebligat yok. Editörün Hukuk sekmesinden '
        '“Süre ekle” ile eklenebilir.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in items)
          () {
            final days = i.at == null
                ? null
                : DateTime(
                    i.at!.year,
                    i.at!.month,
                    i.at!.day,
                  ).difference(today).inDays;
            return _line(
              i.title,
              [
                if (i.at != null) dayText(i.at!),
                if (days != null && !i.done)
                  days < 0
                      ? 'süresi geçti'
                      : days == 0
                      ? 'bugün son gün'
                      : '$days gün',
                if (i.done) 'tamamlandı',
              ].join(' · '),
              leading: Icon(
                i.kind == 'deadline'
                    ? Icons.timer_outlined
                    : Icons.sticky_note_2_outlined,
                size: 18,
                color: AgendaColors.muted,
              ),
              dim: i.done,
              accent: !i.done && days != null && days <= 7
                  ? (days < 0 ? AgendaColors.deadline : AgendaColors.hearing)
                  : null,
            );
          }(),
        for (final n in _notices)
          _line(
            n.message.subject,
            [
              if (n.message.sent != null) dayText(n.message.sent!),
              n.message.sender,
              if (n.message.read == null) 'okunmadı',
            ].where((s) => s.trim().isNotEmpty).join(' · '),
            leading: const Icon(
              Icons.mark_email_unread_outlined,
              size: 18,
              color: AgendaColors.deadline,
            ),
          ),
      ],
    );
  }

  Widget _partiesTab(BuildContext context) {
    final parties = _c.record?.parties ?? const <UyapParty>[];
    if (parties.isEmpty) {
      return _empty('Taraf bilgisi UYAP’tan tazelenince gelir.');
    }
    return Column(
      children: [
        for (final t in parties)
          _line(
            titleName(t.name),
            [
              titleName(t.role),
              if (t.lawyer.trim().isNotEmpty) 'Vekil: ${titleName(t.lawyer)}',
              if (t.kind.trim().isNotEmpty) t.kind,
            ].join(' · '),
          ),
      ],
    );
  }

  Widget _factsTab(BuildContext context) {
    final record = _c.record;
    final kase = _kase!;
    final d = record?.details;
    final kept = kase.details?.value ?? const <String, Object?>{};
    final facts = <(String, String)>[
      ('Mahkeme', kase.court),
      ('Esas no', kase.number),
      if (d != null && d.kind.isNotEmpty) ('Dava türü', d.kind),
      if (d == null || d.kind.isEmpty)
        if ('${kept['tur'] ?? ''}'.isNotEmpty) ('Dosya türü', '${kept['tur']}'),
      if (d != null && d.opening.isNotEmpty) ('Açılış türü', d.opening),
      if ((kase.status?.value ?? '').isNotEmpty) ('Durum', kase.status!.value),
      if ('${kept['acilis'] ?? ''}'.isNotEmpty) ('Açılış', '${kept['acilis']}'),
      if ('${kept['kapanis'] ?? ''}'.isNotEmpty)
        ('Kapanış', '${kept['kapanis']}'),
      ...?d?.decision,
      ...?d?.related,
      ...?d?.enforcement,
      if (record?.money != null) ...[
        if (record!.money!.collected != null)
          ('Tahsilat', formatTl(record.money!.collected!)),
        if (record.money!.paidOut != null)
          ('Reddiyat', formatTl(record.money!.paidOut!)),
        if (record.money!.remaining != null)
          ('Kalan', formatTl(record.money!.remaining!)),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      child: Column(
        children: [
          for (final (label, value) in facts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AgendaColors.muted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      value,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The case's UYAP notifications; opened is read, here and on UYAP.
  Widget _noticesTab(BuildContext context) {
    if (_uyapNotices.isEmpty) {
      return _empty(
        'Bu dosya için UYAP bildirimi yok. UYAP Mobil ya da UYAP Web '
        'bağlıyken gelen bildirimler, dosyayı andıkları için buraya bağlanır.',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    return Column(
      children: [
        for (final n in _uyapNotices)
          InkWell(
            key: ValueKey('case-notice-${n.key}'),
            onTap: n.read ? null : () => unawaited(_readNotice(n)),
            child: _line(
              n.title,
              [
                if (n.body.isNotEmpty) n.body,
                [
                  for (final s in n.sources)
                    s == UyapNoticeSource.mobile ? 'Mobil' : 'Web',
                ].join(' + '),
                if (n.sentAt != null) whenText(n.sentAt!, now),
              ].join(' · '),
              leading: Icon(
                n.read
                    ? Icons.notifications_none_rounded
                    : Icons.notifications_active_rounded,
                size: 18,
                color: n.read ? AgendaColors.muted : scheme.primary,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _readNotice(UyapNotice n) async {
    final db = await _db;
    final sync = PortalSync.started;
    if (sync != null) {
      await sync.markNotices([n], read: true);
    } else {
      db.setUyapNoticeRead(n.rows, true);
    }
    if (!mounted || _kase == null) return;
    setState(() => _uyapNotices = db.uyapNotices(caseKey: _kase!.key));
  }

  Widget _petitionsTab(BuildContext context) {
    if (_petitions.isEmpty) {
      return _empty(
        'Bu dosya için yazılmış dilekçe yok. “Dilekçe yaz” ile '
        'mahkemesi ve esas numarası dolu bir dilekçe başlatın.',
      );
    }
    return Column(
      children: [
        for (final path in _petitions)
          InkWell(
            onTap: widget.onOpenPath == null
                ? null
                : () => widget.onOpenPath!(path),
            child: _line(
              p.basenameWithoutExtension(path),
              () {
                try {
                  return 'son değişiklik ${dayText(File(path).lastModifiedSync())}'
                      ' · ${p.extension(path).replaceFirst('.', '').toUpperCase()}';
                } catch (_) {
                  return '';
                }
              }(),
              leading: Icon(
                Icons.edit_note_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }
}

/// A case's documents one to a page, on a phone or a narrow window.
/// Said with a document sent from its case: which case and what it is.
String _sentWith(UyapCasePanelController c, UyapCaseDocument d) {
  final r = c.record;
  return [
    if (r != null) '${r.number} · ${r.court}',
    if (d.type.isNotEmpty) d.type else d.title,
  ].join('\n');
}

class _CasePreviewPage extends StatefulWidget {
  const _CasePreviewPage({
    required this.controller,
    required this.documents,
    required this.initial,
    required this.fetch,
    required this.open,
    this.giveTask,
  });

  final UyapCasePanelController controller;

  /// Görev ver with the document shown; null when there is no one to give to.
  final Future<void> Function(UyapCaseDocument d)? giveTask;
  final List<UyapCaseDocument> documents;
  final int initial;
  final Future<void> Function(UyapCaseDocument d) fetch;
  final Future<void> Function(UyapCaseDocument d) open;

  @override
  State<_CasePreviewPage> createState() => _CasePreviewPageState();
}

class _CasePreviewPageState extends State<_CasePreviewPage> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _at = widget.initial;
  String? _fetching;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _auto(_at));
  }

  /// The document come to: fetched at once when it is not here and UYAP is
  /// there to ask, as one opened to be read.
  void _auto(int i) {
    if (!mounted || i < 0 || i >= widget.documents.length) return;
    final d = widget.documents[i];
    if (_file(d) != null || _fetching != null) return;
    if (!widget.controller.connected) return;
    unawaited(_fetch(d));
  }

  @override
  void dispose() {
    if (_full) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pages.dispose();
    super.dispose();
  }

  /// The document and nothing else: no bars of this page, none of the
  /// phone's, no signature strip; back or the corner's button comes out.
  bool _full = false;

  void _setFull(bool value) {
    setState(() => _full = value);
    SystemChrome.setEnabledSystemUIMode(
      value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  /// Opened in Folio's own viewer, this page out of its way first: left
  /// on top, it hid the document it had opened.
  void _openInFolio(UyapCaseDocument d) {
    Navigator.of(context).pop();
    unawaited(widget.open(d));
  }

  String _name(UyapCaseDocument d) => d.type.isNotEmpty ? d.type : d.title;

  File? _file(UyapCaseDocument d) {
    final record = widget.controller.record;
    return record == null
        ? null
        : widget.controller.store.fileOf(record, d.key);
  }

  Future<void> _fetch(UyapCaseDocument d) async {
    setState(() => _fetching = d.key);
    try {
      await widget.fetch(d);
    } finally {
      if (mounted) setState(() => _fetching = null);
    }
  }

  void _go(int i) => unawaited(
    _pages.animateToPage(
      i,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final docs = widget.documents;
      final d = docs[_at];
      final file = _file(d);
      final pages = PageView.builder(
        controller: _pages,
        itemCount: docs.length,
        onPageChanged: (i) {
          setState(() => _at = i);
          _auto(i);
        },
        itemBuilder: (context, i) {
          final doc = docs[i];
          final kept = _file(doc);
          return kept != null
              ? FilePreview(
                  key: ValueKey('${kept.path}_$_full'),
                  path: kept.path,
                  chrome: !_full,
                )
              : _CaseDetailPageState._notHere(
                  context,
                  fetching: _fetching == doc.key,
                  onFetch: () => unawaited(_fetch(doc)),
                );
        },
      );
      if (_full) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (popped, _) {
            if (!popped) _setFull(false);
          },
          child: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(child: pages),
                Positioned(
                  top: 6,
                  right: 6,
                  child: SafeArea(
                    child: IconButton.filledTonal(
                      key: const ValueKey('case-preview-unfull'),
                      tooltip: 'Tam ekrandan çık',
                      onPressed: () => _setFull(false),
                      icon: const Icon(Icons.fullscreen_exit_rounded),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      Widget step(int to, {required bool back}) {
        final name = Text(
          _name(docs[to]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
        return TextButton(
          onPressed: () => _go(to),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: back
                ? [
                    const Icon(Icons.chevron_left_rounded),
                    Flexible(child: name),
                  ]
                : [
                    Flexible(child: name),
                    const Icon(Icons.chevron_right_rounded),
                  ],
          ),
        );
      }

      return Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _name(d),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
              Text(
                [
                  '${_at + 1} / ${docs.length}',
                  if (d.date != null) dayText(d.date!),
                ].join(' · '),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AgendaColors.muted,
                ),
              ),
            ],
          ),
          actions: [
            if (file == null)
              IconButton(
                tooltip: 'İndir',
                onPressed: _fetching != null
                    ? null
                    : () => unawaited(_fetch(d)),
                icon: const Icon(Icons.download_rounded),
              )
            else ...[
              // A phone's bar keeps room for the document's name: sending
              // to the office is in "Diğer".
              IconButton(
                key: const ValueKey('case-preview-share'),
                tooltip: 'Paylaş',
                onPressed: () => unawaited(shareAs(context, file.path)),
                icon: const Icon(Icons.share_outlined),
              ),
              IconButton(
                key: const ValueKey('case-preview-full'),
                tooltip: 'Tam ekran',
                onPressed: () => _setFull(true),
                icon: const Icon(Icons.fullscreen_rounded),
              ),
              PopupMenuButton<String>(
                tooltip: 'Diğer',
                onSelected: (v) => switch (v) {
                  'gorev' => unawaited(widget.giveTask!(d)),
                  'gonder' => unawaited(
                    showSendToOffice(context, [
                      file.path,
                    ], text: _sentWith(widget.controller, d)),
                  ),
                  _ => _openInFolio(d),
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'folio',
                    child: Text('Folio’da aç'),
                  ),
                  if (OfficeNetwork.instance.sendTargets.isNotEmpty)
                    const PopupMenuItem(value: 'gonder', child: Text('Gönder')),
                  if (widget.giveTask != null)
                    const PopupMenuItem(
                      value: 'gorev',
                      child: Text('Bu evrakla görev ver'),
                    ),
                ],
              ),
            ],
          ],
        ),
        body: pages,
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    // Its own height: left to fill, it took the page's.
                    heightFactor: 1,
                    child: _at > 0
                        ? step(_at - 1, back: true)
                        : const SizedBox.shrink(),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    heightFactor: 1,
                    child: _at < docs.length - 1
                        ? step(_at + 1, back: false)
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
