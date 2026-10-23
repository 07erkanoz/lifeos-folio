import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/editor/lawyer_profile.dart';
import '../../services/live/live_share.dart';
import '../../services/office/office_network.dart';
import '../../services/office/office_pairing.dart';
import '../agenda/agenda_page.dart' show AgendaColors;

/// The code a guest's pairing makes, large, as both screens show it.
class LiveCode extends StatelessWidget {
  const LiveCode(this.code, {super.key});

  final String code;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('live-guest-code'),
    padding: const EdgeInsets.symmetric(vertical: 12),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      code,
      style: const TextStyle(
        fontSize: 28,
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

/// The invitation's head: who shares what.
Widget _asks(BuildContext context, String who, String title) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Icon(Icons.cast_outlined, color: Theme.of(context).colorScheme.primary),
    const SizedBox(width: 12),
    Expanded(
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: who,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: title.isEmpty
                  ? ' bir belgeyi sizinle canlı paylaşıyor.'
                  : ' “$title” belgesini sizinle canlı paylaşıyor.',
            ),
          ],
        ),
      ),
    ),
  ],
);

/// Takes a dialog away, whether it is in front or not.
void _closeRoute(BuildContext context, [Object? result]) {
  final route = ModalRoute.of(context);
  if (route == null || !route.isActive) return;
  if (route.isCurrent) {
    Navigator.of(context).pop(result);
  } else {
    Navigator.of(context).removeRoute(route);
  }
}

/// A document shared live with this Folio by one of the person's own
/// devices or a colleague of the office: joined with one tap, the
/// document opening at once; or turned down.
class LiveInviteDialog extends StatefulWidget {
  const LiveInviteDialog({super.key, required this.session});

  final LiveSession session;

  /// Whether the user joined.
  static Future<bool> show(BuildContext context, LiveSession session) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => LiveInviteDialog(session: session),
      ) ??
      false;

  @override
  State<LiveInviteDialog> createState() => _LiveInviteDialogState();
}

class _LiveInviteDialogState extends State<LiveInviteDialog> {
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
  }

  /// The sharing ended, or the asking ran out, before it was answered.
  void _changed() {
    if (widget.session.ended && mounted) _closeRoute(context, false);
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Canlı paylaşım daveti'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _asks(context, widget.session.from, widget.session.title),
          const SizedBox(height: 12),
          Text(
            widget.session.right == LiveRight.edit
                ? 'Belgeyi görürsünüz; paylaşan kalemi verince siz de '
                      'yazabilirsiniz. Paylaşım bitince belge bu cihazda kalmaz.'
                : 'Belgeyi yalnız görürsünüz. Paylaşım bitince belge bu '
                      'cihazda kalmaz.',
            style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('live-invite-decline'),
        onPressed: () {
          unawaited(widget.session.decline());
          Navigator.of(context).pop(false);
        },
        child: const Text('Reddet'),
      ),
      FilledButton(
        key: const ValueKey('live-invite-join'),
        onPressed: () {
          widget.session.accept();
          Navigator.of(context).pop(true);
        },
        child: const Text('Katıl'),
      ),
    ],
  );
}

/// A Folio of no office's nor the person's inviting this one to the
/// document it shares: paired with at once, so that the code both
/// screens show is there to see, and joined with one tap. Gives the
/// session once the document comes.
class LiveGuestInviteDialog extends StatefulWidget {
  const LiveGuestInviteDialog({
    super.key,
    required this.invite,
    this.network,
    this.share,
  });

  final GuestInvite invite;
  final OfficeNetwork? network;
  final LiveShare? share;

  static Future<LiveSession?> show(
    BuildContext context,
    GuestInvite invite, {
    OfficeNetwork? network,
    LiveShare? share,
  }) => showDialog<LiveSession>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        LiveGuestInviteDialog(invite: invite, network: network, share: share),
  );

  @override
  State<LiveGuestInviteDialog> createState() => _LiveGuestInviteDialogState();
}

class _LiveGuestInviteDialogState extends State<LiveGuestInviteDialog> {
  OfficeNetwork get _net => widget.network ?? OfficeNetwork.instance;
  LiveShare get _share => widget.share ?? LiveShare.instance;

  OfficePairing? _pairing;
  LiveSession? _came;
  String? _error;
  bool _joined = false;
  Timer? _late;

  /// The sessions there before this joining: none of them its answer.
  Set<LiveSession> _before = {};

