import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ai/ai_refresh.dart';
import '../portal/portal_sync.dart';
import '../signing/udf_signing_service.dart';
import '../uets/uets_api.dart';
import '../uets/uets_card_login.dart';
import '../uyap/uyap_web_service.dart';
import 'ajan_bridge.dart';

/// A connection Folio Ajan asked for on its own screen: only the PIN of
/// the e-signature card, for the UYAP lawyer portal or for UETS. The full
/// connection dialog, with every way in, was too much in the middle of a
/// conversation (22 Kasım 2026).
class AjanLinkAsk {
  AjanLinkAsk(this.need, this.why);

  final UyapNeed need;
  final String why;
  final _done = Completer<bool>();
  bool busy = false;
  String? stage;
  String? error;

  String get title => switch (need) {
    UyapNeed.web => 'UYAP Avukat Portalı’na bağlan',
    UyapNeed.uets => 'UETS’e bağlan',
  };
}

/// What Folio Ajan's screen shows of [AjanLinkAsk], and does with the PIN.
class AjanLinks extends ChangeNotifier {
  AjanLinks._();
  static final instance = AjanLinks._();

  /// Folio Ajan's screen is on: the PIN is asked there.
  int shown = 0;
  AjanLinkAsk? asking;

  /// Who connects with the PIN: [link] here; in Folio Ajan's program the
  /// open Folio, which holds UYAP's and UETS's sessions ([AjanPinRelay]).
  Future<void> Function(
    UyapNeed need,
    String pin,
    void Function(String stage) progress,
  )?
  via;

  /// What was asked, ended from outside (Folio no longer waits for it).
  void end(bool ok) => _end(ok);

  /// The lawyer's answer to [need]; true once connected.
  Future<bool> request(UyapNeed need, String why) {
    final open = asking;
    if (open != null && open.need == need) return open._done.future;
    open?._done.complete(false);
    final ask = asking = AjanLinkAsk(need, why);
    notifyListeners();
    return ask._done.future;
  }

  void cancel() => _end(false);

  void _end(bool ok) {
    final ask = asking;
    if (ask == null) return;
    asking = null;
    if (!ask._done.isCompleted) ask._done.complete(ok);
    notifyListeners();
  }

  /// Connects with the card in the reader and its [pin].
  Future<void> connect(String pin) async {
    final ask = asking;
    if (ask == null || ask.busy) return;
    if (pin.isEmpty) {
      ask.error = 'E-imza PIN kodunu girin.';
      notifyListeners();
      return;
    }
    ask
      ..busy = true
      ..error = null
      ..stage = 'Bağlantı hazırlanıyor';
    notifyListeners();
    void progress(String stage) {
      ask.stage = stage;
      notifyListeners();
    }

    try {
      await (via ?? link)(ask.need, pin, progress);
      if (identical(asking, ask)) _end(true);
    } catch (e) {
      ask.error = '$e'
          .replaceFirst('Bad state: ', '')
          .replaceFirst('Exception: ', '');
    } finally {
      ask
        ..busy = false
        ..stage = null;
      notifyListeners();
    }
  }

  /// Connects [need] here, with the card in the reader and its [pin].
  static Future<void> link(
    UyapNeed need,
    String pin,
    void Function(String stage) progress,
  ) async {
    switch (need) {
      case UyapNeed.web:
        PortalSync.begin();
        await UyapWebService.instance.connect(pin, onProgress: progress);
      case UyapNeed.uets:
        await _uets(pin, progress);
    }
  }

  static Future<void> _uets(String pin, void Function(String) progress) async {
    final service = UdfSigningService();
    progress('Takılı kart aranıyor');
    final cards = await service.cards();
    if (cards.isEmpty) {
      throw StateError(
        'Kart bulunamadı. E-imza kartınızı takıp yeniden '
        'deneyin.',
      );
    }
    final card = cards.first;
    progress('Sertifika okunuyor');
    final certificates = await service.certificates(card, pin);
    final valid = certificates.where((c) => c.info.isValid).toList();
    if (valid.isEmpty) {
      throw StateError('Kartta geçerli bir sertifika bulunamadı.');
    }
    final chosen = valid.firstWhere(
      (c) => _tcOf(c) != null,
      orElse: () => valid.first,
    );
    await loginWithCard(
      UetsApi.instance,
      tckn: _tcOf(chosen),
      sign: (data, {required attached}) =>
          service.signBytes(data, card, chosen, pin, attached: attached),
      onProgress: progress,
    );
  }

  static String? _tcOf(SigningCertificate c) =>
      RegExp(r'\d{11}').firstMatch(c.info.subjectSerialNumber ?? '')?.group(0);
}

