import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';

/// The computer Folio runs on, as the system names it once and for all:
/// Windows' MachineGuid, the Mac's IOPlatformUUID, Linux's machine-id. Kept
/// only as a hash of it. Null where there is none to read (a phone), or it
/// could not be read: nothing is then concluded from it.
abstract final class MachineIdentity {
  static String? _current;
  static bool _read = false;

  /// Read once a run.
  static String? current() {
    if (_read) return _current;
    _read = true;
    final raw = _raw();
    _current = raw == null || raw.trim().isEmpty
        ? null
        : sha256
              .convert(utf8.encode('folio-makine:${raw.trim().toLowerCase()}'))
              .toString()
              .substring(0, 32);
    return _current;
  }

  static String? _raw() {
    try {
      if (Platform.isWindows) return _windowsGuid();
      if (Platform.isMacOS) {
        final r = Process.runSync('ioreg', [
          '-rd1',
          '-c',
          'IOPlatformExpertDevice',
        ]);
        if (r.exitCode != 0) return null;
        return RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"')
            .firstMatch('${r.stdout}')
            ?.group(1);
      }
      if (Platform.isLinux) {
        for (final path in ['/etc/machine-id', '/var/lib/dbus/machine-id']) {
          final file = File(path);
          if (file.existsSync()) return file.readAsStringSync();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Read from the registry itself: a `reg` run at every start would be a
  /// process of its own, and a console's flash.
  static String? _windowsGuid() {
    final regGetValue = DynamicLibrary.open('advapi32.dll')
        .lookupFunction<
          Int32 Function(
            IntPtr,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Uint32,
            Pointer<Uint32>,
            Pointer<Uint16>,
            Pointer<Uint32>,
          ),
          int Function(
            int,
            Pointer<Utf16>,
            Pointer<Utf16>,
            int,
            Pointer<Uint32>,
            Pointer<Uint16>,
            Pointer<Uint32>,
          )
        >('RegGetValueW');
    const localMachine = -2147483646; // HKEY_LOCAL_MACHINE, sign-extended
    const stringOnly = 0x00000002; // RRF_RT_REG_SZ
    const view64 = 0x00010000; // RRF_SUBKEY_WOW6464KEY
    final key = r'SOFTWARE\Microsoft\Cryptography'.toNativeUtf16();
    final name = 'MachineGuid'.toNativeUtf16();
    final data = calloc<Uint16>(128);
    final size = calloc<Uint32>()..value = 256;
    try {
      final status = regGetValue(
        localMachine,
        key,
        name,
        stringOnly | view64,
        nullptr,
        data,
        size,
      );
      if (status != 0) return null;
      return data.cast<Utf16>().toDartString();
    } finally {
      calloc
        ..free(key)
        ..free(name)
        ..free(data)
        ..free(size);
    }
  }
}
