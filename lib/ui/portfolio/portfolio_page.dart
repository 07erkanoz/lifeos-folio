import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/portal/portal_channel.dart';
import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../../services/uyap/uyap_mobile_api.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../agenda/mobile_connect.dart';
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
  CaseKind? _kind;
  String? _role, _place;
  int _shown = 100;
  bool _includeClosed = false;
  DateTime? _portfolioAt, _checkedAt;
  bool _showFilters = false;

  PortalSync? get _sync => PortalSync.started;

  @override
  void initState() {
    super.initState();
    _sync?.addListener(_synced);
    UyapCaseStore.changes.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _sync?.removeListener(_synced);
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

  Future<void> _setIncludeClosed(bool value) async {
    PortalSync.begin();
    await PortalSync.instance.setIncludeClosed(value);
    setState(() => _includeClosed = value);
    if (value) unawaited(_refresh());
  }

  // Filtering.

  bool _matchesFilters(PortfolioRow r, {bool status = true}) {
    if (status && _development != _Development.hearing && r.closed != _closed) {
      return false;
    }
    switch (_development) {
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
    if (_kind != null && r.kind != _kind) return false;
    if (_role != null && r.ourRole != _role) return false;
    if (_place != null && r.place != _place) return false;
    return true;
  }

  bool _matchesSearch(PortfolioRow r) {
    final q = UyapWebService.fold(_search.text.trim());
    if (q.length < 2) return true;
    final words = q.split(RegExp(r'\s+'));
    final where = switch (_scope) {
      _Scope.all => r.haystack,
      _Scope.party => UyapWebService.fold(
        [
          for (final p in [...r.ours, ...r.others]) p.name,
        ].join(' '),
      ),
      _Scope.number => UyapWebService.fold(r.kase.number),
      _Scope.court => UyapWebService.fold(r.kase.court),
    };
    return words.every(where.contains);
  }

  List<PortfolioRow> get _visible {
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
      _kind != null ||
      _role != null ||
      _place != null ||
      _closed;

  void _clearFilters() => setState(() {
    _development = null;
    _kind = null;
    _role = null;
    _place = null;
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
    Widget source(String name, bool on, String detail) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(999),
      ),
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
            style: const TextStyle(fontSize: 12, color: Color(0xFF3F4656)),
          ),
        ],
      ),
    );
    final actions = [
      if (wide) ...[
        source(
          'UYAP Mobil',
          mobile,
          !mobile
              ? 'bağlı değil'
              : _portfolioAt == null
              ? 'henüz taranmadı'
              : 'tam tarama ${whenText(_portfolioAt!, now)}',
        ),
        const SizedBox(width: 8),
        source(
          'UYAP Web',
          web,
          !web
              ? 'bağlı değil'
              : _checkedAt == null
              ? 'bağlı'
              : 'evraklar ${whenText(_checkedAt!, now)}',
        ),
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
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 8),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 6,
                  children: actions,
                ),
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
              _kind == kind,
              () => pick(() => _kind = _kind == kind ? null : kind),
              swatch: kind.ink,
            ),
        if (roles.isNotEmpty) ...[
          heading('TARAFIMIZ'),
          for (final e in roles.entries)
            item(
              e.key,
              e.value,
              _role == e.key,
              () => pick(() => _role = _role == e.key ? null : e.key),
            ),
        ],
        if (places.length > 1) ...[
          heading('BİRİM'),
          for (final e in places.entries)
            item(
              e.key,
              e.value,
              _place == e.key,
              () => pick(() => _place = _place == e.key ? null : e.key),
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

  Widget _list(BuildContext context, bool wide) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visible;
    final shown = visible.take(_shown).toList();
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

/// One case in the list: its kind's stripe, its number, kind and court,
/// its chips, its parties and what is new in it.
class _CaseRow extends StatefulWidget {
  const _CaseRow({
    required this.row,
    required this.first,
    required this.wide,
    required this.onTap,
  });
  final PortfolioRow row;
  final bool first, wide;
  final VoidCallback onTap;

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
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            r.kase.court,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
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
              text: titleName(p.name as String),
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
