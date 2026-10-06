import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';

/// Where a portal's tokens are kept on this device (UYGULAMAPLANI §4,
/// P02, §13): encrypted for the Windows user with DPAPI; on a phone in the
/// Android Keystore or the iOS Keychain. Where there is no such
/// protection, nothing is written: the session lasts as long as Folio is
/// open, never as a plain token file.
class SecretStore {
  SecretStore({Future<Directory> Function()? directory})
    : _directory = directory ?? _default;

  static Future<Directory> _default() async =>
      Directory(p.join((await folioSupportDirectory()).path, 'portal'));

  final Future<Directory> Function() _directory;

  static bool get available =>
      Platform.isWindows || Platform.isAndroid || Platform.isIOS;

  static bool get _phone => Platform.isAndroid || Platform.isIOS;
  static const _keychain = FlutterSecureStorage();
  static String _key(String name) => 'folio.$name';

  Future<File> _file(String name) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    return File(p.join(dir.path, '$name.secret'));
  }

  /// Keeps [value] under [name]; false where it cannot be kept safely.
  Future<bool> write(String name, Map<String, Object?> value) async {
    if (!available) return false;
    if (_phone) {
      try {
        await _keychain.write(key: _key(name), value: jsonEncode(value));
        return await read(name) != null;
      } catch (_) {
        return false;
      }
    }
    try {
      final sealed = Dpapi.protect(utf8.encode(jsonEncode(value)));
      final file = await _file(name);
      final part = File('${file.path}.part');
      await part.writeAsBytes(sealed, flush: true);
      await part.rename(file.path);
      // Read back: a store that cannot be read is no store.
      return await read(name) != null;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, Object?>?> read(String name) async {
    if (!available) return null;
    if (_phone) {
      try {
        final text = await _keychain.read(key: _key(name));
        final data = text == null ? null : jsonDecode(text);
        return data is Map ? Map<String, Object?>.from(data) : null;
      } catch (_) {
        return null;
      }
    }
    try {
      final file = await _file(name);
      if (!await file.exists()) return null;
      final opened = Dpapi.unprotect(await file.readAsBytes());
      final data = jsonDecode(utf8.decode(opened));
      return data is Map ? Map<String, Object?>.from(data) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String name) async {
    if (_phone) {
      try {
        await _keychain.delete(key: _key(name));
      } catch (_) {}
      return;
    }
    try {
      final file = await _file(name);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

final class _Blob extends Struct {
  @Uint32()
  external int size;
  external Pointer<Uint8> data;
}

typedef _ProtectC = Int32 Function(
  Pointer<_Blob>,
  Pointer<Utf16>,
  Pointer<_Blob>,
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
  Pointer<_Blob>,
);
typedef _ProtectDart = int Function(
  Pointer<_Blob>,
  Pointer<Utf16>,
  Pointer<_Blob>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  Pointer<_Blob>,
);
typedef _UnprotectC = Int32 Function(
  Pointer<_Blob>,
  Pointer<Pointer<Utf16>>,
  Pointer<_Blob>,
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
  Pointer<_Blob>,
);
typedef _UnprotectDart = int Function(
  Pointer<_Blob>,
  Pointer<Pointer<Utf16>>,
  Pointer<_Blob>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  Pointer<_Blob>,
);

/// Windows' Data Protection API: bytes sealed for the signed-in user.
abstract final class Dpapi {
  static final _crypt = DynamicLibrary.open('crypt32.dll');
  static final _kernel = DynamicLibrary.open('kernel32.dll');
  static final _protect = _crypt.lookupFunction<_ProtectC, _ProtectDart>(
    'CryptProtectData',
  );
  static final _unprotect = _crypt.lookupFunction<_UnprotectC, _UnprotectDart>(
    'CryptUnprotectData',
  );
  static final _free = _kernel
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('LocalFree');

  /// No dialog may ever be shown for it.
  static const _uiForbidden = 0x1;

  static Uint8List protect(List<int> bytes) => _run(bytes, (input, output) {
    final label = 'LifeOS Folio'.toNativeUtf16();
    try {
      return _protect(
        input,
        label,
        nullptr,
        nullptr,
        nullptr,
        _uiForbidden,
        output,
      );
    } finally {
      calloc.free(label);
    }
  });

  static Uint8List unprotect(List<int> bytes) => _run(
    bytes,
    (input, output) => _unprotect(
      input,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      _uiForbidden,
      output,
    ),
  );

  static Uint8List _run(
    List<int> bytes,
    int Function(Pointer<_Blob> input, Pointer<_Blob> output) call,
  ) {
    final data = calloc<Uint8>(bytes.length);
    final input = calloc<_Blob>();
    final output = calloc<_Blob>();
    try {
      data.asTypedList(bytes.length).setAll(0, bytes);
      input.ref
        ..size = bytes.length
        ..data = data;
      if (call(input, output) == 0) {
        throw StateError('Windows veri koruması başarısız oldu.');
      }
      final result = Uint8List.fromList(
        output.ref.data.asTypedList(output.ref.size),
      );
      _free(output.ref.data.cast());
      return result;
    } finally {
      calloc.free(data);
      calloc.free(input);
      calloc.free(output);
    }
  }
}
