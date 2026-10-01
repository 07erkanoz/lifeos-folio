/// PKCS#11 üst seviye oturum yönetimi.
///
/// [Pkcs11Module] (low-level FFI) üzerine kurulan güvenli, kullanıcı dostu API.
/// Token algılama, PIN ile giriş, sertifika okuma ve imzalama işlemleri.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'pkcs11_bindings.dart';

// ─── Veri Modelleri ───────────────────────────────────────────────────

/// Token (akıllı kart / USB token) bilgisi.
class TokenInfo {
  final int slotId;
  final String label;
  final String manufacturer;
  final String model;
  final String serialNumber;
  final bool loginRequired;
  final bool hasProtectedAuthPath;
  final int minPinLen;
  final int maxPinLen;

  const TokenInfo({
    required this.slotId,
    required this.label,
    required this.manufacturer,
    required this.model,
    required this.serialNumber,
    required this.loginRequired,
    required this.hasProtectedAuthPath,
    required this.minPinLen,
    required this.maxPinLen,
  });

  @override
  String toString() => '$label (SN: $serialNumber) [slot $slotId]';
}

/// X.509 sertifika bilgisi.
class CertificateInfo {
  final Uint8List keyId;
  final Uint8List derBytes;
  final String label;
  final Uint8List issuerDer;
  final Uint8List serialNumberDer;
  final Uint8List subjectDer;

  const CertificateInfo({
    required this.keyId,
    required this.derBytes,
    required this.label,
    required this.issuerDer,
    required this.serialNumberDer,
    required this.subjectDer,
  });
}

// ─── Pkcs11Session ────────────────────────────────────────────────────

/// Bir PKCS#11 modülü ile etkileşim için oturum yönetimi.
///
/// Kullanım:
/// ```dart
/// final session = Pkcs11Session('C:\\Windows\\System32\\akisp11.dll');
/// try {
///   session.initialize();
///   final tokens = session.getTokens();
///   session.openSession(tokens.first.slotId);
///   session.login('123456');
///   final certs = session.getCertificates();
///   final signature = session.sign(data, certs.first.keyId);
/// } finally {
///   session.dispose();
/// }
/// ```
class Pkcs11Session {
  final String modulePath;
  Pkcs11Module? _loadedModule;
  Pkcs11Module get _module => _loadedModule!;
  bool _ownsInitialization = false;
  bool _initialized = false;
  int _sessionHandle = CK_INVALID_HANDLE;
  bool _loggedIn = false;
  bool _ownsLogin = false;

  Pkcs11Session(this.modulePath);

  bool get isInitialized => _initialized;
  bool get hasSession => _sessionHandle != CK_INVALID_HANDLE;
  bool get isLoggedIn => _loggedIn;

