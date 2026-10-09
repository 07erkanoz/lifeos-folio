import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/editor/lawyer_profile.dart';
import '../../services/live/live_share.dart';
import '../../services/office/office_known.dart';
import '../../services/office/office_network.dart';
import '../../services/office/office_pairing.dart';
import '../../services/office/office_peer.dart';
import '../agenda/agenda_page.dart' show AgendaColors;

/// The code a pairing makes, large, as both screens show it.
class _Code extends StatelessWidget {
  const _Code(this.code);

  final String code;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('live-guest-code'),
    padding: const EdgeInsets.symmetric(vertical: 14),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      code,
      style: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: 6,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );
}

Widget _waiting(String text) => Row(
  children: [
    const SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    const SizedBox(width: 12),
    Expanded(child: Text(text)),
  ],
);

/// A guest asking to be shown the document being shared: who they say
/// they are, and the code both screens show, for the lawyer to take or
/// turn away.
class LiveGuestAskDialog extends StatefulWidget {
  const LiveGuestAskDialog({super.key, required this.pairing, this.title = ''});

  final OfficePairing pairing;

  /// The document asked for.
  final String title;

  static Future<void> show(
    BuildContext context,
    OfficePairing pairing, {
    String title = '',
  }) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => LiveGuestAskDialog(pairing: pairing, title: title),
  );

  @override
  State<LiveGuestAskDialog> createState() => _LiveGuestAskDialogState();
}

class _LiveGuestAskDialogState extends State<LiveGuestAskDialog> {
  OfficePairing get pairing => widget.pairing;
  Timer? _leave;

  @override
  void initState() {
    super.initState();
    pairing.addListener(_changed);
    _changed();
  }

  /// Ended: the dialog goes by itself a moment later, that one asking
  /// after another does not leave a pile of them.
  void _changed() {
    if (!pairing.finished || _leave != null) return;
    _leave = Timer(
      pairing.state == PairingState.done
          ? const Duration(seconds: 2)
          : const Duration(seconds: 4),
      _close,
    );
  }

  void _close() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  @override
  void dispose() {
    _leave?.cancel();
    pairing.removeListener(_changed);
    // Gone some other way while asking: not taken.
    if (!pairing.finished) pairing.reject();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: pairing,
    builder: (context, _) {
      final state = pairing.state;
      final who = [
        if (pairing.guestName.isNotEmpty) pairing.guestName else 'Bir misafir',
        if (pairing.guestOffice.isNotEmpty) '(${pairing.guestOffice})',
      ].join(' ');
      final open =
          state == PairingState.connecting ||
          state == PairingState.waiting ||
          state == PairingState.code ||
          state == PairingState.confirmed;
      final body = switch (state) {
        PairingState.connecting ||
        PairingState.waiting => _waiting('Misafirin cihazıyla bağlanılıyor…'),
        PairingState.code || PairingState.confirmed => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$who ${widget.title.isEmpty ? 'belgeyi' : '“${widget.title}” belgesini'} '
              'canlı izlemek istiyor. Onun ekranında da aynı kod görünüyorsa '
              'kabul edin.',
            ),
            const SizedBox(height: 12),
            _Code(pairing.code ?? ''),
            const SizedBox(height: 10),
            if (state == PairingState.confirmed)
              _waiting('Misafirin onayı bekleniyor…')
            else
              const Text(
                'Misafir yalnız bu belgeyi, yalnız bu paylaşım sürerken '
                'görür; büronuza ya da cihazlarınıza eklenmez.',
                style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
              ),
          ],
        ),
        PairingState.done => Text('$who belgeyi izlemeye başladı.'),
        PairingState.rejected => Text(
          pairing.reason ?? 'Misafir kabul edilmedi.',
        ),
        PairingState.failed => Text(
          pairing.reason ?? 'Misafirle bağlantı kurulamadı.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      };
      return AlertDialog(
        title: const Text('Misafir katılmak istiyor'),
        content: SizedBox(width: 400, child: body),
        actions: [
          if (open)
            TextButton(
              key: const ValueKey('live-guest-reject'),
              onPressed: () {
                pairing.reject();
                _close();
              },
              child: const Text('Reddet'),
            ),
          if (state == PairingState.code)
            FilledButton(
              key: const ValueKey('live-guest-accept'),
              onPressed: pairing.confirm,
              child: const Text('Kabul et'),
            )
          else if (!open)
            FilledButton(onPressed: _close, child: const Text('Tamam')),
        ],
      );
    },
  );
}

