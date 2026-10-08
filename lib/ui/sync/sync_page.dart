import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/office/office_known.dart';
import '../../services/office/office_network.dart';
import '../../services/office/office_peer.dart';
import '../../services/sync/own_sync.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../office/qr_pairing.dart';
import '../portfolio/portfolio_rows.dart' show clockText, dayText;

/// Senkron (docs/design, the approved mock): the person's own devices and
/// what they keep alike when on the same network.
class SyncPage extends StatefulWidget {
  const SyncPage({super.key, this.network, this.sync});

  final OfficeNetwork? network;
  final OwnSync? sync;

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  OfficeNetwork get _net => widget.network ?? OfficeNetwork.instance;
  OwnSync get _sync => widget.sync ?? OwnSync.instance;
  bool _syncing = false;

  static bool get _phone =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _now() async {
    setState(() => _syncing = true);
    await _net.syncOwn();
    if (mounted) setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: dark ? scheme.surface : AgendaColors.page,
      child: ListenableBuilder(
        listenable: Listenable.merge([_net, _sync]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 900;
            final pad = wide ? 24.0 : 12.0;
            final own = _net.ownKnown;
            return ListView(
              key: const ValueKey('sync-page'),
              padding: EdgeInsets.fromLTRB(pad, wide ? 18 : 10, pad, 24),
              children: [
                _head(context, own.isNotEmpty),
                const SizedBox(height: 14),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _devices(context, own),
                        const SizedBox(height: 12),
                        _parts(context),
                        const SizedBox(height: 12),
                        _sessions(context),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _head(BuildContext context, bool any) => Row(
    children: [
      if (Scaffold.maybeOf(context)?.hasDrawer ?? false)
        IconButton(
          tooltip: 'Menü',
          onPressed: () => Scaffold.of(context).openDrawer(),
          icon: const Icon(Icons.menu_rounded),
        ),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Senkron',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 2),
            Text(
              'Yalnız kendi cihazlarınız arasında; aynı ağda olunca '
              'kendiliğinden',
              style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
            ),
          ],
        ),
      ),
      if (any && _net.joined)
        OutlinedButton.icon(
          key: const ValueKey('sync-now'),
          onPressed: _syncing ? null : () => unawaited(_now()),
          icon: _syncing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync_rounded, size: 18),
          label: const Text('Şimdi eşitle'),
        ),
    ],
  );

  Widget _card(BuildContext context, {required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }

  Widget _devices(BuildContext context, List<KnownDevice> own) {
    final self = _net.self;
    IconData icon(OfficePlatform p) =>
        p.phone ? Icons.smartphone_rounded : Icons.laptop_rounded;
    return _card(
      context,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cihazlarım',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (!_net.joined)
              const Text(
                'Senkron, Büro ağı açıkken çalışır. Büro ağı sayfasından ağa '
                'katılın.',
                style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
              )
            else ...[
              if (self != null)
                _deviceRow(
                  icon(self.platform),
                  'Bu cihaz · ${self.device}',
                  null,
                ),
              for (final d in _net.ownKnown)
                _deviceRow(
                  icon(d.platform),
                  d.device.isEmpty ? d.name : d.device,
                  _seenText(d.deviceId),
                  key: ValueKey('sync-device-${d.deviceId}'),
                  online: _net.isOnline(d.deviceId),
                ),
              if (own.isEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _phone
                      ? 'Henüz başka cihazınız yok. Bilgisayarınızda Büro '
                            'ağı’nda “Telefonumu ekle”ye basın ve çıkan QR’ı '
                            'okutun.'
                      : 'Henüz başka cihazınız yok. Telefonunuzu QR ile '
                            'ekleyin; başka bir bilgisayarınızı Büro ağı’nda '
                            '“Tanı” ile, “Bu cihaz da benim” işaretleyerek '
                            'ekleyin.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AgendaColors.muted,
                  ),
                ),
                const SizedBox(height: 10),
                _phone
                    ? FilledButton.tonalIcon(
                        key: const ValueKey('sync-qr-scan'),
                        onPressed: () => unawaited(scanAndPair(context, _net)),
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: const Text('QR okut'),
                      )
                    : FilledButton.tonalIcon(
                        key: const ValueKey('sync-qr-invite'),
                        onPressed: () =>
                            unawaited(QrInviteDialog.show(context, _net)),
                        icon: const Icon(Icons.qr_code_2_rounded),
                        label: const Text('Telefonumu ekle'),
                      ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _seenText(String deviceId) {
    final online = _net.isOnline(deviceId);
    final at = _net.synced[deviceId];
    final when = at == null
        ? null
        : DateUtils.isSameDay(at, DateTime.now())
        ? clockText(at)
        : '${dayText(at)} ${clockText(at)}';
    return [
      online ? 'ağda' : 'ağda değil',
      if (when != null) 'son eşitleme $when',
    ].join(' · ');
  }

  Widget _deviceRow(
    IconData icon,
    String name,
    String? detail, {
    Key? key,
    bool online = false,
  }) => Padding(
    key: key,
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 19),
        const SizedBox(width: 10),
        Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
        if (detail != null)
          Text(
            detail,
            style: TextStyle(
              fontSize: 12,
              color: online ? AgendaColors.ok : AgendaColors.muted,
            ),
          ),
      ],
    ),
  );

  Widget _parts(BuildContext context) => _card(
    context,
    child: Column(
      children: [
        SwitchListTile(
          key: const ValueKey('sync-agenda'),
          secondary: const Icon(Icons.event_note_rounded),
          title: const Text(
            'Ajanda ve notlar',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text(
            'Görevler, notlar ve süre işaretleriniz; birinde silinen '
            'ötekinde de silinir.',
            style: TextStyle(fontSize: 12),
          ),
          value: _sync.isOn(OwnSync.agenda),
          onChanged: (on) => unawaited(_sync.turn(OwnSync.agenda, on)),
        ),
      ],
    ),
  );

  static const _kinds = {
    'mobil': 'UYAP Mobil',
    'uets': 'UETS',
    'web': 'UYAP Web',
  };

  String _nameOf(KnownDevice d) => d.device.isEmpty ? d.name : d.device;

  Future<void> _move(Future<String?> Function() doIt) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _syncing = true);
    final error = await doIt();
    if (!mounted) return;
    setState(() => _syncing = false);
    messenger?.showSnackBar(
      SnackBar(content: Text(error ?? 'Oturum taşındı.')),
    );
  }

  Widget _sessions(BuildContext context) {
    final here = _sync.heldHere;
    final online = [
      for (final d in _net.ownKnown)
        if (_net.isOnline(d.deviceId)) d,
    ];
    return _card(
      context,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.key_rounded),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Oturumlar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Yeniden e-imza atmadan öbür cihazınızda devam edin. '
                        'Oturum tek cihazda açık olur; aldığınız cihaza geçer.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final MapEntry(key: kind, value: label) in _kinds.entries)
              () {
                final there = [
                  for (final d in online)
                    if (_sync.held[d.deviceId]?.contains(kind) ?? false) d,
                ];
                final Widget? action;
                if (here.contains(kind) && online.isNotEmpty) {
                  action = online.length == 1
                      ? OutlinedButton(
                          key: ValueKey('sync-give-$kind'),
                          onPressed: _syncing
                              ? null
                              : () => unawaited(
                                  _move(
                                    () => _sync.give(
                                      online.single.deviceId,
                                      kind,
                                    ),
                                  ),
                                ),
                          child: const Text('Öbür cihaza ver'),
                        )
                      : PopupMenuButton<KnownDevice>(
                          key: ValueKey('sync-give-$kind'),
                          tooltip: 'Hangi cihaza?',
                          onSelected: (d) => unawaited(
                            _move(() => _sync.give(d.deviceId, kind)),
                          ),
                          itemBuilder: (_) => [
                            for (final d in online)
                              PopupMenuItem(value: d, child: Text(_nameOf(d))),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('Cihaza ver…'),
                          ),
                        );
                } else if (!here.contains(kind) && there.isNotEmpty) {
                  action = OutlinedButton(
                    key: ValueKey('sync-take-$kind'),
                    onPressed: _syncing
                        ? null
                        : () => unawaited(
                            _move(() => _sync.take(there.first.deviceId, kind)),
                          ),
                    child: const Text('Bu cihaza al'),
                  );
                } else {
                  action = null;
                }
                final status = here.contains(kind)
                    ? 'bu cihazda açık'
                    : there.isNotEmpty
                    ? 'açık · ${_nameOf(there.first)}'
                    : 'kapalı';
                return Padding(
                  padding: const EdgeInsets.fromLTRB(40, 4, 0, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$label · $status',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      ?action,
                    ],
                  ),
                );
              }(),
          ],
        ),
      ),
    );
  }
}