  /// PKCS#11 modülünü yükle ve başlat.
  void initialize() {
    if (_initialized) return;
    _loadedModule = Pkcs11Module.load(modulePath);
    try {
      final rv = _module.cInitialize(nullptr);
      // An already initialized module may belong to another native consumer.
      if (rv != CKR_OK && rv != 0x00000191) checkRv('C_Initialize', rv);
      _ownsInitialization = rv == CKR_OK;
      _initialized = true;
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  /// Token bulunan slot'ları listele.
  List<TokenInfo> getTokens() {
    _ensureInitialized();
    final tokens = <TokenInfo>[];

    // Önce slot sayısını öğren
    final pCount = calloc<UnsignedLong>();
    try {
      checkRv('C_GetSlotList', _module.cGetSlotList(CK_TRUE, nullptr, pCount));
      final count = pCount.value;
      if (count == 0) return tokens;

      // Slot ID'lerini al
      final pSlotIds = calloc<UnsignedLong>(count);
      try {
        pCount.value = count;
        checkRv(
          'C_GetSlotList',
          _module.cGetSlotList(CK_TRUE, pSlotIds, pCount),
        );

        // Her slot için token bilgisini oku
        final pTokenInfo = calloc<CkTokenInfo>();
        try {
          for (var i = 0; i < pCount.value; i++) {
            final slotId = pSlotIds[i];
            final rv = _module.cGetTokenInfo(slotId, pTokenInfo);
            if (rv == CKR_OK) {
              final info = pTokenInfo.ref;
              tokens.add(
                TokenInfo(
                  slotId: slotId,
                  label: paddedBytesToString(info.label, 32),
                  manufacturer: paddedBytesToString(info.manufacturerID, 32),
                  model: paddedBytesToString(info.model, 16),
                  serialNumber: paddedBytesToString(info.serialNumber, 16),
                  loginRequired: (info.flags & CKF_LOGIN_REQUIRED) != 0,
                  hasProtectedAuthPath:
                      (info.flags & CKF_PROTECTED_AUTHENTICATION_PATH) != 0,
                  minPinLen: info.ulMinPinLen,
                  maxPinLen: info.ulMaxPinLen,
                ),
              );
            }
          }
        } finally {
          calloc.free(pTokenInfo);
        }
      } finally {
        calloc.free(pSlotIds);
      }
    } finally {
      calloc.free(pCount);
    }

    return tokens;
  }

  /// Belirtilen slot'ta oturum aç.
  void openSession(int slotId) {
    _ensureInitialized();
    if (_sessionHandle != CK_INVALID_HANDLE) {
      closeSession();
    }

    final pHandle = calloc<UnsignedLong>();
    try {
      checkRv(
        'C_OpenSession',
        _module.cOpenSession(
          slotId,
          CKF_SERIAL_SESSION, // Read-only oturum
          nullptr,
          nullptr,
          pHandle,
        ),
      );
      _sessionHandle = pHandle.value;
    } finally {
      calloc.free(pHandle);
    }
  }

  /// PIN ile giriş yap.
  void login(String pin) {
    _ensureSession();

    final pinBytes = Uint8List.fromList(pin.codeUnits);
    final pPin = uint8ListToPointer(pinBytes);
    try {
      final rv = _module.cLogin(
        _sessionHandle,
        CKU_USER,
        pPin,
        pinBytes.length,
      );
      if (rv == CKR_USER_ALREADY_LOGGED_IN) {
        _loggedIn = true;
        return;
      }
      checkRv('C_Login', rv);
      _ownsLogin = true;
      _loggedIn = true;
    } finally {
      // PIN'i bellekten temizle — HEM native pointer HEM Dart dizisi (Dalga-3
      // güvenlik bulgusu: pinBytes sıfırlanmayınca PIN, GC taşıyana kadar Dart
      // yığınında okunabilir kalıyordu). Not: `pin` String'i immutable olduğundan
      // Dart'ta sıfırlanamaz — çağıran katman String'i kısa ömürlü tutmalı.
      for (var i = 0; i < pinBytes.length; i++) {
        pPin[i] = 0;
        pinBytes[i] = 0;
      }
      calloc.free(pPin);
    }
  }

  /// Token üzerindeki X.509 sertifikaları oku.
  List<CertificateInfo> getCertificates() {
    _ensureSession();
    final certs = <CertificateInfo>[];

    // Sertifika nesnelerini ara
    final objectHandles = _findObjects(CKO_CERTIFICATE);
    debugPrint('PKCS#11: ${objectHandles.length} sertifika bulundu');

    for (final handle in objectHandles) {
      try {
        final cert = _readCertificate(handle);
        if (cert != null) certs.add(cert);
      } catch (e) {
        debugPrint('PKCS#11: Sertifika okunamadı (handle=$handle): $e');
      }
    }

    return certs;
  }

  /// Veriyi imzala.
  ///
  /// [data]: İmzalanacak ham veri (hash'lenmemiş - mekanizma hash'ler).
  /// [keyId]: Kullanılacak private key'in CKA_ID'si (sertifika ile eşleşen).
  /// [mechanism]: İmzalama mekanizması (varsayılan: CKM_SHA256_RSA_PKCS).
  ///
  /// Döndürülen değer: Ham imza byte'ları.
  Uint8List sign(
    Uint8List data,
    Uint8List keyId, {
    int mechanism = CKM_SHA256_RSA_PKCS,
  }) {
    _ensureLoggedIn();

    // Private key'i bul
    final keyHandle = _findPrivateKey(keyId);
    if (keyHandle == CK_INVALID_HANDLE) {
      throw Pkcs11Exception('FindPrivateKey', CKR_KEY_HANDLE_INVALID);
    }

    // Mekanizma oluştur
    final pMechanism = calloc<CkMechanism>();
    pMechanism.ref.mechanism = mechanism;
    pMechanism.ref.pParameter = nullptr;
    pMechanism.ref.ulParameterLen = 0;

    try {
      // C_SignInit — operasyonu başlat
      checkRv(
        'C_SignInit',
        _module.cSignInit(_sessionHandle, pMechanism, keyHandle),
      );

      // Veriyi native belleğe kopyala
      final pData = uint8ListToPointer(data);
      final pSigLen = calloc<UnsignedLong>();

      try {
        // PKCS#11 spec iki-geçişli imzalama:
        // 1. NULL buffer ile gerekli boyutu öğren (operasyonu sonlandırmaz)
        // 2. Doğru boyutta buffer ile imzala
        int sigBufSize;
        pSigLen.value = 0;
        final rvSize = _module.cSign(
          _sessionHandle,
          pData,
          data.length,
          nullptr,
          pSigLen,
        );
        if (rvSize == CKR_OK && pSigLen.value > 0) {
          sigBufSize = pSigLen.value;
        } else {
          // NULL çağrı desteklenmiyor — varsayılan büyük buffer
          // Operasyon sonlanmış olabilir, yeniden başlat
          if (rvSize != CKR_OK) {
            checkRv(
              'C_SignInit',
              _module.cSignInit(_sessionHandle, pMechanism, keyHandle),
            );
          }
          sigBufSize = 1024; // RSA-8192'ye kadar destekler
        }

        pSigLen.value = sigBufSize;
        final pSignature = calloc<Uint8>(sigBufSize);

        try {
          // C_Sign — imzala
          checkRv(
            'C_Sign',
            _module.cSign(
              _sessionHandle,
              pData,
              data.length,
              pSignature,
              pSigLen,
            ),
          );

          // İmza byte'larını kopyala
          final sigBytes = Uint8List(pSigLen.value);
          for (var i = 0; i < pSigLen.value; i++) {
            sigBytes[i] = pSignature[i];
          }
          return sigBytes;
        } finally {
          calloc.free(pSignature);
        }
      } finally {
        // Veriyi bellekten temizle
        for (var i = 0; i < data.length; i++) {
          pData[i] = 0;
        }
        calloc.free(pData);
        calloc.free(pSigLen);
      }
    } finally {
      calloc.free(pMechanism);
    }
  }

  /// Ham veriyi CKM_RSA_PKCS mekanizması ile imzala (hash'lenmiş DigestInfo ile).
  /// CAdES-BES için kullanılır: önce SHA-256 hash hesaplanır,
  /// DigestInfo ASN.1 yapısı oluşturulur, sonra bu metot ile imzalanır.
  Uint8List signRaw(Uint8List digestInfo, Uint8List keyId) {
    return sign(digestInfo, keyId, mechanism: CKM_RSA_PKCS);
  }

  /// Oturumu kapat.
  void closeSession() {
    if (_ownsLogin && _sessionHandle != CK_INVALID_HANDLE) {
      try {
        _module.cLogout(_sessionHandle);
      } catch (_) {}
    }
    _loggedIn = false;
    _ownsLogin = false;
    if (_sessionHandle != CK_INVALID_HANDLE) {
      try {
        _module.cCloseSession(_sessionHandle);
      } catch (_) {}
      _sessionHandle = CK_INVALID_HANDLE;
    }
  }

  /// Modülü temizle ve kapat.
  void dispose() {
    try {
      closeSession();
      if (_initialized && _ownsInitialization) {
        try {
          _module.cFinalize(nullptr);
        } catch (_) {}
      }
    } finally {
      _initialized = false;
      _ownsInitialization = false;
      final module = _loadedModule;
      _loadedModule = null;
      module?.dispose();
    }
  }

  // ─── Private yardımcılar ────────────────────────────────────────────

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('PKCS#11 modülü başlatılmamış. initialize() çağırın.');
    }
  }

