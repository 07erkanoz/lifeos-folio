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
            if (_tab == 2)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Kodla katılan misafirle canlı paylaşım sonraki adımda '
                  'geliyor.',
                  style: TextStyle(color: AgendaColors.muted),
                ),
              )
            else if (_tab == 0)
              ..._office()
            else
              ..._devices(),
            const SizedBox(height: 8),
            const Text(
              'Belge bu cihazda kalır; yalnız seçtiklerinizin ekranına canlı '
              'yansır, yalnız görebilirler, kopyalayamazlar. Paylaşım bitince '
              'onlarda belge kalmaz.',
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

  /// The office's members on the network now, each a device: not the
  /// person's own, which are under Cihazlarım.
  List<Widget> _office() {
    final ledger = _net.ledger;
    if (_net.self == null || ledger.officeId == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Bir büro ağına bağlı değilsiniz. Büro ağı Büro sayfasından '
            'kurulur ya da büroya katılınır.',
            style: TextStyle(color: AgendaColors.muted),
          ),
        ),
      ];
    }
    final me = _net.self!.userId;
    final peers = {for (final p in widget.host.peers.value) p.deviceId: p};
    final members = [
      for (final m in ledger.members)
        if (m.userId != me &&
            (_net.isOnline(m.deviceId) || peers.containsKey(m.deviceId)))
          m,
    ];
    if (members.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Şu an büro ağında açık bir meslektaşınız yok.',
            style: TextStyle(color: AgendaColors.muted),
          ),
        ),
      ];
    }
    return [
      for (final m in members)
        _row(
          id: m.deviceId,
          name: m.name,
          device: m.device,
          peer: peers[m.deviceId],
          office: true,
        ),
    ];
  }

  String _state(LivePeer? p) => switch (p?.state) {
    LivePeerState.joining => 'bağlanıyor',
    LivePeerState.watching => 'izliyor',
    LivePeerState.gone => 'ayrıldı',
    LivePeerState.unreachable => 'ulaşılamadı',
    null => '',
  };

  Widget _row({
    required String id,
    required String name,
    String device = '',
    LivePeer? peer,
    bool office = false,
  }) => CheckboxListTile(
    key: ValueKey('live-${office ? 'member' : 'device'}-$id'),
    dense: true,
    contentPadding: EdgeInsets.zero,
    value:
        peer?.state == LivePeerState.joining ||
        peer?.state == LivePeerState.watching,
    onChanged: (on) async {
      if (on ?? false) {
        await widget.host.invite(id, name, office: office);
      } else {
        await widget.host.remove(id);
      }
    },
    title: Text(name),
    subtitle: Text(
      [
        if (device.isNotEmpty) device,
        'Yalnız görebilir',
        if (_state(peer).isNotEmpty) _state(peer),
      ].join(' · '),
    ),
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
    final ids = {for (final d in online) d.deviceId, ...peers.keys};
    return [
      for (final id in ids)
        _row(
          id: id,
          name:
              online.where((d) => d.deviceId == id).firstOrNull?.device ??
              peers[id]?.name ??
              'Cihaz',
          peer: peers[id],
        ),
    ];
  }
}
