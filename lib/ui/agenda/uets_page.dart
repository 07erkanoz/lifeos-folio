import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/portal/portal_case.dart';
import '../../services/portal/portal_channel.dart';
import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/uets/notice_matcher.dart';
import '../../services/uets/uets_api.dart';
import '../../services/uyap/uyap_case_store.dart';
import 'agenda_page.dart' show AgendaColors;
import 'uets_connect.dart';

enum _Filter { all, unread, untied }

/// UETS Tebligatlarım (UYGULAMAPLANI §10, T10): the notifications kept on
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
  });

  @override
  State<UetsPage> createState() => _UetsPageState();
}

class _UetsPageState extends State<UetsPage> {
  PortalDatabase? _db;
  List<KeptNotice> _notices = const [];
  Map<String, PortalCase> _cases = const {};
  List<AgendaItem> _deadlines = const [];
  _Filter _filter = _Filter.all;
  String? _selected;
  final Map<String, List<UetsPart>> _parts = {};
  String? _partsLoading;
  String? _downloading;
  String? _partsProblem;
  Timer? _clock;

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
    _sync.removeListener(_syncChanged);
    super.dispose();
  }

  void _syncChanged() {
    if (!mounted) return;
    _reload();
    widget.onChanged?.call();
  }

  Future<void> _open() async {
    final db = widget.database ?? await PortalDatabase.shared();
    if (!mounted) return;
    _db = db;
    _reload();
    if (_api.connected) await _sync.syncUets();
  }

  void _reload() {
    final db = _db;
    if (db == null) return;
    setState(() {
      _notices = db.notices();
      _cases = db.cases();
      _deadlines = [
        for (final i in db.agenda())
          if (i.id.startsWith('uets:')) i,
      ];
      if (_selected == null ||
          !_notices.any((n) => n.message.id == _selected)) {
        _selected = _notices.firstOrNull?.message.id;
      }
    });
  }

  List<KeptNotice> get _shown => [
    for (final n in _notices)
      if (switch (_filter) {
        _Filter.all => true,
        _Filter.unread => n.message.read == null,
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

  // Building.

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: dark ? Theme.of(context).colorScheme.surface : AgendaColors.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(context),
          _channel(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: LayoutBuilder(
                builder: (context, box) {
                  final main = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _stats(context),
                      const SizedBox(height: 12),
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
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }

  Widget _kicker(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: .8,
      color: AgendaColors.muted,
    ),
  );

  Widget _topBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = _api.connected;
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
            'UETS Tebligatlarım',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          const Flexible(
            child: Text(
              '/ Elektronik tebligatlar ve dosyalarınızla eşleşmeleri',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
          ),
          const Spacer(),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                for (final (filter, label) in const [
                  (_Filter.all, 'Tümü'),
                  (_Filter.unread, 'Okunmamış'),
                  (_Filter.untied, 'Eşleşmeyen'),
                ])
                  InkWell(
                    key: ValueKey('uets-filter-${filter.name}'),
                    onTap: () => setState(() => _filter = filter),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _filter == filter
                            ? scheme.primary.withValues(alpha: .09)
                            : null,
                        border: Border(
                          right: filter == _Filter.untied
                              ? BorderSide.none
                              : BorderSide(color: scheme.outlineVariant),
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _filter == filter
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: _filter == filter ? scheme.primary : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          FilledButton.icon(
            key: const ValueKey('uets-sync'),
            onPressed: _sync.state(PortalChannel.uets).running
                ? null
                : connected
                ? _sync.syncUets
                : () => connectUets(context, api: _api, secrets: _sync.secrets),
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
            icon: Icon(connected ? Icons.sync_rounded : Icons.link, size: 16),
            label: Text(connected ? 'Senkronize et' : 'UETS’ye bağlan'),
          ),
        ],
      ),
    );
  }

  Widget _channel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = _sync.state(PortalChannel.uets);
    final session = _api.session.value;
    final (Color dot, String text) = !_api.connected
        ? (
            scheme.outline,
            _notices.isEmpty
                ? 'UETS · bağlı değil'
                : 'UETS · bağlı değil — kayıtlı tebligatlar gösteriliyor',
          )
        : state.running
        ? (AgendaColors.ok, 'UETS · tebligatlar alınıyor…')
        : state.problem != null
        ? (
            AgendaColors.task,
            'UETS · ${state.problem!.replaceFirst('Bad state: ', '')}',
          )
        : (
            AgendaColors.ok,
            'UETS · bağlı${session == null ? '' : ', ${_left(session.expires)}'}'
                '${state.finished == null ? '' : ' · son alım ${_date(state.finished, time: true)}'}',
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Align(
        alignment: Alignment.centerLeft,
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
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (_api.connected) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    _api.logout();
                    setState(() {});
                  },
                  child: const Text(
                    'Çıkış',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AgendaColors.hearing,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _left(DateTime until) {
    final left = until.difference(DateTime.now());
    if (left.isNegative) return 'süresi doldu';
    return '${left.inMinutes} dk';
  }

  Widget _stats(BuildContext context) {
    final today = _day(_now());
    final unread = _notices.where((n) => n.message.read == null).length;
    final week = _notices.where((n) {
      final s = n.message.sent;
      return s != null && !s.isBefore(today.subtract(const Duration(days: 6)));
    }).length;
    final untied = _notices.where((n) => n.caseKey == null).length;
    final soon = _deadlines.where((d) {
      final at = d.at;
      return !d.done &&
          at != null &&
          !at.isBefore(today) &&
          at.isBefore(today.add(const Duration(days: 8)));
    }).length;
    Widget stat(IconData icon, Color fill, Color tint, int value, String l) =>
        Expanded(
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
          Icons.mark_email_unread_outlined,
          AgendaColors.deadlineFill,
          AgendaColors.deadline,
          unread,
          'Okunmamış',
        ),
        const SizedBox(width: 12),
        stat(
          Icons.inbox_outlined,
          AgendaColors.hearingFill,
          AgendaColors.hearing,
          week,
          'Son 7 günde gelen',
        ),
        const SizedBox(width: 12),
        stat(
          Icons.link_off,
          AgendaColors.taskFill,
          AgendaColors.task,
          untied,
          'Dosyayla eşleşmeyen',
        ),
        const SizedBox(width: 12),
        stat(
          Icons.timer_outlined,
          AgendaColors.eHearingFill,
          AgendaColors.eHearing,
          soon,
          'Bu hafta dolan süre',
        ),
      ],
    );
  }

  Widget _list(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = _shown;
    if (shown.isEmpty) {
      return _card(
        context,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
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
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AgendaColors.muted,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return _card(
      context,
      padding: EdgeInsets.zero,
      child: ListView.separated(
        itemCount: shown.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: scheme.outlineVariant),
        itemBuilder: (context, i) => _row(context, shown[i]),
      ),
    );
  }

  Widget _row(BuildContext context, KeptNotice n) {
    final scheme = Theme.of(context).colorScheme;
    final m = n.message;
    final parsed = NoticeSubject.parse(m.subject);
    final kind = noticeKind(m);
    final unread = m.read == null;
    final selected = m.id == _selected;
    final kase = n.caseKey == null ? null : _cases[n.caseKey];
    return InkWell(
      key: ValueKey('uets-row-${m.id}'),
      onTap: () => setState(() {
        _selected = m.id;
        _partsProblem = null;
      }),
      child: Container(
        color: selected ? scheme.primary.withValues(alpha: .06) : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: unread ? AgendaColors.deadline : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parsed == null
                        ? m.subject
                        : '${parsed.unit} · ${parsed.number}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (kind.isNotEmpty) kind,
                      if (m.sender.isNotEmpty && parsed == null) m.sender,
                    ].join(' · ').ifEmpty('Tebligat'),
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
            const SizedBox(width: 10),
            _tag(
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
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 92,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_date(m.sent), style: const TextStyle(fontSize: 12)),
                  Text(
                    'tebliğ ${_date(m.served)}',
                    style: const TextStyle(
                      fontSize: 10.5,
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
            const Text(
              'Ayrıntısını görmek için bir tebligat seçin.',
              style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
            ),
          ],
        ),
      );
    }
    final m = n.message;
    final parsed = NoticeSubject.parse(m.subject);
    final kind = noticeKind(m);
    final kase = n.caseKey == null ? null : _cases[n.caseKey];
    final deadlines = [
      for (final d in _deadlines)
        if (d.id.startsWith('uets:${m.id}:')) d,
    ]..sort((a, b) => a.at!.compareTo(b.at!));
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
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
                  style: const TextStyle(
                    fontSize: 13,
                    color: AgendaColors.hearingText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 12),
              row('Gönderim', _date(m.sent, time: true)),
              row('Tebliğ sayılır', '${_date(m.served)} (5. günün sonu)'),
              if (m.read != null) row('Okundu', _date(m.read, time: true)),
              if (m.sender.isNotEmpty) row('Gönderen', m.sender),
              if (m.barcode.isNotEmpty) row('Barkod', m.barcode),
              if (parsed != null) row('Konu', m.subject),
            ],
          ),
        ),
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
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AgendaColors.muted,
                  ),
                ),
              ] else
                Text(
                  n.link == 'manual'
                      ? 'Bu tebligat bir dosyaya bağlanmasın diye işaretlendi.'
                      : 'Portföyünüzde tek bir karşılığı bulunamadı; '
                            'dosyayı siz seçebilirsiniz.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AgendaColors.muted,
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (kase != null && widget.onOpenCase != null) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        style: _buttonStyle(),
                        onPressed: () {
                          if (!widget.onOpenCase!(kase.key)) {
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Bu dosya henüz UYAP Dosyalarım’da yok; '
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
              if (deadlines.isEmpty)
                const Text(
                  'Belge türü konudan kesin anlaşılmadı; süreyi ajandada '
                  '“Not / iş ekle → Süre” ile hesaplayabilirsiniz.',
                  style: TextStyle(fontSize: 12, color: AgendaColors.muted),
                )
              else
                for (final d in deadlines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 3,
                          height: 30,
                          color: AgendaColors.deadline,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.title,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  decoration: d.done
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              Text(
                                'Son gün ${_date(d.at)}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AgendaColors.deadlineText,
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
      TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );

  Widget _attachments(BuildContext context, KeptNotice n) {
    final m = n.message;
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
            const Text(
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
              const Text(
                'Bu tebligatta ek yok.',
                style: TextStyle(fontSize: 12, color: AgendaColors.muted),
              ),
            for (final part in parts)
              InkWell(
                onTap: busy ? null : () => _download(n, part),
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
                        const Icon(
                          Icons.download_outlined,
                          size: 16,
                          color: AgendaColors.muted,
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
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
          const Text(
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
      if (m.read == null) {
        _db?.mergeNotices([
          UetsMessage(
            id: m.id,
            subject: m.subject,
            sender: m.sender,
            sent: m.sent,
            read: DateTime.now(),
            barcode: m.barcode,
            status: m.status,
          ),
        ]);
        _reload();
        widget.onChanged?.call();
      }
      if (part != null && widget.onOpenFile != null) {
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
    addNoticeDeadlines(db);
    _reload();
    widget.onChanged?.call();
  }
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
        height: 420,
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
