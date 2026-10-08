import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/office/office_known.dart';
import '../../services/office/office_network.dart';
import '../../services/office/office_peer.dart';
import '../../services/sync/folder_sync.dart';
import '../../services/sync/own_sync.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../office/office_pairing_dialog.dart';
import '../office/qr_pairing.dart';
import '../widgets/drop_zone.dart';
import '../portfolio/portfolio_rows.dart' show clockText, dayText;

/// Senkron (docs/design, the approved mock): the person's own devices and
/// what they keep alike when on the same network.
class SyncPage extends StatefulWidget {
  const SyncPage({
    super.key,
    this.network,
    this.sync,
    this.folderSync,
    this.archiveFolders,
  });

  final OfficeNetwork? network;
  final OwnSync? sync;
  final FolderSync? folderSync;

  /// The library's folders, to choose one to keep alike.
  final List<String> Function()? archiveFolders;

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  OfficeNetwork get _net => widget.network ?? OfficeNetwork.instance;
  OwnSync get _sync => widget.sync ?? OwnSync.instance;
  FolderSync get _folders => widget.folderSync ?? FolderSync.instance;
  bool _syncing = false;
  bool _walled = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      OfficeNetwork.firewallBlocks(at: _net.listeningPort).then((on) {
        if (mounted && on) setState(() => _walled = true);
      }),
    );
  }

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
    return DropZoneOverlay(
      title: 'Klasörü buraya bırakın',
      subtitle: 'Bırakılan klasör kendi cihazlarınızla eşitlenir',
      onFilesDropped: (paths) => unawaited(_dropped(paths)),
      child: ColoredBox(
        color: dark ? scheme.surface : AgendaColors.page,
        child: ListenableBuilder(
          listenable: Listenable.merge([_net, _sync, _folders]),
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
                          _folderCard(context),
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
            if (!_net.joined) ...[
              const Text(
                'Senkron açılınca bu cihaz aynı ağdaki kendi cihazlarınızı '
                'bulur. Büro kurmanız gerekmez; başka kimse sizin cihazınızı '
                'tanımadan hiçbir şey alamaz.',
                style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
              ),
              if (_net.error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _net.error!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AgendaColors.taskText,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const ValueKey('sync-join'),
                onPressed: _net.starting ? null : () => unawaited(_net.join()),
                icon: const Icon(Icons.sync_rounded),
                label: Text(_net.starting ? 'Açılıyor…' : 'Senkronu aç'),
              ),
            ] else ...[
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
                      ? 'Henüz başka cihazınız yok. Bilgisayarınızda Senkron’da '
                            '“Telefonumu ekle”ye basın ve çıkan QR’ı burada '
                            '“QR okut” ile okutun.'
                      : 'Henüz başka cihazınız yok. Telefonunuzu QR ile, başka '
                            'bir bilgisayarınızı ağda seçerek ekleyin.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AgendaColors.muted,
                  ),
                ),
              ],
              if (_walled) ...[
                const SizedBox(height: 10),
                FirewallNote(at: _net.listeningPort),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _phone
                    ? [
                        FilledButton.tonalIcon(
                          key: const ValueKey('sync-qr-scan'),
                          onPressed: () =>
                              unawaited(scanAndPair(context, _net)),
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          label: const Text('QR okut'),
                        ),
                      ]
                    : [
                        FilledButton.tonalIcon(
                          key: const ValueKey('sync-qr-invite'),
                          onPressed: () =>
                              unawaited(QrInviteDialog.show(context, _net)),
                          icon: const Icon(Icons.qr_code_2_rounded),
                          label: const Text('Telefonumu ekle'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('sync-add-computer'),
                          onPressed: () => unawaited(_addComputer()),
                          icon: const Icon(Icons.laptop_rounded),
                          label: const Text('Bilgisayarımı ekle'),
                        ),
                      ],
              ),
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
        // The state under the name: a phone has no room beside it.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 13)),
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
      SnackBar(content: Text(error ?? 'Oturum öbür cihazda da açık.')),
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
                        'İki cihazda da açık kalır; UYAP Mobil’i telefon, '
                        'bilgisayarınız üzerinden yeniler. UYAP Web aynı anda '
                        'tek işlem kabul eder; iki cihazdan birlikte '
                        'kullanılırsa oturum düşebilir.',
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
                          child: const Text('Öbür cihazla paylaş'),
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
                            child: Text('Paylaş…'),
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
                    child: const Text('Bu cihazda da aç'),
                  );
                } else {
                  action = null;
                }
                final status = here.contains(kind)
                    ? 'bu cihazda açık'
                    : there.isNotEmpty
                    ? 'açık · ${_nameOf(there.first)}'
                    : 'kapalı';
                // On a phone the button goes under its words.
                return Padding(
                  padding: const EdgeInsets.fromLTRB(40, 4, 0, 4),
                  child: MediaQuery.sizeOf(context).width < 600
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$label · $status',
                              style: const TextStyle(fontSize: 13),
                            ),
                            if (action != null) ...[
                              const SizedBox(height: 4),
                              action,
                            ],
                          ],
                        )
                      : Row(
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

  Future<void> _pickFolder() async {
    final shared = {for (final f in _folders.folders.values) f.path};
    final choices = [
      for (final path in widget.archiveFolders?.call() ?? const <String>[])
        if (!shared.contains(path)) path,
    ];
    if (choices.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Eşitlenecek bir arşiv klasörü yok. Önce Ayarlar’daki Arşiv '
            'klasörleri’nden bir klasör ekleyin.',
          ),
        ),
      );
      return;
    }
    final path = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Hangi klasör eşitlensin?'),
        children: [
          for (final path in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, path),
              child: Text(path, style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
    if (path == null || !mounted) return;
    await _share(path);
  }

  Future<void> _join(OfferedFolder o) async {
    var existing = true;
    if (_phone) {
      final answer = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('“${o.name}” bu telefona gelsin mi?'),
          content: const Text(
            'Klasördeki mevcut dosyalar da gelsin mi, yoksa yalnız bundan '
            'sonra eklenen ve değişen dosyalar mı? Telefonda yer kısıtlıysa '
            'yalnız yenileri seçin.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Yalnız yeniler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Mevcutlar da gelsin'),
            ),
          ],
        ),
      );
      if (answer == null) return;
      existing = answer;
    }
    final why = await _folders.join(o.id, existing: existing);
    if (why != null && mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(why)));
    }
  }

  Widget _folderCard(BuildContext context) {
    final mine = _folders.folders.values.toList();
    final offered = _folders.offered.values.toList();
    // On a phone the buttons go under the words they are about.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final pick = OutlinedButton(
      key: const ValueKey('sync-folder-pick'),
      onPressed: () => unawaited(_pickFolder()),
      child: const Text('Klasör seç'),
    );
    return _card(
      context,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_outlined),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Klasörler',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Seçtiğiniz klasörler iki yönde eşitlenir. İkisinde de '
                        'değişen dosyanın iki hâli kalır; silinen 30 gün '
                        'Senkron çöpünde durur.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (!narrow) pick,
              ],
            ),
            if (narrow)
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 8, 0, 0),
                child: pick,
              ),
            const SizedBox(height: 6),
            for (final f in mine)
              Padding(
                key: ValueKey('sync-folder-${f.id}'),
                padding: const EdgeInsets.fromLTRB(40, 2, 0, 2),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: AgendaColors.ok,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [
                          f.name,
                          if (_folders.counts[f.id] case final n?) '$n dosya',
                          if (f.since != null) 'yalnız yeniler',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Eşitlemeyi durdur',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => unawaited(_folders.stop(f.id)),
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
                  ],
                ),
              ),
            for (final o in offered)
              Padding(
                key: ValueKey('sync-offered-${o.id}'),
                padding: const EdgeInsets.fromLTRB(40, 4, 0, 4),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${o.name} · paylaşan: ${o.fromName}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    FilledButton.tonal(
                      key: ValueKey('sync-join-${o.id}'),
                      onPressed: () => unawaited(_join(o)),
                      child: const Text('Bu cihazda da eşitle'),
                    ),
                  ],
                ),
              ),
            if (mine.isEmpty && offered.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(40, 2, 0, 4),
                child: Text(
                  'Henüz eşitlenen klasör yok.',
                  style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _dropped(List<String> paths) async {
    final folders = [
      for (final path in paths)
        if (FileSystemEntity.isDirectorySync(path)) path,
    ];
    if (folders.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Buraya klasör bırakın. Dosya göndermek için Büro ağı sayfasına '
            'bırakın.',
          ),
        ),
      );
      return;
    }
    for (final path in folders) {
      // Searched in the archive too, as a chosen folder is.
      _folders.onAdded?.call(path);
      await _share(path);
    }
  }

  /// A folder to keep alike: chosen, or dropped on the page.
  Future<void> _share(String path) async {
    final why = _folders.whyNot(path);
    if (why != null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(why)));
      return;
    }
    await _folders.share(path);
  }

  /// Another computer of the person's on the network, known by a code;
  /// "Bu cihaz da benim" comes ticked here.
  Future<void> _addComputer() async {
    final nearby = [
      for (final person in _net.people)
        for (final d in person.devices)
          if (d.online &&
              d.deviceId != _net.self?.deviceId &&
              !_net.isKnown(d.deviceId) &&
              !d.platform.phone)
            d,
    ];
    if (nearby.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Ağda başka bir bilgisayar görünmüyor. Öbür bilgisayarda Folio’yu '
            'açıp Senkron’da “Senkronu aç”a basın.',
          ),
        ),
      );
      return;
    }
    final peer = await showDialog<OfficePeer>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Hangi bilgisayar sizin?'),
        children: [
          for (final d in nearby)
            SimpleDialogOption(
              key: ValueKey('sync-add-${d.deviceId}'),
              onPressed: () => Navigator.pop(context, d),
              child: Text('${d.device} · ${d.platform.label}'),
            ),
        ],
      ),
    );
    if (peer == null || !mounted) return;
    final pairing = _net.pair(peer);
    if (pairing == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Şu anda başka bir cihaz tanınıyor; bitince deneyin.'),
        ),
      );
      return;
    }
    pairing.mine = true;
    await OfficePairingDialog.show(context, pairing);
  }
}
