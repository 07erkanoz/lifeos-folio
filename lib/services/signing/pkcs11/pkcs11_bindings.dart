// Keep the standard PKCS#11 ABI names for comparison with native headers.
// ignore_for_file: camel_case_types, constant_identifier_names
/// PKCS#11 (Cryptoki) v2.40 Dart FFI bindings.
///
/// Ref: OASIS PKCS#11 Specification
/// http://docs.oasis-open.org/pkcs11/pkcs11-base/v2.40/pkcs11-base-v2.40.html
///
/// Yalnızca e-imza işlemleri için gereken fonksiyon/struct alt kümesi.
library;

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ─── PKCS#11 Tür Aliasları ────────────────────────────────────────────

/// CK_ULONG: platforma göre 32 veya 64 bit unsigned integer.
/// Windows 64-bit'te PKCS#11 `unsigned long` = 4 byte.
/// Linux 64-bit'te de 8 byte. 32-bit platformlarda 4 byte.
///
/// Dart FFI: `UnsignedLong` platforma uygun boyutu otomatik kullanır.
typedef CK_ULONG = UnsignedLong;
typedef CK_FLAGS = UnsignedLong;
typedef CK_SLOT_ID = UnsignedLong;
typedef CK_SESSION_HANDLE = UnsignedLong;
typedef CK_OBJECT_HANDLE = UnsignedLong;
typedef CK_OBJECT_CLASS = UnsignedLong;
typedef CK_ATTRIBUTE_TYPE = UnsignedLong;
typedef CK_MECHANISM_TYPE = UnsignedLong;
typedef CK_USER_TYPE = UnsignedLong;
typedef CK_RV = UnsignedLong;
typedef CK_BYTE = Uint8;
typedef CK_BBOOL = Uint8;
typedef CK_VOID_PTR = Pointer<Void>;
typedef CK_NOTIFY = Pointer<NativeFunction<Void Function()>>;

// ─── PKCS#11 Sabitler ─────────────────────────────────────────────────

// Dönüş değerleri (CK_RV)
const int CKR_OK = 0x00000000;
const int CKR_CANCEL = 0x00000001;
const int CKR_SLOT_ID_INVALID = 0x00000003;
const int CKR_GENERAL_ERROR = 0x00000005;
const int CKR_ARGUMENTS_BAD = 0x00000007;
const int CKR_ATTRIBUTE_TYPE_INVALID = 0x00000012;
const int CKR_DEVICE_ERROR = 0x00000030;
const int CKR_DEVICE_MEMORY = 0x00000031;
const int CKR_DEVICE_REMOVED = 0x00000032;
const int CKR_FUNCTION_FAILED = 0x00000006;
const int CKR_KEY_HANDLE_INVALID = 0x00000060;
const int CKR_MECHANISM_INVALID = 0x00000070;
const int CKR_PIN_INCORRECT = 0x000000A0;
const int CKR_PIN_LOCKED = 0x000000A4;
const int CKR_SESSION_HANDLE_INVALID = 0x000000B3;
const int CKR_TOKEN_NOT_PRESENT = 0x000000E0;
const int CKR_TOKEN_NOT_RECOGNIZED = 0x000000E1;
const int CKR_USER_ALREADY_LOGGED_IN = 0x00000100;
const int CKR_USER_NOT_LOGGED_IN = 0x00000101;
const int CKR_USER_PIN_NOT_INITIALIZED = 0x00000102;
const int CKR_BUFFER_TOO_SMALL = 0x00000150;
const int CKR_CRYPTOKI_NOT_INITIALIZED = 0x00000190;

// Oturum türleri
const int CKF_SERIAL_SESSION = 0x00000004; // Zorunlu flag
const int CKF_RW_SESSION = 0x00000002;

// Kullanıcı türleri
const int CKU_SO = 0; // Security Officer
const int CKU_USER = 1; // Normal kullanıcı

// Nesne sınıfları
const int CKO_CERTIFICATE = 0x00000001;
const int CKO_PUBLIC_KEY = 0x00000002;
const int CKO_PRIVATE_KEY = 0x00000003;

// Sertifika türleri
const int CKC_X_509 = 0x00000000;

