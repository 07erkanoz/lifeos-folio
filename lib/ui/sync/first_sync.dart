import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/office/office_network.dart';
import '../../services/sync/own_sync.dart';
import '../../services/sync/settings_sync.dart';
import '../office/qr_pairing.dart';
import '../widgets/folio_dialog.dart';

/// A phone being set up, made one of the lawyer's devices with the
/// computer's QR, and given at once what the computer has (Senkron): the
/// profile, the snippets and choices, the agenda and clients, the cases.
/// True once it was taken in.
Future<bool> pairWithDesktop(
  BuildContext context, {
  OfficeNetwork? network,
  OwnSync? sync,
}) async {
  final net = network ?? OfficeNetwork.instance;
  if (!net.joined) await net.join();
  if (!context.mounted) return false;
  if (!net.joined) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(net.error ?? 'Senkron açılamadı.')));
    return false;
  }
  final known = {for (final d in net.ownKnown) d.deviceId};
  await scanAndPair(context, net);
  if (!context.mounted) return false;
  final paired = net.ownKnown.any((d) => !known.contains(d.deviceId));
  if (!paired && known.isEmpty) return false;
  await (sync ?? OwnSync.instance).start();
  if (!context.mounted) return false;
  return FirstSyncDialog.show(context, net, sync: sync);
}

/// The first sync, part by part: each with its state, and the whole with
/// how far it has come.
class FirstSyncDialog extends StatefulWidget {
  const FirstSyncDialog({
    super.key,
    required this.events,
    required this.run,
    this.documents,
    this.takeDocuments,
  });

  /// How many documents the computer has downloaded, and their size.
  final Future<({int count, int bytes})?> Function()? documents;

  /// The computer asked to send them; true when it was.
  final Future<bool> Function()? takeDocuments;

  /// Each part as it is taken in, and when it is.
  final Stream<({String part, bool done})> events;

  /// What makes the devices alike.
  final Future<void> Function() run;

  static Future<bool> show(
    BuildContext context,
    OfficeNetwork network, {
    OwnSync? sync,
  }) async {
    final docs = (sync ?? OwnSync.instance).documents;
    // The computer it was set up from: the own device on the network.
    String? computer() => network.ownOnline.firstOrNull?.deviceId;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => FirstSyncDialog(
            events: network.ownMerging,
            run: network.syncOwn,
            documents: () async {
              final id = computer();
              return id == null ? null : docs.count(id);
            },
            takeDocuments: () async {
              final id = computer();
              return id != null && await docs.ask(id);
            },
          ),
        ) ??
        false;
  }

  /// The parts, in the order they are shown, by what the lawyer calls them.
  static const parts = [
    (OwnSync.profilePart, 'Avukat profili', Icons.badge_outlined),
    (OwnSync.settingsPart, 'Kalıplar ve ayarlar', Icons.tune_rounded),
    (
      OwnSync.agenda,
      'Ajanda, müvekkiller ve süreler',
      Icons.event_note_rounded,
    ),
    (OwnSync.uyapData, 'Dava dosyaları ve duruşmalar', Icons.gavel_rounded),
    (OwnSync.sessionsPart, 'Portal bağlantıları', Icons.link_rounded),
  ];

  @override
  State<FirstSyncDialog> createState() => _FirstSyncDialogState();
}

enum _State { coming, done }

class _FirstSyncDialogState extends State<FirstSyncDialog> {
  final _states = <String, _State>{};
  StreamSubscription<({String part, bool done})>? _heard;
  bool _finished = false;
  bool _failed = false;

  /// The computer's documents: how many, and whether they were asked for.
  ({int count, int bytes})? _docs;
  bool _docsAsked = false;

  @override
  void initState() {
    super.initState();
    unawaited(_go());
  }

