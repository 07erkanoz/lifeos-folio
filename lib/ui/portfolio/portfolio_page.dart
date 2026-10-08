import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/office/office_network.dart';
import '../../services/portal/portal_channel.dart';
import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../../services/uyap/uyap_mobile_api.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../agenda/mobile_connect.dart';
import '../office/tasks_page.dart' show TaskDetail;
import '../widgets/uyap_connect_view.dart';
import 'portfolio_rows.dart';

/// UYAP Dosyalarım (docs/design/uyap-portfoy-taslak.png): the whole
/// portfolio, filled by the portals on their own, filtered on the left,
/// searched by scope, each case with its kind, state, hearing, parties and
/// what is new in it.
class PortfolioPage extends StatefulWidget {
  const PortfolioPage({
    super.key,
    required this.onShowCase,
    this.lawyer = '',
    this.database,
    this.store,
  });

  final ValueChanged<String> onShowCase;

  /// "Av. Deniz Kaya": whose side is "MÜVEKKİL".
  final String lawyer;
  final PortalDatabase? database;
  final UyapCaseStore? store;

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

enum _Scope { all, party, number, court }

enum _Sort { change, newest, oldest, hearing, number }

enum _Development { fresh, hearing, thisWeek }

class _PortfolioPageState extends State<PortfolioPage> {
  List<PortfolioRow>? _rows;
  final _search = TextEditingController();
  _Scope _scope = _Scope.all;
  _Sort _sort = _Sort.change;
  bool _closed = false;
  _Development? _development;
  // Each list's choices, any of which a case may match; none chosen, the
  // list does not narrow.
  Set<CaseKind> _kinds = const {};
  Set<String> _roles = const {}, _places = const {};
  int _shown = 100;
  bool _includeClosed = false;
  DateTime? _portfolioAt, _checkedAt;
  bool _showFilters = false;

  PortalSync? get _sync => PortalSync.started;

  @override
  void initState() {
    super.initState();
    _sync?.addListener(_synced);
    _sync?.portfolioVersion.addListener(_grew);
    UyapCaseStore.changes.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _sync?.removeListener(_synced);
    _sync?.portfolioVersion.removeListener(_grew);
    _grewSoon?.cancel();
    UyapCaseStore.changes.removeListener(_reload);
    _search.dispose();
    super.dispose();
  }

  bool _wasRunning = false;
  void _synced() {
    final running = _sync?.state(PortalChannel.uyapMobile).running ?? false;
    // What the reading added is shown as it comes, at most every few
    // seconds, and once more when it ends.
    if (_wasRunning && !running) _reload();
    _wasRunning = running;
    if (mounted) setState(() {});
  }

  /// A case came or changed while a sync runs: shown within a few seconds,
  /// a burst of them read once.
  void _grew() {
    _grewSoon ??= Timer(const Duration(seconds: 4), () {
      _grewSoon = null;
      if (mounted) unawaited(_reload());
    });
  }

  Timer? _grewSoon;