// Attribute türleri
const int CKA_CLASS = 0x00000000;
const int CKA_TOKEN = 0x00000001;
const int CKA_PRIVATE = 0x00000002;
const int CKA_LABEL = 0x00000003;
const int CKA_VALUE = 0x00000011;
const int CKA_CERTIFICATE_TYPE = 0x00000080;
const int CKA_ISSUER = 0x00000081;
const int CKA_SERIAL_NUMBER = 0x00000082;
const int CKA_SUBJECT = 0x00000101;
const int CKA_ID = 0x00000102;
const int CKA_SIGN = 0x00000108;
const int CKA_KEY_TYPE = 0x00000100;
const int CKA_MODULUS_BITS = 0x00000121;

// Mekanizmalar
const int CKM_RSA_PKCS = 0x00000001;
const int CKM_SHA256_RSA_PKCS = 0x00000040;
const int CKM_SHA384_RSA_PKCS = 0x00000041;
const int CKM_SHA512_RSA_PKCS = 0x00000042;
const int CKM_SHA256 = 0x00000250;

// Token bilgi flagları
const int CKF_TOKEN_PRESENT = 0x00000001;
const int CKF_LOGIN_REQUIRED = 0x00000004;
const int CKF_USER_PIN_INITIALIZED = 0x00000008;
const int CKF_PROTECTED_AUTHENTICATION_PATH = 0x00000100;

// Boolean
const int CK_TRUE = 1;
const int CK_FALSE = 0;

// Özel değer
const int CK_INVALID_HANDLE = 0;

// ─── PKCS#11 Struct'lar ───────────────────────────────────────────────

/// CK_VERSION
@Packed(1)
final class CkVersion extends Struct {
  @Uint8()
  external int major;

  @Uint8()
  external int minor;
}

/// CK_TOKEN_INFO (padded string alanları 32/16 byte)
///
/// Windows: PKCS#11 pack(1), Linux: natural alignment.
/// @Packed(1) her iki platformda da doğru çalışır çünkü
/// Linux 64-bit'te CK_ULONG=8 byte, tüm alanlar zaten hizalı.
@Packed(1)
final class CkTokenInfo extends Struct {
  // label: 32 byte UTF-8 padded
  @Array(32)
  external Array<Uint8> label;

  // manufacturerID: 32 byte
  @Array(32)
  external Array<Uint8> manufacturerID;

  // model: 16 byte
  @Array(16)
  external Array<Uint8> model;

  // serialNumber: 16 byte
  @Array(16)
  external Array<Uint8> serialNumber;

  @UnsignedLong()
  external int flags;

  @UnsignedLong()
  external int ulMaxSessionCount;

  @UnsignedLong()
  external int ulSessionCount;

  @UnsignedLong()
  external int ulMaxRwSessionCount;

  @UnsignedLong()
  external int ulRwSessionCount;

  @UnsignedLong()
  external int ulMaxPinLen;

  @UnsignedLong()
  external int ulMinPinLen;

  @UnsignedLong()
  external int ulTotalPublicMemory;

  @UnsignedLong()
  external int ulFreePublicMemory;

  @UnsignedLong()
  external int ulTotalPrivateMemory;

  @UnsignedLong()
  external int ulFreePrivateMemory;

  external CkVersion hardwareVersion;
  external CkVersion firmwareVersion;

  // utcTime: 16 byte
  @Array(16)
  external Array<Uint8> utcTime;
}

/// CK_SLOT_INFO
@Packed(1)
final class CkSlotInfo extends Struct {
  @Array(64)
  external Array<Uint8> slotDescription;

  @Array(32)
  external Array<Uint8> manufacturerID;

  @UnsignedLong()
  external int flags;

  external CkVersion hardwareVersion;
  external CkVersion firmwareVersion;
}

/// CK_ATTRIBUTE - Nesne attribute'u (anahtar, sertifika vb.)
@Packed(1)
final class CkAttribute extends Struct {
  @UnsignedLong()
  external int type;

  external Pointer<Void> pValue;

  @UnsignedLong()
  external int ulValueLen;
}

/// CK_MECHANISM - İmzalama/hash mekanizması
@Packed(1)
final class CkMechanism extends Struct {
  @UnsignedLong()
  external int mechanism;

  external Pointer<Void> pParameter;

  @UnsignedLong()
  external int ulParameterLen;
}

