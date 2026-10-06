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

  Future<void> _connectWeb() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('UYAP Web’e bağlan'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: UyapConnectView(
            note:
                'UYAP Web her şeyi verir: dosya bilgileri, tam evrak listesi, '
                'Yargıtay ve Cumhuriyet Başsavcılığı dosyaları.',
            onConnected: (_) async {
              if (context.mounted) Navigator.pop(context);
              unawaited(_sync.syncWeb());
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    ),
  );

  Widget _chip({
    required Key key,
    required Color dot,
    required String text,
    String? tooltip,
    VoidCallback? onTap,
    List<(String, VoidCallback)>? menu,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
          if (menu != null) ...[
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
    final web = _sync.web;
    final mobile = _sync.mobile;
    final uets = _sync.uets;

    Widget channel({
      required String name,
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
          text: '$name · bağlan',
          tooltip: '$name bağlı değil',
          onTap: connect,
        );
      }
      final state = _sync.state(channel);
      final time = until == null ? '' : ' · ${left(until)}';
      final (dot, text) = state.running
          ? (AgendaColors.ok, '$name · güncelleniyor…')
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (!widget.phone)
                channel(
                  name: 'UYAP Web',
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
                syncNow: _sync.syncMobile,
                disconnect: () => unawaited(mobile.logout()),
              ),
              channel(
                name: 'UETS',
                channel: PortalChannel.uets,
                connected: uets.connected,
                until: uetsSession?.expires,
                who: null,
                validity: 'UETS oturumu şu saate kadar açık:',
                connect: () => unawaited(
                  connectUets(context, api: uets, secrets: _sync.secrets),
                ),
                syncNow: _sync.syncUets,
                disconnect: () {
                  uets.logout();
                  _changed();
                },
              ),
            ],
          ),
        ),
        if (widget.showSyncAll && !widget.phone)
          TextButton.icon(
            key: const ValueKey('agenda-sync'),
            onPressed: any
                ? () {
                    if (web.connected) unawaited(_sync.syncWeb());
                    if (mobile.connected) unawaited(_sync.syncMobile());
                    if (uets.connected) unawaited(_sync.syncUets());
                  }
                : null,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(
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
