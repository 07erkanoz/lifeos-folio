/// CAdES-BES (CMS Advanced Electronic Signatures - Basic Electronic Signature)
/// imza zarfı oluşturucu.
///
/// RFC 5652 (CMS SignedData) + RFC 5126/ETSI EN 319 122-1 (CAdES)
/// uyumlu detached ve attached imza üretir.
///
/// UYAP CAdES-BES (detached) ve UETS CAdES-BES (attached) formatlarını
/// destekler. Her iki format Türk hukuk sisteminde elektronik belge
/// imzalama standardıdır.
library;

import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';

// ─── OID Sabitleri ────────────────────────────────────────────────────

// ContentType OID'leri
final _oidData = ASN1ObjectIdentifier.fromComponentString(
  '1.2.840.113549.1.7.1',
);
final _oidSignedData = ASN1ObjectIdentifier.fromComponentString(
  '1.2.840.113549.1.7.2',
);

// DigestAlgorithm OID'leri
final _oidSha256 = ASN1ObjectIdentifier.fromComponentString(
  '2.16.840.1.101.3.4.2.1',
);

// SignatureAlgorithm OID'leri
final _oidSha256WithRsa = ASN1ObjectIdentifier.fromComponentString(
  '1.2.840.113549.1.1.11',
);

// Signed Attribute OID'leri
final _oidContentType = ASN1ObjectIdentifier.fromComponentString(
  '1.2.840.113549.1.9.3',
);
final _oidMessageDigest = ASN1ObjectIdentifier.fromComponentString(
  '1.2.840.113549.1.9.4',
);
final _oidSigningTime = ASN1ObjectIdentifier.fromComponentString(
  '1.2.840.113549.1.9.5',
);
final _oidSigningCertificateV2 = ASN1ObjectIdentifier.fromComponentString(
  '1.2.840.113549.1.9.16.2.47',
);

// ─── CAdES-BES Builder ───────────────────────────────────────────────

/// CAdES-BES detached imza oluşturma sonucu.
class CadesSignatureResult {
  /// DER-encoded CAdES-BES imza zarfı (ContentInfo).
  final Uint8List signatureBytes;

  /// İmzalanmış attribute'lar (doğrulama için).
  final Uint8List signedAttributesDer;

  const CadesSignatureResult({
    required this.signatureBytes,
    required this.signedAttributesDer,
  });
}

/// CAdES-BES imza zarfı oluşturma parametreleri.
class CadesSigningParams {
  /// İmzalanacak belgenin ham byte'ları.
  final Uint8List documentBytes;

  /// İmzacının X.509 sertifikası (DER-encoded).
  final Uint8List signerCertDer;

  /// Sertifikanın Issuer alanı (DER-encoded Name).
  final Uint8List issuerDer;

  /// Sertifikanın Serial Number alanı (DER-encoded INTEGER).
  final Uint8List serialNumberDer;

  /// PKCS#11 tarafından üretilen ham imza byte'ları.
  /// Bu değer [buildSignedAttributes] çağrıldıktan SONRA set edilir.
  Uint8List? signatureValue;

  /// İmzalama zamanı (varsayılan: şimdi).
  final DateTime signingTime;

  CadesSigningParams({
    required this.documentBytes,
    required this.signerCertDer,
    required this.issuerDer,
    required this.serialNumberDer,
    this.signatureValue,
    DateTime? signingTime,
  }) : signingTime = signingTime ?? DateTime.now().toUtc();
}

/// CAdES-BES imza oluşturma işlemi.
///
/// İki aşamalı süreç:
/// 1. [buildSignedAttributes] → İmzalanacak DER byte'ları döndürür
/// 2. [buildCadesSignature] → PKCS#11 imzasını alıp CAdES-BES zarfını oluşturur
class CadesBuilder {
  /// Aşama 1: SignedAttributes oluştur ve DER-encode et.
  ///
  /// Bu byte'lar PKCS#11 ile imzalanacak.
  /// CKM_RSA_PKCS mekanizması kullanılacaksa, DigestInfo+hash döndürür.
  /// CKM_SHA256_RSA_PKCS kullanılacaksa, ham signedAttrs DER döndürür.
  ///
  /// [forRawRsa]: true ise DigestInfo(SHA256(signedAttrs)) döndürür (CKM_RSA_PKCS için).
  ///              false ise ham signedAttrs DER döndürür (CKM_SHA256_RSA_PKCS için).
  static Uint8List buildSignedAttributes(
    CadesSigningParams params, {
    bool forRawRsa = false,
    bool includeSigningTime = true,
  }) {
    final signedAttrs = _buildSignedAttributesSet(
      params,
      includeSigningTime: includeSigningTime,
    );

    // DER-encode: İmzalama için SET tag (0x31) kullanılmalı
    final derBytes = signedAttrs.encodedBytes;

    if (forRawRsa) {
      // DigestInfo oluştur: SEQUENCE { AlgorithmIdentifier, OCTET STRING hash }
      final hash = sha256.convert(derBytes).bytes;
      return _buildDigestInfo(Uint8List.fromList(hash));
    }

    return Uint8List.fromList(derBytes);
  }