// ─── CK_FUNCTION_LIST - Fonksiyon pointer tablosu ─────────────────────

/// PKCS#11 modülünden C_GetFunctionList ile alınan fonksiyon pointer'ları.
/// Tam CK_FUNCTION_LIST yapısı çok büyük (60+ fonksiyon).
/// Burada yalnızca ihtiyaç duyulanları offset ile okuyoruz.
///
/// CK_FUNCTION_LIST layout (v2.40) — 64-bit offset'ler:
///   CK_VERSION version;          // offset 0 (2 bytes + 6 padding)
///   [0]  CK_C_Initialize          // offset 8
///   [1]  CK_C_Finalize            // offset 16
///   [2]  CK_C_GetInfo             // offset 24
///   [3]  CK_C_GetFunctionList     // offset 32
///   [4]  CK_C_GetSlotList         // offset 40
///   [5]  CK_C_GetSlotInfo         // offset 48
///   [6]  CK_C_GetTokenInfo        // offset 56
///   [7]  CK_C_GetMechanismList    // offset 64
///   [8]  CK_C_GetMechanismInfo    // offset 72
///   [9]  CK_C_InitToken           // offset 80
///   [10] CK_C_InitPIN             // offset 88
///   [11] CK_C_SetPIN              // offset 96
///   [12] CK_C_OpenSession         // offset 104
///   [13] CK_C_CloseSession        // offset 112
///   [14] CK_C_CloseAllSessions    // offset 120
///   [15] CK_C_GetSessionInfo      // offset 128
///   [16] CK_C_GetOperationState   // offset 136
///   [17] CK_C_SetOperationState   // offset 144
///   [18] CK_C_Login               // offset 152
///   [19] CK_C_Logout              // offset 160
///   [20] CK_C_CreateObject        // offset 168
///   [21] CK_C_CopyObject          // offset 176
///   [22] CK_C_DestroyObject       // offset 184
///   [23] CK_C_GetObjectSize       // offset 192
///   [24] CK_C_GetAttributeValue   // offset 200
///   [25] CK_C_SetAttributeValue   // offset 208
///   [26] CK_C_FindObjectsInit     // offset 216
///   [27] CK_C_FindObjects         // offset 224
///   [28] CK_C_FindObjectsFinal    // offset 232
///   [29] CK_C_EncryptInit         // offset 240
///   [30] CK_C_Encrypt             // offset 248
///   [31] CK_C_EncryptUpdate       // offset 256
///   [32] CK_C_EncryptFinal        // offset 264
///   [33] CK_C_DecryptInit         // offset 272
///   [34] CK_C_Decrypt             // offset 280
///   [35] CK_C_DecryptUpdate       // offset 288
///   [36] CK_C_DecryptFinal        // offset 296
///   [37] CK_C_DigestInit          // offset 304
///   [38] CK_C_Digest              // offset 312
///   [39] CK_C_DigestUpdate        // offset 320
///   [40] CK_C_DigestKey           // offset 328
///   [41] CK_C_DigestFinal         // offset 336
///   [42] CK_C_SignInit            // offset 344
///   [43] CK_C_Sign                // offset 352

// Platform pointer boyutu
final int _ptrSize = sizeOf<Pointer>();

// ─── Fonksiyon tipleri ────────────────────────────────────────────────

// C_Initialize(CK_VOID_PTR pInitArgs)
typedef _CInitializeNative = UnsignedLong Function(Pointer<Void>);
typedef CInitialize = int Function(Pointer<Void>);

// C_Finalize(CK_VOID_PTR pReserved)
typedef _CFinalizeNative = UnsignedLong Function(Pointer<Void>);
typedef CFinalize = int Function(Pointer<Void>);

// C_GetSlotList(CK_BBOOL tokenPresent, CK_SLOT_ID_PTR pSlotList, CK_ULONG_PTR pulCount)
typedef _CGetSlotListNative = UnsignedLong Function(
  Uint8,
  Pointer<UnsignedLong>,
  Pointer<UnsignedLong>,
);
typedef CGetSlotList = int Function(
  int,
  Pointer<UnsignedLong>,
  Pointer<UnsignedLong>,
);

