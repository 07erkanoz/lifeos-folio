import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/signing/pkcs11/pkcs11_session.dart';
import 'package:evrak_convert/services/signing/pkcs11/pkcs11_bindings.dart';

void main() {
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