  void _ensureSession() {
    _ensureInitialized();
    if (_sessionHandle == CK_INVALID_HANDLE) {
      throw StateError('Oturum açılmamış. openSession() çağırın.');
    }
  }

  void _ensureLoggedIn() {
    _ensureSession();
    if (!_loggedIn) {
      throw StateError('Giriş yapılmamış. login() çağırın.');
    }
  }

  /// Belirli sınıftaki nesneleri bul.
  List<int> _findObjects(int objectClass) {
    final handles = <int>[];

    // Template: CKA_CLASS = objectClass, CKA_TOKEN = true
    final pTemplate = calloc<CkAttribute>(2);
    final pClass = calloc<UnsignedLong>();
    final pTrue = calloc<Uint8>();

    pClass.value = objectClass;
    pTrue.value = CK_TRUE;

    pTemplate[0].type = CKA_CLASS;
    pTemplate[0].pValue = pClass.cast();
    pTemplate[0].ulValueLen = sizeOf<UnsignedLong>();

    pTemplate[1].type = CKA_TOKEN;
    pTemplate[1].pValue = pTrue.cast();
    pTemplate[1].ulValueLen = 1;

    try {
      checkRv(
        'C_FindObjectsInit',
        _module.cFindObjectsInit(_sessionHandle, pTemplate, 2),
      );

      // 32 nesne batch'ler halinde oku
      final pObjects = calloc<UnsignedLong>(32);
      final pCount = calloc<UnsignedLong>();
      try {
        while (true) {
          pCount.value = 0;
          checkRv(
            'C_FindObjects',
            _module.cFindObjects(_sessionHandle, pObjects, 32, pCount),
          );
          if (pCount.value == 0) break;
          for (var i = 0; i < pCount.value; i++) {
            handles.add(pObjects[i]);
          }
        }
      } finally {
        calloc.free(pObjects);
        calloc.free(pCount);
      }

      _module.cFindObjectsFinal(_sessionHandle);
    } finally {
      calloc.free(pTemplate);
      calloc.free(pClass);
      calloc.free(pTrue);
    }

    return handles;
  }