// C_GetSlotInfo(CK_SLOT_ID slotID, CK_SLOT_INFO_PTR pInfo)
typedef _CGetSlotInfoNative = UnsignedLong Function(
  UnsignedLong,
  Pointer<CkSlotInfo>,
);
typedef CGetSlotInfo = int Function(int, Pointer<CkSlotInfo>);

// C_GetTokenInfo(CK_SLOT_ID slotID, CK_TOKEN_INFO_PTR pInfo)
typedef _CGetTokenInfoNative = UnsignedLong Function(
  UnsignedLong,
  Pointer<CkTokenInfo>,
);
typedef CGetTokenInfo = int Function(int, Pointer<CkTokenInfo>);

// C_OpenSession(slotID, flags, pApplication, Notify, phSession)
typedef _COpenSessionNative = UnsignedLong Function(
  UnsignedLong,
  UnsignedLong,
  Pointer<Void>,
  Pointer<NativeFunction<Void Function()>>,
  Pointer<UnsignedLong>,
);
typedef COpenSession = int Function(
  int,
  int,
  Pointer<Void>,
  Pointer<NativeFunction<Void Function()>>,
  Pointer<UnsignedLong>,
);

// C_CloseSession(hSession)
typedef _CCloseSessionNative = UnsignedLong Function(UnsignedLong);
typedef CCloseSession = int Function(int);

// C_Login(hSession, userType, pPin, ulPinLen)
typedef _CLoginNative = UnsignedLong Function(
  UnsignedLong,
  UnsignedLong,
  Pointer<Uint8>,
  UnsignedLong,
);
typedef CLogin = int Function(int, int, Pointer<Uint8>, int);

// C_Logout(hSession)
typedef _CLogoutNative = UnsignedLong Function(UnsignedLong);
typedef CLogout = int Function(int);

// C_FindObjectsInit(hSession, pTemplate, ulCount)
typedef _CFindObjectsInitNative = UnsignedLong Function(
  UnsignedLong,
  Pointer<CkAttribute>,
  UnsignedLong,
);
typedef CFindObjectsInit = int Function(int, Pointer<CkAttribute>, int);

// C_FindObjects(hSession, phObject, ulMaxObjectCount, pulObjectCount)
typedef _CFindObjectsNative = UnsignedLong Function(
  UnsignedLong,
  Pointer<UnsignedLong>,
  UnsignedLong,
  Pointer<UnsignedLong>,
);
typedef CFindObjects = int Function(
  int,
  Pointer<UnsignedLong>,
  int,
  Pointer<UnsignedLong>,
);

// C_FindObjectsFinal(hSession)
typedef _CFindObjectsFinalNative = UnsignedLong Function(UnsignedLong);
typedef CFindObjectsFinal = int Function(int);

// C_GetAttributeValue(hSession, hObject, pTemplate, ulCount)
typedef _CGetAttributeValueNative = UnsignedLong Function(
  UnsignedLong,
  UnsignedLong,
  Pointer<CkAttribute>,
  UnsignedLong,
);
typedef CGetAttributeValue = int Function(int, int, Pointer<CkAttribute>, int);

// C_SignInit(hSession, pMechanism, hKey)
typedef _CSignInitNative = UnsignedLong Function(
  UnsignedLong,
  Pointer<CkMechanism>,
  UnsignedLong,
);
typedef CSignInit = int Function(int, Pointer<CkMechanism>, int);

// C_Sign(hSession, pData, ulDataLen, pSignature, pulSignatureLen)
typedef _CSignNative = UnsignedLong Function(
  UnsignedLong,
  Pointer<Uint8>,
  UnsignedLong,
  Pointer<Uint8>,
  Pointer<UnsignedLong>,
);
typedef CSign = int Function(
  int,
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  Pointer<UnsignedLong>,
);

// C_GetFunctionList(CK_FUNCTION_LIST_PTR_PTR ppFunctionList)
typedef _CGetFunctionListNative = UnsignedLong Function(Pointer<Pointer<Void>>);
typedef CGetFunctionListDart = int Function(Pointer<Pointer<Void>>);

// ─── PKCS#11 Modül Yükleyici ──────────────────────────────────────────

/// Bir PKCS#11 shared library (.dll/.so/.dylib) yükleyip
/// fonksiyon pointer'larını çözümleyen sınıf.
class Pkcs11Module {
  final DynamicLibrary
  library; // Retains ownership of the loaded native module.
  final Pointer<Void> _functionList;
  bool _closed = false;

