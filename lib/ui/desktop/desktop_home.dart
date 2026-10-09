import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../models/evrak_file.dart';
import '../../services/portal/portal_channel.dart';
import '../../services/portal/portal_database.dart';
import '../../services/portal/observed.dart';
import '../../services/portal/portal_hearing.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/portal/uyap_notice.dart';
import '../../services/uets/notice_matcher.dart';
import '../../services/uets/uets_api.dart';
import '../../services/uyap/uyap_case_links.dart';
import '../../services/uyap/uyap_mobile_api.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../agenda/mobile_connect.dart';
import '../agenda/uets_connect.dart';
import '../search/global_search.dart';
import '../search/home_search_box.dart';
import '../widgets/uyap_connect_view.dart';

/// What the desktop's first page shows of the office, gathered by the home
/// page from the portal database.
class DesktopHomeOffice {
  const DesktopHomeOffice({
    this.today = const [],
    this.next,
    this.deadlines = const [],
    this.unread = 0,
    this.newest,
    this.notices = const [],
    this.noticesUnread = 0,
  });

  /// Today's hearings, and the next when there are none.
  final List<PortalHearing> today;
  final PortalHearing? next;

  /// The deadlines still open, soonest first.
  final List<AgendaItem> deadlines;

  /// The UETS notices unread, and the newest of them.
  final int unread;
  final UetsMessage? newest;

  /// UYAP's notifications not yet read: how many, and the newest few with
  /// the case each is tied to (its number and court, when it has one).
  final List<({UyapNotice notice, String? caseLine})> notices;
  final int noticesUnread;
}

/// The desktop's first page (docs/design/masaustu-anasayfa-taslak.png): the
/// greeting and the day's count, the search, the three portals with what
/// they are doing and for how much longer, the document worked on last to
/// go back to, the documents opened lately, today's hearings or the next
/// one, the deadlines coming and UETS.
class DesktopHome extends StatefulWidget {
  const DesktopHome({
    super.key,
    required this.name,
    required this.recent,
    required this.office,
    required this.onSearch,
    required this.onOpen,
    required this.onEdit,
    required this.onSendUyap,
    required this.onArchive,
    required this.onDrafts,
    required this.onAgenda,
    required this.onUets,
    this.onNotices,
    this.search,
    this.onFound,
    this.onShowCases,
    this.uyapFolder,
    this.links,
    this.now,
  });

  /// "Av. Erkan Öz"; empty for none.
  final String name;
  final List<EvrakFile> recent;
  final DesktopHomeOffice office;

  /// The archive searched for these words: Enter with nothing found, or
  /// its group's "tümünü göster".
  final ValueChanged<String> onSearch;

  /// What is found as it is typed, grouped (UYAP's cases, parties and
  /// documents, the archive, the agenda); null for the archive alone.
  final GlobalSearch? search;

  /// Opens the one place of a row found.
  final ValueChanged<Found>? onFound;

  /// UYAP Dosyalarım searched for these words.
  final ValueChanged<String>? onShowCases;
  final ValueChanged<EvrakFile> onOpen, onEdit, onSendUyap;
  final VoidCallback onArchive, onDrafts, onAgenda, onUets;

  /// UYAP Bildirimleri; null where it is not shown.
  final VoidCallback? onNotices;

  /// Where UYAP's documents are saved: "UYAP'tan inen".
  final String? uyapFolder;
  final UyapCaseLinks? links;
  final DateTime Function()? now;

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

enum _Filter { all, petitions, uyap, scans, week }

class _DesktopHomeState extends State<DesktopHome> {
  /// The search field's, for Ctrl K.
  final _searchFocus = FocusNode();
  _Filter _filter = _Filter.all;
  Timer? _tick;

  /// The case each document is written for, as far as it is known.
  final _cases = <String, UyapCaseLink?>{};

