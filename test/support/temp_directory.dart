import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Removes a directory a widget test built under the system temp folder.
///
/// A save the widget started finishes in a continuation scheduled on the
/// test's own async zone, and that zone only advances when the test pumps.
/// Until it does, the file the widget wrote is still open, and Windows refuses
/// to delete a directory holding an open file: the teardown fails with
/// `errno = 32`. Linux deletes it either way, which is why these tests pass
/// there and hid the problem.
///
/// Pumping between attempts is what actually finishes that work. Waiting on a
/// timer does not, because the pending continuation is not on the real clock —
/// a fixed delay before the delete is a guess that cannot come true.
///
/// The budget is generous on purpose: the index isolate a test may have
/// started is given up to three seconds to shut down, and its files stay
/// open until it does. Waiting costs nothing when nothing is holding the
/// directory, because the first attempt succeeds.
///
/// A directory that never frees up still fails the test, on the last attempt,
/// rather than passing quietly.
Future<void> removeTemporaryDirectory(
  WidgetTester tester,
  Directory directory, {
  int attempts = 120,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    final removed = await tester.runAsync(() async {
      try {
        if (await directory.exists()) await directory.delete(recursive: true);
        return true;
      } on FileSystemException {
        // Real time, not the test's clock: a pump finishes work the test zone
        // is holding, but the file is closed by the operating system and that
        // takes wall-clock milliseconds, more of them when the whole suite is
        // running at once.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return false;
      }
    });
    if (removed ?? true) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.runAsync(() => directory.delete(recursive: true));
}