  /// Sertifika nesnesinden bilgi oku.
  CertificateInfo? _readCertificate(int handle) {
    // Önce attribute boyutlarını öğren
    // İhtiyacımız olan: CKA_ID, CKA_VALUE, CKA_LABEL, CKA_ISSUER, CKA_SERIAL_NUMBER, CKA_SUBJECT
    const attrTypes = [
      CKA_ID,
      CKA_VALUE,
      CKA_LABEL,
      CKA_ISSUER,
      CKA_SERIAL_NUMBER,
      CKA_SUBJECT,
    ];

    final pTemplate = calloc<CkAttribute>(attrTypes.length);
    try {
      // İlk geçiş: boyutları al
      for (var i = 0; i < attrTypes.length; i++) {
        pTemplate[i].type = attrTypes[i];
        pTemplate[i].pValue = nullptr;
        pTemplate[i].ulValueLen = 0;
      }

      var rv = _module.cGetAttributeValue(
        _sessionHandle,
        handle,
        pTemplate,
        attrTypes.length,
      );
      // Bazı attribute'lar yoksa da devam et
      if (rv != CKR_OK && rv != CKR_ATTRIBUTE_TYPE_INVALID) {
        return null;
      }

      // Buffer'lar tahsis et
      final buffers = <Pointer<Uint8>>[];
      for (var i = 0; i < attrTypes.length; i++) {
        final len = pTemplate[i].ulValueLen;
        if (len > 0 && len < 0x80000000) {
          // Geçerli uzunluk - 2GB altı
          final buf = calloc<Uint8>(len);
          pTemplate[i].pValue = buf.cast();
          buffers.add(buf);
        } else {
          pTemplate[i].pValue = nullptr;
          pTemplate[i].ulValueLen = 0;
          buffers.add(nullptr);
        }
      }

      // İkinci geçiş: verileri oku
      rv = _module.cGetAttributeValue(
        _sessionHandle,
        handle,
        pTemplate,
        attrTypes.length,
      );

      // Verileri Dart'a kopyala
      Uint8List readAttr(int index) {
        final len = pTemplate[index].ulValueLen;
        if (len <= 0 || buffers[index] == nullptr) return Uint8List(0);
        final bytes = Uint8List(len);
        final ptr = buffers[index];
        for (var i = 0; i < len; i++) {
          bytes[i] = ptr[i];
        }
        return bytes;
      }

      String readStringAttr(int index) {
        final bytes = readAttr(index);
        if (bytes.isEmpty) return '';
        return String.fromCharCodes(bytes).trim();
      }

      final keyId = readAttr(0);
      final derBytes = readAttr(1);
      final label = readStringAttr(2);
      final issuerDer = readAttr(3);
      final serialNumberDer = readAttr(4);
      final subjectDer = readAttr(5);

      // Buffer'ları temizle
      for (final buf in buffers) {
        if (buf != nullptr) calloc.free(buf);
      }

      if (derBytes.isEmpty) return null;

      return CertificateInfo(
        keyId: keyId,
        derBytes: derBytes,
        label: label,
        issuerDer: issuerDer,
        serialNumberDer: serialNumberDer,
        subjectDer: subjectDer,
      );
    } finally {
      calloc.free(pTemplate);
    }
  }