  /// Aşama 2: Tam CAdES-BES ContentInfo zarfını oluştur.
  ///
  /// [params]: İmzalama parametreleri (signatureValue doldurulmuş olmalı).
  /// [attached]: true ise eContent (belge verileri) imza zarfının içine dahil
  ///   edilir (CAdES-BES attached). false ise detached imza üretilir.
  ///   UETS e-İmza signatureType "C" için attached=true kullanılır.
  static Uint8List buildCadesSignature(
    CadesSigningParams params, {
    bool attached = false,
    bool includeSigningTime = true,
  }) {
    if (params.signatureValue == null) {
      throw ArgumentError(
        'signatureValue boş olamaz. Önce PKCS#11 ile imzalayın.',
      );
    }

    final signedAttrs = _buildSignedAttributesSet(
      params,
      includeSigningTime: includeSigningTime,
    );

    // ─── SignerInfo oluştur ───

    // sid: IssuerAndSerialNumber
    final issuerAndSerial = ASN1Sequence()
      ..add(_rawDerObject(params.issuerDer)) // issuer Name
      ..add(_rawDerObject(params.serialNumberDer)); // serialNumber INTEGER

    // digestAlgorithm: SHA-256 (RFC 5754: parametre ABSENT olmalı)
    final digestAlgId = ASN1Sequence()..add(_oidSha256);

    // signedAttrs [0] IMPLICIT SET OF Attribute
    // IMPLICIT tagging: SET tag (0x31) → context [0] (0xA0) ile değiştirilir.
    // Sadece SET'in value byte'ları alınır (tag+length atlanır).
    final signedAttrsImplicit = _contextTag(0, signedAttrs.valueBytes());

    // signatureAlgorithm: sha256WithRSAEncryption
    final sigAlgId = ASN1Sequence()
      ..add(_oidSha256WithRsa)
      ..add(ASN1Null());

    // signature OCTET STRING
    final signatureOctet = ASN1OctetString(params.signatureValue!);

    // SignerInfo SEQUENCE
    final signerInfo = ASN1Sequence()
      ..add(ASN1Integer.fromInt(1)) // version
      ..add(issuerAndSerial) // sid
      ..add(digestAlgId) // digestAlgorithm
      ..add(signedAttrsImplicit) // signedAttrs [0]
      ..add(sigAlgId) // signatureAlgorithm
      ..add(signatureOctet); // signature

    // ─── SignedData oluştur ───

    // digestAlgorithms SET OF AlgorithmIdentifier (RFC 5754: parametre ABSENT)
    final digestAlgs = ASN1Set()..add(ASN1Sequence()..add(_oidSha256));

    // encapContentInfo
    final encapContent = ASN1Sequence()..add(_oidData);
    if (attached) {
      // Attached: eContent [0] EXPLICIT OCTET STRING (belge verileri dahil)
      final eContent = ASN1OctetString(params.documentBytes);
      encapContent.add(_contextTag(0, eContent.encodedBytes));
    }
    // Detached: eContent yok (UYAP için)

    // certificates [0] IMPLICIT CertificateSet
    // IMPLICIT tagging: SET tag → [0] ile değiştirilir.
    // Sertifika DER doğrudan [0] içine konur (SET sarmalı yok).
    final certsImplicit = _contextTag(0, params.signerCertDer);

    // signerInfos SET OF SignerInfo
    final signerInfos = ASN1Set()..add(signerInfo);

    // SignedData SEQUENCE
    final signedData = ASN1Sequence()
      ..add(ASN1Integer.fromInt(1)) // version
      ..add(digestAlgs) // digestAlgorithms
      ..add(encapContent) // encapContentInfo
      ..add(certsImplicit) // certificates [0]
      ..add(signerInfos); // signerInfos

    // ─── ContentInfo oluştur ───

    // content [0] EXPLICIT SignedData
    final contentExplicit = _contextTag(0, signedData.encodedBytes);

    final contentInfo = ASN1Sequence()
      ..add(_oidSignedData)
      ..add(contentExplicit);

    return Uint8List.fromList(contentInfo.encodedBytes);
  }

  // ─── Private yardımcılar ────────────────────────────────────────────

