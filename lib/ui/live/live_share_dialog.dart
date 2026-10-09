import 'package:flutter/material.dart';

import '../../services/live/live_share.dart';
import '../../services/office/office_network.dart';
import '../agenda/agenda_page.dart' show AgendaColors;

/// Who a document is shared with live: the person's own devices, the
/// office's members, and guests who join by a code. Each is shown it the
/// moment it is ticked (a guest accepted), and no more when it is
/// unticked.
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
        listenable: Listenable.merge([
          _net,
          widget.host.peers,
          widget.host.pen,
        ]),
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
              ..._guests()
            else if (_tab == 0)
              ..._office()
            else
              ..._devices(),
            if (widget.host.pen.value != null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  key: const ValueKey('live-take-back'),
                  onPressed: widget.host.takeBack,
                  child: const Text('Kalemi geri al'),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Belge bu cihazda kalır; yalnız seçtiklerinizin ekranına canlı '
              'yansır. "Yalnız görebilir" olanlar kopyalayamaz. "Sırayla '
              'düzenleyebilir" olanlara kalemi verince yazdıkları belgenize '
              'işlenir; o sırada belgeniz yalnız okunur, kalemi istediğiniz an '
              'geri alırsınız, 2 dakika yazılmazsa kendiliğinden döner. '
              'Paylaşım bitince onlarda belge kalmaz.',
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
    bool guest = false,
  }) {
    final host = widget.host;
    final on =
        peer?.state == LivePeerState.joining ||
        peer?.state == LivePeerState.watching;
    final right = host.rightOf(id);
    final holds = host.pen.value == id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(
            key: ValueKey(
              'live-${guest ? 'guest' : (office ? 'member' : 'device')}-$id',
            ),
            value: on,
            onChanged: (v) async {
              if (v ?? false) {
                // A guest gone is not shown it again: it asks anew, by a code.
                if (guest) return;
                await host.invite(id, name, office: office);
              } else {
                await host.remove(id);
              }
            },
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, overflow: TextOverflow.ellipsis),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      [
                        if (device.isNotEmpty) device,
                        if (_state(peer).isNotEmpty) _state(peer),
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AgendaColors.muted,
                      ),
                    ),
                    if (holds)
                      Container(
                        key: ValueKey('live-holds-$id'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AgendaColors.taskFill,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 12,
                              color: AgendaColors.taskText,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'kalem onda',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AgendaColors.taskText,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (on && right == LiveRight.edit && !holds && host.apply != null)
            TextButton(
              key: ValueKey('live-give-$id'),
              onPressed: peer?.state == LivePeerState.watching
                  ? () => host.give(id)
                  : null,
              child: const Text('Kalemi ver'),
            ),
          DropdownButton<LiveRight>(
            key: ValueKey('live-right-$id'),
            value: right,
            isDense: true,
            underline: const SizedBox(),
            style: Theme.of(context).textTheme.bodySmall,
            onChanged: (r) {
              if (r == null) return;
              host.setRight(id, r);
              setState(() {});
            },
            items: [
              const DropdownMenuItem(
                value: LiveRight.view,
                child: Text('Yalnız görebilir'),
              ),
              if (host.apply != null)
                const DropdownMenuItem(
                  value: LiveRight.edit,
                  child: Text('Sırayla düzenleyebilir'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Guests, who join by a code: taken while the switch is on, each
  /// asking and the lawyer accepting; the ones shown it below.
  List<Widget> _guests() {
    final guests = [
      for (final p in widget.host.peers.value)
        if (widget.host.isGuest(p.deviceId)) p,
    ];
    return [
      SwitchListTile(
        key: const ValueKey('live-take-guests'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: widget.host.takingGuests,
        onChanged: (on) async {
          await widget.host.takeGuests(on);
          if (mounted) setState(() {});
        },
        title: const Text('Misafirleri kabul et'),
        subtitle: const Text(
          'Büronuzda olmayan, Folio kullanan biri aynı ağda Dosya ▸ Canlı '
          'belgeye katıl\'a basar ve sizi seçer. İki ekranda aynı kod çıkar; '
          'siz kabul edince belgeyi görür.',
        ),
      ),
      for (final g in guests)
        _row(id: g.deviceId, name: g.name, peer: g, guest: true),
      if (widget.host.takingGuests && guests.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Henüz katılan misafir yok.',
            style: TextStyle(color: AgendaColors.muted),
          ),
        ),
    ];
  }

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
    final me = _net.self!.userId;
    // The person's own: not a guest, nor a colleague (under Büro).
    final peers = {
      for (final p in widget.host.peers.value)
        if (!widget.host.isGuest(p.deviceId) &&
            !_net.ledger.members.any(
              (m) => m.deviceId == p.deviceId && m.userId != me,
            ))
          p.deviceId: p,
    };
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
