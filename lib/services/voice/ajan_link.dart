import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ai/ai_refresh.dart';
import '../portal/portal_sync.dart';
import '../signing/udf_signing_service.dart';
import '../uets/uets_api.dart';
import '../uets/uets_card_login.dart';
import '../uyap/uyap_web_service.dart';

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
      switch (ask.need) {
        case UyapNeed.web:
          PortalSync.begin();
          await UyapWebService.instance.connect(pin, onProgress: progress);
        case UyapNeed.uets:
          await _uets(pin, progress);
      }
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
