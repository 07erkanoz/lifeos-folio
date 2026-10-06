import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/editor/document_history.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late DocumentHistory history;
  final key = DocumentHistory.documentKey('/documents/example.udf');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('folio-history-');
    history = DocumentHistory(directory: root, maxVersions: 3, maxBytes: 100);
  });
  tearDown(() async => root.delete(recursive: true));
  Future<void> capture(String text, {String kind = 'saved'}) => history.capture(
    document: key,
    name: 'example.udf',
    sourcePath: '/documents/example.udf',
    format: 'txt',
    bytes: utf8.encode(text),
    kind: kind,
  );
  test(
    'versions survive restart, deduplicate and retain newest within bounds',
    () async {
      for (final text in [
        'original',
        'original',
        'second',
        'third',
        'fourth',
      ]) {
        await capture(text);
      }
      final restarted = DocumentHistory(directory: root);
      final entries = await restarted.versions(key);
      expect(entries.length, 3);
      expect(utf8.decode(await restarted.read(entries.first)), 'fourth');
      expect(utf8.decode(await restarted.read(entries.last)), 'second');
      await capture('x' * 90);
      expect((await history.versions(key)).length, 2);
    },
  );
  test(
    'only complete latest recovery is offered and clear survives restart',
    () async {
      await capture('last saved');
      await capture('unfinished 1', kind: 'recovery');
      await capture('unfinished 2', kind: 'recovery');
      final restarted = DocumentHistory(directory: root);
      final entries = await restarted.recoveries();
      expect(entries.length, 1);
      expect(utf8.decode(await restarted.read(entries.single)), 'unfinished 2');
      expect(
        utf8.decode(
          await restarted.read((await restarted.versions(key)).single),
        ),
        'last saved',
      );
      await restarted.clearRecovery(key);
      expect(await DocumentHistory(directory: root).recoveries(), isEmpty);
    },
  );
  test('malformed manifests and interrupted unpublished payloads are ignored; tampering is detected', () async {
    await capture('recover me', kind: 'recovery');
    final entry = (await history.recoveries()).single;
    await File('${root.path}/recovery/interrupted.bin')
        .writeAsString('partial');
    await File('${root.path}/recovery/bad.json').writeAsString('{');
    await File('${root.path}/recovery/bad-types.json').writeAsString('{}');
    expect((await history.recoveries()).length, 1);
    await File('${root.path}/recovery/${entry.id}.bin')
        .writeAsString('damaged');
    await expectLater(history.read(entry), throwsFormatException);
  });
  test('clear waits for in-flight recovery and prevents a queued write from resurrecting it', () async {
    final started = Completer<void>(), finish = Completer<void>();
    var writes = 0;
    final recovery = DraftRecovery(
      write: () async {
        writes++;
        started.complete();
        await finish.future;
        await capture('pending', kind: 'recovery');
      },
      remove: () => history.clearRecovery(key),
      onError: (e) => fail('$e'),
    );
    final writing = recovery.flush();
    await started.future;
    final queued = recovery.flush();
    final clearing = recovery.clear();
    finish.complete();
    await Future.wait([writing, queued, clearing]);
    expect(writes, 1);
    expect(await history.recoveries(), isEmpty);
    recovery.dispose();
  });
  test(
    'each editor session keeps its own draft; open ones are not offered',
    () async {
      Future<void> draft(String slot, String text) => history.capture(
        document: slot,
        name: 'example.udf',
        sourcePath: '/documents/example.udf',
        format: 'rich-draft',
        bytes: utf8.encode(text),
        kind: 'recovery',
      );
      final crashed = DocumentHistory.draftKey();
      final reopened = DocumentHistory.draftKey();
      expect(crashed, isNot(reopened));
      await draft(crashed, 'before the crash');
      DocumentHistory.holdDraft(reopened);
      addTearDown(() => DocumentHistory.releaseDraft(reopened));
      // The second session writing, and clearing, its own slot leaves the
      // first session's draft where it was.
      await draft(reopened, 'after reopening');
      await history.clearRecovery(reopened);
      await draft(reopened, 'still typing');
      final offered = await history.recoveries();
      expect(offered.map((e) => e.document), [crashed]);
      expect(
        (await history.recoveriesFor('/documents/example.udf')).single.document,
        crashed,
      );
      expect(await history.recoveriesFor('/documents/other.udf'), isEmpty);
      expect(
        (await history.recoveries(includeOpen: true)).map((e) => e.document),
        unorderedEquals([crashed, reopened]),
      );
      DocumentHistory.releaseDraft(reopened);
      expect((await history.recoveries()).length, 2);
    },
  );
  test(
    'a signed UDF is marked as such, and restoring keeps what it replaces',
    () async {
      final big = DocumentHistory(directory: root);
      final path = '${root.path}/belge.udf';
      List<int> udf({required bool signed}) {
        final archive = Archive()
          ..addFile(ArchiveFile('content.xml', 3, utf8.encode('<a>')));
        if (signed) archive.addFile(ArchiveFile('sign.sgn', 2, [1, 2]));
        return ZipEncoder().encode(archive);
      }

      final signed = udf(signed: true), plain = udf(signed: false);
      Future<void> keep(List<int> bytes, String kind) => big.capture(
        document: DocumentHistory.documentKey(path),
        name: 'belge.udf',
        sourcePath: path,
        format: 'udf',
        bytes: bytes,
        kind: kind,
      );
      await keep(signed, 'signed');
      await keep(plain, 'saved');
      await File(path).writeAsBytes(plain);
      var versions = await big.versions(DocumentHistory.documentKey(path));
      expect(versions.map((v) => v.signed), [false, true]);
      expect(versions.last.kindLabel, 'E-imzalandı');

      await big.restoreToFile(versions.last, path);
      expect(await File(path).readAsBytes(), signed);
      versions = await big.versions(DocumentHistory.documentKey(path));
      expect(versions.first.kind, 'restored');
      expect(versions.first.signed, isTrue);
      // What the file held until then is right under it — already kept as the
      // last save, so not kept twice — and can be gone back to in turn.
      expect(versions[1].kind, 'saved');
      expect(versions[1].signed, isFalse);
      expect(versions, hasLength(3));
    },
  );
  test('continuous changes use a bounded interval, not an endlessly delayed debounce', () async {
    var writes = 0;
    final recovery = DraftRecovery(
      write: () async {
        writes++;
      },
      remove: () async {},
      onError: (e) => fail('$e'),
      delay: const Duration(milliseconds: 20),
    );
    for (var i = 0; i < 15; i++) {
      recovery.changed();
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(writes, greaterThanOrEqualTo(2));
    await recovery.clear();
    recovery.dispose();
  });
}
