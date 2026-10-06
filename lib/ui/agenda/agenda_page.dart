import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/portal/hearing_sync.dart';
import '../../services/portal/portal_case.dart';
import '../../services/portal/portal_channel.dart';
import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_hearing.dart';
import '../../services/uyap/uyap_web_service.dart';

/// The agenda: the hearings both UYAP portals report, merged, and the
/// lawyer's own notes, tasks and deadlines, laid out as the approved design
/// (docs/design/ajanda-taslak.png, UYGULAMAPLANI §10).
class AgendaPage extends StatefulWidget {
  const AgendaPage({
    super.key,
    this.database,
    this.web,
    this.now,
    this.onOpenCase,
    this.onPetition,
    this.onChanged,
  });

  /// Tests pass their own; otherwise the one in Folio's data folder.
  final PortalDatabase? database;
  final UyapWebService? web;
  final DateTime Function()? now;

  /// Opens the case with this [caseKey] in UYAP Dosyalarım; null when the
  /// case is not kept there.
  final bool Function(String caseKey)? onOpenCase;
  final bool Function(String caseKey)? onPetition;

  /// Something the sidebar counts changed.
  final VoidCallback? onChanged;

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

enum _View { day, week, month, list }

/// The design's colours: one per kind of entry.
abstract final class AgendaColors {
  static const hearing = Color(0xFF2D5AA8);
  static const hearingFill = Color(0xFFE8EEF8);
  static const hearingText = Color(0xFF1F467F);
  static const eHearing = Color(0xFF139C8B);
  static const eHearingFill = Color(0xFFE3F4F1);
  static const eHearingText = Color(0xFF0C6B5F);
  static const deadline = Color(0xFFD93B3B);
  static const deadlineFill = Color(0xFFFDECEC);
  static const deadlineText = Color(0xFF9C2525);
  static const task = Color(0xFFE08A00);
  static const taskFill = Color(0xFFFFF3E0);
  static const taskText = Color(0xFF8A5300);
  static const page = Color(0xFFF4F6F9);
  static const line = Color(0xFFE3E7EE);
  static const muted = Color(0xFF6B7383);
  static const ok = Color(0xFF1FA37A);
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
  _View _view = _View.week;
  late DateTime _anchor = _day(_now());
  String? _selected;
  List<PortalHearing> _hearings = const [];
  List<AgendaItem> _items = const [];
  Map<String, PortalCase> _cases = const {};
  bool _syncing = false;
  String? _syncError;
  Timer? _clock;

  DateTime _now() => (widget.now ?? DateTime.now)();
  UyapWebService get _web => widget.web ?? UyapWebService.instance;

  @override
  void initState() {
    super.initState();
    _web.session.addListener(_sessionChanged);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_open());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _web.session.removeListener(_sessionChanged);
    super.dispose();
  }

  void _sessionChanged() {
    if (mounted) setState(() {});
    if (_web.connected) unawaited(_syncWeb());
  }

  Future<void> _open() async {
    final db = widget.database ?? await PortalDatabase.shared();
    if (!mounted) return;
    _db = db;
    _reload();
    if (_web.connected) await _syncWeb();
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
      _items = db.agenda();
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

  Future<void> _syncWeb() async {
    final db = _db;
    if (db == null || _syncing || !_web.connected) return;
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      final result = await syncHearings(
        PortalChannel.uyapWeb,
        db,
        _web.hearingRows,
      );
      _syncError = result.complete ? null : 'Bazı tarihler alınamadı';
    } catch (e) {
      _syncError = '$e';
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
        _reload();
        widget.onChanged?.call();
      }
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
      if (i.at != null && _day(i.at!) == day && i.hearingKey == null) i,
  ];

  // Saving

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

  void _toggle(AgendaItem item) {
    _db?.saveAgenda(item.copyWith(done: !item.done));
    _reload();
    widget.onChanged?.call();
  }

