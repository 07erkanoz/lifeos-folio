import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/editor/suggestions/phrases.dart';
import '../../services/portal/portal_case.dart';
import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/portal/uyap_notice.dart';
import '../../services/portal/uyap_notice_alerts.dart';
import '../mobile/scroll_chrome.dart';
import '../portfolio/portfolio_rows.dart';
import 'agenda_page.dart' show AgendaColors;
import 'channel_bar.dart';

enum _Filter { all, unread, untied }

/// UYAP Bildirimleri (docs/design/uyap-bildirim-taslak.png): UYAP Mobil's
/// and the portal's notifications in one list, each tied to its case,
/// read and unread as on UYAP.
class UyapNoticesPage extends StatefulWidget {
  final PortalDatabase? database;
  final PortalSync? sync;
  final DateTime Function()? now;

  /// Shows a case's page; false when Folio has no page for it.
  final bool Function(String caseKey)? onOpenCase;

  /// Something kept changed: the sidebar's count may need refreshing.
  final VoidCallback? onChanged;

  /// The notification to show selected (its [UyapNotice.signature]),
  /// coming from the desktop's word of it.
  final String? initialNotice;

  const UyapNoticesPage({
    super.key,
    this.database,
    this.sync,
    this.now,
    this.onOpenCase,
    this.onChanged,
    this.initialNotice,
  });

  @override
  State<UyapNoticesPage> createState() => _UyapNoticesPageState();
}

class _UyapNoticesPageState extends State<UyapNoticesPage> {
  PortalDatabase? _db;
  List<UyapNotice> _notices = const [];
  Map<String, PortalCase> _cases = const {};
  _Filter _filter = _Filter.all;
  UyapNoticeKind? _kind;
  String? _selected;
  final _search = TextEditingController();
  Timer? _soon;
  bool _narrow = false;