  @override
  void dispose() {
    unawaited(_heard?.cancel());
    SettingsSync.receiveOnly = false;
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _states.clear();
      _finished = false;
      _failed = false;
    });
    _heard ??= widget.events.listen((e) {
      if (mounted) {
        setState(() => _states[e.part] = e.done ? _State.done : _State.coming);
      }
    });
    // This phone's fresh defaults are not given back as the newer.
    SettingsSync.receiveOnly = true;
    try {
      await widget.run();
    } catch (_) {}
    SettingsSync.receiveOnly = false;
    if (!mounted) return;
    setState(() {
      _finished = true;
      _failed = _states.isEmpty;
    });
    if (!_failed && widget.documents != null) {
      final docs = await widget.documents!();
      if (mounted) setState(() => _docs = docs);
    }
  }

  Future<void> _takeDocuments() async {
    final ok = await (widget.takeDocuments?.call() ?? Future.value(false));
    if (mounted) setState(() => _docsAsked = ok);
  }

  static String _size(int bytes) => bytes >= 1 << 30
      ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB'
      : bytes >= 1 << 20
      ? '${(bytes / (1 << 20)).toStringAsFixed(0)} MB'
      : '${(bytes / 1024).ceil()} KB';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = FirstSyncDialog.parts;
    final done = shown.where((p) => _states[p.$1] == _State.done).length;
    return FolioDialog(
      width: 460,
      icon: Icons.sync_rounded,
      title: _failed
          ? 'Bilgisayara ulaşılamadı'
          : _finished
          ? 'Hazır'
          : 'Bilgisayarınızdan alınıyor',
      subtitle: _failed
          ? 'Telefon ile bilgisayar aynı Wi‑Fi ağında olmalı'
          : 'Profil, ayarlar ve verileriniz bu telefona geliyor',
      actions: [
        if (_failed) ...[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const ValueKey('first-sync-retry'),
            onPressed: () => unawaited(_go()),
            child: const Text('Yeniden dene'),
          ),
        ] else
          FilledButton(
            key: const ValueKey('first-sync-done'),
            onPressed: _finished ? () => Navigator.pop(context, true) : null,
            child: Text(_finished ? 'Devam et' : 'Alınıyor…'),
          ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_failed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  key: const ValueKey('first-sync-progress'),
                  minHeight: 6,
                  value: _finished ? 1 : done / shown.length,
                ),
              ),
            ),
          for (final (part, label, icon) in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                key: ValueKey('first-sync-$part'),
                children: [
                  Icon(icon, size: 19, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label)),
                  switch (_states[part]) {
                    _State.done => Icon(
                      Icons.check_circle_rounded,
                      key: ValueKey('first-sync-$part-done'),
                      size: 19,
                      color: scheme.primary,
                    ),
                    _State.coming => const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    _ when _finished => Text(
                      'yok',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    _ => Icon(
                      Icons.radio_button_unchecked_rounded,
                      size: 19,
                      color: scheme.outlineVariant,
                    ),
                  },
                ],
              ),
            ),
          if (_finished && !_failed && (_docs?.count ?? 0) > 0)
            Container(
              key: const ValueKey('first-sync-documents'),
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _docsAsked
                  ? const Text(
                      'Evraklar geliyor. İki cihaz aynı ağda kaldıkça arka '
                      'planda tamamlanır; açtığınız evrak hemen iner.',
                      style: TextStyle(fontSize: 12.5),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Bilgisayarınızda indirilmiş ${_docs!.count} evrak '
                          'var (${_size(_docs!.bytes)}). Bu telefona da '
                          'alınsın mı?',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: const ValueKey('first-sync-take-documents'),
                            onPressed: () => unawaited(_takeDocuments()),
                            icon: const Icon(Icons.download_rounded, size: 17),
                            label: const Text('Evrakları da al'),
                          ),
                        ),
                      ],
                    ),
            ),
          if (_finished && !_failed)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Almadığınız evrak, açtığınızda bu telefona indirilir. '
                'Bundan sonra iki cihaz aynı ağda oldukça kendiliğinden '
                'eşitlenir.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
