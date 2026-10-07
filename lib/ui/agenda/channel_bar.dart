import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/portal/portal_channel.dart';
import '../../services/portal/portal_sync.dart';
import '../widgets/uyap_connect_view.dart';
import 'agenda_page.dart' show AgendaColors;
import 'mobile_connect.dart';
import 'uets_connect.dart';

/// The three portals as one row, the same on every page that uses them
/// (Ajanda, UYAP Dosyalarım, UETS Tebligatlarım): whether each is
/// connected, for how much longer, and what it is doing; a tap connects,
/// syncs or ends it.
class PortalChannelBar extends StatefulWidget {
  const PortalChannelBar({
    super.key,
    this.sync,
    this.showSyncAll = true,
    this.phone = false,
  });

  final PortalSync? sync;

  /// The phone's first page: no web portal (a phone has no card), no names,
  /// no "Senkronize et" of its own.
  final bool phone;

  /// "Senkronize et" for every connected portal at the end of the row.
  final bool showSyncAll;

  @override
  State<PortalChannelBar> createState() => _PortalChannelBarState();
}

class _PortalChannelBarState extends State<PortalChannelBar> {
  PortalSync get _sync => widget.sync ?? PortalSync.instance;
  Timer? _tick;
  late final List<Listenable> _heard = [
    _sync,
    _sync.web.session,
    _sync.mobile.session,
    _sync.uets.session,
  ];

