import '../../services/portal/agenda_ics.dart';
import 'calendar_export.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/folio_palette.dart';

import 'package:path/path.dart' as p;

import '../../services/legal/deadlines/belge_turu.dart';
import '../../services/legal/deadlines/deadline_service.dart';
import '../../services/legal/deadlines/mahkeme_kategori.dart';
import '../../services/legal/deadlines/sure_katalogu.dart' show SureGuveni;
import '../../services/office/office_network.dart';
import '../../services/platform/app_directories.dart';
import '../../services/portal/portal_case.dart';
import '../../services/portal/portal_channel.dart';
import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_deadline.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/portal/portal_hearing.dart';
import '../../services/uets/notice_matcher.dart';
import '../../services/uyap/uyap_mobile_api.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../help/help_button.dart';
import '../mobile/scroll_chrome.dart';
import '../office/task_give_dialog.dart';
import '../office/tasks_page.dart' show TaskDetail;
import '../portfolio/portfolio_rows.dart' show splitParties, titleName;
import 'channel_bar.dart';
import 'deadline_review.dart';
import '../widgets/folio_select.dart';

/// The agenda: the hearings both UYAP portals report, merged, and the
/// lawyer's own notes, tasks and deadlines, laid out as the approved design
/// (docs/design/ajanda-taslak.png, UYGULAMAPLANI §10).
class AgendaPage extends StatefulWidget {
  const AgendaPage({
    super.key,
    this.database,
    this.sync,
    this.now,
    this.onOpenCase,
    this.onPetition,
    this.onChanged,
    this.onOpenNotice,
    this.showDay,
    this.showHearing,
    this.lawyer = '',
  });

  /// The lawyer's name, by which a hearing's parties are told apart: their
  /// clients first, the other side under them.
  final String lawyer;

  /// Opened at this day, and at this hearing in it: the home page's search
  /// sent here.
  final DateTime? showDay;
  final String? showHearing;

  /// Tests pass their own; otherwise the one in Folio's data folder.
  final PortalDatabase? database;

  /// The channels' syncs; the app's own unless a test passes one.
  final PortalSync? sync;
  final DateTime Function()? now;

  /// Opens the case with this [caseKey] in Dava Dosyalarım; null when the
  /// case is not kept there.
  final bool Function(String caseKey)? onOpenCase;

  /// Begins a petition for this case in the editor.
  final void Function(PortalCase kase)? onPetition;

  /// Something the sidebar counts changed.
  final VoidCallback? onChanged;

  /// Opens the UETS page on the notice with this id.
  final void Function(String noticeId)? onOpenNotice;

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

enum _View { day, week, month, list }

/// The design's colours: one per kind of entry, each with its dark
/// counterpart (FolioPalette).
abstract final class AgendaColors {
  static Color get hearing => tone(const Color(0xFF2D5AA8));
  static Color get hearingFill => tone(const Color(0xFFE8EEF8));
  static Color get hearingText => tone(const Color(0xFF1F467F));
  static Color get eHearing => tone(const Color(0xFF139C8B));
  static Color get eHearingFill => tone(const Color(0xFFE3F4F1));
  static Color get eHearingText => tone(const Color(0xFF0C6B5F));
  static Color get deadline => tone(const Color(0xFFD93B3B));
  static Color get deadlineFill => tone(const Color(0xFFFDECEC));
  static Color get deadlineText => tone(const Color(0xFF9C2525));
  static Color get task => tone(const Color(0xFFE08A00));
  static Color get taskFill => tone(const Color(0xFFFFF3E0));
  static Color get taskText => tone(const Color(0xFF8A5300));

  /// The page under the cards: the app's own black on the dark theme.
  static Color get page =>
      FolioPalette.dark ? Colors.black : const Color(0xFFF4F6F9);
  static Color get line =>
      FolioPalette.dark ? const Color(0xFF2B2F36) : const Color(0xFFE3E7EE);
  static Color get muted => tone(const Color(0xFF6B7383));
  static Color get ok => tone(const Color(0xFF1FA37A));
}

const _days = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];
const _months = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];
String _short(int month) => _months[month - 1].substring(0, 3);
String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);
DateTime _monday(DateTime t) => _day(t).subtract(Duration(days: t.weekday - 1));

class _AgendaPageState extends State<AgendaPage> {
  PortalDatabase? _db;
  late _View _view = widget.showDay == null ? _View.week : _View.day;
  late DateTime _anchor = _day(widget.showDay ?? _now());
  late String? _selected = widget.showHearing;
  List<PortalHearing> _hearings = const [];
  List<AgendaItem> _items = const [];

  /// The month the small calendar shows; the shown range's until moved.
  DateTime? _miniMonth;

  /// The kinds the lawyer has hidden from the calendar ("Göster"):
  /// hearing, ehearing, deadline, task.
  final _hidden = <String>{};

  static String _kindOfHearing(PortalHearing h) =>
      h.isEHearing ? 'ehearing' : 'hearing';
  static String _kindOfItem(AgendaItem i) =>
      i.kind == 'deadline' ? 'deadline' : 'task';

  /// The hearings the calendar shows, the hidden kinds left out.
  Iterable<PortalHearing> get _shownHearings =>
      _hearings.where((h) => !_hidden.contains(_kindOfHearing(h)));

  /// The notices' deadlines the lawyer is still to look at.
  List<KeptDeadline> _review = const [];

  /// Their notices' subjects, for the court and number each belongs to.
  Map<String, String> _subjects = const {};
  Map<String, PortalCase> _cases = const {};
  Timer? _clock;
  String? _caseSyncing;

  /// A phone's width: two rows on top, the list for the week and the
  /// month, and the preparation card in a sheet from below (§13).
  bool _narrow = false;
  static const narrowWidth = 700.0;