  /// How long the document may take once joined.
  static const _wait = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _share.incoming.addListener(_arrived);
    _net.liveInvite.addListener(_withdrawn);
    unawaited(_start());
  }

  /// Turned off here meanwhile: nothing more asked.
  void _withdrawn() {
    if (_net.liveInvite.value == null && !_joined && mounted) {
      _closeRoute(context);
    }
  }

  /// Paired with the inviting Folio by the guest's name and office, as
  /// the profile has them.
  Future<void> _start() async {
    var name = '', office = '';
    try {
      final p = await LawyerProfile.load();
      name = p.lawyer?.titled ?? '';
      office = p.officeName.trim();
    } catch (_) {}
    if (!mounted) return;
    final pairing = _net.joinAsGuest(
      widget.invite.from,
      name: name,
      office: office,
    );
    if (pairing == null) {
      setState(() => _error = 'Şu an başka bir bağlantı kuruluyor.');
      return;
    }
    _before = Set<LiveSession>.identity()..addAll(_share.incoming.value);
    setState(() => _pairing = pairing..addListener(_paired));
  }

  void _paired() {
    final pairing = _pairing;
    if (pairing == null || !mounted) return;
    // The one paired with is the one that invited, by its key's id.
    final other = pairing.other?.deviceId;
    if (pairing.code != null &&
        other != widget.invite.from.deviceId &&
        !pairing.finished) {
      pairing.reject();
      setState(() => _error = 'Davet eden cihaz doğrulanamadı.');
      return;
    }
    if (pairing.state == PairingState.done) {
      _late ??= Timer(_wait, () {
        if (mounted && _came == null) {
          setState(() => _error = 'Paylaşan kabul etti ama belge gelmedi.');
        }
      });
      _arrived();
    }
    setState(() {});
  }

  void _arrived() {
    if (_came != null || !mounted) return;
    if (_pairing?.state != PairingState.done) return;
    final session = _share.incoming.value
        .where(
          (s) =>
              s.fromDevice == widget.invite.from.deviceId &&
              !s.ended &&
              !_before.contains(s),
        )
        .firstOrNull;
    if (session == null) return;
    _came = session;
    _late?.cancel();
    // Joined already: by the invitation's answer.
    session.accept();
    Navigator.of(context).pop(session);
  }

  void _join() {
    final pairing = _pairing;
    if (pairing == null || pairing.state != PairingState.code) return;
    setState(() => _joined = true);
    pairing.confirm();
  }

  @override
  void dispose() {
    _late?.cancel();
    _share.incoming.removeListener(_arrived);
    _net.liveInvite.removeListener(_withdrawn);
    final pairing = _pairing;
    pairing?.removeListener(_paired);
    if (_came == null) {
      // Not joined after all: nothing of the host kept.
      if (pairing != null && !pairing.finished) pairing.reject();
      final grant = pairing?.state == PairingState.done
          ? _net.guestGrant(widget.invite.from.deviceId)
          : null;
      if (grant != null) {
        unawaited(_net.forgetGuest(widget.invite.from.deviceId, grant));
      }
    }
    if (identical(_net.liveInvite.value, widget.invite)) {
      _net.liveInvite.value = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pairing = _pairing;
    final state = pairing?.state;
    final failed =
        _error != null ||
        state == PairingState.failed ||
        state == PairingState.rejected;
    final who = widget.invite.name.isNotEmpty
        ? widget.invite.name
        : (widget.invite.from.device.isNotEmpty
              ? widget.invite.from.device
              : 'Bir Folio kullanıcısı');
    final code = pairing?.code;
    return AlertDialog(
      title: const Text('Canlı paylaşım daveti'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _asks(context, who, widget.invite.title),
            const SizedBox(height: 14),
            if (failed)
              Text(
                _error ??
                    (state == PairingState.rejected
                        ? 'Paylaşan daveti geri aldı.'
                        : pairing?.reason ?? 'Bağlantı kurulamadı.'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (_joined)
              _waiting('Belge açılıyor…')
            else if (code == null)
              _waiting('Paylaşanın cihazına bağlanılıyor…')
            else ...[
              LiveCode(code),
              const SizedBox(height: 8),
              Text(
                'Paylaşanın ekranında da bu kod görünür. Belge yalnız bu '
                'paylaşım sürerken görünür; paylaşım bitince bu cihazda '
                'kalmaz.',
                style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (failed)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tamam'),
          )
        else ...[
          TextButton(
            key: const ValueKey('live-invite-decline'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_joined ? 'Vazgeç' : 'Reddet'),
          ),
          if (!_joined)
            FilledButton(
              key: const ValueKey('live-invite-join'),
              onPressed: state == PairingState.code ? _join : null,
              child: const Text('Katıl'),
            ),
        ],
      ],
    );
  }
}