  /// CKA_ID ile eşleşen private key nesnesini bul.
  ///
  /// Önce CKA_CLASS + CKA_ID + CKA_SIGN ile arar.
  /// Bulunamazsa CKA_CLASS + CKA_ID ile tekrar dener (bazı token'lar CKA_SIGN filtresini desteklemez).
  /// Yine bulunamazsa sadece CKA_CLASS = PRIVATE_KEY ile tüm anahtarları arar.
  int _findPrivateKey(Uint8List keyId) {
    if (keyId.isEmpty) return CK_INVALID_HANDLE;
    // 1. Deneme: CKA_CLASS + CKA_ID + CKA_SIGN
    var result = _searchPrivateKey(keyId, withSign: true);
    if (result != CK_INVALID_HANDLE) return result;

    // 2. Deneme: CKA_CLASS + CKA_ID (CKA_SIGN filtresi olmadan)
    result = _searchPrivateKey(keyId, withSign: false);
    if (result != CK_INVALID_HANDLE) return result;

    // Never fall back to an unrelated private key on a multi-certificate card.
    return CK_INVALID_HANDLE;
  }

  int _searchPrivateKey(Uint8List keyId, {required bool withSign}) {
    final attrCount = withSign ? 3 : 2;
    final pTemplate = calloc<CkAttribute>(attrCount);
    final pClass = calloc<UnsignedLong>();
    final pKeyId = uint8ListToPointer(keyId);
    final pTrue = withSign ? calloc<Uint8>() : nullptr.cast<Uint8>();

    pClass.value = CKO_PRIVATE_KEY;
    if (withSign && pTrue != nullptr) pTrue.value = CK_TRUE;

    pTemplate[0].type = CKA_CLASS;
    pTemplate[0].pValue = pClass.cast();
    pTemplate[0].ulValueLen = sizeOf<UnsignedLong>();

    pTemplate[1].type = CKA_ID;
    pTemplate[1].pValue = pKeyId.cast();
    pTemplate[1].ulValueLen = keyId.length;

    if (withSign) {
      pTemplate[2].type = CKA_SIGN;
      pTemplate[2].pValue = pTrue.cast();
      pTemplate[2].ulValueLen = 1;
    }

    try {
      final rv = _module.cFindObjectsInit(_sessionHandle, pTemplate, attrCount);
      if (rv != CKR_OK) return CK_INVALID_HANDLE;

      final pObject = calloc<UnsignedLong>();
      final pCount = calloc<UnsignedLong>();
      try {
        pCount.value = 0;
        final rv2 = _module.cFindObjects(_sessionHandle, pObject, 1, pCount);
        if (rv2 != CKR_OK) return CK_INVALID_HANDLE;

        if (pCount.value > 0) return pObject.value;
        return CK_INVALID_HANDLE;
      } finally {
        _module.cFindObjectsFinal(_sessionHandle);
        calloc.free(pObject);
        calloc.free(pCount);
      }
    } finally {
      calloc.free(pTemplate);
      calloc.free(pClass);
      calloc.free(pKeyId);
      if (withSign) calloc.free(pTrue);
    }
  }
}
