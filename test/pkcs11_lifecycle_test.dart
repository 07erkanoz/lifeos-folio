import 'dart:convert';
import 'dart:io';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/signing/pkcs11/pkcs11_session.dart';
import 'package:evrak_convert/services/signing/pkcs11/pkcs11_bindings.dart';

void main() {
  // What the module writes into: CK_ULONG is 4 bytes and packed on Windows,
  // 8 bytes and naturally aligned on 64-bit Linux and macOS, where the
  // struct is rounded up to 8. Short of that, a module writing the whole
  // struct wrote past the buffer.
  test('the token and slot info are as big as the module writes them', () {
    expect(sizeOf<CkTokenInfo>(), Platform.isWindows ? 164 : 208);
    expect(sizeOf<CkSlotInfo>(), Platform.isWindows ? 108 : 112);
  });

  test('a card\'s padded label is read as UTF-8', () {
    final label = calloc<CkTokenInfo>();
    try {
      final bytes = utf8.encode('TÜBİTAK İMZA');
      for (var i = 0; i < 32; i++) {
        label.ref.label[i] = i < bytes.length ? bytes[i] : 0x20;
      }
      expect(paddedBytesToString(label.ref.label, 32), 'TÜBİTAK İMZA');
    } finally {
      calloc.free(label);
    }
  });

  for (final scenario in <(int, String, List<String>)>[
    (
      0,
      'success',
      [
        'load',
        'initialize',
        'open',
        'login',
        'logout',
        'close',
        'finalize',
        'unload',
      ],
    ),
    (1, 'failed initialization', ['load', 'initialize', 'unload']),
    (
      2,
      'failed login',
      ['load', 'initialize', 'open', 'login', 'close', 'finalize', 'unload'],
    ),
    (
      3,
      'borrowed initialization',
      ['load', 'initialize', 'open', 'login', 'logout', 'close', 'unload'],
    ),
    (
      4,
      'driver cleanup errors',
      [
        'load',
        'initialize',
        'open',
        'login',
        'logout',
        'close',
        'finalize',
        'unload',
      ],
    ),
    (5, 'missing entry point', ['load', 'unload']),
  ]) {
    test(
      'PKCS11 releases native module after ${scenario.$2}',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'pkcs11-lifecycle-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final log = File('${directory.path}/events.txt');
        final library = '${directory.path}/mock.so';
        final compiled = await Process.run('cc', [
          '-shared',
          '-fPIC',
          '-std=c11',
          '-DMODE=${scenario.$1}',
          '-DLOG_PATH=${jsonEncode(log.path)}',
          'test/fixtures/pkcs11/lifecycle.c',
          '-o',
          library,
        ]);
        expect(compiled.exitCode, 0, reason: compiled.stderr.toString());
        final session = Pkcs11Session(library);
        try {
          if (scenario.$1 == 1) {
            expect(session.initialize, throwsA(isA<Pkcs11Exception>()));
          } else if (scenario.$1 == 5) {
            expect(session.initialize, throwsArgumentError);
          } else {
            session.initialize();
            session.openSession(0);
            if (scenario.$1 == 2) {
              expect(
                () => session.login('offline-test'),
                throwsA(isA<Pkcs11Exception>()),
              );
            } else {
              session.login('offline-test');
            }
          }
        } finally {
          session.dispose();
          session.dispose(); // Safe from an outer finally after early release.
        }
        expect(session.isInitialized, isFalse);
        expect(session.hasSession, isFalse);
        expect(session.isLoggedIn, isFalse);
        expect(await log.readAsLines(), scenario.$3);
      },
      skip: !Platform.isLinux
          ? 'Native fixture uses the Linux test compiler.'
          : false,
    );
  }
}