  Pkcs11Module._(this.library, this._functionList);

  /// PKCS#11 modülünü yükle.
  /// [path]: .dll / .so / .dylib dosya yolu.
  factory Pkcs11Module.load(String path) {
    final lib = DynamicLibrary.open(path);

    try {
      final getFunctionList = lib
          .lookupFunction<_CGetFunctionListNative, CGetFunctionListDart>(
            'C_GetFunctionList',
          );
      final ppFuncList = calloc<Pointer<Void>>();
      try {
        final rv = getFunctionList(ppFuncList);
        if (rv != CKR_OK) throw Pkcs11Exception('C_GetFunctionList', rv);
        if (ppFuncList.value == nullptr) {
          throw Pkcs11Exception('C_GetFunctionList', CKR_GENERAL_ERROR);
        }
        return Pkcs11Module._(lib, ppFuncList.value);
      } finally {
        calloc.free(ppFuncList);
      }
    } catch (_) {
      lib.close();
      rethrow;
    }
  }

  /// Release the OS module reference after every native call/session has ended.
  void dispose() {
    if (_closed) return;
    _closed = true;
    library.close();
  }

  // ── Fonksiyon pointer offset'leri ──

  // CK_FUNCTION_LIST başlangıcı: CK_VERSION (2 byte) + platform-dependent padding
  //
  // Windows: PKCS#11 header'ları `#pragma pack(push, cryptoki, 1)` kullanır.
  //   → Padding YOK, ilk pointer offset 2'de.
  // Linux/macOS: Natural alignment (padding var).
  //   → 64-bit: version=2 + pad=6 → offset 8, 32-bit: version=2 + pad=2 → offset 4

  int get _baseOffset => Platform.isWindows ? 2 : _ptrSize;

  Pointer<NativeFunction<T>> _funcAt<T extends Function>(int index) {
    if (_closed) throw StateError('PKCS#11 sürücüsü kapatıldı.');
    final offset = _baseOffset + (index * _ptrSize);
    // Struct alanındaki fonksiyon pointer değerini oku (dereference)
    final funcAddr = Pointer<IntPtr>.fromAddress(_functionList.address + offset)
        .value;
    return Pointer<NativeFunction<T>>.fromAddress(funcAddr);
  }

  // ── PKCS#11 fonksiyonları ──

  /// C_Initialize - index 0
  CInitialize get cInitialize =>
      _funcAt<_CInitializeNative>(0).asFunction<CInitialize>();

  /// C_Finalize - index 1
  CFinalize get cFinalize =>
      _funcAt<_CFinalizeNative>(1).asFunction<CFinalize>();

  /// C_GetSlotList - index 4
  CGetSlotList get cGetSlotList =>
      _funcAt<_CGetSlotListNative>(4).asFunction<CGetSlotList>();

  /// C_GetSlotInfo - index 5
  CGetSlotInfo get cGetSlotInfo =>
      _funcAt<_CGetSlotInfoNative>(5).asFunction<CGetSlotInfo>();

  /// C_GetTokenInfo - index 6
  CGetTokenInfo get cGetTokenInfo =>
      _funcAt<_CGetTokenInfoNative>(6).asFunction<CGetTokenInfo>();

  /// C_OpenSession - index 12
  COpenSession get cOpenSession =>
      _funcAt<_COpenSessionNative>(12).asFunction<COpenSession>();

  /// C_CloseSession - index 13
  CCloseSession get cCloseSession =>
      _funcAt<_CCloseSessionNative>(13).asFunction<CCloseSession>();

  /// C_Login - index 18
  CLogin get cLogin => _funcAt<_CLoginNative>(18).asFunction<CLogin>();

  /// C_Logout - index 19
  CLogout get cLogout => _funcAt<_CLogoutNative>(19).asFunction<CLogout>();

  /// C_GetAttributeValue - index 24
  CGetAttributeValue get cGetAttributeValue =>
      _funcAt<_CGetAttributeValueNative>(24).asFunction<CGetAttributeValue>();

  /// C_FindObjectsInit - index 26
  CFindObjectsInit get cFindObjectsInit =>
      _funcAt<_CFindObjectsInitNative>(26).asFunction<CFindObjectsInit>();