  DateTime _now() => (widget.now ?? DateTime.now)();
  UyapCaseLinks get _links => widget.links ?? UyapCaseLinks.instance;

  static const _months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', //
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];
  static const _days = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _loadCases();
  }

  @override
  void didUpdateWidget(DesktopHome old) {
    super.didUpdateWidget(old);
    _loadCases();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _searchFocus.dispose();
    super.dispose();
  }

  void _loadCases() {
    for (final f in widget.recent.take(12)) {
      if (_cases.containsKey(f.path)) continue;
      _cases[f.path] = null;
      unawaited(
        _links.of(f.path).then((link) {
          if (mounted && link != null) setState(() => _cases[f.path] = link);
        }, onError: (Object _) {}),
      );
    }
  }

  String _greeting(DateTime t) => t.hour >= 5 && t.hour < 12
      ? 'Günaydın'
      : t.hour >= 12 && t.hour < 18
      ? 'İyi günler'
      : 'İyi akşamlar';

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  /// "Bugün 08:47", "Dün 16:02", "5 Ekim".
  String _when(DateTime t) {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    if (day == today) return 'Bugün ${_clock(t)}';
    if (day == today.subtract(const Duration(days: 1))) {
      return 'Dün ${_clock(t)}';
    }
    return t.year == now.year
        ? '${t.day} ${_months[t.month - 1]}'
        : '${t.day} ${_months[t.month - 1]} ${t.year}';
  }

  /// "bugün 08:47", "dün 17:20", "3 gün önce".
  String _ago(DateTime t) {
    final now = _now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(t.year, t.month, t.day)).inDays;
    if (days <= 0) return 'bugün ${_clock(t)}';
    if (days == 1) return 'dün ${_clock(t)}';
    if (days < 30) return '$days gün önce';
    return _when(t);
  }

  static DateTime? _modified(EvrakFile f) {
    try {
      return File(f.path).lastModifiedSync();
    } catch (_) {
      return null;
    }
  }

  static String _kind(EvrakFile f) {
    final ext = p.extension(f.path).replaceFirst('.', '').toUpperCase();
    return ext.isEmpty || ext.length > 4 ? f.format.label : ext;
  }

  static (Color, Color) _kindColors(String kind) => switch (kind) {
    'UDF' => (const Color(0xFFFFF1E2), const Color(0xFFC26A00)),
    'PDF' => (AgendaColors.deadlineFill, AgendaColors.deadline),
    'DOCX' || 'DOC' => (AgendaColors.hearingFill, AgendaColors.hearing),
    _ => (const Color(0xFFF1F3F7), const Color(0xFF4B5465)),
  };

  Widget _kindBadge(String kind, {double w = 34, double h = 38}) {
    final (fill, ink) = _kindColors(kind);
    return Container(
      width: w,
      height: h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        kind,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(
          fontSize: w < 30 ? 9 : 10,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _kicker(String text, {String? link, VoidCallback? onLink, Key? key}) =>
      Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: .9,
                color: AgendaColors.muted,
              ),
            ),
          ),
          if (link != null)
            InkWell(
              key: key,
              onTap: onLink,
              child: Text(
                '$link →',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            _searchFocus.requestFocus(),
      },
      child: ColoredBox(
        color: dark ? Theme.of(context).colorScheme.surface : AgendaColors.page,
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 1080;
            // The list takes what the window leaves; in a low one it keeps
            // a height of its own and the column scrolls.
            Widget leftColumn(bool fill) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _continue(context),
                const SizedBox(height: 16),
                if (fill)
                  Expanded(child: _recentCard(context))
                else
                  SizedBox(height: 420, child: _recentCard(context)),
              ],
            );
            final left = leftColumn(false);
            final right = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _todayCard(context),
                const SizedBox(height: 16),
                _deadlinesCard(context),
                const SizedBox(height: 16),
                if (widget.onNotices != null) ...[
                  _noticesCard(context),
                  const SizedBox(height: 16),
                ],
                _uetsCard(context),
              ],
            );
            final top = [
              _head(context),
              const SizedBox(height: 16),
              _portals(context),
              const SizedBox(height: 16),
            ];
            if (!wide) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                children: [...top, left, const SizedBox(height: 16), right],
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...top,
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, column) =>
                                column.maxHeight >= 600
                                ? leftColumn(true)
                                : SingleChildScrollView(child: left),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 380,
                          child: SingleChildScrollView(child: right),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _head(BuildContext context) {
    final now = _now();
    final o = widget.office;
    final today = DateTime(now.year, now.month, now.day);
    final dueToday = o.deadlines
        .where(
          (d) =>
              d.at != null &&
              DateTime(d.at!.year, d.at!.month, d.at!.day) == today,
        )
        .length;
    final summary = [
      '${now.day} ${_months[now.month - 1]} ${now.year} ${_days[now.weekday - 1]}',
      o.today.isEmpty ? 'bugün duruşma yok' : '${o.today.length} duruşma',
      if (dueToday > 0) '$dueToday süre bugün',
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.name.isEmpty
                    ? _greeting(now)
                    : '${_greeting(now)}, ${widget.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                summary,
                style: const TextStyle(fontSize: 13, color: AgendaColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: HomeSearchBox(
              focusNode: _searchFocus,
              search: widget.search,
              onSearch: widget.onSearch,
              onFound: widget.onFound,
              onShowCases: widget.onShowCases,
            ),
          ),
        ),
      ],
    );
  }

  // The portals.

  static String _left(DateTime until) {
    final d = until.difference(DateTime.now());
    if (d.isNegative) return 'süresi doldu';
    if (d.inDays > 0) return '${d.inDays} gün ${d.inHours % 24} sa';
    if (d.inHours > 0) return '${d.inHours} sa ${d.inMinutes % 60} dk';
    return '${d.inMinutes} dk';
  }

  Widget _portals(BuildContext context) {
    final web = UyapWebService.instance;
    final mobile = UyapMobileApi.instance;
    final uets = UetsApi.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        ?PortalSync.started,
        web.session,
        mobile.session,
        uets.session,
      ]),
      builder: (context, _) {
        final sync = PortalSync.started;
        ChannelSync state(PortalChannel c) =>
            sync?.state(c) ?? const ChannelSync();
        String last(PortalChannel c) {
          final at = state(c).finished;
          return at == null ? '' : ' · son senkron ${_clock(at)}';
        }

        final webSession = web.session.value;
        final mobileSession = mobile.session.value;
        final uetsSession = uets.session.value;
        final uetsSoon =
            uetsSession != null &&
            uetsSession.expires.difference(DateTime.now()).inMinutes < 10;
        final mobileState = state(PortalChannel.uyapMobile);
        return Row(
          children: [
            Expanded(
              child: _portal(
                key: const ValueKey('home-portal-web'),
                icon: Icons.account_balance_outlined,
                fill: AgendaColors.hearingFill,
                tint: AgendaColors.hearing,
                title: 'UYAP Web',
                dot: web.connected ? AgendaColors.ok : const Color(0xFF9AA2B1),
                status: web.connected && webSession != null
                    ? 'Bağlı · ${webSession.user} · '
                          '${_left(DateTime.now().add(webSession.remaining()))} kaldı'
                          '${last(PortalChannel.uyapWeb)}'
                    : 'Bağlı değil · Yargıtay ve tam evrak için',
                busy: state(PortalChannel.uyapWeb).running,
                connected: web.connected,
                action: web.connected ? 'Senkronize et' : 'Bağlan',
                onAction: () => web.connected
                    ? unawaited(PortalSync.instance.syncWeb(force: true))
                    : unawaited(
                        connectUyapWeb(
                          context,
                          onConnected: () =>
                              unawaited(PortalSync.instance.syncWeb()),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _portal(
                key: const ValueKey('home-portal-mobile'),
                icon: Icons.gavel_rounded,
                fill: AgendaColors.eHearingFill,
                tint: AgendaColors.eHearing,
                title: 'UYAP Mobil',
                dot: mobile.connected
                    ? AgendaColors.ok
                    : const Color(0xFF9AA2B1),
                status: !mobile.connected
                    ? 'Bağlı değil · portföy ve duruşmalar için'
                    : mobileState.running
                    ? 'Güncelleniyor${mobileState.progress == null ? '…' : ' · ${mobileState.progress}'}'
                    : 'Bağlı · ${_left(mobileSession?.expires ?? DateTime.now())} geçerli'
                          '${last(PortalChannel.uyapMobile)}',
                busy: mobileState.running,
                connected: mobile.connected,
                action: mobile.connected ? 'Senkronize et' : 'Bağlan',
                onAction: () async {
                  PortalSync.begin();
                  if (mobile.connected) {
                    unawaited(PortalSync.instance.syncMobile(full: true));
                  } else if (await connectUyapMobile(context, api: mobile)) {
                    unawaited(PortalSync.instance.syncMobile());
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _portal(
                key: const ValueKey('home-portal-uets'),
                icon: Icons.mark_email_unread_outlined,
                fill: AgendaColors.deadlineFill,
                tint: AgendaColors.deadline,
                title: 'UETS',
                dot: !uets.connected
                    ? const Color(0xFF9AA2B1)
                    : uetsSoon
                    ? AgendaColors.task
                    : AgendaColors.ok,
                status: uets.connected && uetsSession != null
                    ? '${uetsSoon ? 'Oturum ${_left(uetsSession.expires)} sonra kapanacak' : 'Bağlı · ${_left(uetsSession.expires)} kaldı'}'
                          ' · ${widget.office.unread} okunmamış'
                    : 'Bağlı değil · ${widget.office.unread} okunmamış',
                busy: state(PortalChannel.uets).running,
                connected: uets.connected,
                action: uets.connected ? 'Yenile' : 'Bağlan',
                onAction: () {
                  PortalSync.begin();
                  final sync = PortalSync.instance;
                  if (uets.connected) {
                    unawaited(sync.syncUets());
                  } else {
                    unawaited(
                      connectUets(context, api: uets, secrets: sync.secrets),
                    );
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _portal({
    required Key key,
    required IconData icon,
    required Color fill,
    required Color tint,
    required String title,
    required Color dot,
    required String status,
    required bool busy,
    required bool connected,
    required String action,
    required VoidCallback onAction,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: tint, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: dot,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
          const SizedBox(width: 8),
          if (connected)
            OutlinedButton.icon(
              key: ValueKey('$key-action'),
              onPressed: busy ? null : onAction,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: scheme.primary,
                textStyle: const TextStyle(
                  fontFamily: 'LiberationSans',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              icon: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, size: 16),
              label: Text(action),
            )
          else
            FilledButton(
              key: ValueKey('$key-action'),
              onPressed: onAction,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                  fontFamily: 'LiberationSans',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              child: Text(action),
            ),
        ],
      ),
    );
  }

  // The document worked on last.

  List<EvrakFile> get _existing => [
    for (final f in widget.recent)
      if (File(f.path).existsSync()) f,
  ];

  Widget _continue(BuildContext context) {
    final files = _existing;
    if (files.isEmpty) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kicker('KALDIĞINIZ YERDEN DEVAM EDİN'),
            const SizedBox(height: 12),
            const Text(
              'Açtığınız ve düzenlediğiniz belgeler burada görünür.',
              style: TextStyle(fontSize: 13, color: AgendaColors.muted),
            ),
          ],
        ),
      );
    }
    final file = files.first;
    final link = _cases[file.path];
    final modified = _modified(file);
    final kind = _kind(file);
    final stem = p.basenameWithoutExtension(file.path);
    final others = files.skip(1).take(3).toList();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kicker(
            'KALDIĞINIZ YERDEN DEVAM EDİN',
            link: 'Tüm taslaklar',
            onLink: widget.onDrafts,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Paper(kind: kind),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link == null ? stem : '$stem — ${link.number}',
                      key: const ValueKey('home-continue-title'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (link != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AgendaColors.eHearingFill,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          link.court,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AgendaColors.eHearingText,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (modified != null)
                          'Son düzenleme ${_when(modified).toLowerCase()}',
                        file.format.label,
                        p.basename(p.dirname(file.path)),
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.6,
                        color: AgendaColors.muted,
                      ),
                    ),
                    if (link != null) _hearingOf(link),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('home-continue-edit'),
                          onPressed: () => widget.onEdit(file),
                          icon: const Icon(Icons.edit_rounded, size: 16),
                          label: const Text('Devam et'),
                        ),
                        OutlinedButton(
                          key: const ValueKey('home-continue-preview'),
                          onPressed: () => widget.onOpen(file),
                          child: const Text('Önizle'),
                        ),
                        if (file.format == EvrakFormat.udf)
                          OutlinedButton(
                            key: const ValueKey('home-continue-send'),
                            onPressed: () => widget.onSendUyap(file),
                            child: const Text('UYAP’a gönder'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (others.isNotEmpty) ...[
                const SizedBox(width: 16),
                Container(
                  width: 270,
                  padding: const EdgeInsets.only(left: 16),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [for (final f in others) _otherRow(f)],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// "Duruşma: 7 Ekim 09:35 (E-duruşma)", the case's next hearing.
  Widget _hearingOf(UyapCaseLink link) {
    final o = widget.office;
    final key = PortalHearingKeys.caseOf(link.number, link.court);
    final h = [...o.today, ?o.next].where((h) => h.caseKey == key).firstOrNull;
    if (h == null) return const SizedBox.shrink();
    return Text(
      'Duruşma: ${h.at.day} ${_months[h.at.month - 1]} ${_clock(h.at)}'
      '${h.isEHearing ? ' (e-duruşma)' : ''}',
      style: const TextStyle(fontSize: 12.5, color: AgendaColors.muted),
    );
  }

  Widget _otherRow(EvrakFile f) {
    final link = _cases[f.path];
    final modified = _modified(f);
    return InkWell(
      onTap: () => widget.onOpen(f),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            _kindBadge(_kind(f)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.basenameWithoutExtension(f.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    [
                      link?.number ?? p.basename(p.dirname(f.path)),
                      if (modified != null) _ago(modified),
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
          ],
        ),
      ),
    );
  }

  // The documents opened lately.

  bool _shows(EvrakFile f) {
    final kind = _kind(f);
    final name = p.basename(f.path).toLowerCase();
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.petitions:
        return const {'UDF', 'DOCX', 'DOC', 'RTF', 'ODT'}.contains(kind);
      case _Filter.uyap:
        final folder = widget.uyapFolder;
        return folder != null && p.isWithin(folder, f.path);
      case _Filter.scans:
        return name.startsWith('tarama');
      case _Filter.week:
        final m = _modified(f);
        return m != null && _now().difference(m) < const Duration(days: 7);
    }
  }

  Widget _recentCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = [
      for (final f in _existing)
        if (_shows(f)) f,
    ];
    Widget chip(_Filter f, String label) {
      final on = _filter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: on ? const Color(0xFFEAF0F9) : scheme.surface,
          shape: StadiumBorder(
            side: BorderSide(
              color: on ? const Color(0xFFCFDDF1) : scheme.outlineVariant,
            ),
          ),
          child: InkWell(
            key: ValueKey('home-filter-${f.name}'),
            customBorder: const StadiumBorder(),
            onTap: () => setState(() => _filter = f),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                  color: on ? scheme.primary : null,
                ),
              ),
            ),
          ),
        ),
      );
    }

    const heading = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AgendaColors.muted,
    );
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kicker(
            'SON EVRAKLAR',
            link: 'Arşivde ara',
            onLink: widget.onArchive,
            key: const ValueKey('home-archive'),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chip(_Filter.all, 'Tümü'),
                chip(_Filter.petitions, 'Dilekçeler'),
                chip(_Filter.uyap, 'UYAP’tan inen'),
                chip(_Filter.scans, 'Taramalar'),
                chip(_Filter.week, 'Bu hafta'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: const [
                Expanded(flex: 5, child: Text('Evrak', style: heading)),
                Expanded(flex: 2, child: Text('Dosya', style: heading)),
                Expanded(flex: 2, child: Text('Klasör', style: heading)),
                Expanded(flex: 2, child: Text('Değişiklik', style: heading)),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Text(
                      'Bu süzgece uyan evrak yok.',
                      style: TextStyle(color: AgendaColors.muted),
                    ),
                  )
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xFFF0F2F6)),
                    itemBuilder: (context, i) {
                      final f = rows[i];
                      final m = _modified(f);
                      return InkWell(
                        key: ValueKey('home-recent-$i'),
                        onTap: () => widget.onOpen(f),
                        onDoubleTap: () => widget.onEdit(f),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: Row(
                                  children: [
                                    _kindBadge(_kind(f), w: 26, h: 30),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        p.basename(f.path),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _cases[f.path]?.number ?? '—',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  p.basename(p.dirname(f.path)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  m == null ? '' : _when(m),
                                  style: const TextStyle(fontSize: 13),
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
    );
  }

  // Today, the deadlines, UETS.

  Widget _hearingBlock(PortalHearing h) {
    final e = h.isEHearing;
    final until = h.at.difference(_now());
    final relative = until.isNegative
        ? 'geçti'
        : until.inHours < 1
        ? '${until.inMinutes} dk sonra'
        : '${until.inHours} sa sonra';
    final kind = (h.kind?.value ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _clock(h.at),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: e
                      ? AgendaColors.eHearingText
                      : AgendaColors.hearingText,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: e ? AgendaColors.eHearingFill : AgendaColors.hearingFill,
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                    color: e ? AgendaColors.eHearing : AgendaColors.hearing,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e ? 'E-duruşma' : 'Duruşma'} · ${h.court}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: e
                          ? AgendaColors.eHearingText
                          : AgendaColors.hearingText,
                    ),
                  ),
                  Text(
                    [h.number, if (kind.isNotEmpty) kind, relative].join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: e
                          ? AgendaColors.eHearingText
                          : AgendaColors.hearingText,
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

  Widget _todayCard(BuildContext context) {
    final now = _now();
    final o = widget.office;
    final next = o.next;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kicker(
            'BUGÜN · ${now.day} ${_months[now.month - 1].toUpperCase()}',
            link: 'Ajanda',
            onLink: widget.onAgenda,
            key: const ValueKey('home-agenda'),
          ),
          for (final h in o.today) _hearingBlock(h),
          if (o.today.isEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'SIRADAKİ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
                color: AgendaColors.hearing,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              key: const ValueKey('home-next'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AgendaColors.muted,
                    height: 1.4,
                  ),
                  children: next == null
                      ? const [TextSpan(text: 'Bugün ve yakında duruşma yok.')]
                      : [
                          const TextSpan(text: 'Bugün duruşma yok. Sıradaki: '),
                          TextSpan(
                            text:
                                '${next.at.day} ${_months[next.at.month - 1]} '
                                '${_days[next.at.weekday - 1]} ${_clock(next.at)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AgendaColors.hearingText,
                            ),
                          ),
                          TextSpan(text: ' · ${next.court} · ${next.number}'),
                        ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deadlinesCard(BuildContext context) {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final items = widget.office.deadlines.take(4).toList();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kicker('YAKLAŞAN SÜRELER', link: 'Tümü', onLink: widget.onAgenda),
          const SizedBox(height: 4),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Yaklaşan süre yok.',
                style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
              ),
            ),
          for (final (i, d) in items.indexed) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFF0F2F6)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  () {
                    final at = d.at!;
                    final days = DateTime(
                      at.year,
                      at.month,
                      at.day,
                    ).difference(today).inDays;
                    final (fill, ink) = days <= 0
                        ? (AgendaColors.deadlineFill, AgendaColors.deadlineText)
                        : days <= 3
                        ? (AgendaColors.taskFill, AgendaColors.taskText)
                        : (const Color(0xFFF1F3F7), const Color(0xFF4B5465));
                    return Container(
                      width: 58,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${days < 0 ? 0 : days}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: ink,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            days <= 0 ? 'BUGÜN' : 'GÜN',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                        ],
                      ),
                    );
                  }(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          [
                            '${d.at!.day} ${_months[d.at!.month - 1]} '
                                '${_days[d.at!.weekday - 1]}',
                            if (d.body.trim().isNotEmpty) d.body.trim(),
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
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// UYAP's notifications not yet read, the newest three with their case.
  Widget _noticesCard(BuildContext context) {
    final o = widget.office;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kicker(
            o.noticesUnread > 0
                ? 'UYAP BİLDİRİMLERİ · ${o.noticesUnread} OKUNMAMIŞ'
                : 'UYAP BİLDİRİMLERİ',
            link: 'Tümü',
            onLink: widget.onNotices,
            key: const ValueKey('home-notices'),
          ),
          const SizedBox(height: 6),
          if (o.notices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Okunmamış bildirim yok',
                style: TextStyle(fontSize: 13),
              ),
            ),
          for (final (i, (:notice, :caseLine)) in o.notices.indexed)
            InkWell(
              onTap: widget.onNotices,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: i == o.notices.length - 1
                      ? null
                      : const Border(
                          bottom: BorderSide(color: Color(0xFFF0F2F6)),
                        ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.notifications_active_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notice.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            [
                              caseLine ?? 'Dosyası bulunamadı',
                              if (notice.sentAt != null) _ago(notice.sentAt!),
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
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _uetsCard(BuildContext context) {
    final o = widget.office;
    final newest = o.newest;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kicker(
            'UETS',
            link: 'Tebligatlarım',
            onLink: widget.onUets,
            key: const ValueKey('home-uets'),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (o.unread > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AgendaColors.deadline,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '${o.unread}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.unread > 0
                          ? 'okunmamış tebligat'
                          : 'Okunmamış tebligat yok',
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (newest != null)
                      Text(
                        'En yenisi: ${(newest.sender.trim().isEmpty ? newest.subject : newest.sender)}'
                        '${noticeKind(newest).isEmpty ? '' : ' · ${noticeKind(newest)}'}'
                        '${newest.sent == null ? '' : ' · ${_ago(newest.sent!)}'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AgendaColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A sheet of paper, the document's first page as a drawing.
class _Paper extends StatelessWidget {
  const _Paper({required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context) => Container(
    width: 108,
    height: 140,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(6),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Stack(
      children: [
        Positioned(
          left: 12,
          right: 12,
          top: 16,
          child: Column(
            children: [
              for (var i = 0; i < 12; i++)
                Container(
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 6),
                  color: i == 0
                      ? const Color(0xFF9AA3B2)
                      : const Color(0xFFC3CAD6),
                ),
            ],
          ),
        ),
        Positioned(
          right: 6,
          bottom: 6,
          child: Text(
            kind,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Color(0xFF9AA3B2),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The hearing key's case part, for a document's case.
abstract final class PortalHearingKeys {
  static String caseOf(String number, String court) => caseKey(number, court);
}
