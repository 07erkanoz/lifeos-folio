import 'dart:io';

import 'package:evrak_convert/services/uyap/uyap_sent_log.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _case = UyapCase('id-1', '2025/80', 'h1', 'Ankara 3. Asliye Hukuk');

UyapSendReceipt _sent(DateTime at, String name) => UyapSendReceipt(
  target: _case,
  documentName: name,
  documentType: 'Beyan Dilekçesi',
  startedAt: at,
  confirmed: true,
);

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('folio-gonderilen-');
  });
  tearDown(() => root.delete(recursive: true));

  test('what an editor window sent is followed in Folio, those of the '
      'last two days alone, each once', () async {
    // Each window a process of its own, with its own web service.
    final editor = UyapWebService.forTesting(
      sentLog: UyapSentLog(directory: root),
    );
    final folio = UyapWebService.forTesting(
      sentLog: UyapSentLog(directory: root),
    );
    final now = DateTime.now();
    await UyapSentLog(
      directory: root,
    ).add(_sent(now.subtract(const Duration(days: 3)), 'Eski.udf'));
    editor.track(_sent(now, 'Beyan.udf'));
    folio.track(_sent(now.subtract(const Duration(minutes: 1)), 'Cevap.udf'));
    // Written after the track returns.
    for (var i = 0; i < 250; i++) {
      if ((await UyapSentLog(directory: root).read()).length == 2) break;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    await folio.loadSent();
    await folio.loadSent();
    expect(folio.sent.map((r) => r.documentName), ['Beyan.udf', 'Cevap.udf']);
    final back = folio.sent.first;
    expect(back.target.number, '2025/80');
    expect(back.target.courtName, 'Ankara 3. Asliye Hukuk');
    expect(back.documentType, 'Beyan Dilekçesi');
    expect(back.confirmed, isTrue);
  });

  test('a stand-in keeps no sends', () async {
    final web = UyapWebService.forTesting();
    web.track(_sent(DateTime.now(), 'Beyan.udf'));
    await web.loadSent();
    expect(web.sent, hasLength(1));
  });
}