/// The two sides of a PIN asked on Folio Ajan's screen for the open Folio
/// (two programs since 22 Kasım 2026). Folio asks ([ask]); Folio Ajan
/// shows its PIN box ([AjanLinks]) and sends the PIN back ([sendPin]);
/// Folio connects with it ([heardInFolio]) and says how it went
/// ([heardInAjan]). The PIN goes over the programs' loopback socket only.
class AjanPinRelay {
  AjanPinRelay._();
  static final instance = AjanPinRelay._();

  // Folio's side.
  Completer<bool>? _waiting;
  UyapNeed? _need;
  bool _connecting = false;

  /// The lawyer's answer on Folio Ajan's screen; null when it is not on
  /// screen, and Folio asks in its own window.
  Future<bool?> ask(UyapNeed need, String why) async {
    if (!await AjanBridge.shown()) return null;
    final open = _waiting;
    if (open != null && !open.isCompleted) {
      if (_need == need) return open.future;
      open.complete(false);
    }
    final waiting = _waiting = Completer<bool>();
    _need = need;
    if (!await AjanBridge.toAjan([AjanBridge.askLink, need.name, why])) {
      _waiting = null;
      return null;
    }
    return waiting.future;
  }

  /// What Folio Ajan said, in Folio; true when it was this relay's.
  bool heardInFolio(List<String> args) {
    if (args.isEmpty) return false;
    switch (args.first) {
      case AjanBridge.pin when args.length >= 3:
        unawaited(_connect(UyapNeed.values.byName(args[1]), args[2]));
        return true;
      case AjanBridge.pinCancel:
        final waiting = _waiting;
        _waiting = null;
        if (waiting != null && !waiting.isCompleted) waiting.complete(false);
        return true;
    }
    return false;
  }

  Future<void> _connect(UyapNeed need, String pin) async {
    if (_connecting) return;
    _connecting = true;
    try {
      await AjanLinks.link(need, pin, (stage) {
        unawaited(AjanBridge.toAjan([AjanBridge.linkStage, stage]));
      });
      await AjanBridge.toAjan([AjanBridge.linkResult, 'tamam']);
      final waiting = _waiting;
      _waiting = null;
      if (waiting != null && !waiting.isCompleted) waiting.complete(true);
    } catch (e) {
      // The box stays on Folio Ajan's screen, for the PIN again.
      await AjanBridge.toAjan([AjanBridge.linkResult, 'hata', _plain(e)]);
    } finally {
      _connecting = false;
    }
  }

  static String _plain(Object e) =>
      '$e'.replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');

  // Folio Ajan's side.
  Completer<void>? _sent;
  void Function(String stage)? _progress;

  /// Set in Folio Ajan's program: its PIN box connects through Folio.
  void startInAjan() {
    AjanLinks.instance.via = sendPin;
  }

  /// The PIN to the open Folio, and Folio's answer awaited.
  Future<void> sendPin(
    UyapNeed need,
    String pin,
    void Function(String stage) progress,
  ) async {
    final sent = _sent = Completer<void>();
    _progress = progress;
    if (!await AjanBridge.toFolio([AjanBridge.pin, need.name, pin])) {
      _sent = null;
      throw StateError(
        'LifeOS Folio açık değil; Folio’yu açıp yeniden deneyin.',
      );
    }
    try {
      await sent.future.timeout(const Duration(minutes: 3));
    } on TimeoutException {
      throw StateError('Folio bağlantıyı zamanında bitiremedi.');
    } finally {
      _sent = null;
      _progress = null;
    }
  }

  /// What Folio said, in Folio Ajan; true when it was this relay's.
  bool heardInAjan(List<String> args) {
    if (args.isEmpty) return false;
    switch (args.first) {
      case AjanBridge.askLink when args.length >= 2:
        final need = UyapNeed.values.byName(args[1]);
        final why = args.length > 2 ? args[2] : '';
        unawaited(
          AjanLinks.instance.request(need, why).then((ok) {
            if (!ok) unawaited(AjanBridge.toFolio([AjanBridge.pinCancel]));
          }),
        );
        return true;
      case AjanBridge.linkStage when args.length >= 2:
        _progress?.call(args[1]);
        return true;
      case AjanBridge.linkResult when args.length >= 2:
        final sent = _sent;
        if (sent != null && !sent.isCompleted) {
          if (args[1] == 'tamam') {
            sent.complete();
          } else {
            sent.completeError(
              StateError(args.length > 2 ? args[2] : 'Bağlanılamadı.'),
            );
          }
        }
        return true;
      case AjanBridge.linkGone:
        AjanLinks.instance.end(false);
        return true;
    }
    return false;
  }
}