  PortalSync get _sync => widget.sync ?? PortalSync.instance;
  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _sync.noticesVersion.addListener(_changed);
    unawaited(_load(first: true));
    // The page opened: UYAP is asked, at most once a minute.
    unawaited(_sync.syncNotices());
  }

  @override
  void dispose() {
    _soon?.cancel();
    _sync.noticesVersion.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  /// Told often while a reading runs: read again once it is quiet a moment.
  void _changed() {
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 400), () => unawaited(_load()));
  }

  Future<void> _load({bool first = false}) async {
    final db = _db ??= widget.database ?? await PortalDatabase.shared();
    final notices = db.uyapNotices();
    final cases = db.cases();
    if (!mounted) return;
    setState(() {
      _notices = notices;
      _cases = cases;
      if (first && widget.initialNotice != null) {
        _selected = notices
            .where((n) => n.signature == widget.initialNotice)
            .firstOrNull
            ?.key;
      }
      // A twin arriving makes a new key: the one chosen stays chosen.
      if (_selected != null && !notices.any((n) => n.key == _selected)) {
        _selected = notices
            .where((n) => n.key.contains(_selected!.split('+').first))
            .firstOrNull
            ?.key;
      }
    });
    widget.onChanged?.call();
  }

  bool _shows(UyapNotice n) {
    if (_filter == _Filter.unread && n.read) return false;
    if (_filter == _Filter.untied && n.caseKey != null) return false;
    if (_kind != null && n.kind != _kind) return false;
    final q = foldPhrase(_search.text.trim());
    if (q.isEmpty) return true;
    final kase = n.caseKey == null ? null : _cases[n.caseKey];
    return foldPhrase(
      '${n.title} ${n.body} ${kase?.number ?? ''} ${kase?.court ?? ''}',
    ).contains(q);
  }

  Future<void> _choose(UyapNotice n) async {
    setState(() => _selected = n.key);
    if (_narrow) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(n.title)),
            body: ListenableBuilder(
              listenable: _sync.noticesVersion,
              builder: (context, _) => SingleChildScrollView(
                child: _detail(
                  context,
                  _notices.where((x) => x.key == _selected).firstOrNull ?? n,
                ),
              ),
            ),
          ),
        ),
      );
    }
    // Opened is read, here and on UYAP.
    if (!n.read) await _sync.markNotices([n], read: true);
  }

  void _openCase(String key) => widget.onOpenCase?.call(key);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    _narrow = MediaQuery.sizeOf(context).width < 900;
    final gutter = MediaQuery.sizeOf(context).width < 700 ? 12.0 : 20.0;
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
                _topBar(context),
                Container(
                  color: Theme.of(context).colorScheme.surface,
                  padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 8),
                  child: PortalChannelBar(sync: _sync),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 16),
              child: _narrow
                  ? _card(context, child: _list(context))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 560,
                          child: _card(context, child: _list(context)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _card(
                            context,
                            child: switch (_notices
                                .where((n) => n.key == _selected)
                                .firstOrNull) {
                              null => const Center(
                                child: Text(
                                  'Okumak için soldan bir bildirim seçin.',
                                  style: TextStyle(color: AgendaColors.muted),
                                ),
                              ),
                              final n => _detail(context, n),
                            },
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

  Widget _card(BuildContext context, {required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _topBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = _notices.where((n) => !n.read).length;
    final checked = _sync.noticesCheckedAt;
    final problem = _sync.noticeProblem;
    final busy = _sync.noticesRunning;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'UYAP Bildirimleri',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          [
            '${_notices.length} bildirim',
            '$unread okunmamış',
            if (checked != null) 'son kontrol ${clockText(checked)}',
          ].join(' · '),
          key: const ValueKey('notices-summary'),
          style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
        ),
        if (problem != null)
          Text(
            problem,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              color: AgendaColors.deadline,
            ),
          ),
      ],
    );
    final actions = [
      IconButton(
        key: const ValueKey('notices-alerts'),
        tooltip: 'Masaüstü uyarıları',
        onPressed: () => unawaited(_alerts(context)),
        icon: const Icon(Icons.notifications_active_outlined),
      ),
      OutlinedButton.icon(
        key: const ValueKey('notices-read-all'),
        onPressed: unread == 0
            ? null
            : () => unawaited(
                _sync.markNotices([
                  for (final n in _notices)
                    if (!n.read) n,
                ], read: true),
              ),
        icon: const Icon(Icons.done_all_rounded, size: 17),
        label: const Text('Tümünü okundu say'),
      ),
      FilledButton.icon(
        key: const ValueKey('notices-refresh'),
        onPressed: busy
            ? null
            : () => unawaited(_sync.syncNotices(force: true)),
        icon: const Icon(Icons.sync_rounded, size: 17),
        label: const Text('Yenile'),
      ),
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(_narrow ? 12 : 24, 14, _narrow ? 8 : 24, 10),
      color: scheme.surface,
      child: _narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: actions),
              ],
            )
          : Row(
              children: [
                Expanded(child: title),
                Wrap(spacing: 8, runSpacing: 6, children: actions),
              ],
            ),
    );
  }

  /// Which kinds pop up on the desktop, and whether any do.
  Future<void> _alerts(BuildContext context) async {
    final db = _db;
    if (db == null) return;
    var alerts = UyapNoticeAlerts.of(db);
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) {
          void set(UyapNoticeAlerts next) {
            alerts = next;
            next.save(db);
            setDialog(() {});
          }

          return AlertDialog(
            title: const Text('Masaüstü uyarıları'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    key: const ValueKey('notices-alerts-on'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Yeni bildirim gelince uyar'),
                    subtitle: const Text(
                      'Folio açıkken, işletim sisteminin bildirimi olarak.',
                    ),
                    value: alerts.on,
                    onChanged: (v) =>
                        set(UyapNoticeAlerts(on: v, quiet: alerts.quiet)),
                  ),
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Uyarılacak türler',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AgendaColors.muted,
                      ),
                    ),
                  ),
                  for (final kind in UyapNoticeKind.values)
                    CheckboxListTile(
                      key: ValueKey('notices-alert-${kind.name}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(kind.label),
                      value: !alerts.quiet.contains(kind),
                      onChanged: alerts.on
                          ? (v) => set(
                              UyapNoticeAlerts(
                                on: alerts.on,
                                quiet: v == true
                                    ? ({...alerts.quiet}..remove(kind))
                                    : {...alerts.quiet, kind},
                              ),
                            )
                          : null,
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tamam'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _list(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = [
      for (final n in _notices)
        if (_shows(n)) n,
    ];
    final entries = <Object>[];
    String? bucket;
    for (final n in shown) {
      final b = _bucket(n.sentAt);
      if (b != bucket) {
        bucket = b;
        entries.add(b);
      }
      entries.add(n);
    }
    Widget filter(_Filter f, String label) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        key: ValueKey('notices-filter-${f.name}'),
        label: Text(label),
        selected: _filter == f,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _filter = f),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('notices-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                  hintText:
                      'Bildirimlerde ara: dosya no, mahkeme, karar, reddiyat',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 6,
                children: [
                  filter(_Filter.all, 'Tümü · ${_notices.length}'),
                  filter(
                    _Filter.unread,
                    'Okunmamış · ${_notices.where((n) => !n.read).length}',
                  ),
                  filter(
                    _Filter.untied,
                    'Dosyası bulunamayan · ${_notices.where((n) => n.caseKey == null).length}',
                  ),
                  PopupMenuButton<UyapNoticeKind?>(
                    key: const ValueKey('notices-kind'),
                    tooltip: 'Türe göre',
                    onSelected: (k) => setState(() => _kind = k),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: null,
                        child: Text('Tüm türler'),
                      ),
                      for (final k in UyapNoticeKind.values)
                        if (_notices.any((n) => n.kind == k))
                          PopupMenuItem(
                            value: k,
                            child: Text(
                              '${k.label} · ${_notices.where((n) => n.kind == k).length}',
                            ),
                          ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      child: Text(
                        '${_kind?.label ?? 'Türe göre'} ▾',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _kind == null
                              ? FontWeight.w400
                              : FontWeight.w700,
                          color: _kind == null
                              ? AgendaColors.muted
                              : scheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _notices.isEmpty
                          ? 'Henüz bildirim yok. UYAP Mobil ya da UYAP Web '
                                'bağlıyken bildirimler burada toplanır.'
                          : 'Bu süzgece uyan bildirim yok.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AgendaColors.muted),
                    ),
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('notices-list'),
                  itemCount: entries.length,
                  itemBuilder: (context, i) => switch (entries[i]) {
                    final String b => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        b,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .9,
                          color: AgendaColors.muted,
                        ),
                      ),
                    ),
                    final UyapNotice n => _row(context, n),
                    _ => const SizedBox.shrink(),
                  },
                ),
        ),
      ],
    );
  }

  String _bucket(DateTime? at) {
    if (at == null) return 'TARİHİ BİLİNMİYOR';
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final ago = today.difference(day).inDays;
    if (ago <= 0) return 'BUGÜN';
    if (ago == 1) return 'DÜN';
    return dayText(at);
  }

  Widget _caseChip(UyapNotice n, {bool short = false}) {
    final kase = n.caseKey == null ? null : _cases[n.caseKey];
    if (kase == null) {
      return _chip(
        n.named == null
            ? 'Dosyası bulunamadı'
            : '${n.named!.number} · portföyde yok',
        const Color(0xFF6B7383),
        const Color(0xFFF1F3F7),
      );
    }
    final kind = CaseKind.of(kase);
    return _chip(
      short ? kase.number : '${kase.number} · ${_shortCourt(kase.court)}',
      kind.ink,
      kind.fill,
      bold: true,
    );
  }

  static String _shortCourt(String court) => court
      .replaceAll(RegExp(r'\s+Mahkemesi$'), '')
      .replaceAll(RegExp(r'\s+Dairesi$'), '');

  Widget _chip(String text, Color ink, Color fill, {bool bold = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: ink,
          ),
        ),
      );

  Widget _source(UyapNoticeSource s) => Container(
    margin: const EdgeInsets.only(left: 5),
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      border: Border.all(color: AgendaColors.line),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      s == UyapNoticeSource.mobile ? 'Mobil' : 'Web',
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Color(0xFF5E6677),
      ),
    ),
  );

  Widget _row(BuildContext context, UyapNotice n) {
    final scheme = Theme.of(context).colorScheme;
    final selected = !_narrow && n.key == _selected;
    return InkWell(
      key: ValueKey('notice-${n.key}'),
      onTap: () => unawaited(_choose(n)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 10, 14, 10),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: .08) : null,
          border: Border(
            left: BorderSide(
              color: selected ? scheme.primary : Colors.transparent,
              width: 3,
            ),
            bottom: const BorderSide(color: Color(0xFFF0F2F6)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 14,
              child: n.read
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.title.isEmpty ? 'UYAP bildirimi' : n.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: n.read ? FontWeight.w500 : FontWeight.w700,
                    ),
                  ),
                  if (n.body.isNotEmpty)
                    Text(
                      n.body,
                      maxLines: _narrow ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.8,
                        color: Color(0xFF4B5465),
                      ),
                    ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Flexible(child: _caseChip(n, short: _narrow)),
                      if (!_narrow)
                        for (final s in n.sources) _source(s),
                      const Spacer(),
                      if (n.sentAt != null)
                        Text(
                          clockText(n.sentAt!),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AgendaColors.muted,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, UyapNotice n) {
    final scheme = Theme.of(context).colorScheme;
    final kase = n.caseKey == null ? null : _cases[n.caseKey];
    final at = n.sentAt;
    final both = n.sources.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BİLDİRİM${at == null ? '' : ' · ${dayText(at)} ${clockText(at)}'}'
                ' · ${n.kind.label.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .9,
                  color: AgendaColors.muted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                n.title.isEmpty ? 'UYAP bildirimi' : n.title,
                key: const ValueKey('notice-detail-title'),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final s in n.sources) _source(s),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      both
                          ? 'İki kanaldan da geldi, bir kez gösteriliyor'
                          : n.sources.single == UyapNoticeSource.mobile
                          ? 'UYAP Mobil’den geldi'
                          : 'UYAP web portalından geldi',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AgendaColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? scheme.surfaceContainerLow
                      : const Color(0xFFF7F8FA),
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  n.body.isEmpty
                      ? 'Bildirimin metni UYAP Mobil’den henüz alınmadı; bir '
                            'sonraki yenilemede gelir.'
                      : n.body,
                  style: const TextStyle(fontSize: 13.5, height: 1.6),
                ),
              ),
              const SizedBox(height: 16),
              if (kase != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .05),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: .25),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.folder_open_rounded, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              kase.number,
                              style: const TextStyle(
                                fontFamily: 'Consolas',
                                fontFamilyFallback: [
                                  'Cascadia Mono',
                                  'monospace',
                                ],
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              kase.court,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AgendaColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.onOpenCase != null)
                        FilledButton.icon(
                          key: const ValueKey('notice-open-case'),
                          onPressed: () => _openCase(kase.key),
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 17,
                          ),
                          label: const Text('Dosyaya git'),
                        ),
                    ],
                  ),
                )
              else
                Text(
                  n.named == null
                      ? 'Bildirimin metni bir dosya adı vermiyor; hiçbir dosyaya '
                            'bağlanmadı.'
                      : '${n.named!.court} ${n.named!.number} dosyası portföyde '
                            'yok. Portföy yenilenince bağlanır.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AgendaColors.muted,
                  ),
                ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEA),
                  border: Border.all(color: const Color(0xFFEAD89A)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Bildirim tebligat değildir. ',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text:
                            'UYAP bildirimi bir süre başlatmaz. Tebliğ '
                            'UETS’ten gelince süre orada hesaplanır.',
                      ),
                    ],
                  ),
                  style: TextStyle(fontSize: 12, color: Color(0xFF5C4A12)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('notice-toggle-read'),
                onPressed: () =>
                    unawaited(_sync.markNotices([n], read: !n.read)),
                icon: Icon(
                  n.read
                      ? Icons.mark_email_unread_outlined
                      : Icons.mark_email_read_outlined,
                  size: 17,
                ),
                label: Text(n.read ? 'Okunmadı yap' : 'Okundu say'),
              ),
              Text(
                n.sources.contains(UyapNoticeSource.mobile)
                    ? 'Okundu bilgisi UYAP Mobil’e de gider.'
                    : 'Web portalı okundu bilgisini almıyor; Folio’da tutulur.',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AgendaColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