  /// SignedAttributes SET oluştur (RFC 5652 Section 11.1).
  ///
  /// Zorunlu attribute'lar:
  /// 1. content-type (1.2.840.113549.1.9.3)
  /// 2. message-digest (1.2.840.113549.1.9.4)
  /// 3. signing-time (1.2.840.113549.1.9.5)
  /// 4. signing-certificate-v2 (1.2.840.113549.1.9.16.2.47) [CAdES]
  static ASN1Set _buildSignedAttributesSet(
    CadesSigningParams params, {
    bool includeSigningTime = true,
  }) {
    final attrs = ASN1Set();

    // 1. content-type = id-data
    attrs.add(_buildAttribute(_oidContentType, ASN1Set()..add(_oidData)));

    // 2. signing-time — UYAP Avukat Portal e-imza GİRİŞİ'nde bu öznitelik YOK
    //    (resmî tray'in ürettiği imza birebir incelendi: yalnız content-type,
    //    message-digest, signing-certificate-v2). e-Devlet/UETS belge imzasında
    //    ise eklenir → includeSigningTime ile ayrılır.
    if (includeSigningTime) {
      attrs.add(
        _buildAttribute(
          _oidSigningTime,
          ASN1Set()..add(ASN1UtcTime(params.signingTime)),
        ),
      );
    }

    // 3. message-digest = SHA256(document)
    final docHash = sha256.convert(params.documentBytes).bytes;
    attrs.add(
      _buildAttribute(
        _oidMessageDigest,
        ASN1Set()..add(ASN1OctetString(Uint8List.fromList(docHash))),
      ),
    );

    // 4. signing-certificate-v2 (ESSCertIDv2)
    // RFC 5035: ESSCertIDv2 ::= SEQUENCE {
    //   hashAlgorithm  AlgorithmIdentifier DEFAULT {sha-256},
    //   certHash       Hash,
    //   issuerSerial   IssuerSerial OPTIONAL
    // }
    final certHash = sha256.convert(params.signerCertDer).bytes;

    // IssuerSerial ::= SEQUENCE { issuer GeneralNames, serialNumber CertificateSerialNumber }
    // GeneralNames ::= SEQUENCE OF GeneralName
    // GeneralName ::= [4] EXPLICIT Name (directoryName)
    final directoryName = _contextTag(4, params.issuerDer);
    final generalNames = ASN1Sequence()..add(directoryName);
    final issuerSerial = ASN1Sequence()
      ..add(generalNames)
      ..add(_rawDerObject(params.serialNumberDer));

    // ESSCertIDv2 - hashAlgorithm DEFAULT sha-256 olduğu için atlanabilir
    final essCertIdV2 = ASN1Sequence()
      ..add(ASN1OctetString(Uint8List.fromList(certHash))) // certHash
      ..add(issuerSerial); // issuerSerial

    // SigningCertificateV2 ::= SEQUENCE { certs SEQUENCE OF ESSCertIDv2 }
    final signingCertV2 = ASN1Sequence()..add(ASN1Sequence()..add(essCertIdV2));

    attrs.add(
      _buildAttribute(_oidSigningCertificateV2, ASN1Set()..add(signingCertV2)),
    );

    // DER SET OF must be sorted lexicographically by the complete encoding.
    final sorted = attrs.elements.toList()
      ..sort((a, b) {
        final left = a.encodedBytes;
        final right = b.encodedBytes;
        for (var i = 0; i < left.length && i < right.length; i++) {
          if (left[i] != right[i]) return left[i].compareTo(right[i]);
        }
        return left.length.compareTo(right.length);
      });
    return ASN1Set()..elements.addAll(sorted);
  }

  /// CMS Attribute yapısı oluştur.
  /// Attribute ::= SEQUENCE { attrType OBJECT IDENTIFIER, attrValues SET OF ANY }
  static ASN1Sequence _buildAttribute(
    ASN1ObjectIdentifier oid,
    ASN1Set values,
  ) {
    return ASN1Sequence()
      ..add(oid)
      ..add(values);
  }

  /// DigestInfo (PKCS#1 v1.5) yapısı oluştur.
  /// DigestInfo ::= SEQUENCE { digestAlgorithm AlgorithmIdentifier, digest OCTET STRING }
  static Uint8List _buildDigestInfo(Uint8List hash) {
    final digestInfo = ASN1Sequence()
      ..add(
        ASN1Sequence()
          ..add(_oidSha256)
          ..add(ASN1Null()),
      )
      ..add(ASN1OctetString(hash));
    return Uint8List.fromList(digestInfo.encodedBytes);
  }

  /// Ham DER bytes'ı ASN1Object olarak sar (mevcut encoding'i koru).
  static ASN1Object _rawDerObject(Uint8List derBytes) {
    final parser = ASN1Parser(derBytes);
    return parser.nextObject();
  }

  /// Context-specific tag ile sar.
  /// [tagNumber]: 0, 1, 2, ... (tag numarası)
  /// [content]: İçerik DER bytes'ı
  static ASN1Object _contextTag(int tagNumber, List<int> content) {
    // Context-specific, constructed: 0xA0 | tagNumber
    final tag = 0xA0 | tagNumber;
    final lengthBytes = ASN1Object.encodeLength(content.length);
    final encoded = <int>[tag, ...lengthBytes, ...content];
    final parser = ASN1Parser(Uint8List.fromList(encoded));
    return parser.nextObject();
  }
}
