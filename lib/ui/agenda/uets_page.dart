import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/portal/portal_case.dart';
import '../../services/portal/portal_channel.dart';
import '../../services/legal/deadlines/aidiyet.dart';
import '../../services/legal/deadlines/belge_turu.dart';
import '../../services/legal/deadlines/turkish_legal_calendar.dart';
import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_deadline.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/uets/envelope_directives.dart';
import '../../services/uets/notice_deadlines.dart';
import '../../services/uets/notice_documents.dart';
import '../../services/uets/notice_matcher.dart';
import '../../services/uets/notice_packages.dart';
import '../../services/uets/uets_api.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../../services/uyap/uyap_web_service.dart' show UyapParty;
import 'agenda_page.dart' show AgendaColors;
import '../help/help_button.dart';
import '../mobile/scroll_chrome.dart';
import '../portfolio/portfolio_rows.dart' show titleName;
import 'channel_bar.dart';
import '../office/send_to_office.dart';
import 'deadline_choice_dialog.dart';
import 'deadline_review.dart';
import 'uets_connect.dart';
import '../theme/folio_palette.dart';

enum _Filter { all, pending, unread, withDeadline, untied }

/// Tebligatlarım (UYGULAMAPLANI §10, T10): the notifications kept on
/// this computer, each with the case it was tied to and the deadlines it
/// started; the attachments are fetched from UETS on demand. In the
/// agenda's colours and cards.
class UetsPage extends StatefulWidget {
  final PortalDatabase? database;
  final PortalSync? sync;
  final DateTime Function()? now;

  /// Shows a case's page; false when Folio has no page for it yet.
  final bool Function(String caseKey)? onOpenCase;

  /// Opens a downloaded attachment in Folio.
  final void Function(String path)? onOpenFile;

  /// The notice to show selected, coming from its deadline elsewhere.
  final String? initialNotice;

  /// Where the cases' parties are read from, for whom the lawyer acts for;
  /// the app's own unless a test passes one.
  final UyapCaseStore? store;

  /// Something kept changed: the sidebar's count may need refreshing.
  final VoidCallback? onChanged;

  const UetsPage({
    super.key,
    this.database,
    this.sync,
    this.now,
    this.onOpenCase,
    this.onOpenFile,
    this.onChanged,
    this.initialNotice,
    this.store,
  });

  @override
  State<UetsPage> createState() => _UetsPageState();
}

class _UetsPageState extends State<UetsPage> {
  PortalDatabase? _db;
  List<KeptNotice> _notices = const [];
  Map<String, PortalCase> _cases = const {};
  List<KeptDeadline> _deadlines = const [];
  Map<String, NoticeEnvelope> _envelopes = const {};
  Map<
    String,
    ({String state, String? fetchedAt, List<({String id, String name})> parts})
  >
  _manifests = const {};
  _Filter _filter = _Filter.all;

  /// The words the list is narrowed to: a court, a number, a kind.
  String _search = '';
  String? _selected;
  final Map<String, List<UetsPart>> _parts = {};
  String? _partsLoading;
  String? _downloading;
  String? _partsProblem;
  Timer? _clock;

  /// A phone's width (§13): two rows on top, the stats in a strip, the
  /// notice on a page of its own.
  bool _narrow = false;

