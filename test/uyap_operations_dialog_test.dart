import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/widgets/uyap_operations_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _court = 'Ankara 3. Asliye Hukuk Mahkemesi';

UyapOperation _op(String name, DateTime at, String status, String number) =>
    UyapOperation(
      orderNumber: name,
      date: '${at.day}.${at.month}.${at.year} ${at.hour}:${at.minute}',
      court: _court,
      caseNumber: number,
      caseId: '',
      name: name,
      status: status,
      owner: '',
      documentId: name,
      globalDocumentId: '',
      documentNumber: '',
      documentDate: '',
      documentType: '',
    );

/// The web portal's "İşlemlerim": the send's record and an old one.
class _Web extends UyapWebService {
  _Web() : super.forTesting() {
    session.value = UyapSession(
      user: 'DENİZ KAYA',
      since: DateTime.now(),
      route: UyapLoginRoute.tray,
    );
  }

  /// The day each query was asked from.
  final asked = <DateTime>[];
  String status = 'Devam Ediyor';
  late final DateTime sentAt;

  @override
  bool get connected => true;

  @override
  Future<List<UyapOperation>> operations({
    required DateTime from,
    required DateTime to,
  }) async {
    asked.add(from);
    final old = DateTime.now().subtract(const Duration(days: 30));
    return [
      _op('Beyan Dilekçesi', sentAt, status, '2025/80'),
      if (!old.isBefore(DateTime(from.year, from.month, from.day)))
        _op('Eski Dilekçe', old, 'Devam Ediyor', '2024/12'),
    ];
  }
}

void main() {
  late UyapWebService before;
  setUp(() => before = UyapWebService.instance);
  tearDown(() => UyapWebService.instance = before);

  testWidgets('an unfinished send is followed less often while nothing '
      'changes, from its own day, the rest of the list kept', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final web = _Web()..sentAt = DateTime.now();
    web.track(
      UyapSendReceipt(
        target: const UyapCase('id-1', '2025/80', 'h1', _court),
        documentName: 'Beyan.udf',
        documentType: 'Beyan Dilekçesi',
        startedAt: web.sentAt,
        confirmed: true,
      ),
    );
    UyapWebService.instance = web;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UyapOperationsDialog())),
    );
    await tester.pump();
    await tester.pump();
    expect(web.asked, hasLength(1));
    expect(
      DateTime.now().difference(web.asked.first).inDays,
      greaterThanOrEqualTo(89),
    );
    Future<void> wait(int seconds) async {
      await tester.pump(Duration(seconds: seconds));
      await tester.pump();
    }

    await wait(30);
    expect(web.asked, hasLength(2));
    // Asked from the send's day alone.
    expect(DateTime.now().difference(web.asked[1]).inDays, 0);
    expect(find.textContaining('Eski Dilekçe'), findsWidgets);
    // Nothing changed: the next waits a minute.
    await wait(30);
    expect(web.asked, hasLength(2));
    await wait(30);
    expect(web.asked, hasLength(3));
    // Then two minutes; the send done meanwhile, the following ends.
    web.status = 'Tamamlandı';
    await wait(119);
    expect(web.asked, hasLength(3));
    await wait(1);
    expect(web.asked, hasLength(4));
    await wait(600);
    expect(web.asked, hasLength(4));
    await tester.pumpWidget(const SizedBox());
  });
}