  /// C_FindObjects - index 27
  CFindObjects get cFindObjects =>
      _funcAt<_CFindObjectsNative>(27).asFunction<CFindObjects>();

  /// C_FindObjectsFinal - index 28
  CFindObjectsFinal get cFindObjectsFinal =>
      _funcAt<_CFindObjectsFinalNative>(28).asFunction<CFindObjectsFinal>();

  /// C_SignInit - index 42
  CSignInit get cSignInit =>
      _funcAt<_CSignInitNative>(42).asFunction<CSignInit>();

  /// C_Sign - index 43
  CSign get cSign => _funcAt<_CSignNative>(43).asFunction<CSign>();
}

// ─── Hata Yönetimi ────────────────────────────────────────────────────

class Pkcs11Exception implements Exception {
  final String function;
  final int returnValue;

  Pkcs11Exception(this.function, this.returnValue);

  String get rvName =>
      _rvNames[returnValue] ??
      '0x${returnValue.toRadixString(16).padLeft(8, '0')}';

  @override
  String toString() => 'PKCS#11 Error: $function returned $rvName';

  static const _rvNames = {
    CKR_OK: 'CKR_OK',
    CKR_CANCEL: 'CKR_CANCEL',
    CKR_SLOT_ID_INVALID: 'CKR_SLOT_ID_INVALID',
    CKR_GENERAL_ERROR: 'CKR_GENERAL_ERROR',
    CKR_ARGUMENTS_BAD: 'CKR_ARGUMENTS_BAD',
    CKR_DEVICE_ERROR: 'CKR_DEVICE_ERROR',
    CKR_DEVICE_MEMORY: 'CKR_DEVICE_MEMORY',
    CKR_DEVICE_REMOVED: 'CKR_DEVICE_REMOVED',
    CKR_FUNCTION_FAILED: 'CKR_FUNCTION_FAILED',
    CKR_KEY_HANDLE_INVALID: 'CKR_KEY_HANDLE_INVALID',
    CKR_MECHANISM_INVALID: 'CKR_MECHANISM_INVALID',
    CKR_PIN_INCORRECT: 'CKR_PIN_INCORRECT',
    CKR_PIN_LOCKED: 'CKR_PIN_LOCKED',
    CKR_SESSION_HANDLE_INVALID: 'CKR_SESSION_HANDLE_INVALID',
    CKR_TOKEN_NOT_PRESENT: 'CKR_TOKEN_NOT_PRESENT',
    CKR_TOKEN_NOT_RECOGNIZED: 'CKR_TOKEN_NOT_RECOGNIZED',
    CKR_USER_ALREADY_LOGGED_IN: 'CKR_USER_ALREADY_LOGGED_IN',
    CKR_USER_NOT_LOGGED_IN: 'CKR_USER_NOT_LOGGED_IN',
    CKR_USER_PIN_NOT_INITIALIZED: 'CKR_USER_PIN_NOT_INITIALIZED',
    CKR_BUFFER_TOO_SMALL: 'CKR_BUFFER_TOO_SMALL',
    CKR_CRYPTOKI_NOT_INITIALIZED: 'CKR_CRYPTOKI_NOT_INITIALIZED',
  };
}

// ─── Yardımcı Fonksiyonlar ────────────────────────────────────────────

/// PKCS#11 padded string alanını Dart String'e çevir (boşlukları temizle).
String paddedBytesToString(Array<Uint8> arr, int length) {
  final bytes = <int>[];
  for (var i = 0; i < length; i++) {
    bytes.add(arr[i]);
  }
  // Sondaki boşlukları (0x20) ve null byte'ları temizle
  while (bytes.isNotEmpty && (bytes.last == 0x20 || bytes.last == 0x00)) {
    bytes.removeLast();
  }
  return String.fromCharCodes(bytes);
}

/// Uint8List'i native `Pointer<Uint8>`'e kopyala.
Pointer<Uint8> uint8ListToPointer(Uint8List data) {
  final ptr = calloc<Uint8>(data.length);
  for (var i = 0; i < data.length; i++) {
    ptr[i] = data[i];
  }
  return ptr;
}

/// CK_RV kontrol et, OK değilse exception fırlat.
void checkRv(String function, int rv) {
  if (rv != CKR_OK) {
    throw Pkcs11Exception(function, rv);
  }
}