  /// Ticks with every change, for the notice's own page.
  final _changes = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _changes.value++;
  }

  DateTime _now() => (widget.now ?? DateTime.now)();
  PortalSync get _sync => widget.sync ?? PortalSync.instance;
  UetsApi get _api => _sync.uets;

  @override
  void initState() {
    super.initState();
    _sync.addListener(_syncChanged);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_open());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _reloadSoon?.cancel();
    _changes.dispose();
    _sync.removeListener(_syncChanged);
    super.dispose();
  }

  /// Read again when a sync ends, and while one runs at most every few
  /// seconds: a thousand notices read at every word of its progress held
  /// the window.
  void _syncChanged() {
    if (!mounted) return;
    // The other channels' news is not this page's.
    final now = _sync.state(PortalChannel.uets);
    final was = _uetsWas;
    _uetsWas = now;
    if (was != null &&
        was.running == now.running &&
        was.finished == now.finished &&
        was.problem == now.problem &&
        was.progress == now.progress) {
      return;
    }
    final running = now.running;
    if (running) {
      _reloadSoon ??= Timer(const Duration(seconds: 3), () {
        _reloadSoon = null;
        if (!mounted) return;
        _reload();
        widget.onChanged?.call();
      });
      setState(() {});
      return;
    }
    _reloadSoon?.cancel();
    _reloadSoon = null;
    _reload();
    widget.onChanged?.call();
  }

  Timer? _reloadSoon;
  ChannelSync? _uetsWas;

  Future<void> _open() async {
    final db = widget.database ?? await PortalDatabase.shared();
    if (!mounted) return;
    _db = db;
    _reload();
    // Opened on one notice, from the home page or a notification: that
    // one is looked at.
    final asked = widget.initialNotice;
    if (asked != null &&
        _notices.any((n) => n.message.id == asked && n.unread)) {
      _markSeen([asked]);
    }
    if (_api.connected) await _sync.syncUets();
  }

  void _reload() {
    final db = _db;
    if (db == null) return;
    setState(() {
      _notices = db.notices();
      _cases = db.cases();
      _deadlines = db.deadlines();
      _envelopes = db.envelopes();
      _manifests = db.manifests();
      if (_selected == null ||
          !_notices.any((n) => n.message.id == _selected)) {
        _selected =
            _notices
                .where((n) => n.message.id == widget.initialNotice)
                .firstOrNull
                ?.message
                .id ??
            _notices.firstOrNull?.message.id;
      }
    });
  }

  /// [n]'s deadlines, not set aside by the lawyer.
  List<KeptDeadline> _of(KeptNotice n) {
    // Grouped by notice once for each reading of the deadlines: looked up
    // for every notice on every build, all of them were scanned each time.
    if (!identical(_byNoticeOf, _deadlines)) {
      _byNoticeOf = _deadlines;
      _byNotice = {};
      for (final d in _deadlines) {
        if (d.user?.dismissed ?? false) continue;
        (_byNotice[d.record.noticeId] ??= []).add(d);
      }
    }
    return _byNotice[n.message.id] ?? const [];
  }

  List<KeptDeadline>? _byNoticeOf;
  var _byNotice = <String, List<KeptDeadline>>{};

  /// What the notice is, by its documents' names, else by its envelope's
  /// heading, else by its subject.
  String _kindOf(KeptNotice n) {
    final names = <String>[
      for (final p in _manifests[n.message.id]?.parts ?? const []) p.name,
    ];
    final kinds = BelgeTuruTespit.ekTurleri(names);
    if (kinds.isNotEmpty) return belgeTuruEtiket[kinds.first.tur] ?? '';
    final text = _envelopes[n.message.id]?.envelopeText ?? '';
    if (text.isNotEmpty) {
      final t = BelgeTuruTespit.tebligatTuru(const [], metin: text);
      if (!BelgeTuruTespit.belirsiz(t)) return belgeTuruEtiket[t] ?? '';
    }
    return noticeKind(n.message);
  }

  /// The notice's nearest deadline, as its row shows it.
  (Color, Color, IconData, String)? _badge(KeptNotice n) {
    final live = [
      for (final d in _of(n))
        if (d.record.state != 'eski' && !(d.user?.done ?? false)) d,
    ];
    final dated = live.where((d) => d.day != null).toList()
      ..sort((a, b) => a.day!.compareTo(b.day!));
    final ours = dated.where((d) => d.record.ownership != 'olasiKarsi');
    if (ours.isNotEmpty) {
      final d = ours.first;
      final day = _date(DateTime.parse(d.day!));
      return d.onAgenda
          ? (
              AgendaColors.deadlineFill,
              AgendaColors.deadlineText,
              Icons.timer_outlined,
              '$day · onaylı',
            )
          : (
              AgendaColors.taskFill,
              AgendaColors.taskText,
              Icons.pending_actions_outlined,
              '$day · onay bekliyor',
            );
    }
    if (dated.isNotEmpty) {
      return (
        tone(const Color(0xFFEEF0F3)),
        AgendaColors.muted,
        Icons.swap_horiz,
        'Karşı tarafın süresi',
      );
    }
    if (live.isNotEmpty) {
      return (
        tone(const Color(0xFFEEF0F3)),
        AgendaColors.muted,
        Icons.help_outline,
        'Süreyi kontrol edin',
      );
    }
    final e = _envelopes[n.message.id];
    return e == null
        ? (
            tone(const Color(0xFFEEF0F3)),
            AgendaColors.muted,
            Icons.downloading,
            'Paket bekleniyor',
          )
        : (
            tone(const Color(0xFFEEF0F3)),
            AgendaColors.muted,
            Icons.check,
            'Süre yok',
          );
  }

  /// Lower case the Turkish way, for the search.
  static String _fold(String s) =>
      s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

  int get _pendingCount => _notices
      .where(
        (n) => _of(n).any(
          (d) => d.toReview && !d.expired(_now()) && d.record.state == 'aday',
        ),
      )
      .length;

  List<KeptNotice> get _shown => [
    for (final n in _notices)
      if ((_search.isEmpty ||
              _fold(n.message.subject).contains(_fold(_search.trim()))) &&
          switch (_filter) {
            _Filter.all => true,
            _Filter.pending => _of(n).any(
              (d) =>
                  d.toReview && !d.expired(_now()) && d.record.state == 'aday',
            ),
            _Filter.unread => n.unread,
            _Filter.withDeadline => _of(n).any((d) => d.record.state != 'eski'),
            _Filter.untied => n.caseKey == null,
          })
        n,
  ];

  KeptNotice? get _current {
    for (final n in _notices) {
      if (n.message.id == _selected) return n;
    }
    return null;
  }

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  static const _months = [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', //
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ];

  static String _date(DateTime? t, {bool time = false}) {
    if (t == null) return '—';
    final d = '${t.day} ${_months[t.month - 1]} ${t.year}';
    if (!time) return d;
    String two(int v) => v.toString().padLeft(2, '0');
    return '$d ${two(t.hour)}:${two(t.minute)}';
  }

  /// "11 Eki" this year, "11 Eki 25" before: the list's date column.
  String _short(DateTime? t) {
    if (t == null) return '—';
    final d = '${t.day} ${_months[t.month - 1]}';
    return t.year == _now().year ? d : '$d ${t.year % 100}';
  }

  // Building.

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    _narrow = MediaQuery.sizeOf(context).width < 700;
    final gutter = _narrow ? 12.0 : 20.0;
    return ColoredBox(
      color: dark ? Theme.of(context).colorScheme.surface : AgendaColors.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FoldingChrome(
            enabled: _narrow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_topBar(context), _channel(context)],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 16),
              child: LayoutBuilder(
                builder: (context, box) {
                  final main = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FoldingChrome(
                        enabled: _narrow,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _stats(context),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                      Expanded(child: _list(context)),
                    ],
                  );
                  if (box.maxWidth < 900) return main;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: main),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: math.min(400, box.maxWidth * .34),
                        child: SingleChildScrollView(child: _detail(context)),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }

  Widget _kicker(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: .8,
      color: AgendaColors.muted,
    ),
  );

  /// Notices looked at in Folio: their badge goes, here and in the panel.
  /// UETS is not told; the day each was served stays UETS's.
  void _markSeen(Iterable<String> ids) {
    final db = _db;
    if (db == null) return;
    db.markNoticesSeen(ids);
    _reload();
    widget.onChanged?.call();
  }

  Future<void> _markAllSeen() async {
    final ids = [
      for (final n in _notices)
        if (n.unread) n.message.id,
    ];
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tümünü okundu say'),
        content: Text(
          '${ids.length} tebligat Folio’da okundu sayılacak ve okunmamış '
          'sayısından düşecek.\n\nUETS’e bir şey gönderilmez: tebligatların '
          'UETS’teki okunma (tebliğ) tarihi değişmez, süreler de buna göre '
          'hesaplanmaya devam eder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const ValueKey('uets-mark-all-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Okundu say'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) _markSeen(ids);
  }

  Widget _topBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = _api.connected;
    final unread = _notices.where((n) => n.unread).length;
    final button = FilledButton.icon(
      key: const ValueKey('uets-sync'),
      onPressed: _sync.state(PortalChannel.uets).running
          ? null
          : connected
          ? _sync.syncUets
          : () => connectUets(context, api: _api, secrets: _sync.secrets),
      icon: Icon(connected ? Icons.sync_rounded : Icons.link, size: 17),
      label: Text(connected ? 'Senkronize et' : 'UETS’ye bağlan'),
    );
    if (_narrow) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Tebligatlarım',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            const HelpButton(Help.uets),
            button,
          ],
        ),
      );
    }
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          const Text(
            'Tebligatlarım',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -.3,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              '/ Elektronik tebligatlar ve dosyalarınızla eşleşmeleri',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
          ),
          const Spacer(),
          const HelpButton(Help.uets),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const ValueKey('uets-mark-all-read'),
            onPressed: unread == 0 ? null : _markAllSeen,
            icon: const Icon(Icons.done_all_rounded, size: 17),
            label: const Text('Tümünü okundu say'),
          ),
          const SizedBox(width: 8),
          button,
        ],
      ),
    );
  }

  /// The list's choices, as pills on a grey track, each with its count.
  Widget _filters(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = _notices.where((n) => n.unread).length;
    final untied = _notices.where((n) => n.caseKey == null).length;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (filter, label, count) in [
            (_Filter.all, 'Tümü', _notices.length),
            (_Filter.unread, 'Okunmamış', unread),
            (_Filter.pending, 'Onay bekleyen', _pendingCount),
            (_Filter.withDeadline, 'Süresi olan', null),
            (_Filter.untied, 'Eşleşmeyen', untied),
          ])
            InkWell(
              key: ValueKey('uets-filter-${filter.name}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _filter = filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _filter == filter ? scheme.surface : null,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: _filter == filter
                      ? const [
                          BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  count == null ? label : '$label $count',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: _filter == filter
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: _filter == filter
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Over the list: its choices and a search through it.
  Widget _listHead(BuildContext context) {
    final search = SizedBox(
      height: 36,
      child: TextField(
        key: const ValueKey('uets-search'),
        onChanged: (v) => setState(() => _search = v),
        style: const TextStyle(fontSize: 13),
        decoration: const InputDecoration(
          hintText: 'Mahkeme, dosya no, tür…',
          prefixIcon: Icon(Icons.search_rounded, size: 18),
          contentPadding: EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
    );
    if (_narrow) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _filters(context),
                  ),
                ),
                // On a phone beside the choices, the bar having no room.
                IconButton(
                  key: const ValueKey('uets-mark-all-read'),
                  tooltip: 'Tümünü okundu say',
                  onPressed: _notices.any((n) => n.unread)
                      ? _markAllSeen
                      : null,
                  icon: const Icon(Icons.done_all_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            search,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Row(
        children: [
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _filters(context),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(width: 240, child: search),
        ],
      ),
    );
  }

  /// The columns' names, over the rows on a wide window.
  Widget _columns(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: scheme.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 8, 14, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border.symmetric(
          horizontal: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: Text('Tebligat', style: style)),
          SizedBox(width: 150, child: Text('Dosya', style: style)),
          SizedBox(width: 210, child: Text('Süre', style: style)),
          SizedBox(
            width: 64,
            child: Text('Geliş', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _channel(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(_narrow ? 12 : 20, 10, _narrow ? 12 : 20, 0),
    child: PortalChannelBar(sync: _sync, showSyncAll: false),
  );

  Widget _stats(BuildContext context) {
    final today = _day(_now());
    final unread = _notices.where((n) => n.unread).length;
    final pending = _deadlines
        .where(
          (d) => d.toReview && !d.expired(_now()) && d.record.state == 'aday',
        )
        .length;
    final untied = _notices.where((n) => n.caseKey == null).length;
    // Only what the lawyer confirmed or gave a day counts, as on the agenda.
    final soon = _deadlines.where((d) {
      if (!d.onAgenda || (d.user?.done ?? false)) return false;
      final at = DateTime.parse(d.day!);
      return !at.isBefore(today) &&
          at.isBefore(today.add(const Duration(days: 8)));
    }).length;
    Widget stat(
      IconData icon,
      Color fill,
      Color tint,
      int value,
      String l, {
      Widget? action,
    }) => _Slot(
      narrow: _narrow,
      child: _card(
        context,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: tint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    l,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
                  ),
                ],
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
    final row = Row(
      children: [
        stat(
          Icons.pending_actions_outlined,
          AgendaColors.taskFill,
          AgendaColors.task,
          pending,
          'Onayınızı bekleyen süre',
        ),
        const SizedBox(width: 12),
        stat(
          Icons.timer_outlined,
          AgendaColors.deadlineFill,
          AgendaColors.deadline,
          soon,
          '7 gün içinde son günü olan (onaylı)',
        ),
        const SizedBox(width: 12),
        stat(
          Icons.mark_email_unread_outlined,
          AgendaColors.hearingFill,
          AgendaColors.hearing,
          unread,
          'Okunmamış',
        ),
        const SizedBox(width: 12),
        stat(
          Icons.link_off,
          tone(const Color(0xFFEEF0F3)),
          AgendaColors.muted,
          untied,
          'Dosyayla eşleşmeyen',
        ),
      ],
    );
    return _narrow
        ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: row)
        : row;
  }

  Widget _list(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = _shown;
    final Widget body;
    if (shown.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.mark_email_read_outlined,
                size: 34,
                color: AgendaColors.muted,
              ),
              const SizedBox(height: 10),
              Text(
                _notices.isEmpty
                    ? _api.connected
                          ? 'UETS kutunuzda tebligat yok.'
                          : 'UETS’ye bağlandığınızda tebligatlarınız burada '
                                'listelenir, dosyalarınızla eşleştirilir ve '
                                'süreleri ajandaya düşer.'
                    : 'Bu süzgece uyan tebligat yok.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
              ),
            ],
          ),
        ),
      );
    } else {
      body = ListView.separated(
        itemCount: shown.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: scheme.outlineVariant),
        itemBuilder: (context, i) => _row(context, shown[i]),
      );
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _listHead(context),
          if (!_narrow && shown.isNotEmpty)
            _columns(context)
          else
            Divider(height: 1, color: scheme.outlineVariant),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, KeptNotice n) {
    final scheme = Theme.of(context).colorScheme;
    final m = n.message;
    final parsed = NoticeSubject.parse(m.subject);
    final kind = _kindOf(n);
    final badge = _badge(n);
    final unread = n.unread;
    final selected = m.id == _selected;
    final kase = n.caseKey == null ? null : _cases[n.caseKey];
    final tag = _tag(
      kase != null
          ? (
              AgendaColors.eHearingFill,
              AgendaColors.eHearingText,
              Icons.link,
              kase.number,
            )
          : (
              AgendaColors.taskFill,
              AgendaColors.taskText,
              Icons.link_off,
              n.link == 'manual' ? 'Bağsız' : 'Eşleşmedi',
            ),
    );
    return InkWell(
      key: ValueKey('uets-row-${m.id}'),
      onTap: () {
        setState(() {
          _selected = m.id;
          _partsProblem = null;
        });
        if (unread) _markSeen([m.id]);
        if (_narrow) _openNotice();
      },
      child: Container(
        color: selected ? scheme.primaryContainer.withValues(alpha: .5) : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: _narrow
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.only(top: _narrow ? 5 : 0),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: unread ? scheme.primary : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // What came, first: the kind; the court and the case's
                  // number under it.
                  Text(
                    kind.isNotEmpty ? kind : (parsed?.unit ?? m.subject),
                    maxLines: _narrow ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    parsed == null
                        ? [
                            if (kind.isNotEmpty) m.subject,
                            if (m.sender.isNotEmpty) m.sender,
                          ].join(' · ')
                        : '${parsed.unit} · ${parsed.number}',
                    maxLines: _narrow ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AgendaColors.muted),
                  ),
                  Text(
                    [
                      'kutuya giriş ${_date(m.sent)}',
                      'tebliğ ${_date(m.served)}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: AgendaColors.muted),
                  ),
                  if (_narrow) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        tag,
                        if (badge != null)
                          KeyedSubtree(
                            key: ValueKey('uets-badge-${m.id}'),
                            child: _tag(badge),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (!_narrow) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 150,
                child: Align(alignment: Alignment.centerLeft, child: tag),
              ),
              SizedBox(
                width: 210,
                child: badge == null
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: KeyedSubtree(
                          key: ValueKey('uets-badge-${m.id}'),
                          child: _tag(badge),
                        ),
                      ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  _short(m.sent),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: AgendaColors.muted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The notice's page on a phone, while it is open.
  Route<void>? _noticePage;

  /// Going to the case or to a document leaves the notice's page first, or
  /// it stays over the page that opens.
  void _leaveNoticePage() {
    final page = _noticePage;
    _noticePage = null;
    if (page != null && page.isActive) Navigator.of(context).removeRoute(page);
  }

  /// The notice on a page of its own, on a phone.
  void _openNotice() {
    final page = _noticePage = MaterialPageRoute<void>(
      builder: (page) => Scaffold(
        appBar: AppBar(
          title: const Text('Tebligat', style: TextStyle(fontSize: 16)),
        ),
        backgroundColor: AgendaColors.page,
        body: ValueListenableBuilder<int>(
          valueListenable: _changes,
          builder: (page, _, _) => SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: _detail(page),
          ),
        ),
      ),
    );
    unawaited(
      Navigator.of(context).push(page).whenComplete(() {
        if (_noticePage == page) _noticePage = null;
      }),
    );
  }

  Widget _tag((Color, Color, IconData, String) look) {
    final (fill, text, icon, label) = look;
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: text),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // The selected notification.

  Widget _detail(BuildContext context) {
    final n = _current;
    if (n == null) {
      return _card(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kicker('TEBLİGAT'),
            const SizedBox(height: 8),
            Text(
              'Ayrıntısını görmek için bir tebligat seçin.',
              style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
            ),
          ],
        ),
      );
    }
    final m = n.message;
    final parsed = NoticeSubject.parse(m.subject);
    final kind = _kindOf(n);
    final kase = n.caseKey == null ? null : _cases[n.caseKey];
    final envelope = _envelopes[m.id];
    final deadlines = [
      for (final d in _deadlines)
        if (d.record.noticeId == m.id) d,
    ];
    final manifest = _db?.manifest(m.id);
    final cover = _coverage(m.id);
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _kicker(
                      m.read == null ? 'TEBLİGAT · OKUNMAMIŞ' : 'TEBLİGAT',
                    ),
                  ),
                  if (kind.isNotEmpty)
                    Flexible(
                      child: _tag((
                        AgendaColors.hearingFill,
                        AgendaColors.hearingText,
                        Icons.description_outlined,
                        kind,
                      )),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                parsed?.unit ?? m.subject,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (parsed != null)
                Text(
                  parsed.number,
                  style: TextStyle(
                    fontSize: 13,
                    color: AgendaColors.hearingText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 12),
              _timeline(n, deadlines),
              const SizedBox(height: 8),
              Text(
                'Tebliğ, kutuya girişi izleyen 5. günün sonunda sayılır '
                '(Tebligat K. m.7/a). Okuma tarihi bunu öne çekmez.',
                style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
              ),
              const SizedBox(height: 10),
              if (m.sender.isNotEmpty) row('Gönderen', m.sender),
              if (m.barcode.isNotEmpty) row('Barkod', m.barcode),
              if (parsed != null) row('Konu', m.subject),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _envelopeCard(context, n, envelope),
        const SizedBox(height: 12),
        _card(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kicker('DOSYA'),
              const SizedBox(height: 8),
              if (kase != null) ...[
                Text(
                  kase.court,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${kase.number} · '
                  '${n.link == 'manual' ? 'elle eşleştirildi' : 'otomatik eşleşti'}',
                  style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
                ),
              ] else
                Text(
                  n.link == 'manual'
                      ? 'Bu tebligat bir dosyaya bağlanmasın diye işaretlendi.'
                      : 'Portföyünüzde tek bir karşılığı bulunamadı; '
                            'dosyayı siz seçebilirsiniz.',
                  style: TextStyle(fontSize: 12, color: AgendaColors.muted),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (kase != null && widget.onOpenCase != null) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        style: _buttonStyle(),
                        onPressed: () {
                          _leaveNoticePage();
                          if (!widget.onOpenCase!(kase.key)) {
                            // The page's own heading, the notice's page
                            // having gone.
                            ScaffoldMessenger.maybeOf(this.context)
                                ?.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Bu dosya henüz Dava Dosyalarım’da yok; '
                                      'önce UYAP’tan alın.',
                                    ),
                                  ),
                                );
                          }
                        },
                        icon: const Icon(Icons.folder_open_outlined, size: 16),
                        label: const Text('Dosyayı aç'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('uets-link'),
                      style: _buttonStyle(),
                      onPressed: () => _chooseCase(n),
                      icon: const Icon(Icons.link, size: 16),
                      label: Text(kase == null ? 'Dosya seç' : 'Değiştir'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kicker('SÜRELER'),
              const SizedBox(height: 8),
              if (n.caseKey != null)
                _representation(context, n, n.caseKey!, deadlines),
              if (deadlines.isEmpty && cover != null)
                Text(
                  key: const ValueKey('uets-coverage'),
                  cover.reading
                      ? 'Belgeler okunuyor; süreler okuma bitince hesaplanır.'
                      : cover.unread > 0
                      ? '${cover.total} belgeden ${cover.unread} tanesi '
                            'okunamadı. Bu tebligatta süre olup olmadığı kesin '
                            'değil; okunamayan belgeyi açıp kontrol edin.'
                      : '${cover.total} belgenin hepsi okundu; süre doğuran '
                            'bir belge ya da talimat bulunmadı. Gerekirse '
                            '“Süre ekle” ile kendiniz ekleyin.',
                  style: TextStyle(
                    fontSize: 12,
                    color: !cover.reading && cover.unread > 0
                        ? tone(const Color(0xFF7A4B00))
                        : AgendaColors.muted,
                  ),
                )
              else if (deadlines.isEmpty)
                Text(switch (manifest?.state) {
                  'alinmadi' || null =>
                    'Ekler henüz alınmadı; bir sonraki eşitlemede alınır ve '
                        'süreler hesaplanır.',
                  'hata' => 'Ekler UETS’ten alınamadı; yeniden denenecek.',
                  'bos' => 'Tebligatta ek yok; süre hesaplanamadı.',
                  _ =>
                    'Eklerin adından süre doğuran bir belge türü '
                        'anlaşılmadı; süreyi ajandada “Not / iş ekle → '
                        'Süre” ile hesaplayabilirsiniz.',
                }, style: TextStyle(fontSize: 12, color: AgendaColors.muted))
              else ...[
                Text(
                  'Süreler siz onaylayana kadar ajandaya ve sayaçlara girmez.',
                  style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
                ),
                if (_db?.meta('takip:${m.id}')?.isNotEmpty == true ||
                    deadlines.any(
                      (d) => d.record.reasons.any(
                        (r) => r.code == 'takipTuruBelirsiz',
                      ),
                    ))
                  _proceedings(m.id),
                for (final d in deadlines)
                  DeadlineReviewTile(
                    deadline: d,
                    onChange: () => unawaited(_addDeadline(n, replacing: d)),
                    onConfirm:
                        d.confirmed ||
                            d.record.state != 'aday' ||
                            d.record.dueDay == null
                        ? null
                        : () {
                            _db?.confirmDeadline(d.record.id);
                            _reload();
                            widget.onChanged?.call();
                          },
                    onSetDay: () async {
                      final day = await askDeadlineDay(context, d);
                      final db = _db;
                      if (day == null || db == null) return;
                      db.saveDeadlineUser(
                        (d.user ?? DeadlineUser(deadlineId: d.record.id))
                            .copyWith(manualDay: day),
                      );
                      _reload();
                      widget.onChanged?.call();
                    },
                    onDismiss: () {
                      _db?.removeAgenda(d.record.id);
                      _reload();
                      widget.onChanged?.call();
                    },
                    onDetails: () {
                      final db = _db;
                      if (db != null) showDeadlineDetails(context, db, d);
                    },
                  ),
              ],
              const SizedBox(height: 6),
              TextButton.icon(
                key: const ValueKey('uets-add-deadline'),
                onPressed: () => unawaited(_addDeadline(n)),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Süre ekle'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _attachments(context, n),
      ],
    );
  }

  ButtonStyle _buttonStyle() => ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );

  /// The payment order's kind of proceedings, told by the lawyer when the
  /// order does not: the deadlines of the other then go.
  Widget _proceedings(String id) {
    final said = _db?.meta('takip:$id') ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SegmentedButton<String>(
        key: const ValueKey('uets-proceedings'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: '', label: Text('İkisi de')),
          ButtonSegment(value: 'genel', label: Text('Genel haciz (Örnek 7)')),
          ButtonSegment(value: 'kambiyo', label: Text('Kambiyo (Örnek 10)')),
        ],
        selected: {said},
        onSelectionChanged: (v) {
          final db = _db;
          if (db == null) return;
          db.setMeta('takip:$id', v.single);
          refreshNoticeDeadlines(
            db,
            parties: NoticeDeadlineContext.parties,
            lawyer: NoticeDeadlineContext.lawyer,
          );
          _reload();
          widget.onChanged?.call();
        },
      ),
    );
  }

  /// The parties of each case, by its key, as UYAP or a notice's package
  /// gave them: name and role, for whom the lawyer acts for.
  final _partiesOf = <String, List<({String ad, String rol, String vekil})>>{};
  final _partiesAsked = <String>{};

  /// The case the lawyer is saying whom they act for in, its choices open.
  String? _choosingFor;

  void _askParties(String key, KeptNotice n) {
    if (!_partiesAsked.add(key)) return;
    // The parties kept for the case, with their lawyers, at once; else the
    // package's own list of them; UYAP's record, once read, in their place.
    final kept = _db?.caseParties(caseKey: key)[key] ?? const <UyapParty>[];
    if (kept.isNotEmpty) {
      _partiesOf[key] = [
        for (final t in kept)
          if (t.name.trim().isNotEmpty)
            (ad: t.name, rol: t.role, vekil: t.lawyer),
      ];
      return;
    }
    final file = (_db?.noticeDocuments(n.message.id) ?? const [])
        .map((d) => d.caseFile)
        .whereType<NoticeCaseFile>()
        .firstOrNull;
    _partiesOf[key] = [
      for (final t
          in file?.parties ??
              const <({String name, String role, bool institution})>[])
        if (t.name.trim().isNotEmpty) (ad: t.name, rol: t.role, vekil: ''),
    ];
    final kase = _cases[key];
    if (kase == null) return;
    () async {
      try {
        final record = await (widget.store ?? UyapCaseStore.instance).load(
          kase.court,
          kase.number,
        );
        final parties = <({String ad, String rol, String vekil})>[
          for (final t in record?.parties ?? const <UyapParty>[])
            if (t.name.trim().isNotEmpty)
              (ad: t.name, rol: t.role, vekil: t.lawyer),
        ];
        if (parties.isEmpty || !mounted) return;
        setState(() => _partiesOf[key] = parties);
      } catch (_) {}
    }();
  }

  /// Whom the lawyer acts for in the case (the audit's §7): asked once
  /// when a deadline's owner is not known, then said in a line that can
  /// be changed. Every notice of the case goes by it.
  Widget _representation(
    BuildContext context,
    KeptNotice n,
    String key,
    List<KeptDeadline> deadlines,
  ) {
    final db = _db;
    if (db == null) return const SizedBox.shrink();
    final said = db.representation(key);
    _askParties(key, n);
    final parties = _partiesOf[key];
    // Where UYAP names the lawyer among a party's lawyers: whom it says
    // they act for, the lawyer not asked when it tells one side.
    final byUyap = [
      for (final t
          in parties ?? const <({String ad, String rol, String vekil})>[])
        if (vekilOlarakGeciyor(t.vekil, NoticeDeadlineContext.lawyer))
          (ad: t.ad, rol: t.rol),
    ];
    final told = byUyap.isNotEmpty && tekYanda(byUyap.map((t) => t.rol));
    final unknown = deadlines.any(
      (d) => d.record.ownership == AidiyetSinyali.belirsiz.name,
    );
    final choosing = _choosingFor == key || (said.isEmpty && !told && unknown);
    if (!choosing) {
      final shown = said.isNotEmpty ? said : (told ? byUyap : const []);
      if (shown.isEmpty) return const SizedBox.shrink();
      return Container(
        key: const ValueKey('uets-represented'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
        decoration: BoxDecoration(
          color: tone(const Color(0xFFE6F4EC)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${said.isEmpty ? 'UYAP’a göre bu dosyada' : 'Bu dosyada'} '
                '${[for (final t in shown) '${titleName(t.ad)} (${t.rol})'].join(', ')} '
                'vekilisiniz.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: tone(const Color(0xFF1B6B3A)),
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('uets-represented-change'),
              onPressed: () => setState(() => _choosingFor = key),
              child: const Text('Değiştir'),
            ),
          ],
        ),
      );
    }
    // Chosen so far: the lawyer's word, else what UYAP suggests.
    final chosen = said.isNotEmpty ? said : byUyap;
    bool on(({String ad, String rol, String vekil}) t) =>
        chosen.any((s) => s.ad == t.ad && s.rol == t.rol);
    return Container(
      key: const ValueKey('uets-represent-ask'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AgendaColors.hearingFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bu dosyada kimi temsil ediyorsunuz?',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AgendaColors.hearingText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Bir kez seçin; sürenin size mi karşı tarafa mı ait olduğu buna '
            'göre belirlenir.',
            style: TextStyle(fontSize: 12, color: AgendaColors.hearingText),
          ),
          const SizedBox(height: 10),
          if (parties == null)
            Text(
              'Taraflar okunuyor…',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            )
          else if (parties.isEmpty)
            Text(
              'Bu dosyanın tarafları henüz bilinmiyor; dosyayı UYAP’tan '
              'tazeleyin.',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in parties)
                  FilterChip(
                    key: ValueKey('uets-represent-${t.ad}-${t.rol}'),
                    selected: on(t),
                    label: Text('${titleName(t.ad)} · ${t.rol}'),
                    onSelected: (_) {
                      final next = on(t)
                          ? [
                              for (final s in chosen)
                                if (!(s.ad == t.ad && s.rol == t.rol)) s,
                            ]
                          : [...chosen, (ad: t.ad, rol: t.rol)];
                      db.setRepresentation(key, next);
                      refreshNoticeDeadlines(
                        db,
                        parties: NoticeDeadlineContext.parties,
                        lawyer: NoticeDeadlineContext.lawyer,
                        only: {
                          for (final x in _notices)
                            if (x.caseKey == key) x.message.id,
                        },
                      );
                      _reload();
                      widget.onChanged?.call();
                    },
                  ),
              ],
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Birden fazla müvekkiliniz varsa hepsini seçin.',
                  style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
                ),
              ),
              if (said.isNotEmpty || chosen.isNotEmpty)
                TextButton(
                  key: const ValueKey('uets-represent-done'),
                  onPressed: () {
                    // UYAP's suggestion kept as the lawyer's word.
                    if (said.isEmpty) {
                      db.setRepresentation(key, chosen);
                      refreshNoticeDeadlines(
                        db,
                        parties: NoticeDeadlineContext.parties,
                        lawyer: NoticeDeadlineContext.lawyer,
                        only: {
                          for (final x in _notices)
                            if (x.caseKey == key) x.message.id,
                        },
                      );
                      _reload();
                      widget.onChanged?.call();
                    }
                    setState(() => _choosingFor = null);
                  },
                  child: Text(said.isEmpty ? 'Doğru' : 'Tamam'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// How far a notice's package was read (the audit's B25): null when it
  /// has no package kept; [reading] while its documents are not read yet.
  ({int total, int unread, bool reading})? _coverage(String id) {
    final e = _envelopes[id];
    if (e == null || e.state == 'hata' || e.attachments.isEmpty) return null;
    final docs = [
      for (final d in _db?.noticeDocuments(id) ?? const <NoticeDocument>[])
        if (d.state != 'ustveri') d,
    ];
    final total = [
      for (final a in e.attachments)
        if (!a.path.toLowerCase().endsWith('.xml')) a,
    ].length;
    return (
      total: total,
      unread: docs.where((d) => !d.read).length,
      reading: docs.isEmpty && total > 0,
    );
  }

  /// The lawyer's own deadline for the notice, or one in place of a
  /// deadline Folio made ([replacing]): kept as the notice's record, and
  /// confirmed, choosing it being the lawyer's word.
  Future<void> _addDeadline(KeptNotice n, {KeptDeadline? replacing}) async {
    final db = _db;
    if (db == null) return;
    final id = n.message.id;
    final docs = db.noticeDocuments(id);
    final unit = docs
        .map((d) => d.caseFile)
        .whereType<NoticeCaseFile>()
        .firstOrNull;
    final hint = [
      _envelopes[id]?.envelopeText ?? '',
      for (final d in docs)
        if (d.hasText) d.text,
    ].join('\n');
    final choice = await askDeadlineChoice(
      context,
      noticeId: id,
      served: n.message.served ?? DateTime.now(),
      category:
          TurkishLegalCalendar.kategoriFromMahkemeAdi(unit?.unitName) ??
          TurkishLegalCalendar.kategoriFromMahkemeAdi(
            NoticeSubject.parse(n.message.subject)?.unit,
          ),
      hint: hint.length > 50000 ? hint.substring(0, 50000) : hint,
      replacing: replacing?.record.id,
      replacingRule: replacing?.record.ruleId,
    );
    if (choice == null || !mounted) return;
    db.saveDeadlineChoice(choice);
    if (replacing != null) db.removeAgenda(replacing.record.id);
    refreshNoticeDeadlines(
      db,
      parties: NoticeDeadlineContext.parties,
      lawyer: NoticeDeadlineContext.lawyer,
      only: {id},
    );
    db.confirmDeadline(choice.deadlineId);
    _reload();
    widget.onChanged?.call();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Süre eklendi ve onaylandı.')),
    );
  }

  /// The package's documents as kept on this computer, each opened in
  /// Folio.
  Widget _keptFiles(
    BuildContext context,
    NoticeEnvelope kept,
    List<NoticeDocument> docs,
  ) => _card(
    context,
    child: Column(
      key: const ValueKey('uets-files'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _kicker('EKLER · ${kept.attachments.length}')),
            // The package's documents to the office, with the notice they
            // came by; nothing shown where there is no one to send to.
            SendToOfficeButton(
              paths: () => [
                ?kept.envelopePath,
                for (final a in kept.attachments)
                  if (!a.path.toLowerCase().endsWith('.xml')) a.path,
              ],
              text:
                  [
                    for (final n in _notices)
                      if (n.message.id == kept.noticeId) n.message.subject,
                  ].firstOrNull ??
                  '',
            ),
          ],
        ),
        if (docs.where((d) => !d.read).length case final unread when unread > 0)
          Container(
            key: const ValueKey('uets-files-unread'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tone(const Color(0xFFFFF6E5)),
              border: Border.all(color: tone(const Color(0xFFF2D59B))),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$unread belge okunamadı; bu tebligattaki süreleri o belgeyi '
              'açıp kendiniz kontrol edin.',
              style: TextStyle(
                fontSize: 12,
                color: tone(const Color(0xFF7A4B00)),
              ),
            ),
          ),
        const SizedBox(height: 6),
        if (kept.attachments.isEmpty)
          Text(
            'Pakette ek yok.',
            style: TextStyle(fontSize: 12, color: AgendaColors.muted),
          ),
        for (final a in kept.attachments)
          InkWell(
            key: ValueKey('uets-file-${a.name}'),
            onTap: widget.onOpenFile == null
                ? null
                : () {
                    _leaveNoticePage();
                    widget.onOpenFile!(a.path);
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 17,
                    color: AgendaColors.hearing,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  if (docs.where((d) => d.path == a.path).firstOrNull
                      case final doc?)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, right: 6),
                      child: Text(
                        switch (doc.state) {
                          'okundu' => 'Okundu',
                          'ocr' => 'Görüntüden okundu',
                          'ustveri' => 'Dosya bilgileri',
                          'kismi' => 'Kısmen okundu',
                          'kayip' => 'Bulunamadı',
                          _ => 'Okunamadı',
                        },
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: doc.read
                              ? FontWeight.w400
                              : FontWeight.w700,
                          color: doc.read
                              ? AgendaColors.muted
                              : tone(const Color(0xFFC62828)),
                        ),
                      ),
                    ),
                  Icon(Icons.open_in_new, size: 15, color: AgendaColors.muted),
                ],
              ),
            ),
          ),
        if (kept.folder != null) ...[
          const SizedBox(height: 4),
          SelectableText(
            kept.folder!,
            style: TextStyle(fontSize: 11, color: AgendaColors.muted),
          ),
        ],
      ],
    ),
  );

  /// In the box, read, served, and the nearest last day, on one line.
  Widget _timeline(KeptNotice n, List<KeptDeadline> deadlines) {
    final m = n.message;
    final next = [
      for (final d in deadlines)
        if (d.day != null && d.record.state != 'eski') d,
    ]..sort((a, b) => a.day!.compareTo(b.day!));
    final steps = <(String, String, Color?)>[
      ('Kutuya giriş', _date(m.sent, time: true), AgendaColors.hearing),
      (
        'Okundu',
        m.read == null ? '—' : _date(m.read, time: true),
        m.read == null ? null : AgendaColors.hearing,
      ),
      ('Tebliğ sayılır', _date(m.served), AgendaColors.deadline),
      if (next.isNotEmpty)
        (
          next.first.onAgenda ? 'Son gün' : 'Son gün (aday)',
          _date(DateTime.parse(next.first.day!)),
          next.first.onAgenda ? AgendaColors.deadline : AgendaColors.task,
        ),
    ];
    return Row(
      key: const ValueKey('uets-timeline'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value, color) in steps)
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color ?? Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color ?? tone(const Color(0xFF9AA2B1)),
                      width: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AgendaColors.muted),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// The envelope: the sentences that give a time marked, and the
  /// envelope itself to open.
  Widget _envelopeCard(
    BuildContext context,
    KeptNotice n,
    NoticeEnvelope? envelope,
  ) {
    final text = envelope?.envelopeText ?? '';
    final directives = text.isEmpty
        ? const <EnvelopeDirective>[]
        : envelopeDirectives(text);
    final path = envelope?.envelopePath;
    final Widget body;
    final sent = n.message.sent;
    final old =
        sent != null && sent.isBefore(_now().subtract(autoPackageWindow));
    if (envelope == null && old) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bu tebligat 40 günden eski; paketi kendiliğinden inmedi. '
            'İndirirseniz UETS’te okundu olarak görünür; tebliğ günü '
            'değişmez.',
            style: TextStyle(fontSize: 12, color: AgendaColors.muted),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            key: const ValueKey('uets-fetch-package'),
            style: _buttonStyle(),
            onPressed: !_api.connected || _fetching == n.message.id
                ? null
                : () => unawaited(_fetchPackage(n.message.id)),
            icon: _fetching == n.message.id
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined, size: 16),
            label: Text(
              _api.connected ? 'Paketi indir' : 'Paket için UETS’ye bağlanın',
            ),
          ),
        ],
      );
    } else if (envelope == null) {
      body = Text(
        _api.connected
            ? 'Tebligat paketi indiriliyor; zarf ve ekler birazdan burada.'
            : 'Tebligat paketi UETS’ye bağlandığınızda kendiliğinden iner.',
        style: TextStyle(fontSize: 12, color: AgendaColors.muted),
      );
    } else if (envelope.state == 'hata') {
      body = Text(
        'Tebligat paketi alınamadı (${envelope.error ?? 'bilinmeyen hata'}); '
        'yarın yeniden denenecek.',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.error,
        ),
      );
    } else if (envelope.state == 'zarfYok') {
      body = Text(
        'Pakette zarf (üst yazı) yok.',
        style: TextStyle(fontSize: 12, color: AgendaColors.muted),
      );
    } else if (text.isEmpty) {
      body = Text(
        'Zarfın metni okunamadı; zarfı açıp süreyi kendiniz kontrol edin.',
        style: TextStyle(fontSize: 12, color: AgendaColors.muted),
      );
    } else {
      final shown = directives.isEmpty
          ? [text.length > 420 ? '${text.substring(0, 420)}…' : text]
          : [for (final d in directives) d.quote];
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final quote in shown)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tone(const Color(0xFFFFFCF5)),
                border: Border.all(color: tone(const Color(0xFFE7DCC4))),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText.rich(
                _marked(quote),
                style: const TextStyle(fontSize: 12.5, height: 1.45),
              ),
            ),
          Text(
            directives.isEmpty
                ? 'Zarfta süre veren bir cümle bulunamadı.'
                : 'Zarftan metin olarak okundu; süreleri aşağıda.',
            style: TextStyle(fontSize: 11, color: AgendaColors.muted),
          ),
        ],
      );
    }
    return _card(
      context,
      child: Column(
        key: const ValueKey('uets-envelope'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _kicker('ZARF · ÜST YAZI')),
              if (path != null && widget.onOpenFile != null)
                TextButton.icon(
                  key: const ValueKey('uets-open-envelope'),
                  onPressed: () {
                    _leaveNoticePage();
                    widget.onOpenFile!(path);
                  },
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: const Text('Zarfı aç'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          body,
        ],
      ),
    );
  }

  /// The notice whose package is being fetched at the lawyer's word.
  String? _fetching;

  Future<void> _fetchPackage(String id) async {
    setState(() => _fetching = id);
    final problem = await _sync.fetchPackageOf(id);
    if (!mounted) return;
    setState(() => _fetching = null);
    _reload();
    widget.onChanged?.call();
    if (problem != null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  /// [quote] with the time it gives ("iki hafta içinde") marked.
  static TextSpan _marked(String quote) {
    final m = RegExp(
      r'(\(?\d{1,3}\)?|bir|iki|üç|dört|beş|altı|yedi|sekiz|dokuz|on beş|onbeş|on|yirmi|otuz|altmış|doksan)(\s*\([^)]{1,12}\))?\s+(iş\s+günü|gün|hafta|ay|yıl)\s+(içinde|içerisinde|zarfında)',
      caseSensitive: false,
    ).firstMatch(quote);
    if (m == null) return TextSpan(text: quote);
    return TextSpan(
      children: [
        TextSpan(text: quote.substring(0, m.start)),
        TextSpan(
          text: quote.substring(m.start, m.end),
          style: TextStyle(
            backgroundColor: tone(const Color(0xFFFFE7A8)),
            fontWeight: FontWeight.w700,
          ),
        ),
        TextSpan(text: quote.substring(m.end)),
      ],
    );
  }

  Widget _attachments(BuildContext context, KeptNotice n) {
    final m = n.message;
    final kept = _envelopes[m.id];
    if (kept != null && kept.state != 'hata') {
      return _keptFiles(context, kept, _db?.noticeDocuments(m.id) ?? const []);
    }
    final parts = _parts[m.id];
    final busy = _partsLoading == m.id || _downloading != null;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kicker('EKLER'),
          const SizedBox(height: 8),
          if (!_api.connected)
            Text(
              'Ekleri indirmek için UETS’ye bağlanın.',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            )
          else if (parts == null)
            OutlinedButton.icon(
              key: const ValueKey('uets-parts'),
              style: _buttonStyle(),
              onPressed: busy ? null : () => _loadParts(m.id),
              icon: _partsLoading == m.id
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file, size: 16),
              label: const Text('Ekleri göster'),
            )
          else ...[
            if (parts.isEmpty)
              Text(
                'Bu tebligatta ek yok.',
                style: TextStyle(fontSize: 12, color: AgendaColors.muted),
              ),
            for (final part in parts)
              InkWell(
                onTap: busy ? null : () => _download(n, part),
                // A finger's height, a short name or not.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Icon(
                          part.signed
                              ? Icons.verified_outlined
                              : Icons.insert_drive_file_outlined,
                          size: 16,
                          color: AgendaColors.hearing,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            part.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        if (_downloading == '${m.id}/${part.id}')
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            Icons.download_outlined,
                            size: 16,
                            color: AgendaColors.muted,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: busy ? null : () => _download(n, null),
              icon: const Icon(Icons.archive_outlined, size: 16),
              label: const Text('Tebligat paketini indir (EYP)'),
            ),
          ],
          if (_partsProblem != null) ...[
            const SizedBox(height: 6),
            Text(
              _partsProblem!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'İndirilen ek UETS’de okundu olarak işaretlenir; tebliğ tarihi '
            'değişmez.',
            style: TextStyle(fontSize: 11, color: AgendaColors.muted),
          ),
        ],
      ),
    );
  }

  static String _problem(Object e) =>
      e is StateError ? e.message : '$e'.replaceFirst('Exception: ', '');

  Future<void> _loadParts(String id) async {
    setState(() {
      _partsLoading = id;
      _partsProblem = null;
    });
    try {
      final parts = await _api.parts(id);
      if (mounted) setState(() => _parts[id] = parts);
    } catch (e) {
      if (mounted) setState(() => _partsProblem = _problem(e));
    } finally {
      if (mounted) setState(() => _partsLoading = null);
    }
  }

  /// Saves [part], or the whole package when null, under the UYAP folder's
  /// UETS folder, opens a document in Folio and keeps the notice as read.
  Future<void> _download(KeptNotice n, UetsPart? part) async {
    final m = n.message;
    setState(() {
      _downloading = '${m.id}/${part?.id ?? ''}';
      _partsProblem = null;
    });
    try {
      final bytes = part == null
          ? await _api.package(m.id)
          : await _api.partBytes(m.id, part.id);
      await UyapSettings.instance.load();
      final parsed = NoticeSubject.parse(m.subject);
      final folder = Directory(
        p.join(
          UyapSettings.instance.folder,
          'UETS',
          _safe(
            parsed == null
                ? m.id
                : '${parsed.unit} ${parsed.number.replaceAll('/', '-')}',
          ),
        ),
      );
      await folder.create(recursive: true);
      var name = _safe(part?.name ?? 'Tebligat ${m.barcode.ifEmpty(m.id)}');
      if (p.extension(name).isEmpty) {
        name = '$name.${part == null ? 'zip' : UyapCaseStore.kindOf(bytes)}';
      }
      var file = File(p.join(folder.path, name));
      for (var i = 2; file.existsSync(); i++) {
        file = File(
          p.join(
            folder.path,
            '${p.basenameWithoutExtension(name)} ($i)${p.extension(name)}',
          ),
        );
      }
      await file.writeAsBytes(bytes, flush: true);
      // UETS marks it read; its own read time comes with the next sync,
      // never this computer's clock (an official time it is not).
      if (part != null && widget.onOpenFile != null) {
        _leaveNoticePage();
        widget.onOpenFile!(file.path);
      } else if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('Kaydedildi: ${file.path}')));
      }
    } catch (e) {
      if (mounted) setState(() => _partsProblem = _problem(e));
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  static String _safe(String value) => value
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');

  /// The lawyer ties the notice to a case, or to none; the matcher never
  /// undoes either.
  Future<void> _chooseCase(KeptNotice n) async {
    final db = _db;
    if (db == null) return;
    final number = NoticeSubject.parse(n.message.subject)?.number;
    final cases = _cases.values.toList()
      ..sort((a, b) {
        final sa = a.number.startsWith(number ?? '\u0000') ? 0 : 1;
        final sb = b.number.startsWith(number ?? '\u0000') ? 0 : 1;
        return sa != sb ? sa - sb : a.court.compareTo(b.court);
      });
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => _CaseChooser(cases: cases, current: n.caseKey),
    );
    if (chosen == null) return;
    db.linkNotice(n.message.id, chosen.isEmpty ? null : chosen, 'manual');
    refreshNoticeDeadlines(
      db,
      parties: NoticeDeadlineContext.parties,
      lawyer: NoticeDeadlineContext.lawyer,
    );
    _reload();
    widget.onChanged?.call();
  }
}