/// Joining another's live document as a guest (Canlı belgeye katıl): the
/// Folios sharing to guests on the network, the guest's name, then the
/// code both screens show. Gives the session once the document comes.
class LiveJoinDialog extends StatefulWidget {
  const LiveJoinDialog({super.key, this.network, this.share});

  final OfficeNetwork? network;
  final LiveShare? share;

  /// The dialog, then the document on a page when it came.
  static Future<LiveSession?> show(BuildContext context) =>
      showDialog<LiveSession>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const LiveJoinDialog(),
      );

  @override
  State<LiveJoinDialog> createState() => _LiveJoinDialogState();
}

class _LiveJoinDialogState extends State<LiveJoinDialog> {
  OfficeNetwork get _net => widget.network ?? OfficeNetwork.instance;
  LiveShare get _share => widget.share ?? LiveShare.instance;

  final _name = TextEditingController();
  final _office = TextEditingController();
  String? _host;
  OfficePeer? _asked;
  OfficePairing? _pairing;
  LiveSession? _came;
  String? _error;
  Timer? _late;

  /// The sessions there before this asking: none of them its answer.
  Set<LiveSession> _before = {};

  /// The grant this asking made, let go if the document never came.
  KnownDevice? _grant;

  /// How long the document may take once the codes were confirmed.
  static const _wait = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    unawaited(_net.lookForLive(true));
    _share.incoming.addListener(_arrived);
    unawaited(_prefill());
  }

  /// The guest's name and office, as the profile has them.
  Future<void> _prefill() async {
    try {
      final p = await LawyerProfile.load();
      if (!mounted) return;
      if (_name.text.isEmpty) _name.text = p.lawyer?.titled ?? '';
      if (_office.text.isEmpty) _office.text = p.officeName.trim();
      setState(() {});
    } catch (_) {
      // No profile: the guest writes them.
    }
  }

  @override
  void dispose() {
    _late?.cancel();
    _share.incoming.removeListener(_arrived);
    _pairing?.removeListener(_paired);
    final pairing = _pairing, asked = _asked;
    if (_came == null) {
      // Not joined after all: nothing of the host kept, but only what this
      // asking made.
      if (pairing != null && !pairing.finished) pairing.reject();
      final grant = _grant ?? _grantOf(pairing, asked);
      if (asked != null && grant != null) {
        unawaited(_net.forgetGuest(asked.deviceId, grant));
      }
    }
    unawaited(_net.lookForLive(false));
    _name.dispose();
    _office.dispose();
    super.dispose();
  }

  /// The grant [pairing] made, once it is done.
  KnownDevice? _grantOf(OfficePairing? pairing, OfficePeer? asked) =>
      pairing?.state == PairingState.done && asked != null
      ? _net.guestGrant(asked.deviceId)
      : null;

  void _arrived() {
    final asked = _asked;
    if (asked == null || _came != null || !mounted) return;
    if (_pairing?.state != PairingState.done) return;
    final session = _share.incoming.value
        .where(
          (s) =>
              s.asGuest &&
              s.fromDevice == asked.deviceId &&
              !s.ended &&
              !_before.contains(s),
        )
        .firstOrNull;
    if (session == null) return;
    _came = session;
    _late?.cancel();
    Navigator.of(context).pop(session);
  }

  void _paired() {
    final pairing = _pairing;
    if (pairing == null || !mounted) return;
    if (pairing.state == PairingState.done) {
      _grant ??= _grantOf(pairing, _asked);
      _late?.cancel();
      _late = Timer(_wait, () {
        if (mounted && _came == null) {
          setState(() => _error = 'Paylaşan kabul etti ama belge gelmedi.');
        }
      });
      _arrived();
    }
    setState(() {});
  }

  void _join() {
    final host = _net.liveHosts.where((p) => p.deviceId == _host).firstOrNull;
    if (host == null) return;
    final pairing = _net.joinAsGuest(
      host,
      name: _name.text.trim(),
      office: _office.text.trim(),
    );
    if (pairing == null) {
      setState(
        () => _error =
            'Şu an başka bir tanışma sürüyor; biraz sonra '
            'yeniden deneyin.',
      );
      return;
    }
    _pairing?.removeListener(_paired);
    _before = Set<LiveSession>.identity()..addAll(_share.incoming.value);
    _grant = null;
    setState(() {
      _error = null;
      _asked = host;
      _pairing = pairing..addListener(_paired);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pairing = _pairing;
    final asking = pairing != null && !pairing.finished;
    final waitingDoc = pairing?.state == PairingState.done && _came == null;
    return AlertDialog(
      title: const Text('Canlı belgeye katıl'),
      content: SizedBox(
        width: 400,
        child:
            pairing == null ||
                pairing.state == PairingState.rejected ||
                pairing.state == PairingState.failed
            ? _pick(pairing)
            : waitingDoc
            ? (_error == null
                  ? _waiting('Belge açılıyor…')
                  : Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ))
            : _confirm(pairing),
      ),
      actions: [
        TextButton(
          key: const ValueKey('live-join-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        if (pairing?.state == PairingState.code)
          FilledButton(
            key: const ValueKey('live-join-confirm'),
            onPressed: pairing!.confirm,
            child: const Text('Kod aynı, onayla'),
          )
        else if (!asking && !waitingDoc)
          FilledButton(
            key: const ValueKey('live-join'),
            onPressed:
                _host != null &&
                    _name.text.trim().isNotEmpty &&
                    _net.liveHosts.any((p) => p.deviceId == _host)
                ? _join
                : null,
            child: const Text('Katıl'),
          ),
      ],
    );
  }

  Widget _confirm(OfficePairing pairing) => switch (pairing.state) {
    PairingState.connecting ||
    PairingState.waiting => _waiting('Paylaşanın cihazına bağlanılıyor…'),
    _ => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Paylaşanın ekranında da bu kod görünüyor. Aynıysa onaylayın; '
          'paylaşan da kabul edince belge açılır.',
        ),
        const SizedBox(height: 12),
        _Code(pairing.code ?? ''),
        if (pairing.state == PairingState.confirmed) ...[
          const SizedBox(height: 10),
          _waiting('Paylaşanın kabulü bekleniyor…'),
        ],
      ],
    ),
  };

  Widget _pick(OfficePairing? ended) => ListenableBuilder(
    listenable: _net,
    builder: (context, _) {
      final hosts = _net.liveHosts;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null || _net.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error ?? 'Ağa katılınamadı: ${_net.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            )
          else if (ended != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                ended.reason ??
                    (ended.state == PairingState.rejected
                        ? 'Paylaşan kabul etmedi.'
                        : 'Bağlantı kurulamadı.'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (hosts.isEmpty)
            _waiting(
              'Belge paylaşan aranıyor… Paylaşan, Canlı paylaş ▸ Misafir\'de '
              '"Misafirleri kabul et"i açmış olmalı.',
            )
          else ...[
            const Text(
              'Paylaşan',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
            RadioGroup<String>(
              groupValue: _host,
              onChanged: (v) => setState(() => _host = v),
              child: Column(
                children: [
                  for (final h in hosts)
                    RadioListTile<String>(
                      key: ValueKey('live-host-${h.deviceId}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: h.deviceId,
                      title: Text(h.name.isEmpty ? h.device : h.name),
                      subtitle: h.name.isEmpty ? null : Text(h.device),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('live-join-name'),
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Adınız'),
          ),
          TextField(
            key: const ValueKey('live-join-office'),
            controller: _office,
            decoration: const InputDecoration(labelText: 'Bürosu'),
          ),
          const SizedBox(height: 10),
          const Text(
            'Aynı Wi-Fi\'de olmanız gerekir; misafir Wi-Fi\'leri cihazları '
            'birbirinden ayırıyorsa bağlantı kurulmaz. Belge yalnız '
            'görüntülenir; paylaşım bitince bu cihazda kalmaz.',
            style: TextStyle(fontSize: 12, color: AgendaColors.muted),
          ),
        ],
      );
    },
  );
}