  // Layout

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: dark ? Theme.of(context).colorScheme.surface : AgendaColors.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(context),
          _channels(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: LayoutBuilder(
                builder: (context, box) {
                  final side = box.maxWidth >= 1000;
                  final main = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _stats(context),
                      const SizedBox(height: 12),
                      Expanded(child: _body(context)),
                    ],
                  );
                  if (!side) return main;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: main),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: math.min(380, box.maxWidth * .3),
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              _prepCard(context),
                              const SizedBox(height: 12),
                              _deadlinesCard(context),
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
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
          const Flexible(
            child: Text(
              '/ Duruşmalar, süreler ve işleriniz',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
          ),
          const Spacer(),
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
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
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
                    onTap: () {
                      setState(() => _view = view);
                      _reload();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _view == view
                            ? scheme.primary.withValues(alpha: .09)
                            : null,
                        border: Border(
                          right: view == _View.list
                              ? BorderSide.none
                              : BorderSide(color: scheme.outlineVariant),
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _view == view
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: _view == view ? scheme.primary : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          FilledButton.icon(
            key: const ValueKey('agenda-add'),
            onPressed: _db == null ? null : () => _addItem(),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
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

  Widget _channels(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget chip(Color dot, String text, {VoidCallback? onTap}) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
    final session = _web.session.value;
    final web = !_web.connected
        ? chip(AgendaColors.task, 'UYAP Web · bağlı değil')
        : _syncing
        ? chip(AgendaColors.ok, 'UYAP Web · duruşmalar güncelleniyor…')
        : _syncError != null
        ? chip(AgendaColors.task, 'UYAP Web · $_syncError', onTap: _syncWeb)
        : chip(
            AgendaColors.ok,
            session == null
                ? 'UYAP Web · bağlı'
                : 'UYAP Web · bağlı, ${_left(session.expires)}',
            onTap: _syncWeb,
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          chip(scheme.outline, 'UYAP Mobil · bağlı değil'),
          web,
          chip(scheme.outline, 'UETS · bağlı değil'),
        ],
      ),
    );
  }

  String _left(DateTime? until) {
    if (until == null) return 'oturum açık';
    final left = until.difference(DateTime.now());
    if (left.isNegative) return 'süresi doldu';
    return '${left.inHours} sa ${left.inMinutes % 60} dk';
  }

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
    ) => Expanded(
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
                    style: const TextStyle(
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
    );
    return Row(
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

  Widget _body(BuildContext context) => switch (_view) {
    _View.week => _grid(context, [
      for (var i = 0; i < 5; i++) _monday(_anchor).add(Duration(days: i)),
    ]),
    _View.day => _grid(context, [_anchor]),
    _View.month => _month(context),
    _View.list => _list(context),
  };

  // The week and the day: hours from 08:00 to 18:00.

  static const _firstHour = 8, _lastHour = 18, _hourHeight = 52.0;

  Widget _grid(BuildContext context, List<DateTime> days) {
    final scheme = Theme.of(context).colorScheme;
    final today = _day(_now());
    const gutter = 52.0;
    final hours = _lastHour - _firstHour + 1;
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
                            style: const TextStyle(
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
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFF9AA1AD),
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
          _legend(context),
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

  Widget _column(BuildContext context, DateTime day, bool today) {
    final scheme = Theme.of(context).colorScheme;
    final hearings = _hearings.where((h) => _day(h.at) == day);
    final items = _itemsOn(day);
    final allDay = [
      for (final i in items)
        if (i.kind == 'deadline' || i.allDay) i,
    ];
    final timed = [
      for (final i in items)
        if (!(i.kind == 'deadline' || i.allDay)) i,
    ];
    final now = _now();
    return Container(
      decoration: BoxDecoration(
        color: today ? scheme.primary.withValues(alpha: .025) : null,
        border: Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Stack(
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
          for (final h in hearings)
            Positioned(
              top: _top(h.at),
              left: 5,
              right: 5,
              height: 46,
              child: _hearingBlock(h),
            ),
          for (final i in timed)
            Positioned(
              top: _top(i.at!),
              left: 5,
              right: 5,
              height: 46,
              child: _itemBlock(i),
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
                    decoration: const BoxDecoration(
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
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  color: Color(0xFF5B6576),
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
      onTap: () => setState(() => _selected = h.key),
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
          const Flexible(
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
                      style: const TextStyle(
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
                          final hs = _hearings.where((h) => _day(h.at) == day);
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
                                      style: const TextStyle(
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
      for (final h in _hearings)
        if (!h.at.isBefore(from) && h.at.isBefore(to)) (h.at, _hearingBlock(h)),
      for (final i in _items)
        if (i.at != null && !i.at!.isBefore(from) && i.at!.isBefore(to))
          (i.at!, _itemBlock(i)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (entries.isEmpty) {
      return _card(
        context,
        child: const Center(
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
    style: const TextStyle(
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
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: .3,
        color: Color(0xFF4B5465),
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
              style: const TextStyle(fontSize: 12.5, color: AgendaColors.muted),
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
        : until.inHours < 24
        ? '${until.inHours} SA SONRA'
        : '${until.inDays} GÜN SONRA';
    final kase = _cases[h.caseKey];
    final parties = (h.parties ?? kase?.parties)?.value
        .map((p) => '${p['adi'] ?? p['ad'] ?? p['isim'] ?? ''}'.trim())
        .where((n) => n.isNotEmpty)
        .join(' — ');
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
              style: const TextStyle(fontSize: 12, color: Color(0xFF7A8394)),
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
          _kicker(
            '$when ${_hm(h.at)} · ${h.isEHearing ? 'E-DURUŞMA' : 'DURUŞMA'} · $relative',
          ),
          const SizedBox(height: 4),
          Text(
            h.court,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          Text(
            [
              '${h.number} Esas',
              if ('${details['davaTuru'] ?? details['tur'] ?? ''}'.isNotEmpty)
                '${details['davaTuru'] ?? details['tur']}',
            ].join(' · '),
            style: const TextStyle(fontSize: 11.5, color: AgendaColors.muted),
          ),
          const SizedBox(height: 10),
          if (parties != null && parties.isNotEmpty) row('Taraflar', parties),
          if (h.kind != null) row('İşlem', h.kind!.value),
          if (h.result != null) row('Sonuç', h.result!.value),
          if (h.judgeNote != null) row('Hâkim notu', h.judgeNote!.value),
          row('Kaynak', 'UYAP ${sources.join(' + ')}'),
          _heading('SON EVRAKLAR'),
          if (docs.isEmpty)
            const Text(
              'Dosyanın evrakı senkronla gelir.',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            )
          else
            for (final d in docs.take(3))
              Container(
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFF1F3F6))),
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
                      style: const TextStyle(
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
                          : const Color(0xFF9AA1AD),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.title,
                        style: TextStyle(
                          fontSize: 12,
                          color: t.done ? const Color(0xFF9AA1AD) : null,
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
              textStyle: const TextStyle(fontSize: 12),
            ),
            icon: const Icon(Icons.add, size: 15),
            label: const Text('İş ekle'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: widget.onOpenCase == null
                      ? null
                      : () {
                          if (!widget.onOpenCase!(h.caseKey)) {
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Bu dosya UYAP Dosyalarım’da kayıtlı değil.',
                                ),
                              ),
                            );
                          }
                        },
                  style: _buttonStyle(),
                  child: const Text('Dosyayı aç'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onPetition == null
                      ? null
                      : () => widget.onPetition!(h.caseKey),
                  style: _buttonStyle(),
                  child: const Text('Dilekçe başlat'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: 'Mazeret UYAP Mobil bağlantısıyla gönderilir.',
                  child: OutlinedButton(
                    onPressed: null,
                    style: _buttonStyle(),
                    child: const Text('Mazeret'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  ButtonStyle _buttonStyle() => ButtonStyle(
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 12)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );

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
            const Text(
              'Yaklaşan süre yok.',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
          for (final i in soon.take(6))
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF1F3F6))),
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
                          style: const TextStyle(
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
                            style: const TextStyle(
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
        ],
      ),
    );
  }
}

/// A note, a task or a deadline of the lawyer's own.
class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog({required this.day, this.caseKey, this.hearingKey});
  final DateTime day;
  final String? caseKey, hearingKey;

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  String _kind = 'task';
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
        width: 420,
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
