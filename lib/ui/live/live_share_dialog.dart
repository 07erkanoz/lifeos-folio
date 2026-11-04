import 'dart:async';

import 'package:flutter/material.dart';

import '../help/help_button.dart';
import '../../services/live/live_share.dart';
import '../../services/office/office_network.dart';
import '../../services/office/office_peer.dart';
import '../../services/platform/app_language.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import 'live_remote_dialogs.dart';

/// Who a document is shared with live, in one list: the person's own
/// devices, the office's members, and Folios nearby that may be invited.
/// Each is invited with a tap; their Folio asks them, and the document
/// opens there once they join. Uzaktan: another office, anywhere, by an
/// invitation's code (live_remote.dart).
class LiveShareDialog extends StatefulWidget {
  const LiveShareDialog({
    super.key,
    required this.host,
    this.network,
    this.remote = false,
    this.sheet = false,
  });

  final LiveShareHost host;
  final OfficeNetwork? network;

  /// Opened on its Uzaktan side, a code made (Canlı belge, 26 Ekim 2026).
  final bool remote;

  /// Laid out as a sheet from below, on a phone.
  final bool sheet;

  /// Shown for [host]: a sheet from below on a phone, a dialog elsewhere.
  static Future<void> show(
    BuildContext context,
    LiveShareHost host, {
    bool remote = false,
  }) {
    if (MediaQuery.sizeOf(context).width < 700) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheet).bottom,
          ),
          child: LiveShareDialog(host: host, remote: remote, sheet: true),
        ),
      );
    }
    return showDialog<void>(
      context: context,
      builder: (_) => LiveShareDialog(host: host, remote: remote),
    );
  }

  @override
  State<LiveShareDialog> createState() => _LiveShareDialogState();
}

/// One who may be shown it, as its row lists it.
class _Target {
  const _Target({
    required this.id,
    required this.name,
    this.device = '',
    this.platform,
    this.office = false,
    this.known = false,
    this.guest,
    this.remote = false,
  });

  final String id, name, device;

  /// Came from another office by a code: not invited again from a row.
  final bool remote;
  final OfficePlatform? platform;
  final bool office;

  /// Known by a code alone: neither the person's own nor the office's.
  final bool known;

  /// A Folio nearby, invited as a guest.
  final OfficePeer? guest;
}

class _LiveShareDialogState extends State<LiveShareDialog> {
  OfficeNetwork get _net => widget.network ?? OfficeNetwork.instance;
  LiveShareHost get _host => widget.host;

  /// Showing the invitation by a code rather than the network's list:
  /// where it was left, a code made before.
  late bool _remote =
      widget.remote ||
      widget.host.remoteInvite.value != null ||
      widget.host.peers.value.any((p) => widget.host.isRemote(p.deviceId));

  /// Whether the network is looked around for nearby Folios: while the
  /// list is open on its Bu ağda side, not for another office's code.
  bool _looking = false;

  void _look(bool look) {
    if (look == _looking) return;
    _looking = look;
    unawaited(_net.lookForLive(look));
  }

  @override
  void initState() {
    super.initState();
    if (!_remote) _look(true);
  }

