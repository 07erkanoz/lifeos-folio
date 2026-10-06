import 'dart:typed_data';

import 'uets_api.dart';

/// Logs into UETS with the card (UYGULAMAPLANI P05): the TC number read
/// from the certificate, the challenge UETS gives, the card's CAdES-BES
/// signature of it (inside the signature for type "C", beside it for "S"),
/// and the session UETS opens. Nothing of UYAP or of Adalet E-İmza is used;
/// [sign] is Folio's own card signer.
Future<UetsSession> loginWithCard(
  UetsApi api, {
  required String? tckn,
  required Future<Uint8List> Function(Uint8List data, {required bool attached})
  sign,
  void Function(String stage)? onProgress,
}) async {
  final tc = (tckn ?? '').trim();
  if (!RegExp(r'^\d{11}$').hasMatch(tc)) {
    throw StateError(
      'Sertifikada TC kimlik numarası bulunamadı; UETS kartla girişi için '
      'kişisel e-imza sertifikası gerekir.',
    );
  }
  onProgress?.call('UETS işlemi açılıyor');
  final challenge = await api.startCard(tc);
  onProgress?.call(
    challenge.displayText.isEmpty
        ? 'Kartla imzalanıyor'
        : 'İmzalanıyor: ${challenge.displayText}',
  );
  final signature = await sign(challenge.data, attached: challenge.type != 'S');
  onProgress?.call('UETS oturumu açılıyor');
  return api.finishCard(challenge, signature);
}
