import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/portal/portal_case.dart';
import '../../services/portal/portal_channel.dart';
import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_hearing.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/uyap/uyap_case_links.dart';
import '../../services/uyap/uyap_case_panel_controller.dart';
import '../../services/uyap/uyap_mobile_api.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../agenda/mobile_connect.dart';
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
  });

  /// The portal's key of the case.
  final String caseKey;
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

  @override
  State<CaseDetailPage> createState() => _CaseDetailPageState();
}

enum _Tab { documents, hearings, deadlines, parties, facts, petitions }

enum _DocFilter { all, fresh, decisions, petitions, notDownloaded }

class _CaseDetailPageState extends State<CaseDetailPage> {
  late final UyapCasePanelController _c =
      widget.controller ?? UyapCasePanelController();
  PortalCase? _kase;
  CaseState _state = const CaseState();
  List<PortalHearing> _hearings = const [];
  List<AgendaItem> _items = const [];
  List<KeptNotice> _notices = const [];
  List<String> _petitions = const [];
  bool _loaded = false;

  /// The documents new when the page opened, kept marked while it is open
  /// though they are no longer new once seen.
  final _fresh = <String>{};
  final _cleared = <String>{};
  _Tab _tab = _Tab.documents;
  _DocFilter _filter = _DocFilter.all;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _c.onSaved = widget.onSaved;
    _c.addListener(_changed);
    unawaited(_load());
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    if (widget.controller == null) _c.dispose();
    _search.dispose();
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
      _petitions = petitions;
      _loaded = true;
    });
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
                sliver: SliverToBoxAdapter(child: _tabsCard(context, wide)),
              ),
            ],
          );
        },
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

  Widget _header(BuildContext context, PortalCase kase, bool wide) {
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
                fontSize: wide ? 26 : 21,
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
        Text(
          [
            if (type.trim().isNotEmpty) type.trim(),
            if (opened != null) 'açılış ${dayText(opened)}',
            record == null
                ? 'yalnız künye — evraklar UYAP’tan ilk tazelemede gelir'
                : 'son senkron ${whenText(record.fetchedAt, now)}',
          ].join(' · '),
          style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
        ),
      ],
    );
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  tooltip: 'UYAP Dosyalarım’a dön',
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 6),
                Expanded(child: info),
                const SizedBox(width: 12),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
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

  List<UyapCaseDocument> get _documents {
    final out = <UyapCaseDocument>[];
    for (final d in _c.record?.documents ?? const <UyapCaseDocument>[]) {
      out.add(d);
    }
    out.sort(
      (a, b) => (b.date ?? DateTime(1900)).compareTo(a.date ?? DateTime(1900)),
    );
    return out;
  }

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
    Widget box(
      String title,
      String value,
      String sub, {
      Color? valueColor,
      bool warn = false,
    }) => _card(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
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
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
              color: AgendaColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
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
        : GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.1,
            children: boxes,
          );
  }

  Widget _tabsCard(BuildContext context, bool wide) {
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
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  tab(
                    _Tab.documents,
                    'Evraklar',
                    docCount,
                    fresh: _fresh.length,
                  ),
                  tab(_Tab.hearings, 'Duruşmalar', _hearings.length),
                  tab(_Tab.deadlines, 'Süreler & Tebligat', deadlines),
                  tab(_Tab.parties, 'Taraflar', parties),
                  tab(_Tab.facts, 'Künye', null),
                  tab(_Tab.petitions, 'Dilekçelerim', _petitions.length),
                ],
              ),
            ),
          ),
          switch (_tab) {
            _Tab.documents => _documentsTab(context, wide),
            _Tab.hearings => _hearingsTab(context),
            _Tab.deadlines => _deadlinesTab(context),
            _Tab.parties => _partiesTab(context),
            _Tab.facts => _factsTab(context),
            _Tab.petitions => _petitionsTab(context),
          },
        ],
      ),
    );
  }

  // Documents.

  bool _isDecision(UyapCaseDocument d) =>
      UyapWebService.fold('${d.type} ${d.description}').contains('karar');
  bool _isPetition(UyapCaseDocument d) =>
      UyapWebService.fold('${d.type} ${d.description}').contains('dilekce');

  bool _downloaded(UyapCaseDocument d) {
    final record = _c.record;
    return record != null && _c.store.fileOf(record, d.key) != null;
  }

  bool _shows(UyapCaseDocument d) {
    final q = UyapWebService.fold(_search.text.trim());
    if (q.isNotEmpty &&
        !UyapWebService.fold('${d.title} ${d.sender} ${d.approved}')
            .contains(q)) {
      return false;
    }
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

  Widget _documentsTab(BuildContext context, bool wide) {
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
    final rows = <Widget>[];
    String? bucket;
    for (final d in docs) {
      final children = [
        for (final a in d.attachments)
          if (_shows(a)) a,
      ];
      if (!_shows(d) && children.isEmpty) continue;
      final b = _bucket(d.date);
      if (b != bucket) {
        bucket = b;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
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
        );
      }
      rows.add(_docRow(context, d));
      for (final (i, a) in children.indexed) {
        rows.add(_docRow(context, a, attachment: i + 1));
      }
    }
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
        if (rows.isEmpty)
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

  Widget _docRow(BuildContext context, UyapCaseDocument d, {int? attachment}) {
    final scheme = Theme.of(context).colorScheme;
    final fresh = _fresh.contains(d.key);
    final downloaded = _downloaded(d);
    final folded = UyapWebService.fold('${d.type} ${d.description}');
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
    return InkWell(
      key: ValueKey('case-doc-${d.key}'),
      onTap: () => unawaited(_open(d)),
      child: Container(
        color: fresh ? const Color(0xFFF6F9FE) : null,
        padding: EdgeInsets.fromLTRB(attachment == null ? 18 : 58, 8, 18, 8),
        decoration: null,
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
        ),
      ),
    );
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