  @override
  void initState() {
    super.initState();
    for (final l in _heard) {
      l.addListener(_changed);
    }
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _changed());
  }

  @override
  void dispose() {
    _tick?.cancel();
    for (final l in _heard) {
      l.removeListener(_changed);
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// "6 gün 23 sa", "1 sa 20 dk", "24 dk".
  static String left(DateTime until) {
    final d = until.difference(DateTime.now());
    if (d.isNegative) return 'süresi doldu';
    if (d.inDays > 0) return '${d.inDays} gün ${d.inHours % 24} sa';
    if (d.inHours > 0) return '${d.inHours} sa ${d.inMinutes % 60} dk';
    return '${d.inMinutes} dk';
  }

  static String _date(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _connectWeb() =>
      connectUyapWeb(context, onConnected: () => unawaited(_sync.syncWeb()));

  /// "6 g", "3 sa", "24 dk": a phone's chip's time left.
  static String shortLeft(DateTime until) {
    final d = until.difference(DateTime.now());
    if (d.isNegative) return 'doldu';
    if (d.inDays > 0) return '${d.inDays} g';
    if (d.inHours > 0) return '${d.inHours} sa';
    return '${d.inMinutes} dk';
  }

  Widget _chip({
    required Key key,
    required Color dot,
    required String text,
    String? tooltip,
    VoidCallback? onTap,
    List<(String, VoidCallback)>? menu,
    bool compact = false,
    bool busy = false,
    IconData? tail,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final body = Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: AgendaColors.ok,
              ),
            )
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          SizedBox(width: compact ? 5 : 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11 : 11.5,
                fontWeight: compact ? FontWeight.w600 : FontWeight.w400,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (tail != null) ...[
            const SizedBox(width: 3),
            Icon(tail, size: 13, color: scheme.onSurfaceVariant),
          ] else if (menu != null && !compact) ...[
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 14, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
    );
    final Widget chip = menu != null
        ? PopupMenuButton<int>(
            key: key,
            tooltip: tooltip ?? '',
            onSelected: (i) => menu[i].$2(),
            itemBuilder: (_) => [
              for (var i = 0; i < menu.length; i++)
                PopupMenuItem(value: i, height: 36, child: Text(menu[i].$1)),
            ],
            child: body,
          )
        : Tooltip(
            message: tooltip ?? '',
            child: InkWell(
              key: key,
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: body,
            ),
          );
    return chip;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // On a phone the chips are small and in one row: "● Mobil 6 g".
    final compact = widget.phone || MediaQuery.sizeOf(context).width < 700;
    final web = _sync.web;
    final mobile = _sync.mobile;
    final uets = _sync.uets;

    Widget channel({
      required String name,
      required String short,
      required PortalChannel channel,
      required bool connected,
      required DateTime? until,
      required String? who,
      required String validity,
      required VoidCallback connect,
      required Future<void> Function() syncNow,
      required VoidCallback disconnect,
      List<(String, VoidCallback)> more = const [],
    }) {
      final key = ValueKey('channel-${channel.name}');
      if (!connected) {
        return _chip(
          key: key,
          dot: scheme.outline,
          text: compact ? short : '$name · bağlan',
          tooltip: '$name bağlı değil · bağlanmak için dokunun',
          onTap: connect,
          compact: compact,
          tail: compact ? Icons.add_rounded : null,
        );
      }
      final state = _sync.state(channel);
      if (compact) {
        final problem = state.problem != null;
        return _chip(
          key: key,
          dot:
              problem ||
                  (until != null &&
                      until.difference(DateTime.now()).inMinutes < 10)
              ? AgendaColors.task
              : AgendaColors.ok,
          busy: state.running,
          text: state.running
              ? (state.progress == null ? short : '$short · ${state.progress}')
              : problem || until == null
              ? short
              : '$short ${shortLeft(until)}',
          tail: problem ? Icons.error_outline_rounded : null,
          compact: true,
          tooltip: [
            if (problem) state.problem!.replaceFirst('Bad state: ', ''),
            if (until != null) '$validity ${_date(until)}',
            if (state.finished != null) 'Son senkron ${_date(state.finished!)}',
          ].join('\n'),
          menu: [
            ('Senkronize et', () => unawaited(syncNow())),
            ...more,
            ('Bağlantıyı kes', disconnect),
          ],
        );
      }
      final time = until == null ? '' : ' · ${left(until)}';
      final (dot, text) = state.running
          ? (
              AgendaColors.ok,
              state.progress == null
                  ? '$name · güncelleniyor…'
                  : '$name · ${state.progress}…',
            )
          : state.problem != null
          ? (
              AgendaColors.task,
              '$name · ${state.problem!.replaceFirst('Bad state: ', '')}',
            )
          : (
              until != null && until.difference(DateTime.now()).inMinutes < 10
                  ? AgendaColors.task
                  : AgendaColors.ok,
              '$name${who == null || who.isEmpty ? ' · bağlı' : ' · $who'}$time',
            );
      return _chip(
        key: key,
        dot: dot,
        text: text,
        tooltip: [
          if (until != null) '$validity ${_date(until)}',
          if (state.finished != null) 'Son senkron ${_date(state.finished!)}',
        ].join('\n'),
        menu: [
          ('Senkronize et', () => unawaited(syncNow())),
          ...more,
          ('Bağlantıyı kes', disconnect),
        ],
      );
    }

    final webSession = web.session.value;
    final mobileSession = mobile.session.value;
    final uetsSession = uets.session.value;
    final any = web.connected || mobile.connected || uets.connected;
    final chips = [
      // On a phone the web portal is entered with the mobile signature,
      // through e-Devlet in the phone's own web view.
      channel(
        name: 'UYAP Web',
        short: 'Web',
        channel: PortalChannel.uyapWeb,
        connected: web.connected,
        until: webSession == null
            ? null
            : DateTime.now().add(webSession.remaining()),
        who: webSession?.user,
        validity: 'Oturum şu saate kadar açık:',
        connect: () => unawaited(_connectWeb()),
        syncNow: _sync.syncWeb,
        disconnect: () {
          web.disconnect();
          _changed();
        },
        more: [
          (
            'Oturumu denetle',
            () => unawaited(web.check().then((_) => _changed())),
          ),
        ],
      ),
      channel(
        name: 'UYAP Mobil',
        short: 'Mobil',
        channel: PortalChannel.uyapMobile,
        connected: mobile.connected,
        until: mobileSession?.expires,
        who: widget.phone ? null : mobileSession?.user,
        validity:
            'Erişim kendiliğinden yenilenir; oturum yeniden giriş '
            'gerekmeden şu tarihe kadar geçerli:',
        connect: () async {
          if (await connectUyapMobile(context, api: mobile)) {
            unawaited(_sync.syncMobile());
          }
        },
        syncNow: () => _sync.syncMobile(full: true),
        disconnect: () => unawaited(mobile.logout()),
      ),
      channel(
        name: 'UETS',
        short: 'UETS',
        channel: PortalChannel.uets,
        connected: uets.connected,
        until: uetsSession?.expires,
        who: null,
        validity: 'UETS oturumu şu saate kadar açık:',
        connect: () =>
            unawaited(connectUets(context, api: uets, secrets: _sync.secrets)),
        syncNow: _sync.syncUets,
        disconnect: () {
          uets.logout();
          _changed();
        },
      ),
    ];
    void syncAll() {
      if (web.connected) unawaited(_sync.syncWeb());
      if (mobile.connected) unawaited(_sync.syncMobile(full: true));
      if (uets.connected) unawaited(_sync.syncUets());
    }

    if (compact) {
      return Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (i, c) in chips.indexed) ...[
                    if (i > 0) const SizedBox(width: 6),
                    c,
                  ],
                ],
              ),
            ),
          ),
          if (widget.showSyncAll && !widget.phone)
            IconButton(
              key: const ValueKey('agenda-sync'),
              tooltip: 'Senkronize et',
              visualDensity: VisualDensity.compact,
              onPressed: any ? syncAll : null,
              icon: const Icon(Icons.sync_rounded, size: 19),
            ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Wrap(spacing: 8, runSpacing: 6, children: chips)),
        if (widget.showSyncAll && !widget.phone)
          TextButton.icon(
            key: const ValueKey('agenda-sync'),
            onPressed: any ? syncAll : null,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontFamily: 'LiberationSans', 
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: const Icon(Icons.sync_rounded, size: 16),
            label: const Text('Senkronize et'),
          ),
      ],
    );
  }
}
