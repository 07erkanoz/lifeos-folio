import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/editor/document_history.dart';
import 'package:evrak_convert/services/editor/document_lock.dart';

/// Each editor window is a process of its own; what one holds, the others
/// must see.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('folio-kilit-');
    DocumentLock.folder = () async => Directory('${root.path}/acik');
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// Another window: a process holding the lock [name] with the system's
  /// own lock, as a Folio window would, until it is killed.
  Future<Process> otherWindow(String name) async {
    final file = '${root.path}/acik/$name.lock';
    await Directory('${root.path}/acik').create(recursive: true);
    final process = await Process.start('python3', [
      '-c',
      'import fcntl, sys, time\n'
          'f = open(sys.argv[1], "a")\n'
          'fcntl.lockf(f, fcntl.LOCK_EX)\n'
          'print("held", flush=True)\n'
          'time.sleep(60)\n',
      file,
    ]);
    await process.stdout.transform(utf8.decoder).first;
    return process;
  }

  test('within a window a claim is shared, and let go of with its last '
      'holder', () async {
    final first = await DocumentLock.acquire('belge-a');
    final second = await DocumentLock.acquire('belge-a');
    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(await DocumentLock.heldElsewhere('belge-a'), isFalse);
    await first!.release();
    await first.release();
    // Still held by the second: another window could not take it.
    expect(await _lockedFromOutside('${root.path}/acik/belge-a.lock'), isTrue);
    await second!.release();
    expect(await _lockedFromOutside('${root.path}/acik/belge-a.lock'), isFalse);
  }, skip: Platform.isLinux ? null : 'python3 ile Linux’ta denenir');

  test('what another window holds is not taken, and is free once that '
      'window is gone', () async {
    final key = 'belge-${DocumentHistory.documentKey('/tmp/dilekce.udf')}';
    final other = await otherWindow(key);
    expect(await DocumentLock.document('/tmp/dilekce.udf'), isNull);
    expect(await DocumentLock.documentHeld('/tmp/dilekce.udf'), isTrue);
    expect(await DocumentLock.heldElsewhere(key), isTrue);
    // A crash lets go of it as surely as closing the window.
    other.kill(ProcessSignal.sigkill);
    await other.exitCode;
    final mine = await DocumentLock.document('/tmp/dilekce.udf');
    expect(mine, isNotNull);
    await mine!.release();
  }, skip: Platform.isLinux ? null : 'python3 ile Linux’ta denenir');

  test(
    'a draft another window is writing is not offered for recovery',
    () async {
      final history = DocumentHistory(directory: Directory('${root.path}/h'));
      await history.capture(
        document: 'draft-1-0',
        name: 'Yeni belge.udf',
        sourcePath: null,
        format: 'udf',
        bytes: utf8.encode('yarım'),
        kind: 'recovery',
      );
      final other = await otherWindow('taslak-draft-1-0');
      expect(await history.recoveries(), isEmpty);
      expect(await history.recoveries(includeOpen: true), hasLength(1));
      other.kill(ProcessSignal.sigkill);
      await other.exitCode;
      // Its window is gone: what it left is there to be recovered.
      expect(await history.recoveries(), hasLength(1));
    },
    skip: Platform.isLinux ? null : 'python3 ile Linux’ta denenir',
  );
}

/// Whether another process finds the lock file at [path] taken.
Future<bool> _lockedFromOutside(String path) async {
  final result = await Process.run('python3', [
    '-c',
    'import fcntl, sys\n'
        'f = open(sys.argv[1], "a")\n'
        'try:\n'
        '    fcntl.lockf(f, fcntl.LOCK_EX | fcntl.LOCK_NB)\n'
        '    print("free")\n'
        'except OSError:\n'
        '    print("taken")\n',
    path,
  ]);
  return (result.stdout as String).trim() == 'taken';
}
