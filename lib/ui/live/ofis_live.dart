import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/live/live_links.dart';
import '../../services/live/live_owner.dart';
import '../../services/live/live_share.dart';
import '../../services/office/office_network.dart';
import '../office/office_pairing_dialog.dart';
import 'live_document_page.dart';
import 'live_invite_dialogs.dart';
import 'live_remote_dialogs.dart';

/// Live documents in LifeOS Ofis, as Folio's home page has them: this
/// window on the network (if no other window of Ofis is), a document
/// shared with it asked about and opened, an invitation's code joined
/// with. Ofis has no office of its own: it shares with devices nearby as
/// a guest does, and with anyone by a code.
class OfisLive {
  OfisLive(this._context);

  /// The navigator's context, once there is one.
  final BuildContext? Function() _context;

  bool _started = false;

  /// On the network from now on; false when another window holds it.
  Future<bool> start() async {
    if (_started) return true;
    if (!await LiveOwner.claim()) return false;
    _started = true;
    final net = OfficeNetwork.instance;
    unawaited(net.resume());
    net.incoming.addListener(_pairingAsked);
    LiveShare.instance.listen(net);
    LiveShare.instance.incoming.addListener(_liveCame);
    LiveLinks.came.addListener(_linkCame);
    net.liveInvite.addListener(_guestInvited);
    // A link Ofis was opened with, once there is a page to ask on.
    WidgetsBinding.instance.addPostFrameCallback((_) => _linkCame());
    return true;
  }

  void dispose() {
    if (!_started) return;
    final net = OfficeNetwork.instance;
    net.incoming.removeListener(_pairingAsked);
    LiveShare.instance.incoming.removeListener(_liveCame);
    LiveLinks.came.removeListener(_linkCame);
    net.liveInvite.removeListener(_guestInvited);
  }

  final _told = <LiveSession>{};

  void _liveCame() {
    for (final session in LiveShare.instance.incoming.value) {
      final context = _context();
      if (session.asGuest || context == null || !_told.add(session)) continue;
      unawaited(() async {
        final joined = await LiveInviteDialog.show(context, session);
        if (joined && context.mounted && !session.ended) {
          await LiveDocumentPage.open(context, session);
        }
      }());
    }
    _told.removeWhere((s) => s.ended);
  }

  /// A document shared from anywhere, joined by the code its sharer sent.
  Future<void> join({String? code, bool start = false}) async {
    final context = _context();
    if (context == null) return;
    if (!await this.start()) return;
    if (!context.mounted) return;
    final session = await RemoteJoinDialog.show(
      context,
      code: code,
      start: start,
    );
    if (session != null && context.mounted && !session.ended) {
      await LiveDocumentPage.open(context, session);
    }
  }

  int _linkTaken = 0;

  void _linkCame() {
    final came = LiveLinks.came.value;
    if (came == null || came.n == _linkTaken) return;
    _linkTaken = came.n;
    unawaited(join(code: came.code));
  }

  GuestInvite? _guestTold;

  void _guestInvited() {
    final invite = OfficeNetwork.instance.liveInvite.value;
    final context = _context();
    if (invite == null || context == null || identical(invite, _guestTold)) {
      return;
    }
    _guestTold = invite;
    unawaited(() async {
      final session = await LiveGuestInviteDialog.show(context, invite);
      if (session != null && context.mounted && !session.ended) {
        await LiveDocumentPage.open(context, session);
      }
    }());
  }

  void _pairingAsked() {
    final incoming = OfficeNetwork.instance.incoming;
    final pairing = incoming.value;
    final context = _context();
    if (pairing == null || context == null) return;
    incoming.value = null;
    if (pairing.finished) return;
    unawaited(OfficePairingDialog.show(context, pairing));
  }
}