/// A stat card's place: a share of the row, or 168 px in a phone's strip.
class _Slot extends StatelessWidget {
  const _Slot({required this.narrow, required this.child});
  final bool narrow;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      narrow ? SizedBox(width: 168, child: child) : Expanded(child: child);
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// A searchable list of the kept cases; "" for no case.
class _CaseChooser extends StatefulWidget {
  final List<PortalCase> cases;
  final String? current;
  const _CaseChooser({required this.cases, this.current});

  @override
  State<_CaseChooser> createState() => _CaseChooserState();
}

class _CaseChooserState extends State<_CaseChooser> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final shown = [
      for (final c in widget.cases)
        if (q.isEmpty ||
            c.number.toLowerCase().contains(q) ||
            c.court.toLowerCase().contains(q))
          c,
    ];
    return AlertDialog(
      title: const Text(
        'Tebligatın dosyası',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 440,
        // No taller than the screen leaves over the keyboard.
        height: math.max(
          180.0,
          math.min(
            420.0,
            MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom -
                240,
          ),
        ),
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Esas no ya da birim',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.link_off, size: 18),
                    title: const Text('Hiçbir dosyaya bağlama'),
                    onTap: () => Navigator.pop(context, ''),
                  ),
                  for (final c in shown)
                    ListTile(
                      dense: true,
                      selected: c.key == widget.current,
                      title: Text(c.number),
                      subtitle: Text(c.court),
                      onTap: () => Navigator.pop(context, c.key),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
      ],
    );
  }
}
