import '../editor/document_history.dart';

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:asn1lib/asn1lib.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

import 'cades_builder.dart';
import 'x509_parser.dart';
import 'pkcs11/pkcs11_bindings.dart';
import 'pkcs11/pkcs11_discovery.dart';
import 'pkcs11/pkcs11_session.dart';

class SigningCard {
  final Pkcs11ModuleInfo module;
  final TokenInfo token;
  const SigningCard(this.module, this.token);
  String get label => '${token.label} · ${module.name}';
}

class SigningCertificate {
  final CertificateInfo certificate;
  final X509CertInfo info;
  const SigningCertificate(this.certificate, this.info);
}

/// No card access at application startup. Every card operation runs in a
/// short-lived isolate, on an explicit action. PINs are never persisted/logged.
class UdfSigningService {
  // Isolates share native-library globals. Never overlap initialize/finalize
  // across card operations, even when different dialogs/service instances exist.
  static Future<void> _cardQueue = Future<void>.value();
  static Future<R> _exclusive<A, R>(ComputeCallback<A, R> operation, A args) {
    if (!(Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      return Future<R>.error(
        UnsupportedError('Mobil cihazlarda elektronik imzalama kullanılmaz.'),
      );
    }
    final result = _cardQueue.then((_) => compute(operation, args));
    _cardQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<List<SigningCard>> cards({String? driver}) =>
      _exclusive(_cards, driver);
  Future<List<SigningCertificate>> certificates(SigningCard card, String pin) =>
      _exclusive(_certificates, (card: card, pin: pin));
  Future<String> sign(
    String path,
    SigningCard card,
    SigningCertificate certificate,
    String pin,
  ) async {
    final original = await File(path).readAsBytes();
    Future<void> keep(List<int> bytes, String kind) =>
        DocumentHistory.instance.capture(
          document: DocumentHistory.documentKey(path),
          name: p.basename(path),
          sourcePath: path,
          format: 'udf',
          bytes: bytes,
          kind: kind,
        );
    await keep(original, 'before-sign');
    final signed = await _exclusive(_sign, (
      path: path,
      original: original,
      card: card,
      certificate: certificate,
      pin: pin,
    ));
    // The signed file in the history too, so that saving over it later —
    // which drops the signature — can always be undone.
    try {
      await keep(await File(signed).readAsBytes(), 'signed');
    } catch (_) {
      // The signature is on disk; the history copy is a convenience.
    }
    return signed;
  }

  /// Publish a complete signed archive at the original path. The original
  /// bytes are checked immediately before rename, after card access has ended.
  static String saveSigned(String path, Uint8List original, Uint8List output) {
    final target = File(path);
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError(
        'İmzalanacak dosyanın konumu değişti. Belgeyi yeniden açın.',
      );
    }
    final stage = target.parent.createTempSync('.folio-sign-');
    try {
      final pending = File(p.join(stage.path, 'signed.udf'));
      pending.writeAsBytesSync(output, flush: true);
      if (!listEquals(target.readAsBytesSync(), original)) {
        throw StateError(
          'Belge imzalama sırasında değişti. Dosya kaydedilmedi; güncel belgeyi yeniden açın.',
        );
      }
      if (!Platform.isWindows) {
        final mode = (target.statSync().mode & 0x1ff).toRadixString(8);
        final result = Process.runSync('chmod', [mode, pending.path]);
        if (result.exitCode != 0) {
          throw const FileSystemException('Dosya izinleri korunamadı.');
        }
      }
      pending.renameSync(target.path);
      return target.path;
    } finally {
      stage.deleteSync(recursive: true);
    }
  }

  /// Checks the produced RSA signature against the selected certificate before
  /// saving. This is signature integrity, not trust-chain/revocation validation.
  static bool verifyRsa(
    Uint8List certificate,
    Uint8List signed,
    Uint8List signature,
  ) {
    try {
      final cert = ASN1Parser(certificate).nextObject() as ASN1Sequence;
      final tbs = cert.elements.first as ASN1Sequence;
      final version = tbs.elements.first.tag == 0xa0 ? 1 : 0;
      final spki = tbs.elements[version + 5] as ASN1Sequence;
      final algorithm = spki.elements.first as ASN1Sequence;
      if ((algorithm.elements.first as ASN1ObjectIdentifier).identifier !=
          '1.2.840.113549.1.1.1') {
        return false;
      }
      final bits = spki.elements[1] as ASN1BitString;
      final key =
          ASN1Parser(Uint8List.fromList(bits.valueBytes().sublist(1)))
                  .nextObject()
              as ASN1Sequence;
      final publicKey = RSAPublicKey(
        (key.elements[0] as ASN1Integer).valueAsBigInteger,
        (key.elements[1] as ASN1Integer).valueAsBigInteger,
      );
      final verifier = RSASigner(SHA256Digest(), '0609608648016503040201')
        ..init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
      return verifier.verifySignature(signed, RSASignature(signature));
    } catch (_) {
      return false;
    }
  }

  /// Whether [udf] already carries a signature.
  static bool isSigned(List<int> udf) {
    try {
      return ZipDecoder().decodeBytes(udf).any(
        (e) => e.isFile && e.name.toLowerCase().endsWith('.sgn'),
      );
    } catch (_) {
      return false;
    }
  }

  static Uint8List embed(Uint8List original, Uint8List signature) {
    final archive = ZipDecoder().decodeBytes(original);
    if (archive.any((e) => e.isFile && e.name.toLowerCase().endsWith('.sgn'))) {
      throw StateError(
        'Bu UDF zaten imzalı. Yeni imza için düzenlediğiniz imzasız kopyayı seçin.',
      );
    }
    if (signature.isEmpty || archive.findFile('content.xml') == null) {
      throw const FormatException('UDF veya imza verisi eksik.');
    }
    archive.addFile(ArchiveFile('sign.sgn', signature.length, signature));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}

List<SigningCard> _cards(String? driver) {
  if (!(Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    throw UnsupportedError(
      'Akıllı kartla imzalama masaüstünde PKCS#11 sürücüsü gerektirir.',
    );
  }
  final cards = <SigningCard>[];
  for (final module in detectInstalledModules(
    extraPaths: driver == null || driver.isEmpty ? null : [driver],
  )) {
    final session = Pkcs11Session(module.path);
    try {
      session.initialize();
      cards.addAll(session.getTokens().map((t) => SigningCard(module, t)));
    } catch (_) {
      /* A stale or wrong-architecture driver is skipped. */
    } finally {
      session.dispose();
    }
  }
  return cards;
}

List<SigningCertificate> _certificates(({SigningCard card, String pin}) args) {
  final session = Pkcs11Session(args.card.module.path);
  try {
    session.initialize();
    session.openSession(args.card.token.slotId);
    session.login(args.pin);
    return session
        .getCertificates()
        .map((cert) {
          final info = parseX509Certificate(cert.derBytes);
          return info == null ? null : SigningCertificate(cert, info);
        })
        .whereType<SigningCertificate>()
        .toList();
  } on Pkcs11Exception catch (e) {
    throw StateError(_error(e));
  } finally {
    session.dispose();
  }
}

String _sign(
  ({
    String path,
    Uint8List original,
    SigningCard card,
    SigningCertificate certificate,
    String pin,
  })
  args,
) {
  if (!args.certificate.info.isValid) {
    throw StateError('Sertifikanın geçerlilik tarihleri uygun değil.');
  }
  final original = args.original;
  if (!listEquals(File(args.path).readAsBytesSync(), original)) {
    throw StateError('Belge değişti. İmzalamadan önce yeniden açın.');
  }
  final archive = ZipDecoder().decodeBytes(original);
  if (archive.any((e) => e.isFile && e.name.toLowerCase().endsWith('.sgn'))) {
    throw StateError('Belge zaten imzalı; imzasız kopyayı seçin.');
  }
  final xml = archive.findFile('content.xml');
  if (xml == null) {
    throw const FormatException('UDF içinde content.xml bulunamadı.');
  }
  final cert = args.certificate.certificate;
  final params = CadesSigningParams(
    documentBytes: Uint8List.fromList(xml.content),
    signerCertDer: cert.derBytes,
    issuerDer: args.certificate.info.issuerDer,
    serialNumberDer: args.certificate.info.serialNumberDer,
    signingTime: DateTime.now().toUtc(),
  );
  final signed = CadesBuilder.buildSignedAttributes(params);
  final session = Pkcs11Session(args.card.module.path);
  try {
    session.initialize();
    session.openSession(args.card.token.slotId);
    session.login(args.pin);
    try {
      params.signatureValue = session.sign(signed, cert.keyId);
    } on Pkcs11Exception catch (e) {
      if (e.returnValue != CKR_MECHANISM_INVALID) rethrow;
      params.signatureValue = session.signRaw(
        CadesBuilder.buildSignedAttributes(params, forRawRsa: true),
        cert.keyId,
      );
    }
    session.dispose();
    if (!UdfSigningService.verifyRsa(
      cert.derBytes,
      signed,
      params.signatureValue!,
    )) {
      throw StateError(
        'Üretilen imza seçili sertifikayla doğrulanamadı. Dosya kaydedilmedi.',
      );
    }
    final output = UdfSigningService.embed(
      original,
      CadesBuilder.buildCadesSignature(params),
    );
    return UdfSigningService.saveSigned(args.path, original, output);
  } on Pkcs11Exception catch (e) {
    throw StateError(_error(e));
  } finally {
    session.dispose();
  }
}

String _error(Pkcs11Exception e) => switch (e.returnValue) {
  CKR_PIN_INCORRECT => 'PIN hatalı. Otomatik tekrar denenmedi.',
  CKR_PIN_LOCKED => 'Kart PIN’i kilitli. Kart sağlayıcınıza başvurun.',
  CKR_TOKEN_NOT_PRESENT ||
  CKR_DEVICE_REMOVED => 'E-imza kartı çıkarıldı veya bulunamadı.',
  CKR_KEY_HANDLE_INVALID =>
    'Seçili sertifikaya ait imzalama anahtarı bulunamadı.',
  _ =>
    'Kart işlemi tamamlanamadı (${e.rvName}). Diğer imza uygulamalarının kartı kullanmadığını kontrol edin.',
};