  @override
  void dispose() {
    _look(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l.liveShareTitle),
              Text(
                _host.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AgendaColors.muted,
                ),
              ),
            ],
          ),
        ),
        const HelpButton(Help.live),
      ],
    );
    final body = ListenableBuilder(
      listenable: Listenable.merge([_net, _host.peers, _host.pen]),
      builder: (context, _) {
        final sections = _sections();
        final any = sections.any((s) => s.$2.isNotEmpty);
        final remote = [
          for (final p in _host.peers.value)
            if (_host.isRemote(p.deviceId))
              _Target(id: p.deviceId, name: p.name, remote: true),
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              key: const ValueKey('live-where'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(context.l.liveOnThisNetwork),
                  icon: const Icon(Icons.wifi_rounded, size: 18),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(context.l.liveRemote),
                  icon: const Icon(Icons.public_rounded, size: 18),
                ),
              ],
              selected: {_remote},
              onSelectionChanged: (v) {
                setState(() => _remote = v.first);
                if (!_remote) _look(true);
              },
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _remote
                      ? [
                          RemoteInvitePane(host: _host),
                          if (remote.isNotEmpty) ...[
                            _heading(context.l.liveRemoteJoined),
                            for (final t in remote) _row(t),
                          ],
                        ]
                      : [
                          if (!any) _empty(),
                          for (final (name, rows) in sections)
                            if (rows.isNotEmpty) ...[
                              _heading(name),
                              for (final t in rows) _row(t),
                            ],
                        ],
                ),
              ),
            ),
            if (_host.pen.value != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('live-take-back'),
                  onPressed: _host.takeBack,
                  icon: const Icon(Icons.edit_off_outlined, size: 16),
                  label: Text(
                    context.l.liveTakeBackPen(_host.nameOf(_host.pen.value!)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _remote ? context.l.liveRemoteHint : context.l.liveNearbyHint,
                style: TextStyle(fontSize: 12, color: AgendaColors.muted),
              ),
            ),
          ],
        );
      },
    );
    final actions = <Widget>[
      if (_host.sharing)
        TextButton(
          key: const ValueKey('live-stop'),
          onPressed: () async {
            await _host.close();
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(context.l.liveStopSharing),
        ),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l.liveOk),
      ),
    ];
    if (widget.sheet) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              child: title,
            ),
            const SizedBox(height: 10),
            Flexible(child: body),
            const SizedBox(height: 8),
            Wrap(alignment: WrapAlignment.end, spacing: 8, children: actions),
          ],
        ),
      );
    }
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
      title: title,
      content: SizedBox(width: 480, child: body),
      actions: actions,
    );
  }

  Widget _heading(String name) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
    child: Text(
      name,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: .6,
        color: AgendaColors.muted,
      ),
    ),
  );

  Widget _empty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: _net.joined
        ? Column(
            children: [
              Icon(
                Icons.wifi_find_rounded,
                size: 32,
                color: AgendaColors.muted,
              ),
              const SizedBox(height: 8),
              Text(
                context.l.liveNoDevices,
                textAlign: TextAlign.center,
                style: TextStyle(color: AgendaColors.muted),
              ),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(
                _net.error == null
                    ? context.l.liveSearching
                    : context.l.liveNetworkError('${_net.error}'),
                style: TextStyle(color: AgendaColors.muted),
              ),
            ],
          ),
  );

  /// Who may be shown it, under each heading: the online ones, and any
  /// invited before, whatever came of it.
  List<(String, List<_Target>)> _sections() {
    final self = _net.self;
    final peers = {for (final p in _host.peers.value) p.deviceId: p};
    if (self == null) {
      return [
        (
          context.l.liveInvited,
          [
            for (final p in peers.values)
              if (!_host.isRemote(p.deviceId))
                _Target(id: p.deviceId, name: p.name),
          ],
        ),
      ];
    }
    final me = self.userId;
    final ledger = _net.ledger;
    bool isMember(String id) =>
        ledger.members.any((m) => m.deviceId == id && m.userId != me);

    final own = <_Target>[];
    final seen = <String>{};
    for (final d in _net.ownOnline) {
      if (seen.add(d.deviceId)) {
        own.add(
          _Target(
            id: d.deviceId,
            name: _ownName(d.deviceId, peers[d.deviceId]),
            platform: d.platform,
          ),
        );
      }
    }
    for (final p in peers.values) {
      if (_host.isGuest(p.deviceId) ||
          _host.isRemote(p.deviceId) ||
          isMember(p.deviceId)) {
        continue;
      }
      if (seen.add(p.deviceId)) {
        own.add(_Target(id: p.deviceId, name: _ownName(p.deviceId, p)));
      }
    }

    final office = <_Target>[];
    if (ledger.officeId != null) {
      for (final m in ledger.members) {
        if (m.userId == me || !seen.add(m.deviceId)) continue;
        if (_net.isOnline(m.deviceId) || peers.containsKey(m.deviceId)) {
          // The ledger may know a device by its person alone: its name and
          // kind as it announces itself, that two of one person's tell apart.
          final heard = _net.announced(m.deviceId);
          office.add(
            _Target(
              id: m.deviceId,
              name: m.name,
              device: m.device.isNotEmpty ? m.device : heard?.device ?? '',
              platform: heard?.platform ?? m.platform,
              office: true,
            ),
          );
        }
      }
    }

    final nearby = <_Target>[];
    // Paired by a code, neither one's own nor the office's.
    for (final d in _net.known) {
      if (d.userId == me || !_net.isOnline(d.deviceId)) continue;
      if (!seen.add(d.deviceId)) continue;
      final heard = _net.announced(d.deviceId);
      final name = [
        d.name,
        heard?.name ?? '',
        d.device,
        heard?.device ?? '',
      ].where((n) => n.trim().isNotEmpty).firstOrNull;
      nearby.add(
        _Target(
          id: d.deviceId,
          name: name ?? d.platform.label,
          device: d.device.isNotEmpty ? d.device : heard?.device ?? '',
          platform: heard?.platform ?? d.platform,
          known: true,
        ),
      );
    }
    for (final g in _net.invitableGuests) {
      if (!seen.add(g.deviceId)) continue;
      nearby.add(
        _Target(
          id: g.deviceId,
          name: g.name.isNotEmpty ? g.name : g.device,
          device: g.name.isNotEmpty ? g.device : '',
          platform: g.platform,
          guest: g,
        ),
      );
    }
    for (final p in peers.values) {
      if (!_host.isGuest(p.deviceId) || !seen.add(p.deviceId)) continue;
      nearby.add(_Target(id: p.deviceId, name: p.name));
    }
    return [
      // Written in capitals here: Dart's own makes "i" an "I".
      (context.l.liveMyDevices, own),
      (context.l.liveOffice, office),
      (context.l.liveNearby, nearby),
    ];
  }

  String _state(LivePeer? p) => switch (p?.state) {
    LivePeerState.joining => context.l.livePeerJoining,
    LivePeerState.watching => context.l.livePeerWatching,
    LivePeerState.gone => context.l.livePeerGone,
    LivePeerState.unreachable => context.l.livePeerUnreachable,
    LivePeerState.declined => context.l.livePeerDeclined,
    LivePeerState.unanswered => context.l.livePeerUnanswered,
    null => '',
  };

  IconData _icon(_Target t) {
    return switch (t.platform) {
      OfficePlatform.android || OfficePlatform.ios => Icons.smartphone_rounded,
      OfficePlatform.macos ||
      OfficePlatform.windows ||
      OfficePlatform.linux => Icons.laptop_rounded,
      _ =>
        t.guest != null || t.office
            ? Icons.person_outline_rounded
            : Icons.devices,
    };
  }

  Future<void> _invite(_Target t) async {
    final guest = t.guest;
    if (guest != null) {
      await _host.inviteGuest(guest);
    } else {
      await _host.invite(t.id, t.name, office: t.office, known: t.known);
    }
  }

  Widget _row(_Target t) {
    final peer = _host.peers.value.where((p) => p.deviceId == t.id).firstOrNull;
    final state = peer?.state;
    final on =
        state == LivePeerState.joining || state == LivePeerState.watching;
    final right = _host.rightOf(t.id);
    final holds = _host.pen.value == t.id;
    final scheme = Theme.of(context).colorScheme;
    // A guest no more nearby, invited before: not invited again from here.
    final canInvite = !t.remote && (t.guest != null || !_host.isGuest(t.id));
    final Widget action = on
        ? TextButton(
            key: ValueKey('live-remove-${t.id}'),
            onPressed: () => unawaited(_host.remove(t.id)),
            child: Text(
              state == LivePeerState.joining
                  ? context.l.liveWithdraw
                  : context.l.liveRemovePeer,
            ),
          )
        // Gone from another office: asked again only by a new code.
        : t.remote
        ? const SizedBox()
        : FilledButton.tonal(
            key: ValueKey('live-invite-${t.id}'),
            onPressed: canInvite ? () => unawaited(_invite(t)) : null,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Text(
              peer == null ? context.l.liveInvite : context.l.liveInviteAgain,
            ),
          );
    final controls = <Widget>[
      if (state == LivePeerState.watching &&
          right == LiveRight.edit &&
          !holds &&
          _host.apply != null)
        TextButton(
          key: ValueKey('live-give-${t.id}'),
          onPressed: () => _host.give(t.id),
          child: Text(context.l.liveGivePen),
        ),
      if (_host.apply != null)
        DropdownButton<LiveRight>(
          key: ValueKey('live-right-${t.id}'),
          value: right,
          isDense: true,
          underline: const SizedBox(),
          style: Theme.of(context).textTheme.bodySmall,
          onChanged: (r) {
            if (r == null) return;
            _host.setRight(t.id, r);
            setState(() {});
          },
          items: [
            DropdownMenuItem(
              value: LiveRight.view,
              child: Text(context.l.liveCanView),
            ),
            DropdownMenuItem(
              value: LiveRight.edit,
              child: Text(context.l.liveCanEdit),
            ),
          ],
        ),
      const SizedBox(width: 6),
      action,
    ];
    final sub = [
      if (t.device.isNotEmpty) t.device,
      if (_state(peer).isNotEmpty) _state(peer),
    ].join(' · ');
    final code = peer?.code;
    // On one line only where the row itself has room for the controls:
    // the dialog is narrower than the screen it is on.
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 640;
        final head = Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: state == LivePeerState.watching
                  ? scheme.primary.withValues(alpha: .15)
                  : scheme.surfaceContainerHighest,
              child: Icon(
                _icon(t),
                size: 18,
                color: state == LivePeerState.watching
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name,
                    key: ValueKey('live-target-${t.id}'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (sub.isNotEmpty || holds || code != null)
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (sub.isNotEmpty)
                          Text(
                            sub,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  state == LivePeerState.declined ||
                                      state == LivePeerState.unreachable
                                  ? scheme.error
                                  : AgendaColors.muted,
                            ),
                          ),
                        if (code != null && state == LivePeerState.joining)
                          _chip(
                            context.l.liveCodeChip(code),
                            Icons.verified_user_outlined,
                            key: ValueKey('live-code-${t.id}'),
                          ),
                        if (holds)
                          _chip(
                            context.l.livePenHere,
                            Icons.edit_outlined,
                            key: ValueKey('live-holds-${t.id}'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            if (wide) ...controls,
          ],
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: wide
              ? head
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    head,
                    Padding(
                      padding: const EdgeInsets.only(left: 46),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: controls,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _chip(String text, IconData icon, {Key? key}) => Container(
    key: key,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: AgendaColors.taskFill,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AgendaColors.taskText),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AgendaColors.taskText,
          ),
        ),
      ],
    ),
  );

  /// One of the person's own devices by the name it was known under (its
  /// announcement says none while the office is not open to it).
  String _ownName(String id, LivePeer? peer) {
    final known = _net.ownKnown.where((d) => d.deviceId == id).firstOrNull;
    final seen = _net.ownOnline.where((d) => d.deviceId == id).firstOrNull;
    for (final n in [known?.device, seen?.device, known?.name, peer?.name]) {
      if (n != null && n.trim().isNotEmpty) return n.trim();
    }
    return (known?.platform ?? seen?.platform)?.label ?? context.l.liveDevice;
  }
}