  Future<void> _reload() async {
    try {
      final rows = await loadPortfolio(
        lawyer: widget.lawyer.isNotEmpty
            ? widget.lawyer
            : UyapMobileApi.instance.session.value?.user ?? '',
        database: widget.database,
        store: widget.store,
      );
      final sync = _sync;
      final include = await sync?.includeClosed() ?? false;
      final at = await sync?.portfolioAt();
      final checked = await sync?.casesCheckedAt();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _includeClosed = include;
        _portfolioAt = at;
        _checkedAt = checked;
      });
    } catch (_) {
      if (mounted) setState(() => _rows = const []);
    }
  }

  Future<void> _refresh() async {
    PortalSync.begin();
    final sync = PortalSync.instance;
    if (!sync.mobile.connected) {
      if (!await connectUyapMobile(context, api: sync.mobile)) return;
    }
    await sync.syncMobile(full: true);
    await _reload();
  }

  /// UYAP Mobil: connected, its portfolio read again whole; else its
  /// e-Devlet login first.
  Future<void> _connectMobile() async {
    PortalSync.begin();
    final sync = PortalSync.instance;
    if (sync.mobile.connected ||
        await connectUyapMobile(context, api: sync.mobile)) {
      unawaited(sync.syncMobile(full: true));
    }
  }

  /// The web portal: connected, its documents checked again; else its
  /// login window.
  void _connectWeb() {
    PortalSync.begin();
    final sync = PortalSync.instance;
    if (sync.web.connected) {
      unawaited(sync.syncWeb());
    } else {
      unawaited(
        connectUyapWeb(context, onConnected: () => unawaited(sync.syncWeb())),
      );
    }
  }

  Future<void> _setIncludeClosed(bool value) async {
    PortalSync.begin();
    await PortalSync.instance.setIncludeClosed(value);
    setState(() => _includeClosed = value);
    if (value) unawaited(_refresh());
  }

  // Filtering.

  /// Whether [r] passes the filters; any of them may be put otherwise,
  /// for the count a choice not yet made would give.
  bool _matchesFilters(
    PortfolioRow r, {
    bool? closed,
    Object? development = _keep,
    Set<CaseKind>? kinds,
    Set<String>? roles,
    Set<String>? places,
  }) {
    final dev = identical(development, _keep)
        ? _development
        : development as _Development?;
    if (dev != _Development.hearing && r.closed != (closed ?? _closed)) {
      return false;
    }
    switch (dev) {
      case _Development.fresh:
        if (r.freshCount == 0 && !r.state.isNew) return false;
      case _Development.hearing:
        if (r.hearing == null) return false;
      case _Development.thisWeek:
        final h = r.hearing;
        if (h == null || h.at.difference(DateTime.now()).inDays > 7) {
          return false;
        }
      case null:
    }
    final k = kinds ?? _kinds, ro = roles ?? _roles, pl = places ?? _places;
    if (k.isNotEmpty && !k.contains(r.kind)) return false;
    if (ro.isNotEmpty && !ro.contains(r.ourRole)) return false;
    if (pl.isNotEmpty && !pl.contains(r.place)) return false;
    return true;
  }

  static const _keep = Object();

  /// The search's words, folded; none when it is shorter than two letters.
  List<String> get _words {
    final q = UyapWebService.fold(_search.text.trim());
    return q.length < 2 ? const [] : q.split(' ');
  }

  bool _matchesSearch(PortfolioRow r, [_Scope? scope]) {
    final words = _words;
    if (words.isEmpty) return true;
    final where = switch (scope ?? _scope) {
      _Scope.all => r.haystack,
      _Scope.party => r.partyHaystack,
      _Scope.number => r.numberHaystack,
      _Scope.court => r.courtHaystack,
    };
    return words.every(where.contains);
  }

  /// The rows as the filters, the search and the order leave them; made
  /// again only when one of these changes, not at each frame (two thousand
  /// cases filtered and sorted at every frame of a scroll held the phone).
  List<PortfolioRow> get _visible {
    final key = (
      _development,
      _kinds.map((k) => k.name).join(','),
      _roles.join('\u0001'),
      _places.join('\u0001'),
      _closed,
      _scope,
      _sort,
      _search.text,
    );
    if (identical(_rows, _visibleFor) && key == _visibleKey) {
      return _visibleRows;
    }
    _visibleFor = _rows;
    _visibleKey = key;
    return _visibleRows = _sorted();
  }

  List<PortfolioRow>? _visibleFor;
  Object? _visibleKey;
  List<PortfolioRow> _visibleRows = const [];

  List<PortfolioRow> _sorted() {
    final rows = [
      for (final r in _rows ?? const <PortfolioRow>[])
        if (_matchesFilters(r) && _matchesSearch(r)) r,
    ];
    int byNumber(PortfolioRow a, PortfolioRow b) =>
        a.kase.number.compareTo(b.kase.number);
    switch (_sort) {
      case _Sort.change:
        rows.sort((a, b) {
          final news =
              (b.freshCount > 0 || b.state.isNew ? 1 : 0) -
              (a.freshCount > 0 || a.state.isNew ? 1 : 0);
          return news != 0 ? news : b.lastChange.compareTo(a.lastChange);
        });
      case _Sort.newest:
        rows.sort(
          (a, b) => (b.opened ?? DateTime(1900)).compareTo(
            a.opened ?? DateTime(1900),
          ),
        );
      case _Sort.oldest:
        rows.sort(
          (a, b) => (a.opened ?? DateTime(2999)).compareTo(
            b.opened ?? DateTime(2999),
          ),
        );
      case _Sort.hearing:
        rows.sort(
          (a, b) => (a.hearing?.at ?? DateTime(2999)).compareTo(
            b.hearing?.at ?? DateTime(2999),
          ),
        );
      case _Sort.number:
        rows.sort(byNumber);
    }
    return rows;
  }

  bool get _filtered =>
      _development != null ||
      _kinds.isNotEmpty ||
      _roles.isNotEmpty ||
      _places.isNotEmpty ||
      _closed;

  static Set<T> _toggled<T>(Set<T> set, T value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  void _clearFilters() => setState(() {
    _development = null;
    _kinds = const {};
    _roles = const {};
    _places = const {};
    _closed = false;
    _shown = 100;
  });

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: dark ? Theme.of(context).colorScheme.surface : AgendaColors.page,
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 860;
          // A phone: the heading and the search scroll away with the list,
          // which then has the screen.
          if (!wide) return _narrow(context, rows);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _head(context, wide),
              _progress(context),
              Expanded(
                child: rows == null
                    ? const Center(child: CircularProgressIndicator())
                    : rows.isEmpty
                    ? _empty(context)
                    : Padding(
                        padding: EdgeInsets.fromLTRB(
                          wide ? 24 : 12,
                          16,
                          wide ? 24 : 12,
                          0,
                        ),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 206,
                                    child: SingleChildScrollView(
                                      child: _rail(context),
                                    ),
                                  ),
                                  const SizedBox(width: 22),
                                  Expanded(child: _list(context, wide)),
                                ],
                              )
                            : _list(context, wide),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// A phone (docs/design/telefon-portfoy-suzgec-taslak.png): one bar
  /// with the page's name, and under it the search, open or closed, the
  /// filters as chips each with its own list, and the cases; all but the
  /// bar scroll away with the list.
  Widget _narrow(BuildContext context, List<PortfolioRow>? rows) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visible;
    final shown = visible.take(_shown).toList();
    final words = _scope == _Scope.number ? const <String>[] : _words;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _phoneBar(context),
        _progress(context),
        Expanded(
          child: CustomScrollView(
            key: const ValueKey('portfolio-scroll'),
            slivers: [
              if (rows == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (rows.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _empty(context),
                )
              else ...[
                SliverToBoxAdapter(child: _phoneControls(context)),
                SliverToBoxAdapter(child: _tasked(context)),
                SliverToBoxAdapter(child: _phoneResult(context)),
                if (shown.isEmpty)
                  SliverToBoxAdapter(child: _noMatch(context))
                else
                  DecoratedSliver(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      border: Border(
                        top: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                    sliver: SliverList.builder(
                      key: const ValueKey('portfolio-list'),
                      itemCount:
                          shown.length + (visible.length > _shown ? 1 : 0),
                      itemBuilder: (context, i) => i == shown.length
                          ? TextButton(
                              key: const ValueKey('portfolio-more'),
                              onPressed: () => setState(() => _shown += 100),
                              child: Text(
                                'Daha fazla (${visible.length - _shown} dosya daha)',
                              ),
                            )
                          : _CaseRow(
                              row: shown[i],
                              first: i == 0,
                              wide: false,
                              words: words,
                              onTap: () => widget.onShowCase(shown[i].key),
                            ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The phone's one bar: the menu, the page's name, one dot for the two
  /// channels (its menu connects them or reads them again), the refresh
  /// and what else there is.
  Widget _phoneBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final drawer = Scaffold.maybeOf(context)?.hasDrawer ?? false;
    final now = DateTime.now();
    final mobile = UyapMobileApi.instance.connected;
    final web = UyapWebService.instance.connected;
    final running = _sync?.state(PortalChannel.uyapMobile).running ?? false;
    final dot = mobile && web
        ? AgendaColors.ok
        : mobile || web
        ? const Color(0xFFE0A100)
        : const Color(0xFF9AA2B1);
    PopupMenuItem<String> channel(String value, String text, bool on) =>
        PopupMenuItem(
          key: ValueKey('portfolio-connect-$value'),
          value: value,
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: on ? AgendaColors.ok : const Color(0xFF9AA2B1),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: const TextStyle(fontSize: 13.5)),
              ),
            ],
          ),
        );
    return Container(
      height: 54,
      padding: EdgeInsets.only(left: drawer ? 4 : 16, right: 2),
      color: scheme.surface,
      child: Row(
        children: [
          if (drawer)
            IconButton(
              tooltip: 'Menü',
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          const Expanded(
            child: Text(
              'UYAP Dosyalarım',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700),
            ),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('portfolio-live'),
            tooltip: 'Bağlantılar',
            onSelected: (v) =>
                v == 'mobile' ? unawaited(_connectMobile()) : _connectWeb(),
            itemBuilder: (_) => [
              channel(
                'mobile',
                !mobile
                    ? 'UYAP Mobil · bağlan'
                    : _portfolioAt == null
                    ? 'UYAP Mobil · henüz taranmadı'
                    : 'UYAP Mobil · ${whenText(_portfolioAt!, now)}',
                mobile,
              ),
              channel(
                'web',
                !web
                    ? 'UYAP Web · bağlan'
                    : _checkedAt == null
                    ? 'UYAP Web · bağlı'
                    : 'UYAP Web · ${whenText(_checkedAt!, now)}',
                web,
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: dot.withValues(alpha: .22),
                      spreadRadius: 3,
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('portfolio-refresh'),
            tooltip: 'Portföyü yenile',
            onPressed: running ? null : () => unawaited(_refresh()),
            icon: running
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('portfolio-menu'),
            tooltip: 'Diğer',
            onSelected: (_) => unawaited(_setIncludeClosed(!_includeClosed)),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                key: const ValueKey('portfolio-closed-switch'),
                value: 'closed',
                checked: _includeClosed,
                child: const Text('Kapalı dosyaları da indir'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// What the phone's chips and switches say, counted once for the
  /// filters and the search they are counted under.
  _PhoneCounts get _counts {
    _visible;
    final key = (_visibleKey, _words.join(' '));
    if (identical(_rows, _countsFor) && key == _countsKey) return _countsMemo;
    final rows = _rows ?? const <PortfolioRow>[];
    var open = 0, closed = 0, fresh = 0, week = 0, other = 0;
    final scopes = {for (final s in _Scope.values) s: 0};
    final searching = _words.isNotEmpty;
    for (final r in rows) {
      final found = _matchesSearch(r);
      if (found && _matchesFilters(r, closed: false)) open++;
      if (found && _matchesFilters(r, closed: true)) closed++;
      if (found && _matchesFilters(r, development: _Development.fresh)) {
        fresh++;
      }
      if (found && _matchesFilters(r, development: _Development.thisWeek)) {
        week++;
      }
      if (!searching) continue;
      if (found && _matchesFilters(r, closed: !_closed)) other++;
      if (!_matchesFilters(r)) continue;
      for (final s in _Scope.values) {
        if (_matchesSearch(r, s)) scopes[s] = scopes[s]! + 1;
      }
    }
    _countsFor = _rows;
    _countsKey = key;
    return _countsMemo = (
      open: open,
      closed: closed,
      fresh: fresh,
      week: week,
      otherSide: other,
      scopes: scopes,
    );
  }

  List<PortfolioRow>? _countsFor;
  Object? _countsKey;
  late _PhoneCounts _countsMemo;

  Widget _phoneControls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final counts = _counts;
    final searching = _words.isNotEmpty;
    final well = dark
        ? scheme.surfaceContainerHighest
        : const Color(0xFFF1F3F7);
    void pick(void Function() change) => setState(() {
      change();
      _shown = 100;
    });

    Widget side(String label, int n, bool on, VoidCallback onTap, Key key) =>
        Expanded(
          child: Material(
            color: on ? scheme.surface : Colors.transparent,
            elevation: on ? 1 : 0,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: label),
                      TextSpan(
                        text: '  $n',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: AgendaColors.muted,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        );

    Widget scope(_Scope s, String label) {
      final n = counts.scopes[s] ?? 0;
      final on = _scope == s;
      final ink = on
          ? scheme.primary
          : n == 0
          ? const Color(0xFFA9B0BD)
          : null;
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: s == _Scope.court ? 0 : 6),
          child: Material(
            color: on
                ? dark
                      ? scheme.primary.withValues(alpha: .16)
                      : const Color(0xFFEAF0F9)
                : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
              side: BorderSide(
                color: on ? scheme.primary : scheme.outlineVariant,
              ),
            ),
            child: InkWell(
              key: ValueKey('portfolio-scope-${s.name}'),
              borderRadius: BorderRadius.circular(9),
              onTap: () => pick(() => _scope = s),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  children: [
                    Text(
                      '$n',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    Text(label, style: TextStyle(fontSize: 11, color: ink)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final kindsText = [
      for (final k in CaseKind.values)
        if (_kinds.contains(k)) k.label,
    ].join(', ');
    String several(Set<String> set) =>
        set.length == 1 ? set.first : '${set.first} +${set.length - 1}';
    final lists = <(bool, Widget)>[
      (
        _kinds.isNotEmpty,
        _FilterChip(
          key: const ValueKey('portfolio-kind'),
          label: _kinds.isEmpty ? 'Tür' : kindsText,
          on: _kinds.isNotEmpty,
          list: true,
          onTap: _pickKinds,
          onClear: () => pick(() => _kinds = const {}),
        ),
      ),
      (
        _roles.isNotEmpty,
        _FilterChip(
          key: const ValueKey('portfolio-role'),
          label: _roles.isEmpty ? 'Tarafımız' : several(_roles),
          on: _roles.isNotEmpty,
          list: true,
          onTap: _pickRoles,
          onClear: () => pick(() => _roles = const {}),
        ),
      ),
      (
        _places.isNotEmpty,
        _FilterChip(
          key: const ValueKey('portfolio-place'),
          label: _places.isEmpty
              ? 'Birim'
              : several({
                  for (final p in _places) p.replaceFirst(' Adliyesi', ''),
                }),
          on: _places.isNotEmpty,
          list: true,
          onTap: _pickPlaces,
          onClear: () => pick(() => _places = const {}),
        ),
      ),
    ];
    final toggles = [
      _FilterChip(
        key: const ValueKey('portfolio-fresh'),
        label: 'Yeni evrak',
        count: counts.fresh,
        on: _development == _Development.fresh,
        onTap: () => pick(
          () => _development = _development == _Development.fresh
              ? null
              : _Development.fresh,
        ),
      ),
      _FilterChip(
        key: const ValueKey('portfolio-week'),
        label: 'Bu hafta duruşma',
        count: counts.week,
        on: _development == _Development.thisWeek,
        onTap: () => pick(
          () => _development = _development == _Development.thisWeek
              ? null
              : _Development.thisWeek,
        ),
      ),
    ];
    // What is chosen comes first, where it is seen.
    final chips = [
      for (final (on, chip) in lists)
        if (on) chip,
      ...toggles,
      for (final (on, chip) in lists)
        if (!on) chip,
    ];
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('portfolio-search'),
            controller: _search,
            onChanged: (_) => setState(() => _shown = 100),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: well,
              hintText: 'Dosya no, taraf, mahkeme',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: scheme.primary, width: 2),
              ),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Temizle',
                      icon: const Icon(Icons.close_rounded, size: 19),
                      onPressed: () => pick(() {
                        _search.clear();
                        _scope = _Scope.all;
                      }),
                    ),
            ),
          ),
          if (searching) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                scope(_Scope.all, 'her yerde'),
                scope(_Scope.party, 'tarafta'),
                scope(_Scope.number, 'dosya no'),
                scope(_Scope.court, 'mahkemede'),
              ],
            ),
          ],
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: well,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                side(
                  'Açık',
                  counts.open,
                  !_closed,
                  () => pick(() => _closed = false),
                  const ValueKey('portfolio-side-open'),
                ),
                side(
                  'Kapalı',
                  counts.closed,
                  _closed,
                  () => pick(() => _closed = true),
                  const ValueKey('portfolio-side-closed'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final c in chips)
                  Padding(padding: const EdgeInsets.only(right: 6), child: c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// How many are listed, the way back from the filters, and the order.
  Widget _phoneResult(BuildContext context) {
    final n = _visible.length;
    final other = _counts.otherSide;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 2, 2),
      child: Row(
        children: [
          Text(
            '$n dosya',
            style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
          ),
          if (_words.isNotEmpty && other > 0)
            TextButton(
              key: const ValueKey('portfolio-other-side'),
              onPressed: () => setState(() {
                _closed = !_closed;
                _shown = 100;
              }),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: Text(
                _closed ? 'açıklarda $other daha' : 'kapalılarda $other daha',
                style: const TextStyle(fontSize: 12),
              ),
            )
          else if (_filtered)
            TextButton(
              key: const ValueKey('portfolio-clear'),
              onPressed: _clearFilters,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: const Text('Temizle', style: TextStyle(fontSize: 12)),
            ),
          const Spacer(),
          PopupMenuButton<_Sort>(
            key: const ValueKey('portfolio-sort'),
            tooltip: 'Sırala',
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              for (final s in _Sort.values)
                PopupMenuItem(value: s, child: Text(_sortName(s))),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.swap_vert_rounded, size: 17),
                  const SizedBox(width: 3),
                  Text(
                    _sortName(_sort, short: true),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _sortName(_Sort s, {bool short = false}) => switch (s) {
    _Sort.change => short ? 'Son gelişme' : 'Son gelişme önce',
    _Sort.newest => short ? 'Yeni açılan' : 'Yeni açılan önce',
    _Sort.oldest => short ? 'Eski açılan' : 'Eski açılan önce',
    _Sort.hearing => short ? 'Yaklaşan duruşma' : 'Yaklaşan duruşma önce',
    _Sort.number => 'Esas numarası',
  };

  // A filter's own list, from below: each choice with how many it holds,
  // several at once, the button saying how many will be listed.

  Future<void> _pickKinds() async {
    final picked = await _pickFrom<CaseKind>(
      title: 'Tür',
      chosen: _kinds,
      options: [for (final k in CaseKind.values) (k, k.label, k.ink)],
      matches: (r, set) => _matchesFilters(r, kinds: set),
    );
    if (picked != null) {
      setState(() {
        _kinds = picked;
        _shown = 100;
      });
    }
  }

  Future<void> _pickRoles() async {
    final roles = _topOf(
      (r) => r.ourRole,
      (r, set) => _matchesFilters(r, roles: const {}),
      8,
    );
    final picked = await _pickFrom<String>(
      title: 'Tarafımız',
      chosen: _roles,
      options: [
        for (final v in {...roles, ..._roles}) (v, v, null),
      ],
      matches: (r, set) => _matchesFilters(r, roles: set),
    );
    if (picked != null) {
      setState(() {
        _roles = picked;
        _shown = 100;
      });
    }
  }

  Future<void> _pickPlaces() async {
    final places = _topOf(
      (r) => r.place,
      (r, set) => _matchesFilters(r, places: const {}),
      20,
    );
    final picked = await _pickFrom<String>(
      title: 'Birim',
      chosen: _places,
      options: [
        for (final v in {...places, ..._places})
          (v, v.replaceFirst(' Adliyesi', ''), null),
      ],
      matches: (r, set) => _matchesFilters(r, places: set),
    );
    if (picked != null) {
      setState(() {
        _places = picked;
        _shown = 100;
      });
    }
  }

  /// The [n] values most cases have, among those the other filters and
  /// the search leave.
  List<String> _topOf(
    String? Function(PortfolioRow r) value,
    bool Function(PortfolioRow r, Set<String> none) others,
    int n,
  ) {
    final counts = <String, int>{};
    for (final r in _rows ?? const <PortfolioRow>[]) {
      final v = value(r);
      if (v == null || v.isEmpty) continue;
      if (!others(r, const {}) || !_matchesSearch(r)) continue;
      counts[v] = (counts[v] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in sorted.take(n)) e.key];
  }

  Future<Set<T>?> _pickFrom<T>({
    required String title,
    required Set<T> chosen,
    required List<(T, String, Color?)> options,
    required bool Function(PortfolioRow r, Set<T> set) matches,
  }) {
    final rows = [
      for (final r in _rows ?? const <PortfolioRow>[])
        if (_matchesSearch(r)) r,
    ];
    int count(Set<T> set) => rows.where((r) => matches(r, set)).length;
    final each = {
      for (final o in options) o.$1: count({o.$1}),
    };
    final shown = [
      for (final o in options)
        if (each[o.$1]! > 0 || chosen.contains(o.$1)) o,
    ];
    return showModalBottomSheet<Set<T>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        var local = {...chosen};
        return StatefulBuilder(
          builder: (context, setSheet) {
            final scheme = Theme.of(context).colorScheme;
            final total = count(local);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (local.isNotEmpty)
                        TextButton(
                          onPressed: () => setSheet(() => local = {}),
                          child: const Text('Temizle'),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final (value, label, swatch) in shown)
                        InkWell(
                          key: ValueKey('portfolio-pick-$label'),
                          onTap: () =>
                              setSheet(() => local = _toggled(local, value)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 2,
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: local.contains(value),
                                  onChanged: (_) => setSheet(
                                    () => local = _toggled(local, value),
                                  ),
                                ),
                                if (swatch != null) ...[
                                  Container(
                                    width: 4,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: swatch,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: local.contains(value)
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    '${each[value]}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AgendaColors.muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                          ),
                          child: const Text('Vazgeç'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: FilledButton(
                          key: const ValueKey('portfolio-pick-apply'),
                          onPressed: () => Navigator.pop(context, local),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                          ),
                          child: Text('$total dosyayı göster'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _head(BuildContext context, bool wide) {
    final scheme = Theme.of(context).colorScheme;
    final rows = _rows ?? const <PortfolioRow>[];
    final open = rows.where((r) => !r.closed).length;
    final freshCases = rows.where((r) => r.freshCount > 0).toList();
    final freshDocs = freshCases.fold<int>(0, (s, r) => s + r.freshCount);
    final now = DateTime.now();
    final sync = _sync;
    final mobile = UyapMobileApi.instance.connected;
    final web = UyapWebService.instance.connected;
    final running = sync?.state(PortalChannel.uyapMobile).running ?? false;
    // A channel's chip is its button: not connected, it connects; connected,
    // it syncs that channel again.
    Widget source(
      String name,
      bool on,
      String detail, {
      required Key key,
      required VoidCallback onTap,
    }) => Tooltip(
      message: on ? '$name’i yeniden eşitle' : '$name’e bağlan',
      child: Material(
        color: scheme.surface,
        shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
        child: InkWell(
          key: key,
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: on ? AgendaColors.ok : const Color(0xFF9AA2B1),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  '$name · $detail',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF3F4656),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final chips = [
      source(
        'UYAP Mobil',
        mobile,
        !mobile
            ? 'bağlı değil'
            : _portfolioAt == null
            ? 'henüz taranmadı'
            : 'tam tarama ${whenText(_portfolioAt!, now)}',
        key: const ValueKey('portfolio-connect-mobile'),
        onTap: () => unawaited(_connectMobile()),
      ),
      source(
        'UYAP Web',
        web,
        !web
            ? 'bağlı değil'
            : _checkedAt == null
            ? 'bağlı'
            : 'evraklar ${whenText(_checkedAt!, now)}',
        key: const ValueKey('portfolio-connect-web'),
        onTap: _connectWeb,
      ),
    ];
    final actions = [
      if (wide) ...[
        chips[0],
        const SizedBox(width: 8),
        chips[1],
        const SizedBox(width: 12),
      ],
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            key: const ValueKey('portfolio-closed-switch'),
            value: _includeClosed,
            onChanged: (v) => unawaited(_setIncludeClosed(v)),
          ),
          const SizedBox(width: 4),
          const Flexible(
            child: Text(
              'Kapalı dosyaları da indir',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
      const SizedBox(width: 12),
      FilledButton.icon(
        key: const ValueKey('portfolio-refresh'),
        onPressed: running ? null : () => unawaited(_refresh()),
        icon: running
            ? const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.sync_rounded, size: 17),
        label: const Text('Portföyü yenile'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    ];
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'UYAP Dosyalarım',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          [
            '${rows.length} dosya',
            '$open açık',
            '${rows.length - open} kapalı',
            if (freshDocs > 0)
              '${freshCases.length} dosyada $freshDocs yeni evrak',
          ].join(' · '),
          style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
        ),
      ],
    );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 12, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: wide
          ? Row(
              children: [
                Expanded(child: title),
                ...actions,
              ],
            )
          // A phone: the title with its two actions beside it, the
          // channels under it; the rest of the screen is the list's.
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: title),
                    IconButton(
                      key: const ValueKey('portfolio-refresh'),
                      tooltip: 'Portföyü yenile',
                      onPressed: running ? null : () => unawaited(_refresh()),
                      icon: running
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                    ),
                    PopupMenuButton<String>(
                      key: const ValueKey('portfolio-menu'),
                      tooltip: 'Diğer',
                      onSelected: (_) =>
                          unawaited(_setIncludeClosed(!_includeClosed)),
                      itemBuilder: (_) => [
                        CheckedPopupMenuItem(
                          key: const ValueKey('portfolio-closed-switch'),
                          value: 'closed',
                          checked: _includeClosed,
                          child: const Text('Kapalı dosyaları da indir'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, children: chips),
              ],
            ),
    );
  }

  Widget _progress(BuildContext context) {
    final state = _sync?.state(PortalChannel.uyapMobile);
    if (state == null || !state.running) return const SizedBox.shrink();
    final text = state.progress ?? 'Hazırlanıyor';
    final m = RegExp(r'(\d+)/(\d+)').firstMatch(text);
    final value = m == null
        ? null
        : int.parse(m.group(1)!) / int.parse(m.group(2)!).clamp(1, 1 << 30);
    final what = text.startsWith('Evraklar')
        ? 'Açık dosyaların yenilikleri kontrol ediliyor · $text'
        : text.startsWith('Portföy')
        ? 'Portföy dolduruluyor · $text'
        : '$text alınıyor';
    return Container(
      key: const ValueKey('portfolio-progress'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF3F7FC),
        border: Border(bottom: BorderSide(color: Color(0xFFDCE6F4))),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.downloading_rounded,
            size: 16,
            color: AgendaColors.hearing,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$what — uygulamayı kullanmaya devam edebilirsiniz',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF1F467F)),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: LinearProgressIndicator(
              value: value,
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.gavel_rounded, size: 40, color: AgendaColors.muted),
          const SizedBox(height: 12),
          const Text(
            'Portföy henüz boş',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'UYAP Mobil’e bağlanınca açık dosyalarınızın tamamı buraya '
            'kendiliğinden gelir; seçip eklemeniz gerekmez.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AgendaColors.muted),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => unawaited(_refresh()),
            icon: const Icon(Icons.sync_rounded, size: 17),
            label: const Text('Portföyü getir'),
          ),
        ],
      ),
    ),
  );

  // The rail.

  Widget _rail(BuildContext context) {
    final rows = _rows ?? const <PortfolioRow>[];
    final base = [
      for (final r in rows)
        if (_matchesSearch(r)) r,
    ];
    int count(bool Function(PortfolioRow r) test) => base.where(test).length;
    final open = [
      for (final r in base)
        if (!r.closed) r,
    ];
    final scheme = Theme.of(context).colorScheme;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: AgendaColors.muted,
        ),
      ),
    );
    Widget item(
      String label,
      int n,
      bool on,
      VoidCallback onTap, {
      Color? swatch,
      bool badge = false,
      Key? key,
    }) => Material(
      color: on ? const Color(0xFFEAF0F9) : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: [
              if (swatch != null) ...[
                Container(
                  width: 3,
                  height: 11,
                  decoration: BoxDecoration(
                    color: swatch,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                    color: on ? scheme.primary : null,
                  ),
                ),
              ),
              if (badge && n > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$n',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: on ? scheme.primary : AgendaColors.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    Map<String, int> top(Iterable<String?> values, int n) {
      final counts = <String, int>{};
      for (final v in values) {
        if (v == null || v.isEmpty) continue;
        counts[v] = (counts[v] ?? 0) + 1;
      }
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return {for (final e in sorted.take(n)) e.key: e.value};
    }

    void pick(void Function() change) => setState(() {
      change();
      _shown = 100;
    });
    final roles = top(open.map((r) => r.ourRole), 6);
    final places = top(open.map((r) => r.place), 4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('DURUM'),
        item(
          'Açık',
          open.length,
          !_closed,
          () => pick(() => _closed = false),
          key: const ValueKey('portfolio-open'),
        ),
        item(
          'Kapalı / Arşiv',
          base.length - open.length,
          _closed,
          () => pick(() => _closed = true),
          key: const ValueKey('portfolio-closed'),
        ),
        heading('GELİŞME'),
        item(
          'Yeni evrak gelen',
          count((r) => r.freshCount > 0 || r.state.isNew),
          _development == _Development.fresh,
          () => pick(
            () => _development = _development == _Development.fresh
                ? null
                : _Development.fresh,
          ),
          badge: true,
          key: const ValueKey('portfolio-fresh'),
        ),
        item(
          'Duruşması olan',
          count((r) => r.hearing != null),
          _development == _Development.hearing,
          () => pick(() {
            _development = _development == _Development.hearing
                ? null
                : _Development.hearing;
            if (_development != null) _sort = _Sort.hearing;
          }),
        ),
        item(
          'Bu hafta duruşma',
          count(
            (r) =>
                r.hearing != null &&
                r.hearing!.at.difference(DateTime.now()).inDays <= 7,
          ),
          _development == _Development.thisWeek,
          () => pick(
            () => _development = _development == _Development.thisWeek
                ? null
                : _Development.thisWeek,
          ),
        ),
        heading('TÜR'),
        for (final kind in CaseKind.values)
          if (count((r) => r.kind == kind && r.closed == _closed) > 0)
            item(
              kind.label,
              count((r) => r.kind == kind && r.closed == _closed),
              _kinds.contains(kind),
              () => pick(() => _kinds = _toggled(_kinds, kind)),
              swatch: kind.ink,
            ),
        if (roles.isNotEmpty) ...[
          heading('TARAFIMIZ'),
          for (final e in roles.entries)
            item(
              e.key,
              e.value,
              _roles.contains(e.key),
              () => pick(() => _roles = _toggled(_roles, e.key)),
            ),
        ],
        if (places.length > 1) ...[
          heading('BİRİM'),
          for (final e in places.entries)
            item(
              e.key,
              e.value,
              _places.contains(e.key),
              () => pick(() => _places = _toggled(_places, e.key)),
            ),
        ],
        if (_filtered)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _clearFilters,
                child: const Text('Süzgeçleri temizle'),
              ),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  // The list.

  /// Cases that came with tasks given to this user (docs/design/
  /// buro-yonetim-taslak.png, 2b): seen here though UYAP does not let the
  /// user open them; a tap opens the task, its case and documents in it.
  Widget _tasked(BuildContext context) => ListenableBuilder(
    listenable: OfficeNetwork.instance,
    builder: (context, _) => _taskedNow(context),
  );

  Widget _taskedNow(BuildContext context) {
    final net = OfficeNetwork.instance;
    final me = net.self?.deviceId ?? '';
    final rows = [
      for (final t in net.tasks.all)
        if (t.open && t.assignees.containsKey(me))
          for (final c in t.cases) (t, c, net.receivedCase(t, c.caseKey)),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('portfolio-tasked'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: AgendaColors.task.withValues(alpha: .5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text(
              'GÖREVLE GELEN DOSYALAR · ${rows.length}',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: .7,
                color: AgendaColors.taskText,
              ),
            ),
          ),
          for (final (t, c, got) in rows)
            InkWell(
              key: ValueKey('portfolio-tasked-${t.id}-${c.caseKey}'),
              onTap: () => unawaited(TaskDetail.show(context, net, t)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c.number} · ${c.court}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      [
                        '${t.byName} verdi',
                        t.title,
                        if (got != null) '${got.documents.length} evrak',
                        if (got == null) 'evrak geliyor',
                        if (c.items.isNotEmpty) '${c.items.length} iş',
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
            ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, bool wide) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visible;
    final shown = visible.take(_shown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _controls(context, wide),
        _tasked(context),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: shown.isEmpty
                ? _noMatch(context)
                : ListView.builder(
                    key: const ValueKey('portfolio-list'),
                    itemCount: shown.length + (visible.length > _shown ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == shown.length) {
                        return TextButton(
                          key: const ValueKey('portfolio-more'),
                          onPressed: () => setState(() => _shown += 100),
                          child: Text(
                            'Daha fazla (${visible.length - _shown} dosya daha)',
                          ),
                        );
                      }
                      return _CaseRow(
                        row: shown[i],
                        first: i == 0,
                        wide: wide,
                        onTap: () => widget.onShowCase(shown[i].key),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  /// The search, the scopes, the filters and the order, above the rows.
  Widget _controls(BuildContext context, bool wide) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visible;
    Widget scopeChip(_Scope scope, String label) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: _scope == scope,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _scope = scope),
      ),
    );
    final hint = switch (_scope) {
      _Scope.all => '2024/318 · manavgat asliye · ozturk · icra',
      _Scope.party => 'Taraf adı — ozturk, kaya yapı…',
      _Scope.number => 'Esas no — 2024/318',
      _Scope.court => 'Birim — manavgat icra, bam',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('portfolio-search'),
          controller: _search,
          onChanged: (_) => setState(() => _shown = 100),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            hintText: hint,
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Temizle',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(_search.clear),
                  ),
          ),
        ),
        const SizedBox(height: 9),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (!wide) ...[
                ActionChip(
                  avatar: const Icon(Icons.tune_rounded, size: 16),
                  label: Text(_filtered ? 'Süzgeçler ·' : 'Süzgeçler'),
                  onPressed: () => setState(() => _showFilters = !_showFilters),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
              ],
              scopeChip(_Scope.all, 'Hepsi'),
              scopeChip(_Scope.party, 'Taraf'),
              scopeChip(_Scope.number, 'Dosya no'),
              scopeChip(_Scope.court, 'Mahkeme'),
              if (wide)
                const Padding(
                  padding: EdgeInsets.only(left: 6, right: 12),
                  child: Text(
                    'büyük/küçük harf ve aksan farkı aramayı bozmaz '
                    '(ozturk = ÖZTÜRK)',
                    style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
                  ),
                ),
            ],
          ),
        ),
        if (!wide && _showFilters)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            constraints: const BoxConstraints(maxHeight: 320),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(child: _rail(context)),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _search.text.trim().length >= 2 || _filtered
                    ? '${visible.length} dosya eşleşti'
                    : '${visible.length} dosya',
                style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
              ),
            ),
            PopupMenuButton<_Sort>(
              key: const ValueKey('portfolio-sort'),
              tooltip: 'Sırala',
              initialValue: _sort,
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _Sort.change,
                  child: Text('Son gelişme önce'),
                ),
                PopupMenuItem(
                  value: _Sort.newest,
                  child: Text('Yeni açılan önce'),
                ),
                PopupMenuItem(
                  value: _Sort.oldest,
                  child: Text('Eski açılan önce'),
                ),
                PopupMenuItem(
                  value: _Sort.hearing,
                  child: Text('Yaklaşan duruşma önce'),
                ),
                PopupMenuItem(
                  value: _Sort.number,
                  child: Text('Esas numarası'),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Sırala: ${switch (_sort) {
                    _Sort.change => 'Son gelişme önce',
                    _Sort.newest => 'Yeni açılan önce',
                    _Sort.oldest => 'Eski açılan önce',
                    _Sort.hearing => 'Yaklaşan duruşma önce',
                    _Sort.number => 'Esas numarası',
                  }} ▾',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _noMatch(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Eşleşen dosya yok.'),
          if (_filtered) ...[
            const SizedBox(height: 8),
            const Text(
              'Süzgeçler açık: arama bunların içinde yapıldı.',
              style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
            ),
            TextButton(
              onPressed: _clearFilters,
              child: const Text('Süzgeçleri kaldır'),
            ),
          ],
        ],
      ),
    ),
  );
}

typedef _PhoneCounts = ({
  int open,
  int closed,
  int fresh,
  int week,
  int otherSide,
  Map<_Scope, int> scopes,
});

/// A filter on a phone: a switch with its count, or a list's chip that
/// opens the list and, once something in it is chosen, says what and
/// takes it off with its ✕.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
    this.count,
    this.list = false,
    this.onClear,
  });

  final String label;
  final bool on, list;
  final int? count;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = on ? scheme.onPrimary : scheme.onSurface;
    return Material(
      color: on ? scheme.primary : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: on ? scheme.primary : const Color(0xFFD5DBE5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(11, 7, list ? 5 : 11, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: ink,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              if (list)
                on && onClear != null
                    ? InkResponse(
                        onTap: onClear,
                        radius: 16,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: Icon(
                            Icons.close_rounded,
                            size: 17,
                            color: ink,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.expand_more_rounded,
                        size: 19,
                        color: scheme.onSurfaceVariant,
                      ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One case in the list: its kind's stripe, its number, kind and court,
/// its chips, its parties and what is new in it.
class _CaseRow extends StatefulWidget {
  const _CaseRow({
    required this.row,
    required this.first,
    required this.wide,
    required this.onTap,
    this.words = const [],
  });
  final PortfolioRow row;
  final bool first, wide;
  final VoidCallback onTap;

  /// The search's folded words, marked where they are found.
  final List<String> words;

  @override
  State<_CaseRow> createState() => _CaseRowState();
}

class _CaseRowState extends State<_CaseRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final kind = r.kind;
    final now = DateTime.now();
    final fresh = r.freshDocuments;
    final freshCount = r.freshCount;
    final status = shortStatus(r.status);
    final tone = toneOf(r.status);
    Widget chip(String text, Color fill, Color ink, {Key? key}) => Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ink),
      ),
    );
    final chips = <Widget>[
      if (r.state.isNew) chip('Yeni dosya', AgendaColors.hearing, Colors.white),
      if (freshCount > 0)
        chip(
          '$freshCount yeni evrak',
          AgendaColors.hearing,
          Colors.white,
          key: ValueKey('portfolio-fresh-${r.key}'),
        ),
      if (r.hearing != null)
        () {
          final at = r.hearing!.at;
          final days = DateTime(
            at.year,
            at.month,
            at.day,
          ).difference(DateTime(now.year, now.month, now.day)).inDays;
          return days == 0
              ? chip(
                  'duruşma bugün ${clockText(at)}',
                  AgendaColors.deadlineFill,
                  AgendaColors.deadline,
                )
              : chip(
                  'duruşma ${dayText(at)}${days <= 30 ? ' · $days gün' : ''}',
                  AgendaColors.taskFill,
                  AgendaColors.taskText,
                );
        }(),
      if (status.isNotEmpty)
        switch (tone) {
          StatusTone.open => chip(
            status,
            const Color(0xFFEAF7F1),
            const Color(0xFF157A52),
          ),
          StatusTone.closed => chip(
            status,
            const Color(0xFFEEF0F3),
            const Color(0xFF5D6474),
          ),
          StatusTone.other => chip(
            status,
            AgendaColors.taskFill,
            AgendaColors.taskText,
          ),
        },
    ];
    final words = widget.words;
    final court = Text.rich(
      TextSpan(children: _marked(r.kase.court, words)),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: widget.wide ? 13 : 12.5),
    );
    final line1 = Row(
      children: [
        Text(
          r.kase.number,
          style: const TextStyle(
            fontFamily: 'Consolas',
            fontFamilyFallback: ['Cascadia Mono', 'monospace'],
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 9),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: kind.fill,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            kind.label.toUpperCase().replaceAll('I', 'I'),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: .4,
              color: kind.ink,
            ),
          ),
        ),
        if (widget.wide) ...[
          const SizedBox(width: 9),
          Expanded(child: court),
        ] else
          const Spacer(),
        if (widget.wide)
          for (final c in chips)
            Padding(padding: const EdgeInsets.only(left: 6), child: c),
      ],
    );
    TextSpan names(List<dynamic> parties, {required bool bold}) {
      final shown = parties.take(2).toList();
      return TextSpan(
        children: [
          for (final (i, p) in shown.indexed) ...[
            if (i > 0) const TextSpan(text: ', '),
            TextSpan(
              children: _marked(titleName(p.name as String), words),
              style: TextStyle(
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            TextSpan(
              text: ' ${titleName(p.role as String)}',
              style: const TextStyle(fontSize: 11.5, color: AgendaColors.muted),
            ),
          ],
          if (parties.length > 2)
            TextSpan(
              text: ' · +${parties.length - 2} taraf',
              style: const TextStyle(fontSize: 11.5, color: AgendaColors.muted),
            ),
        ],
      );
    }

    Widget partyLine(String label, Color color, InlineSpan text) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
      ],
    );
    // A party the search found but the two names shown leave out.
    (String, UyapParty)? why;
    if (words.isNotEmpty) {
      bool found(UyapParty p) {
        final name = UyapWebService.fold(p.name);
        return words.any(name.contains);
      }

      for (final (label, list) in [
        ('Müvekkil', r.ours),
        (r.ours.isEmpty ? 'Taraf' : 'Karşı taraf', r.others),
      ]) {
        final at = list.indexWhere(found);
        if (at >= 2) {
          why = (label, list[at]);
          break;
        }
        if (at >= 0) break;
      }
    }
    final record = r.record;
    final opened = r.opened;
    final footer = [
      if (r.state.change != null && fresh.isEmpty) r.state.change!,
      if (r.type.isNotEmpty) r.type,
      if (opened != null) 'açılış ${dayText(opened)}',
      if (record != null) 'senkron ${whenText(record.fetchedAt, now)}',
      if (record == null) 'yalnız künye',
    ];
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        key: ValueKey('portfolio-row-${r.key}'),
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFF8FAFD) : null,
            border: Border(
              top: widget.first
                  ? BorderSide.none
                  : const BorderSide(color: Color(0xFFEEF1F5)),
              left: BorderSide(color: kind.ink, width: 3),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 11, 16, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line1,
              if (!widget.wide) ...[const SizedBox(height: 2), court],
              if (why != null) ...[
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '${why.$1}: '),
                      TextSpan(
                        children: _marked(titleName(why.$2.name), words),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1B2130),
                        ),
                      ),
                      if (why.$2.role.isNotEmpty)
                        TextSpan(text: ' · ${titleName(why.$2.role)}'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AgendaColors.muted,
                  ),
                ),
              ],
              if (!widget.wide && chips.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: chips),
              ],
              if (r.ours.isNotEmpty || r.others.isNotEmpty) ...[
                const SizedBox(height: 6),
                if (r.ours.isNotEmpty)
                  partyLine(
                    'MÜVEKKİL',
                    const Color(0xFF157A52),
                    names(r.ours, bold: true),
                  ),
                if (r.others.isNotEmpty)
                  partyLine(
                    r.ours.isEmpty ? 'TARAFLAR' : 'KARŞI',
                    const Color(0xFF8A92A3),
                    names(r.others, bold: false),
                  ),
              ],
              const SizedBox(height: 5),
              Text.rich(
                TextSpan(
                  children: [
                    if (fresh.isNotEmpty)
                      TextSpan(
                        text:
                            'Yeni: ${fresh.take(3).map((d) => d.type.isNotEmpty ? d.type : d.title).join(', ')}'
                            '${fresh.length > 3 ? ' +${fresh.length - 3}' : ''}'
                            '${footer.isEmpty ? '' : ' · '}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    TextSpan(text: footer.join(' · ')),
                  ],
                ),
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
      ),
    );
  }
}

/// [text] in spans, the places where one of the folded [words] is found
/// in it marked.
List<TextSpan> _marked(String text, List<String> words) {
  if (words.isEmpty || text.isEmpty) return [TextSpan(text: text)];
  final folded = StringBuffer();
  final at = <int>[];
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    final f = c.trim().isEmpty ? ' ' : UyapWebService.fold(c);
    for (var k = 0; k < f.length; k++) {
      folded.write(f[k]);
      at.add(i);
    }
  }
  final hay = folded.toString();
  final mark = List<bool>.filled(text.length, false);
  for (final w in words) {
    if (w.isEmpty) continue;
    for (var j = hay.indexOf(w); j >= 0; j = hay.indexOf(w, j + w.length)) {
      for (var k = j; k < j + w.length; k++) {
        mark[at[k]] = true;
      }
    }
  }
  if (!mark.contains(true)) return [TextSpan(text: text)];
  const style = TextStyle(backgroundColor: Color(0xFFFFE8A3));
  final spans = <TextSpan>[];
  var from = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i == text.length || mark[i] != mark[from]) {
      spans.add(
        TextSpan(
          text: text.substring(from, i),
          style: mark[from] ? style : null,
        ),
      );
      from = i;
    }
  }
  return spans;
}