  /// Ticks with every change, for the sheet that shows the card.
  final _changes = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _changes.value++;
  }

  DateTime _now() => (widget.now ?? DateTime.now)();
  PortalSync get _sync => widget.sync ?? PortalSync.instance;
  UyapWebService get _web => _sync.web;
  UyapMobileApi get _mobile => _sync.mobile;

  @override
  void initState() {
    super.initState();
    _sync.addListener(_syncChanged);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_open());
    unawaited(_loadView());
  }

  /// The view last chosen, kept beside Folio's other settings.
  Future<File> _viewFile() async =>
      File(p.join((await folioSupportDirectory()).path, 'agenda.json'));

  Future<void> _loadView() async {
    try {
      final json = jsonDecode(await (await _viewFile()).readAsString());
      final view = _View.values.asNameMap()[json is Map ? json['view'] : null];
      if (widget.showDay != null) return;
      if (view != null && mounted && view != _view) {
        setState(() => _view = view);
        _reload();
      }
    } catch (_) {
      // First time, or no settings folder: the week.
    }
  }

  Future<void> _saveView() async {
    try {
      await (await _viewFile()).writeAsString(jsonEncode({'view': _view.name}));
    } catch (_) {}
  }

  @override
  void dispose() {
    _clock?.cancel();
    _syncLater?.cancel();
    _sync.removeListener(_syncChanged);
    _changes.dispose();
    super.dispose();
  }

  /// A channel connected, finished or failed: what is kept may have changed.
  /// A line of progress alone reads nothing (the sync card and the channel
  /// bar listen for those themselves); what a running sync keeps is read
  /// again at most every few seconds.
  ///
  /// What is kept is told by the database itself ([PortalDatabase.revision]
  /// changes with any write, from whichever path), not by the sync's own
  /// counters, which some writers (another own device's agenda, a single
  /// notice's package) do not move. A change held back by the few seconds'
  /// wait is read when they are up, whether or not anything is told then.
  void _syncChanged() {
    if (!mounted) return;
    final stamp = _sync.channelStamp;
    if (stamp != _syncStamp) {
      _syncStamp = stamp;
      _readKept();
      return;
    }
    if (_db?.revision == _syncKept) return;
    final wait = _syncEvery - DateTime.now().difference(_syncRead);
    if (wait <= Duration.zero) {
      _readKept();
    } else {
      _syncLater ??= Timer(wait, () {
        _syncLater = null;
        if (mounted && _db?.revision != _syncKept) _readKept();
      });
    }
  }

  void _readKept() {
    _syncLater?.cancel();
    _syncLater = null;
    _syncKept = _db?.revision;
    _syncRead = DateTime.now();
    _reload();
    widget.onChanged?.call();
  }

  String? _syncStamp;
  (int, int)? _syncKept;
  Timer? _syncLater;
  DateTime _syncRead = DateTime.fromMillisecondsSinceEpoch(0);
  static const _syncEvery = Duration(seconds: 4);

  Future<void> _open() async {
    final db = widget.database ?? await PortalDatabase.shared();
    if (!mounted) return;
    _db = db;
    _reload();
    await Future.wait([
      if (_web.connected) _sync.syncWeb(),
      if (_mobile.connected) _sync.syncMobile(),
    ]);
  }

  (DateTime, DateTime) get _range => switch (_view) {
    _View.day => (_anchor, _anchor.add(const Duration(days: 1))),
    _View.week => (
      _monday(_anchor),
      _monday(_anchor).add(const Duration(days: 7)),
    ),
    _View.month => (
      DateTime(_anchor.year, _anchor.month),
      DateTime(_anchor.year, _anchor.month + 1),
    ),
    _View.list => (_day(_now()), _day(_now()).add(const Duration(days: 60))),
  };

  void _reload() {
    final db = _db;
    if (db == null) return;
    final (from, to) = _range;
    final today = _day(_now());
    setState(() {
      _hearings = db.hearings(
        from: from.isBefore(today) ? from : today,
        to: to.isAfter(today.add(const Duration(days: 30)))
            ? to
            : today.add(const Duration(days: 30)),
      );
      _items = [...db.agenda(), ..._officeItems()];
      _review =
          [
            for (final d in db.deadlines())
              if (d.toReview && !d.expired(_now())) d,
          ]..sort((a, b) {
            final x = a.day, y = b.day;
            if (x == null || y == null) {
              return x == null ? (y == null ? 0 : 1) : -1;
            }
            return x.compareTo(y);
          });
      _subjects = db.noticeSubjects({
        for (final d in _review) d.record.noticeId,
        for (final i in _items)
          if (i.id.startsWith('uets:')) i.id.split(':')[1],
      });
      _cases = db.cases();
      final keys = {for (final h in _hearings) h.key};
      if (_selected == null || !keys.contains(_selected)) {
        _selected = _hearings
            .where(
              (h) => !h.at.isBefore(_now().subtract(const Duration(hours: 2))),
            )
            .firstOrNull
            ?.key;
      }
    });
  }

  /// The chosen hearing's case, its details and documents fetched again.
  Future<void> _syncCase(String key) async {
    setState(() => _caseSyncing = key);
    final problem = await _sync.syncCase(key);
    if (!mounted) return;
    setState(() => _caseSyncing = null);
    _reload();
    if (problem != null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  void _move(int step) {
    setState(() {
      _anchor = switch (_view) {
        _View.day => _anchor.add(Duration(days: step)),
        _View.week || _View.list => _anchor.add(Duration(days: 7 * step)),
        _View.month => DateTime(_anchor.year, _anchor.month + step),
      };
    });
    _reload();
  }

  String get _rangeLabel {
    final (from, to) = _range;
    final last = to.subtract(const Duration(days: 1));
    return switch (_view) {
      _View.day =>
        '${from.day} ${_months[from.month - 1]} ${from.year}, ${_days[from.weekday - 1]}',
      _View.month => '${_months[from.month - 1]} ${from.year}',
      _View.list => 'Önümüzdeki 60 gün',
      _View.week =>
        from.month == last.month
            ? '${from.day} – ${last.day - 2} ${_months[from.month - 1]} ${from.year}'
            : '${from.day} ${_short(from.month)} – ${last.day - 2} ${_short(last.month)} ${last.year}',
    };
  }

  PortalHearing? get _selectedHearing =>
      _hearings.where((h) => h.key == _selected).firstOrNull;

  /// The entries of [day] for the calendar. A task tied to a hearing is
  /// shown in that hearing's preparation card, not beside it.
  List<AgendaItem> _itemsOn(DateTime day) => [
    for (final i in _items)
      if (i.at != null &&
          _day(i.at!) == day &&
          i.hearingKey == null &&
          !_hidden.contains(_kindOfItem(i)))
        i,
  ];

  // Saving

  /// The agenda written out for the lawyer's own calendar.
  Future<void> _exportCalendar() => showDialog<void>(
    context: context,
    builder: (_) => CalendarExportDialog(database: _db!),
  );

  Future<void> _addItem({String? caseKey, String? hearingKey}) async {
    final item = await showDialog<AgendaItem>(
      context: context,
      builder: (_) => _AddItemDialog(
        day: _view == _View.day ? _anchor : _day(_now()),
        caseKey: caseKey,
        hearingKey: hearingKey,
      ),
    );
    if (item == null || _db == null) return;
    _db!.saveAgenda(item);
    _reload();
    widget.onChanged?.call();
  }

  /// The office's open tasks with a due day, given to this user or by
  /// them, on that day; a tap opens the task, not a tick.
  List<AgendaItem> _officeItems() {
    final net = OfficeNetwork.instance;
    final me = net.me;
    if (me.isEmpty) return const [];
    return [
      for (final t in net.tasks.all)
        if (t.dueDay != null &&
            t.open &&
            (t.assignees.containsKey(me) || t.by == me))
          AgendaItem(
            id: 'gorev-${t.id}',
            kind: 'task',
            title: 'Görev: ${t.title}',
            body: [
              if (t.cases.isNotEmpty)
                '${t.cases.first.number} · ${t.cases.first.court}',
              '${t.byName} → ${t.assignees.values.join(', ')}',
            ].join('\n'),
            at: DateTime(t.dueDay!.year, t.dueDay!.month, t.dueDay!.day, 9),
            allDay: true,
            updated: t.createdAt,
          ),
    ];
  }

  void _toggle(AgendaItem item) {
    if (item.id.startsWith('gorev-')) {
      final net = OfficeNetwork.instance;
      final task = net.tasks.of(item.id.substring(6));
      if (task != null) unawaited(TaskDetail.show(context, net, task));
      return;
    }
    _db?.saveAgenda(item.copyWith(done: !item.done));
    _reload();
    widget.onChanged?.call();
  }

  // Layout

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    _narrow = MediaQuery.sizeOf(context).width < narrowWidth;
    // The week's and the month's grids need a wide screen; a phone lists.
    if (_narrow && (_view == _View.week || _view == _View.month)) {
      _view = _View.list;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
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
              children: [
                _narrow ? _topBarNarrow(context) : _topBar(context),
                _channels(context),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 16),
              child: LayoutBuilder(
                builder: (context, box) {
                  final side = box.maxWidth >= 1000;
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
                      Expanded(child: _body(context)),
                    ],
                  );
                  if (!side) return main;
                  // Wide enough: the month at a glance on the left, what
                  // to show and the last sync under it, as a calendar's own
                  // app has it; the numbers are the left's then.
                  final left = box.maxWidth >= 1040;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (left) ...[
                        SizedBox(
                          width: 224,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _miniCalendar(context),
                                const SizedBox(height: 12),
                                _rangeSummary(context),
                                const SizedBox(height: 12),
                                _syncCard(context),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      Expanded(
                        child: left ? _body(context, legend: false) : main,
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: left ? 300 : math.min(380, box.maxWidth * .3),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _prepCard(context),
                              const SizedBox(height: 16),
                              _weekList(context),
                              const SizedBox(height: 12),
                              _deadlinesCard(context),
                              if (_review.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _reviewCard(context),
                              ],
                            ],
                          ),
                        ),
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

  Widget _topBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget box(Widget child, {VoidCallback? onTap, String? tooltip}) => Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(9),
          ),
          child: child,
        ),
      ),
    );
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          const Text(
            'Ajanda',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              '/ Duruşmalar, süreler ve işleriniz',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
          ),
          const Spacer(),
          const HelpButton(Help.agenda),
          const SizedBox(width: 8),
          box(
            const Icon(Icons.chevron_left, size: 16),
            onTap: () => _move(-1),
            tooltip: 'Önceki',
          ),
          const SizedBox(width: 6),
          box(
            const Text('Bugün', style: TextStyle(fontSize: 13)),
            onTap: () {
              setState(() => _anchor = _day(_now()));
              _reload();
            },
          ),
          const SizedBox(width: 6),
          box(
            const Icon(Icons.chevron_right, size: 16),
            onTap: () => _move(1),
            tooltip: 'Sonraki',
          ),
          const SizedBox(width: 12),
          Text(
            _rangeLabel,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 14),
          // The views as pills on a grey track.
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                for (final (view, label) in const [
                  (_View.day, 'Gün'),
                  (_View.week, 'Hafta'),
                  (_View.month, 'Ay'),
                  (_View.list, 'Liste'),
                ])
                  InkWell(
                    key: ValueKey('agenda-view-${view.name}'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() => _view = view);
                      unawaited(_saveView());
                      _reload();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _view == view ? scheme.surface : null,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: _view == view
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
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: _view == view
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: _view == view
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const ValueKey('agenda-calendar'),
            tooltip: 'Takvime aktar (Google, Outlook, Apple)',
            onPressed: _db == null ? null : _exportCalendar,
            icon: const Icon(Icons.event_available_outlined, size: 20),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            key: const ValueKey('agenda-add'),
            onPressed: _db == null ? null : () => _addItem(),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Not / iş ekle'),
          ),
        ],
      ),
    );
  }

  Widget _channels(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(_narrow ? 12 : 20, 10, _narrow ? 12 : 20, 0),
    child: PortalChannelBar(sync: _sync),
  );

  /// The top on a phone: the title and adding on one row, the days and the
  /// view on the next.
  Widget _topBarNarrow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget arrow(IconData icon, int step, String tip) => IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      onPressed: () => _move(step),
      icon: Icon(icon, size: 20),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 4),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Ajanda',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              const HelpButton(Help.agenda),
              IconButton(
                key: const ValueKey('agenda-calendar'),
                tooltip: 'Takvime aktar',
                onPressed: _db == null ? null : _exportCalendar,
                icon: const Icon(Icons.event_available_outlined),
              ),
              IconButton(
                key: const ValueKey('agenda-add'),
                tooltip: 'Not / iş ekle',
                onPressed: _db == null ? null : () => _addItem(),
                icon: Icon(Icons.add_circle, color: AgendaColors.hearing),
              ),
            ],
          ),
          Row(
            children: [
              if (_view == _View.day) ...[
                arrow(Icons.chevron_left, -1, 'Önceki'),
                TextButton(
                  onPressed: () {
                    setState(() => _anchor = _day(_now()));
                    _reload();
                  },
                  child: const Text('Bugün'),
                ),
                arrow(Icons.chevron_right, 1, 'Sonraki'),
              ],
              Expanded(
                child: Text(
                  _rangeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SegmentedButton<_View>(
                showSelectedIcon: false,
                // Looks compact, takes a finger's height.
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                segments: const [
                  ButtonSegment(value: _View.day, label: Text('Gün')),
                  ButtonSegment(value: _View.list, label: Text('Liste')),
                ],
                selected: {_view},
                onSelectionChanged: (v) {
                  setState(() => _view = v.first);
                  unawaited(_saveView());
                  _reload();
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }

  /// The chosen hearing's card and the deadlines, from below.
  void _showPrep() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      maxChildSize: .95,
      builder: (sheet, scroll) => ValueListenableBuilder<int>(
        valueListenable: _changes,
        builder: (sheet, _, _) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            _prepCard(sheet),
            const SizedBox(height: 12),
            _deadlinesCard(sheet),
            if (_review.isNotEmpty) ...[
              const SizedBox(height: 12),
              _reviewCard(sheet),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _stats(BuildContext context) {
    final today = _day(_now());
    final week = _monday(today);
    final hearingsToday = _hearings.where((h) => _day(h.at) == today).length;
    final hearingsWeek = _hearings
        .where(
          (h) =>
              !h.at.isBefore(week) &&
              h.at.isBefore(week.add(const Duration(days: 7))),
        )
        .length;
    final soon = _items
        .where(
          (i) =>
              i.kind == 'deadline' &&
              !i.done &&
              i.at != null &&
              !i.at!.isBefore(today) &&
              i.at!.isBefore(today.add(const Duration(days: 8))),
        )
        .length;
    final open = _items.where((i) => i.kind != 'deadline' && !i.done).length;
    Widget stat(
      IconData icon,
      Color fill,
      Color tint,
      int value,
      String label,
    ) => _StatSlot(
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
              child: Icon(icon, size: 17, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final row = Row(
      children: [
        stat(
          Icons.gavel_rounded,
          AgendaColors.hearingFill,
          AgendaColors.hearing,
          hearingsToday,
          'Bugünkü duruşma',
        ),
        const SizedBox(width: 12),
        stat(
          Icons.calendar_view_week_rounded,
          AgendaColors.hearingFill,
          AgendaColors.hearing,
          hearingsWeek,
          'Bu hafta duruşma',
        ),
        const SizedBox(width: 12),
        stat(
          Icons.timer_outlined,
          AgendaColors.deadlineFill,
          AgendaColors.deadline,
          soon,
          'Süresi yaklaşan',
        ),
        const SizedBox(width: 12),
        stat(
          Icons.check_rounded,
          AgendaColors.taskFill,
          AgendaColors.task,
          open,
          'Açık iş / not',
        ),
      ],
    );
    return _narrow
        ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: row)
        : row;
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
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }

  /// The calendar in the chosen view; the colours' key under the grid
  /// unless the left panel shows them ([legend]).
  Widget _body(BuildContext context, {bool legend = true}) => switch (_view) {
    _View.week => _grid(context, [
      for (var i = 0; i < 5; i++) _monday(_anchor).add(Duration(days: i)),
    ], legend: legend),
    _View.day => _grid(context, [_anchor], legend: legend),
    _View.month => _month(context),
    _View.list => _list(context),
  };

  // The week and the day: hours from 08:00 to 18:00.

  static const _firstHour = 8, _lastHour = 18, _hourHeight = 52.0;

  Widget _grid(
    BuildContext context,
    List<DateTime> days, {
    bool legend = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final today = _day(_now());
    const gutter = 52.0;
    const hours = _lastHour - _firstHour + 1;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              children: [
                const SizedBox(width: gutter),
                for (final day in days)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      decoration: BoxDecoration(
                        color: day == today
                            ? scheme.primary.withValues(alpha: .04)
                            : null,
                        border: Border(
                          left: BorderSide(color: scheme.outlineVariant),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _days[day.weekday - 1],
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AgendaColors.muted,
                            ),
                          ),
                          Text(
                            '${day.day} ${_short(day.month)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: day == today ? scheme.primary : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: SizedBox(
                height: hours * _hourHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: gutter,
                      child: Column(
                        children: [
                          for (var h = _firstHour; h <= _lastHour; h++)
                            Container(
                              height: _hourHeight,
                              alignment: Alignment.topRight,
                              padding: const EdgeInsets.only(right: 8, top: 2),
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: scheme.outlineVariant.withValues(
                                      alpha: .5,
                                    ),
                                  ),
                                ),
                              ),
                              child: Text(
                                '${_two(h)}:00',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: tone(const Color(0xFF9AA1AD)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    for (final day in days)
                      Expanded(child: _column(context, day, day == today)),
                  ],
                ),
              ),
            ),
          ),
          if (legend) _legend(context),
        ],
      ),
    );
  }

  double _top(DateTime t) {
    final minutes = (t.hour - _firstHour) * 60 + t.minute;
    return (minutes / 60 * _hourHeight).clamp(
      0,
      (_lastHour - _firstHour + 1) * _hourHeight - 46,
    );
  }

  /// An entry of the day's grid: when it starts and what it shows.
  static const _span = 53; // minutes a block covers: 46 of the hour's 52 px

  Widget _column(BuildContext context, DateTime day, bool today) {
    final scheme = Theme.of(context).colorScheme;
    final items = _itemsOn(day);
    final allDay = [
      for (final i in items)
        if (i.kind == 'deadline' || i.allDay) i,
    ];
    final timed = <(DateTime, Widget)>[
      for (final h in _shownHearings)
        if (_day(h.at) == day) (h.at, _hearingBlock(h)),
      for (final i in items)
        if (!(i.kind == 'deadline' || i.allDay)) (i.at!, _itemBlock(i)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    // Entries that overlap share the column in lanes, side by side, so
    // that none is drawn over another (UYGULAMAPLANI §10).
    final lane = List<int>.filled(timed.length, 0);
    final lanes = List<int>.filled(timed.length, 1);
    var clusterStart = 0;
    var clusterEnd = -1;
    final ends = <int>[];
    void closeCluster(int upTo) {
      for (var k = clusterStart; k < upTo; k++) {
        lanes[k] = ends.length;
      }
    }

    for (var n = 0; n < timed.length; n++) {
      final from = timed[n].$1.hour * 60 + timed[n].$1.minute;
      if (from >= clusterEnd) {
        closeCluster(n);
        clusterStart = n;
        ends.clear();
      }
      var free = ends.indexWhere((e) => e <= from);
      if (free < 0) {
        ends.add(from + _span);
        free = ends.length - 1;
      } else {
        ends[free] = from + _span;
      }
      lane[n] = free;
      clusterEnd = math.max(clusterEnd, from + _span);
    }
    closeCluster(timed.length);
    final now = _now();
    return Container(
      decoration: BoxDecoration(
        color: today ? scheme.primary.withValues(alpha: .025) : null,
        border: Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            for (var h = 0; h <= _lastHour - _firstHour; h++)
              Positioned(
                top: h * _hourHeight,
                left: 0,
                right: 0,
                child: Container(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: .5),
                ),
              ),
            for (var n = 0; n < timed.length; n++)
              Positioned(
                top: _top(timed[n].$1),
                left: 4 + lane[n] * (box.maxWidth - 8) / lanes[n],
                width: (box.maxWidth - 8) / lanes[n] - (lanes[n] > 1 ? 3 : 0),
                height: 46,
                child: timed[n].$2,
              ),
            for (var n = 0; n < allDay.length; n++)
              Positioned(
                top: 8 + n * 34,
                left: 5,
                right: 5,
                height: 30,
                child: _itemBlock(allDay[n]),
              ),
            if (today && now.hour >= _firstHour && now.hour <= _lastHour)
              Positioned(
                top: _top(now),
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AgendaColors.deadline,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Container(height: 2, color: AgendaColors.deadline),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _block({
    required Color fill,
    required Color edge,
    required Color ink,
    required String title,
    String? subtitle,
    bool selected = false,
    VoidCallback? onTap,
    Key? key,
  }) => Material(
    key: key,
    color: fill,
    borderRadius: BorderRadius.circular(7),
    child: InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(7, 5, 7, 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: Border(left: BorderSide(color: edge, width: 3)),
        ),
        foregroundDecoration: selected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AgendaColors.hearing, width: 2),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  color: tone(const Color(0xFF5B6576)),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _hearingBlock(PortalHearing h) {
    final e = h.isEHearing;
    return _block(
      key: ValueKey('agenda-hearing-${h.key}'),
      fill: e ? AgendaColors.eHearingFill : AgendaColors.hearingFill,
      edge: e ? AgendaColors.eHearing : AgendaColors.hearing,
      ink: e ? AgendaColors.eHearingText : AgendaColors.hearingText,
      title: '${_hm(h.at)} ${e ? 'E-duruşma' : 'Duruşma'}',
      subtitle: '${h.court} · ${h.number}',
      selected: h.key == _selected,
      onTap: () {
        setState(() => _selected = h.key);
        if (_narrow) _showPrep();
      },
    );
  }

  Widget _itemBlock(AgendaItem i) {
    final deadline = i.kind == 'deadline';
    return _block(
      fill: deadline ? AgendaColors.deadlineFill : AgendaColors.taskFill,
      edge: deadline ? AgendaColors.deadline : AgendaColors.task,
      ink: deadline ? AgendaColors.deadlineText : AgendaColors.taskText,
      title: deadline ? '⏱ ${i.title}' : i.title,
      subtitle: deadline || i.allDay
          ? null
          : '${i.kind == 'task' ? 'İş' : 'Not'} · ${_hm(i.at!)}',
      onTap: () => _toggle(i),
    );
  }

  /// The month in small: a day pressed shows its week (its day in the
  /// day's view), the days with a hearing or a deadline marked.
  (DateTime, Object, Set<DateTime>)? _marked;

  Widget _miniCalendar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = _day(_now());
    final month = _miniMonth ?? DateTime(_anchor.year, _anchor.month);
    final first = DateTime(month.year, month.month);
    final next = DateTime(month.year, month.month + 1);
    final (from, to) = _range;
    // Read once for each month shown and each reading of the agenda, not
    // at every build (each minute, each sync, each parent's rebuild).
    final kept = _marked;
    final Set<DateTime> marked;
    if (kept != null && kept.$1 == first && identical(kept.$2, _items)) {
      marked = kept.$3;
    } else {
      marked = <DateTime>{};
      final db = _db;
      if (db != null) {
        for (final h in db.hearings(from: first, to: next)) {
          marked.add(_day(h.at));
        }
        for (final i in db.agenda(from: first, to: next)) {
          if (i.kind == 'deadline' && !i.done && i.at != null) {
            marked.add(_day(i.at!));
          }
        }
        _marked = (first, _items, marked);
      }
    }
    final lead = first.weekday - 1;
    final count = next.difference(first).inDays;
    Widget arrow(IconData icon, int step) => IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      onPressed: () =>
          setState(() => _miniMonth = DateTime(month.year, month.month + step)),
      icon: Icon(icon),
    );
    return Container(
      key: const ValueKey('agenda-mini-calendar'),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              arrow(Icons.chevron_left_rounded, -1),
              Expanded(
                child: Text(
                  '${_months[month.month - 1]} ${month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              arrow(Icons.chevron_right_rounded, 1),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1,
            children: [
              for (final d in const ['Pt', 'Sa', 'Ça', 'Pe', 'Cu', 'Ct', 'Pz'])
                Center(
                  child: Text(
                    d,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AgendaColors.muted,
                    ),
                  ),
                ),
              for (var i = 0; i < lead; i++) const SizedBox.shrink(),
              for (var i = 0; i < count; i++)
                () {
                  final day = DateTime(month.year, month.month, i + 1);
                  final isToday = day == today;
                  final inRange = !day.isBefore(from) && day.isBefore(to);
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      setState(() {
                        _anchor = day;
                        _miniMonth = null;
                      });
                      _reload();
                    },
                    child: Container(
                      margin: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        color: isToday
                            ? scheme.primary
                            : inRange && _view != _View.month
                            ? scheme.primaryContainer
                            : null,
                        shape: BoxShape.circle,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: isToday || inRange
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: isToday
                                  ? scheme.onPrimary
                                  : inRange
                                  ? scheme.primary
                                  : null,
                            ),
                          ),
                          if (marked.contains(day))
                            Positioned(
                              bottom: 3,
                              child: Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: isToday
                                      ? scheme.onPrimary
                                      : AgendaColors.deadline,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }(),
            ],
          ),
        ],
      ),
    );
  }

  /// What the shown days hold, kind by kind, in the agenda's colours;
  /// each a box that shows or hides its kind in the calendar.
  Widget _rangeSummary(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (from, to) = _range;
    bool inRange(DateTime? t) =>
        t != null && !t.isBefore(from) && t.isBefore(to);
    final shown = [
      for (final h in _hearings)
        if (inRange(h.at)) h,
    ];
    final items = [
      for (final i in _items)
        if (inRange(i.at) && !i.done) i,
    ];
    final counts = {
      'hearing': shown.where((h) => !h.isEHearing).length,
      'ehearing': shown.where((h) => h.isEHearing).length,
      'deadline': items.where((i) => i.kind == 'deadline').length,
      'task': items.where((i) => i.kind != 'deadline').length,
    };
    Widget line(String kind, Color color, String text) {
      final on = !_hidden.contains(kind);
      return InkWell(
        key: ValueKey('agenda-show-$kind'),
        borderRadius: BorderRadius.circular(8),
        onTap: () =>
            setState(() => on ? _hidden.add(kind) : _hidden.remove(kind)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: on ? color : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: color, width: 1.6),
                ),
                child: on
                    ? const Icon(
                        Icons.check_rounded,
                        size: 12,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: on ? null : AgendaColors.muted,
                  ),
                ),
              ),
              Text(
                '${counts[kind]}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AgendaColors.muted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              'GÖSTER',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
                color: AgendaColors.muted,
              ),
            ),
          ),
          line('hearing', AgendaColors.hearing, 'Duruşmalar'),
          line('ehearing', AgendaColors.eHearing, 'E-duruşmalar'),
          line('deadline', AgendaColors.deadline, 'Süreler'),
          line('task', AgendaColors.task, 'İşler ve notlar'),
        ],
      ),
    );
  }

  /// The hearings from the portals connected, now.
  Future<void> _syncAll() async {
    await Future.wait([
      if (_web.connected) _sync.syncWeb(force: true),
      if (_mobile.connected) _sync.syncMobile(full: true),
    ]);
    if (mounted) _reload();
  }

  /// The hearings' last sync, and a sync now on a press.
  Widget _syncCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _sync,
      builder: (context, _) {
        final states = [
          _sync.state(PortalChannel.uyapWeb),
          _sync.state(PortalChannel.uyapMobile),
        ];
        final running = states.any((s) => s.running);
        final finished = [for (final s in states) ?s.finished]..sort();
        final last = finished.lastOrNull;
        final connected = _web.connected || _mobile.connected;
        return Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('agenda-sync-card'),
            onTap: running || !connected ? null : () => unawaited(_syncAll()),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AgendaColors.hearingFill,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: running
                        ? Padding(
                            padding: const EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AgendaColors.hearing,
                            ),
                          )
                        : Icon(
                            Icons.sync_rounded,
                            size: 19,
                            color: AgendaColors.hearing,
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          running
                              ? 'Eşitleniyor…'
                              : connected
                              ? 'UYAP ile eşit'
                              : 'UYAP’a bağlı değil',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          last == null
                              ? 'Henüz eşitlenmedi'
                              : 'Son eşitleme ${_hm(last)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AgendaColors.muted,
                          ),
                        ),
                      ],
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

  /// The shown days' hearings, tasks and notes, in order, as the right
  /// panel lists them:
  /// each with its kind's colour on its edge; a hearing pressed is shown
  /// in the card above.
  Widget _weekList(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (from, to) = _range;
    final now = _now();
    final start = from.isBefore(_day(now)) && to.isAfter(now)
        ? _day(now)
        : from;
    final entries = <(DateTime, Widget)>[
      for (final h in _shownHearings)
        if (!h.at.isBefore(start) && h.at.isBefore(to))
          (
            h.at,
            _weekEntry(
              context,
              color: h.isEHearing
                  ? AgendaColors.eHearing
                  : AgendaColors.hearing,
              title: '${h.isEHearing ? 'E-duruşma' : 'Duruşma'} · ${h.number}',
              subtitle: '${_whenShort(h.at)} · ${h.court}',
              selected: h.key == _selected,
              onTap: () => setState(() => _selected = h.key),
            ),
          ),
      // The deadlines have their own card under this one.
      for (final i in _items)
        if (i.at != null &&
            !i.done &&
            i.kind != 'deadline' &&
            !i.at!.isBefore(start) &&
            i.at!.isBefore(to) &&
            !_hidden.contains(_kindOfItem(i)))
          (
            i.at!,
            _weekEntry(
              context,
              color: AgendaColors.task,
              title: i.title,
              subtitle: _whenShort(i.at!, time: !i.allDay),
            ),
          ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _view == _View.month
                    ? 'Bu ay'
                    : _view == _View.day
                    ? 'Bu gün'
                    : 'Bu hafta',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.2,
                ),
              ),
            ),
            Text(
              '${entries.length} kayıt',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Kalan günlerde kayıt yok.',
              style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
            ),
          ),
        for (final (_, w) in entries.take(8)) ...[w, const SizedBox(height: 8)],
      ],
    );
  }

  /// "Bugün 14:00", "Çarşamba 09:30", "14 Ekim".
  String _whenShort(DateTime t, {bool time = true}) {
    final today = _day(_now());
    final day = _day(t);
    final d = day == today
        ? 'Bugün'
        : day == today.add(const Duration(days: 1))
        ? 'Yarın'
        : day.difference(today).inDays.abs() < 7
        ? _days[t.weekday - 1]
        : '${t.day} ${_months[t.month - 1]}';
    return time ? '$d ${_hm(t)}' : d;
  }

  Widget _weekEntry(
    BuildContext context, {
    required Color color,
    required String title,
    required String subtitle,
    bool selected = false,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legend(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(Color color, String text) => Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          key(AgendaColors.hearing, 'Duruşma'),
          key(AgendaColors.eHearing, 'E-duruşma'),
          key(AgendaColors.deadline, 'Süre'),
          key(AgendaColors.task, 'Not / iş'),
          const Spacer(),
          Flexible(
            child: Text(
              'Duruşmalar UYAP Mobil ve Web’den birleştirilir',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AgendaColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  // The month and the list.

  Widget _month(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = DateTime(_anchor.year, _anchor.month);
    final start = _monday(first);
    final today = _day(_now());
    return _card(
      context,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Row(
            children: [
              for (final d in _days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      d.substring(0, 3),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AgendaColors.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          for (var week = 0; week < 6; week++)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var d = 0; d < 7; d++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final day = start.add(Duration(days: week * 7 + d));
                          final hs = _shownHearings.where(
                            (h) => _day(h.at) == day,
                          );
                          final is_ = _itemsOn(day);
                          return InkWell(
                            onTap: () {
                              setState(() {
                                _anchor = day;
                                _view = _View.day;
                              });
                              _reload();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: day == today
                                    ? scheme.primary.withValues(alpha: .05)
                                    : null,
                                border: Border(
                                  top: BorderSide(color: scheme.outlineVariant),
                                  left: BorderSide(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${day.day}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: day.month != first.month
                                          ? AgendaColors.muted
                                          : day == today
                                          ? scheme.primary
                                          : null,
                                    ),
                                  ),
                                  for (final h in hs.take(2))
                                    _dot(
                                      AgendaColors.hearing,
                                      '${_hm(h.at)} ${h.court}',
                                    ),
                                  for (final i in is_.take(
                                    math.max(0, 2 - hs.length),
                                  ))
                                    _dot(
                                      i.kind == 'deadline'
                                          ? AgendaColors.deadline
                                          : AgendaColors.task,
                                      i.title,
                                    ),
                                  if (hs.length + is_.length > 2)
                                    Text(
                                      '+${hs.length + is_.length - 2} daha',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AgendaColors.muted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dot(Color color, String text) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5),
          ),
        ),
      ],
    ),
  );

  Widget _list(BuildContext context) {
    final (from, to) = _range;
    final entries = <(DateTime, Widget)>[
      for (final h in _shownHearings)
        if (!h.at.isBefore(from) && h.at.isBefore(to)) (h.at, _hearingBlock(h)),
      for (final i in _items)
        if (i.at != null &&
            !i.at!.isBefore(from) &&
            i.at!.isBefore(to) &&
            !_hidden.contains(_kindOfItem(i)))
          (i.at!, _itemBlock(i)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (entries.isEmpty) {
      return _card(
        context,
        child: Center(
          child: Text(
            'Önümüzdeki 60 günde kayıt yok.',
            style: TextStyle(color: AgendaColors.muted),
          ),
        ),
      );
    }
    final children = <Widget>[];
    DateTime? last;
    for (final (at, block) in entries) {
      if (last == null || _day(at) != _day(last)) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
            child: Text(
              '${at.day} ${_months[at.month - 1]} ${_days[at.weekday - 1]}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        );
      }
      last = at;
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: SizedBox(height: 44, child: block),
        ),
      );
    }
    return _card(
      context,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: ListView(children: children),
    );
  }

  // The right panel.

  Widget _kicker(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: .8,
      color: AgendaColors.hearing,
    ),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: .3,
        color: tone(const Color(0xFF4B5465)),
      ),
    ),
  );

  Widget _prepCard(BuildContext context) {
    final h = _selectedHearing;
    if (h == null) {
      return _card(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kicker('DURUŞMA HAZIRLIĞI'),
            const SizedBox(height: 8),
            Text(
              _web.connected
                  ? 'Yaklaşan duruşma yok.'
                  : 'Duruşmalarınız UYAP bağlantısı kurulunca burada görünür.',
              style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
            ),
          ],
        ),
      );
    }
    final now = _now();
    final when = _day(h.at) == _day(now)
        ? 'BUGÜN'
        : _day(h.at) == _day(now).add(const Duration(days: 1))
        ? 'YARIN'
        : '${h.at.day} ${_short(h.at.month).toUpperCase()}';
    final until = h.at.difference(now);
    final relative = until.isNegative
        ? 'GEÇTİ'
        : until.inMinutes < 60
        ? '${until.inMinutes} DK SONRA'
        : until.inHours < 24
        ? '${until.inHours} SA SONRA'
        : '${until.inDays} GÜN SONRA';
    final kase = _cases[h.caseKey];
    final (ours, others) = _sides(h, kase);
    final sources =
        {...h.seenBy}
            .where((c) => c != PortalChannel.uets)
            .map((c) => c == PortalChannel.uyapWeb ? 'Web' : 'Mobil')
            .toList()
          ..sort();
    final docs = kase?.documents?.value ?? const [];
    final tasks = [
      for (final i in _items)
        if (i.kind != 'deadline' &&
            (i.hearingKey == h.key || i.caseKey == h.caseKey))
          i,
    ];
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              k,
              style: TextStyle(
                fontSize: 12,
                color: tone(const Color(0xFF7A8394)),
              ),
            ),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
    final details = kase?.details?.value ?? const {};
    return _card(
      context,
      child: Column(
        key: const ValueKey('agenda-prep'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _kicker(
                  '$when ${_hm(h.at)} · ${h.isEHearing ? 'E-DURUŞMA' : 'DURUŞMA'} · $relative',
                ),
              ),
              SizedBox(
                width: 28,
                height: 22,
                child: _caseSyncing == h.caseKey
                    ? const Padding(
                        padding: EdgeInsets.all(4),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        key: const ValueKey('agenda-case-sync'),
                        tooltip: 'Dosyayı senkronize et: dava türü ve evrak',
                        padding: EdgeInsets.zero,
                        iconSize: 17,
                        onPressed: () => _syncCase(h.caseKey),
                        icon: Icon(
                          Icons.sync_rounded,
                          color: AgendaColors.hearing,
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            h.court,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            [
              '${h.number} Esas',
              if ('${details['davaTuru'] ?? details['dosyaTuru'] ?? ''}'
                  .isNotEmpty)
                '${details['davaTuru'] ?? details['dosyaTuru']}',
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: AgendaColors.muted),
          ),
          // The parties, the lawyer's clients apart from the other side,
          // each on a line of their own with what they are in the case.
          if (ours.isNotEmpty) ...[
            _heading('MÜVEKKİL'),
            Container(
              key: const ValueKey('agenda-prep-clients'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: tone(const Color(0xFFE6F4EC)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [for (final p in ours) _partyLine(p, client: true)],
              ),
            ),
          ],
          if (others.isNotEmpty) ...[
            _heading(
              ours.isEmpty ? 'TARAFLAR' : 'KARŞI TARAF · ${others.length}',
            ),
            for (final p
                in _partiesOpen.contains(h.key) ? others : others.take(3))
              _partyLine(p),
            if (others.length > 3 && !_partiesOpen.contains(h.key))
              TextButton(
                key: const ValueKey('agenda-prep-more-parties'),
                onPressed: () => setState(() => _partiesOpen.add(h.key)),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 12),
                ),
                child: Text('+ ${others.length - 3} taraf daha'),
              ),
          ],
          _heading('DURUŞMA'),
          row(
            'Tarih',
            '${h.at.day} ${_months[h.at.month - 1]} ${h.at.year} '
                '${_days[h.at.weekday - 1]} · ${_hm(h.at)}',
          ),
          if (h.kind != null) row('İşlem', h.kind!.value),
          if (h.result != null) row('Sonuç', h.result!.value),
          row('Kaynak', 'UYAP ${sources.join(' + ')}'),
          _heading('SON EVRAKLAR'),
          if (docs.isEmpty)
            Text(
              'Evrakı getirmek için ↻ Dosyayı senkronize edin.',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            )
          else
            for (final d in docs.take(3))
              Container(
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: tone(const Color(0xFFF1F3F6))),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${d['ad'] ?? d['evrakTuru'] ?? d['name'] ?? 'Evrak'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      '${d['tarih'] ?? ''}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AgendaColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
          _heading('NOTLARIM VE İŞLERİM'),
          for (final t in tasks)
            InkWell(
              onTap: () => _toggle(t),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      t.done
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 16,
                      color: t.done
                          ? AgendaColors.hearing
                          : tone(const Color(0xFF9AA1AD)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.title,
                        style: TextStyle(
                          fontSize: 12,
                          color: t.done ? tone(const Color(0xFF9AA1AD)) : null,
                          decoration: t.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          TextButton.icon(
            onPressed: () => _addItem(caseKey: h.caseKey, hearingKey: h.key),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 12),
            ),
            icon: const Icon(Icons.add, size: 15),
            label: const Text('İş ekle'),
          ),
          TextButton.icon(
            key: const ValueKey('agenda-hearing-calendar'),
            onPressed: () => openInCalendar(
              context,
              calendarFile([hearingEvent(h)], alarms: const [1440, 120]),
              'Duruşma ${h.number.replaceAll('/', '-')}',
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 12),
            ),
            icon: const Icon(Icons.event_available_outlined, size: 15),
            label: const Text('Takvimime ekle'),
          ),
          // The hearing's preparation given to a colleague, the case and
          // the hearing already in the task.
          if (_mayGiveTask)
            TextButton.icon(
              key: const ValueKey('agenda-hearing-task'),
              onPressed: () => unawaited(_giveTask(h.caseKey)),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 12),
              ),
              icon: const Icon(Icons.assignment_ind_outlined, size: 15),
              label: const Text('Görev ver'),
            ),
          const SizedBox(height: 8),
          // The case first and widest; the petition and the excuse beside it.
          Row(
            children: [
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: widget.onOpenCase == null
                      ? null
                      : () {
                          _leaveSheet(context);
                          if (!widget.onOpenCase!(h.caseKey)) {
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Bu dosya Dava Dosyalarım’da kayıtlı değil.',
                                ),
                              ),
                            );
                          }
                        },
                  style: _buttonStyle(),
                  child: const Text(
                    'Dosyayı aç',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onPetition == null
                        ? null
                        : () {
                            _leaveSheet(context);
                            widget.onPetition!(
                              kase ??
                                  PortalCase.create(
                                    number: h.number,
                                    court: h.court,
                                  ),
                            );
                          },
                    style: _buttonStyle(),
                    child: const Text(
                      'Dilekçe',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Tooltip(
                    message: !_mobile.connected
                        ? 'Mazeret UYAP Mobil ile gönderilir; önce UYAP Mobil’e '
                              'bağlanın.'
                        : h.at.isBefore(now)
                        ? 'Geçmiş bir duruşma için mazeret gönderilemez.'
                        : 'UYAP Mobil ile mazeret talebi gönderin.',
                    child: OutlinedButton(
                      key: const ValueKey('agenda-excuse'),
                      // The mobile API alone takes excuses: whether the web
                      // portal is connected too does not matter.
                      onPressed: _mobile.connected && !h.at.isBefore(now)
                          ? () => unawaited(_askExcuse(context, h))
                          : null,
                      style: _buttonStyle(),
                      child: const Text(
                        'Mazeret',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Hearings whose whole list of parties was asked for.
  final _partiesOpen = <String>{};

  /// [h]'s parties, the lawyer's clients and the other side: from what was
  /// kept of the case (whole names, roles, counsel), else from the
  /// hearing's own list. With no client known, all are the other list.
  (List<UyapParty>, List<UyapParty>) _sides(PortalHearing h, PortalCase? kase) {
    var parties = _db?.caseParties(caseKey: h.caseKey)[h.caseKey] ?? const [];
    if (parties.isEmpty) {
      String field(Map<String, Object?> p, List<String> keys) => [
        for (final k in keys)
          if ('${p[k] ?? ''}'.trim() case final v when v.isNotEmpty) v,
      ].join(' ');
      parties = [
        for (final p
            in (h.parties ?? kase?.parties)?.value ??
                const <Map<String, Object?>>[])
          if (field(p, const ['adi', 'ad', 'isim', 'soyadi', 'soyad'])
              case final name when name.isNotEmpty)
            UyapParty(
              name,
              field(p, const [
                'rol',
                'rolAdi',
                'sifat',
                'sifatAdi',
                'tarafRol',
              ]),
              field(p, const ['vekil', 'vekilAdi']),
              '',
            ),
      ];
    }
    final said = _db?.representation(h.caseKey) ?? const [];
    if (said.isEmpty && widget.lawyer.trim().isEmpty) {
      return (const [], parties);
    }
    return splitParties(parties, widget.lawyer, said: said);
  }

  /// A party on a line: initials, the name whole, and their role.
  Widget _partyLine(UyapParty p, {bool client = false}) {
    final name = titleName(p.name);
    final initials = [
      for (final w in name.split(RegExp(r'\s+')))
        if (w.isNotEmpty) w.characters.first,
    ].take(2).join().toUpperCase();
    final ink = client ? AgendaColors.ok : AgendaColors.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: client
                  ? Theme.of(context).colorScheme.surface
                  : tone(const Color(0xFFF1F3F6)),
              shape: BoxShape.circle,
            ),
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: client ? FontWeight.w600 : FontWeight.w400,
                color: client ? ink : null,
              ),
            ),
          ),
          if (p.role.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: client
                    ? Theme.of(context).colorScheme.surface
                    : tone(const Color(0xFFF1F3F6)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                titleName(p.role),
                style: TextStyle(fontSize: 11, color: ink),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// On a phone the hearing's card is a sheet from below: going to the case
  /// or into a petition closes it first, or the sheet stays over the page
  /// that opens.
  /// The excuse's reason, asked before anything goes to UYAP; then UYAP's
  /// own answer, whatever it is.
  Future<void> _askExcuse(BuildContext context, PortalHearing h) async {
    _leaveSheet(context);
    final reason = await showDialog<String>(
      context: this.context,
      builder: (_) => _ExcuseDialog(hearing: h),
    );
    if (reason == null || !mounted) return;
    final answer = await _sync.requestExcuse(h, reason);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(this.context)?.showSnackBar(
      SnackBar(
        content: Text(answer.message),
        duration: Duration(seconds: answer.ok ? 4 : 8),
      ),
    );
  }

  void _leaveSheet(BuildContext context) {
    if (ModalRoute.of(context) is ModalBottomSheetRoute) {
      Navigator.of(context).pop();
    }
  }

  ButtonStyle _buttonStyle() => ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    alignment: Alignment.center,
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );

  /// The notices' deadlines not yet on the agenda: each to be confirmed,
  /// given a day, or set aside by the lawyer, with why it waits.
  Widget _reviewCard(BuildContext context) {
    final db = _db;
    return _card(
      context,
      child: Column(
        key: const ValueKey('agenda-review'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('İNCELENECEK SÜRELER · ${_review.length}'),
          Text(
            'UETS tebligatlarından hesaplanan süreler, siz onaylayana kadar '
            'ajandaya ve sayaçlara girmez.',
            style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
          ),
          for (final d in _review.take(8))
            DeadlineReviewTile(
              deadline: d,
              subtitle: _whose(d.record.noticeId, d.record.caseKey),
              onOpenCase: d.record.caseKey == null || widget.onOpenCase == null
                  ? null
                  : () => _goToCase(d.record.caseKey!),
              onOpenNotice: widget.onOpenNotice == null
                  ? null
                  : () => widget.onOpenNotice!(d.record.noticeId),
              onConfirm:
                  db == null ||
                      d.record.state != 'aday' ||
                      d.record.dueDay == null
                  ? null
                  : () {
                      db.confirmDeadline(d.record.id);
                      _reload();
                    },
              onSetDay: () async {
                final day = await askDeadlineDay(context, d);
                if (day == null || db == null) return;
                db.saveDeadlineUser(
                  (d.user ?? DeadlineUser(deadlineId: d.record.id)).copyWith(
                    manualDay: day,
                  ),
                );
                _reload();
              },
              onDismiss: () {
                if (db == null) return;
                db.removeAgenda(d.record.id);
                _reload();
              },
              onDetails: () {
                if (db != null) showDeadlineDetails(context, db, d);
              },
            ),
          if (_review.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                've ${_review.length - 8} süre daha; UETS sayfasında '
                'tebligatlarıyla birlikte görünür.',
                style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
              ),
            ),
        ],
      ),
    );
  }

  /// The court and number a notice's deadline belongs to: its case's,
  /// else its notice's subject's.
  String? _whose(String noticeId, String? caseKey) {
    final kase = caseKey == null ? null : _cases[caseKey];
    if (kase != null) return '${kase.court} · ${kase.number}';
    final parsed = NoticeSubject.parse(_subjects[noticeId] ?? '');
    return parsed == null ? null : '${parsed.unit} · ${parsed.number}';
  }

  bool get _mayGiveTask {
    final net = OfficeNetwork.instance;
    return net.ledger.members.any((m) => net.mayGive(m.deviceId));
  }

  /// Görev ver with [caseKey] already in it: from a hearing or a deadline.
  Future<void> _giveTask(String caseKey) => showDialog<void>(
    context: context,
    builder: (_) => TaskGiveDialog(
      network: OfficeNetwork.instance,
      initialCaseKey: caseKey,
    ),
  );

  void _goToCase(String caseKey) {
    if (!(widget.onOpenCase?.call(caseKey) ?? false)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Bu dosya Dava Dosyalarım’da kayıtlı değil.'),
        ),
      );
    }
  }

  Widget _deadlinesCard(BuildContext context) {
    final today = _day(_now());
    final soon = [
      for (final i in _items)
        if (i.kind == 'deadline' &&
            !i.done &&
            i.at != null &&
            !i.at!.isBefore(today))
          i,
    ]..sort((a, b) => a.at!.compareTo(b.at!));
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('YAKLAŞAN SÜRELER'),
          if (soon.isEmpty)
            Text(
              'Yaklaşan süre yok.',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
          for (final i in soon.take(6))
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: tone(const Color(0xFFF1F3F6))),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 74,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i.at!.day} ${_short(i.at!.month)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _days[i.at!.weekday - 1],
                          style: TextStyle(
                            fontSize: 11,
                            color: AgendaColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.title, style: const TextStyle(fontSize: 12)),
                        if (i.body.isNotEmpty)
                          Text(
                            i.body,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AgendaColors.muted,
                            ),
                          ),
                        if (i.caseKey != null || i.id.startsWith('uets:'))
                          Wrap(
                            spacing: 4,
                            children: [
                              if (i.caseKey != null && _mayGiveTask)
                                TextButton(
                                  key: ValueKey('deadline-task-${i.id}'),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                  ),
                                  onPressed: () =>
                                      unawaited(_giveTask(i.caseKey!)),
                                  child: const Text('Görev ver'),
                                ),
                              if (i.caseKey != null &&
                                  widget.onOpenCase != null)
                                TextButton(
                                  key: ValueKey('deadline-case-${i.id}'),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                  ),
                                  onPressed: () => _goToCase(i.caseKey!),
                                  child: const Text('Dosyaya git'),
                                ),
                              if (i.id.startsWith('uets:') &&
                                  widget.onOpenNotice != null)
                                TextButton(
                                  key: ValueKey('deadline-notice-${i.id}'),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                  ),
                                  onPressed: () =>
                                      widget.onOpenNotice!(i.id.split(':')[1]),
                                  child: const Text('Tebligatı aç'),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A note, a task or a deadline of the lawyer's own.
/// A stat card's place: a share of the row on a wide screen, 168 px in
/// the strip a phone scrolls.
class _StatSlot extends StatelessWidget {
  const _StatSlot({required this.narrow, required this.child});
  final bool narrow;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      narrow ? SizedBox(width: 168, child: child) : Expanded(child: child);
}

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog({required this.day, this.caseKey, this.hearingKey});
  final DateTime day;
  final String? caseKey, hearingKey;

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

/// What the deadline calculator offers, in the lawyer's words.
const _documents = {
  BelgeTuru.gerekceliKarar: 'Gerekçeli karar',
  BelgeTuru.kararIlami: 'Karar ilamı',
  BelgeTuru.istinafKarari: 'İstinaf kararı',
  BelgeTuru.davaDilekcesi: 'Dava dilekçesi',
  BelgeTuru.bilirkisiRaporu: 'Bilirkişi raporu',
  BelgeTuru.odemeEmri: 'Ödeme emri',
  BelgeTuru.odemeEmriKambiyo: 'Kambiyo ödeme emri',
  BelgeTuru.icraEmri: 'İcra emri',
  BelgeTuru.hacizIhbarnamesi: 'Haciz ihbarnamesi',
  BelgeTuru.iddianame: 'İddianame',
};
const _courts = {
  MahkemeKategorisi.hukuk: 'Hukuk',
  MahkemeKategorisi.icra: 'İcra',
  MahkemeKategorisi.ceza: 'Ceza',
  MahkemeKategorisi.idare: 'İdare',
  MahkemeKategorisi.vergi: 'Vergi',
};

class _AddItemDialogState extends State<_AddItemDialog> {
  String _kind = 'task';

  // The deadline calculator (UYGULAMAPLANI §11): from what was served, on
  // which day, before which kind of court.
  BelgeTuru _document = BelgeTuru.gerekceliKarar;
  MahkemeKategorisi _court = MahkemeKategorisi.hukuk;
  DateTime? _served;
  bool _holiday = true;
  List<DeadlineItem> _results = const [];

  void _calculate() {
    final served = _served;
    if (served == null) return;
    setState(() {
      _results = DeadlineService.computeFromUsuliTebligTarihi(
        usuliTebligTarihi: served,
        belgeTuru: _document,
        kategori: _court,
        adliTatileTabi: _holiday,
      ).items;
    });
  }

  void _take(DeadlineItem item) {
    final served = item.baslangicTarihi;
    setState(() {
      _title.text = item.sureAdi;
      _body.text = [
        item.kanun,
        'tebliğ ${served.day}.${served.month}.${served.year}',
        ...item.dayanakNotlari,
      ].where((t) => t.isNotEmpty).join(' · ');
      _date = item.etkiliSonGun;
      _error = null;
    });
  }

  String _long(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  Widget _calculator() {
    final scheme = Theme.of(context).colorScheme;
    InputDecoration field(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      labelStyle: const TextStyle(fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    );
    final text = TextStyle(fontSize: 13, color: scheme.onSurface);
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AgendaColors.deadlineFill.withValues(alpha: .5),
        border: Border.all(color: AgendaColors.deadline.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Süreyi hesapla',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AgendaColors.deadlineText,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FolioSelect<BelgeTuru>(
                  initialValue: _document,
                  isExpanded: true,
                  iconSize: 20,
                  style: text,
                  decoration: field('Tebliğ edilen'),
                  items: [
                    for (final e in _documents.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() {
                    _document = v ?? _document;
                    _results = const [];
                  }),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: FolioSelect<MahkemeKategorisi>(
                  initialValue: _court,
                  isExpanded: true,
                  iconSize: 20,
                  style: text,
                  decoration: field('Yargı'),
                  items: [
                    for (final e in _courts.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() {
                    _court = v ?? _court;
                    _results = const [];
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('agenda-served'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _served ?? widget.day,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setState(() {
                        _served = picked;
                        _results = const [];
                      });
                    }
                  },
                  icon: const Icon(Icons.mark_email_read_outlined, size: 16),
                  label: Text(
                    _served == null
                        ? 'Tebliğ tarihi'
                        : 'Tebliğ ${_long(_served!)}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('agenda-calculate'),
                onPressed: _served == null ? null : _calculate,
                child: const Text('Hesapla'),
              ),
            ],
          ),
          GestureDetector(
            onTap: () => setState(() {
              _holiday = !_holiday;
              _results = const [];
            }),
            child: Row(
              children: [
                Checkbox(
                  value: _holiday,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => setState(() {
                    _holiday = v ?? _holiday;
                    _results = const [];
                  }),
                ),
                const Text(
                  'Adli tatile tabi iş (HMK m.103)',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          for (final item in _results)
            InkWell(
              key: ValueKey('agenda-result-${item.sureAdi}'),
              onTap: () => _take(item),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border.all(color: AgendaColors.line),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.sureAdi,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${item.kanun} · ${item.sureMetni}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AgendaColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _long(item.etkiliSonGun),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AgendaColors.deadlineText,
                          ),
                        ),
                        if (item.guven != SureGuveni.yuksek)
                          Text(
                            'kontrol edin',
                            style: TextStyle(
                              fontSize: 11,
                              color: AgendaColors.task,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (_served != null && _results.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Hesapla’ya basın; bir sonuca dokunmak başlığı ve son günü doldurur.',
                style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
              ),
            ),
        ],
      ),
    );
  }

  final _title = TextEditingController();
  final _body = TextEditingController();
  late DateTime _date = widget.day;
  TimeOfDay? _time = const TimeOfDay(hour: 9, minute: 0);
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Bir başlık yazın.');
      return;
    }
    final timed = _kind != 'deadline' && _time != null;
    Navigator.pop(
      context,
      AgendaItem(
        id: AgendaItem.newId(),
        kind: _kind,
        title: _title.text.trim(),
        body: _body.text.trim(),
        at: timed
            ? DateTime(
                _date.year,
                _date.month,
                _date.day,
                _time!.hour,
                _time!.minute,
              )
            : DateTime(_date.year, _date.month, _date.day),
        allDay: !timed,
        caseKey: widget.caseKey,
        hearingKey: widget.hearingKey,
        updated: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      labelStyle: const TextStyle(fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    );
    return AlertDialog(
      title: const Text('Not / iş ekle'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'task', label: Text('İş')),
                  ButtonSegment(value: 'note', label: Text('Not')),
                  ButtonSegment(value: 'deadline', label: Text('Süre')),
                ],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() => _kind = v.first),
              ),
              if (_kind == 'deadline') _calculator(),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('agenda-title'),
                controller: _title,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: field('Başlık').copyWith(errorText: _error),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                style: const TextStyle(fontSize: 13),
                decoration: field('Açıklama (isteğe bağlı)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                          locale: const Locale('tr', 'TR'),
                        );
                        if (picked != null) setState(() => _date = picked);
                      },
                      icon: const Icon(Icons.event, size: 16),
                      label: Text(
                        '${_date.day} ${_months[_date.month - 1]} ${_date.year}',
                      ),
                    ),
                  ),
                  if (_kind != 'deadline') ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime:
                                _time ?? const TimeOfDay(hour: 9, minute: 0),
                          );
                          if (picked != null) setState(() => _time = picked);
                        },
                        icon: const Icon(Icons.schedule, size: 16),
                        label: Text(
                          _time == null
                              ? 'Tüm gün'
                              : '${_two(_time!.hour)}:${_two(_time!.minute)}',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const ValueKey('agenda-save'),
          onPressed: _save,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

/// The reason for an excuse, at most UYAP's own limit; sent only on the
/// lawyer's word.
class _ExcuseDialog extends StatefulWidget {
  const _ExcuseDialog({required this.hearing});

  final PortalHearing hearing;

  @override
  State<_ExcuseDialog> createState() => _ExcuseDialogState();
}

class _ExcuseDialogState extends State<_ExcuseDialog> {
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reason.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.hearing;
    String two(int n) => n.toString().padLeft(2, '0');
    final when =
        '${two(h.at.day)}.${two(h.at.month)}.${h.at.year} '
        '${two(h.at.hour)}:${two(h.at.minute)}';
    final text = _reason.text.trim();
    return AlertDialog(
      title: const Text('Mazeret talebi'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${h.court} · ${h.number}\n$when duruşması',
              style: TextStyle(fontSize: 13, color: AgendaColors.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('excuse-reason'),
              controller: _reason,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              maxLength: UyapMobileApi.excuseLimit,
              decoration: InputDecoration(
                labelText: 'Mazeretin gerekçesi',
                isDense: true,
                labelStyle: const TextStyle(fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            Text(
              'Talep UYAP Mobil üzerinden mahkemeye gönderilir. Göndermeden '
              'önce duruşma UYAP’tan yeniden okunur.',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const ValueKey('excuse-send'),
          onPressed: text.isEmpty
              ? null
              : () => Navigator.of(context).pop(text),
          child: const Text('Gönder'),
        ),
      ],
    );
  }
}
