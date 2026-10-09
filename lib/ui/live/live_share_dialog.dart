import 'package:flutter/material.dart';

import '../../services/live/live_share.dart';
import '../../services/office/office_network.dart';
import '../agenda/agenda_page.dart' show AgendaColors;

/// Who a document is shared with live: the person's own devices in this
/// step; the office and guests next. Each is shown it the moment it is
/// ticked, and no more when it is unticked.
class LiveShareDialog extends StatefulWidget {
  const LiveShareDialog({super.key, required this.host, this.network});

  final LiveShareHost host;
  final OfficeNetwork? network;

  @override
  State<LiveShareDialog> createState() => _LiveShareDialogState();
}

class _LiveShareDialogState extends State<LiveShareDialog> {
  int _tab = 1;
  OfficeNetwork get _net => widget.network ?? OfficeNetwork.instance;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Canlı paylaş · ${widget.host.title}'),
    content: SizedBox(
      width: 440,
      child: ListenableBuilder(
        listenable: Listenable.merge([_net, widget.host.peers]),
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('Büro')),
                ButtonSegment(value: 1, label: Text('Cihazlarım')),
                ButtonSegment(value: 2, label: Text('Misafir')),
              ],
              selected: {_tab},
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
            const SizedBox(height: 10),
            if (_tab != 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Büro meslektaşlarıyla ve kodla katılan misafirle canlı '
                  'paylaşım sonraki adımda geliyor.',
                  style: TextStyle(color: AgendaColors.muted),
                ),
              )
            else
              ..._devices(),
            const SizedBox(height: 8),
            const Text(
              'Belge bu cihazda kalır; seçilen cihazların ekranına canlı '
              'yansır, yalnız görebilirler. Paylaşım bitince orada belge '
              'kalmaz.',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
          ],
        ),
      ),
    ),
    actions: [
      if (widget.host.sharing)
        TextButton(
          key: const ValueKey('live-stop'),
          onPressed: () async {
            await widget.host.close();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Paylaşımı kapat'),
        ),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Tamam'),
      ),
    ],
  );

  List<Widget> _devices() {
    if (_net.self == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Canlı paylaşım Folio\'nun ana penceresinde açılan belgelerde '
            'çalışır.',
            style: TextStyle(color: AgendaColors.muted),
          ),
        ),
      ];
    }
    final online = _net.ownOnline;
    final peers = {for (final p in widget.host.peers.value) p.deviceId: p};
    if (online.isEmpty && peers.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Şu an açık başka cihazınız yok. Senkronla eşleştirdiğiniz '
            'cihazlarda Folio açık ve aynı ağda olunca burada görünür.',
            style: TextStyle(color: AgendaColors.muted),
          ),
        ),
      ];
    }
    String state(LivePeer? p) => switch (p?.state) {
      LivePeerState.joining => 'bağlanıyor',
      LivePeerState.watching => 'izliyor',
      LivePeerState.gone => 'ayrıldı',
      LivePeerState.unreachable => 'ulaşılamadı',
      null => '',
    };
    final ids = {for (final d in online) d.deviceId, ...peers.keys};
    return [
      for (final id in ids)
        CheckboxListTile(
          key: ValueKey('live-device-$id'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          value:
              peers[id]?.state == LivePeerState.joining ||
              peers[id]?.state == LivePeerState.watching,
          onChanged: (on) async {
            final name =
                online.where((d) => d.deviceId == id).firstOrNull?.device ??
                peers[id]?.name ??
                'Cihaz';
            if (on ?? false) {
              await widget.host.invite(id, name);
            } else {
              await widget.host.remove(id);
            }
          },
          title: Text(
            online.where((d) => d.deviceId == id).firstOrNull?.device ??
                peers[id]?.name ??
                'Cihaz',
          ),
          subtitle: Text(
            [
              'Yalnız görebilir',
              if (state(peers[id]).isNotEmpty) state(peers[id]),
            ].join(' · '),
          ),
        ),
    ];
  }
}
