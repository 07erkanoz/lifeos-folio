import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:evrak_convert/services/office/office_task.dart';
import 'package:evrak_convert/services/office/task_package.dart';
import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:evrak_convert/services/uyap/uyap_case_panel_controller.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';

/// UYAP as the giver has it: connected; one document it refuses, the
/// others it gives.
class _Uyap extends UyapCasePanelController {
  _Uyap(this.keep) : super(store: keep, pause: Duration.zero);

  final UyapCaseStore keep;
  final asked = <String>[];

  @override
  bool get connected => true;

  @override
  Future<void> show(UyapCaseRecord record) async {}

  @override
  Future<int> download([Iterable<String>? keys]) async {
    final key = keys!.single;
    asked.add(key);
    if (key == 'b') throw StateError('UYAP vermedi');
    final record = (await keep.load(_court, '2024/318'))!;
    final d = record.documents.firstWhere((d) => d.key == key);
    await keep.save(record, d, Uint8List.fromList(utf8.encode('%PDF $key')));
    return 1;
  }
}

const _court = 'Antalya 3. Asliye Hukuk Mahkemesi';

void main() {
  late Directory dir;
  late UyapCaseStore store;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('folio-task-package-');
    store = UyapCaseStore(
      directory: Directory('${dir.path}/uyap'),
      settings: UyapSettings(
        directory: Directory('${dir.path}/uyap'),
        home: '${dir.path}/ev',
      ),
    );
    UyapCaseDocument doc(String key, String type) => UyapCaseDocument(
      key: key,
      documentId: key,
      caseId: '1',
      type: type,
      number: key,
      approved: '01.10.2026 10:00',
      sender: 'Mahkeme',
      description: '',
    );
    await store.keep(
      target: const UyapCase('1', '2024/318', '', _court),
      details: const UyapCaseDetails(kind: 'Alacak', status: 'Açık'),
      parties: const [UyapParty('AYŞE KARACA', 'Davacı', '', 'Kişi')],
      documents: UyapCaseDocuments([
        doc('a', 'Ara Karar'),
        doc('b', 'Bilirkişi Raporu'),
        doc('c', 'Tensip Zaptı'),
      ]),
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('the documents not here are fetched one at a time: one UYAP refuses '
      'does not keep the others back, and each is told as it is fetched', () async {
    final key = caseKey('2024/318', _court);
    final c = TaskCase(
      caseKey: key,
      number: '2024/318',
      court: _court,
      docKeys: const ['b', 'c'],
    );
    expect(await TaskPackage.notHere(c, store: store), 2);
    final uyap = _Uyap(store);
    final told = <String>[];
    final pack = await TaskPackage.pack(
      c,
      store: store,
      controller: uyap,
      temp: () async => Directory('${dir.path}/tmp'),
      database: () async => null,
      onProgress: told.add,
    );
    expect(uyap.asked, ['b', 'c']);
    expect(pack.missing, ['Bilirkişi Raporu']);
    // dosya.json and the one fetched.
    expect(pack.paths, hasLength(2));
    expect(File(pack.paths.last).readAsStringSync(), '%PDF c');
    expect(told.first, contains('1/2'));
    expect(told.first, contains('Bilirkişi Raporu'));
    expect(told, contains(predicate<String>((t) => t.contains('2/2'))));
    final json = jsonDecode(File(pack.paths.first).readAsStringSync()) as Map;
    expect(json['secili'], ['b', 'c']);
    expect((json['evrakAdlari'] as Map).keys, ['c']);
  });

  test('the case goes with its hearings, deadlines, notices and notes, and '
      'the one it is given to reads them', () async {
    final key = caseKey('2024/318', _court);
    final db = PortalDatabase.memory();
    final at = DateTime(2026, 11, 20, 10, 30);
    db.mergeHearings(
      PortalChannel.uyapWeb,
      DateTime(2026, 11, 1),
      DateTime(2026, 11, 30),
      [
        PortalHearing.create(
          number: '2024/318',
          court: _court,
          at: at,
          kind: Observed(
            'Ön inceleme duruşması',
            PortalChannel.uyapWeb,
            DateTime(2026, 10, 1),
          ),
        ),
      ],
      complete: true,
    );
    db.saveAgenda(
      AgendaItem(
        id: 'n1',
        kind: 'note',
        title: 'Tanık listesi hazırlanacak',
        caseKey: key,
        updated: DateTime(2026, 10, 1),
      ),
    );
    db.saveAgenda(
      AgendaItem(
        id: 'd1',
        kind: 'deadline',
        title: 'Bilirkişi raporuna itiraz',
        at: DateTime(2026, 11, 3),
        caseKey: key,
        updated: DateTime(2026, 10, 1),
      ),
    );
    final c = TaskCase(caseKey: key, number: '2024/318', court: _court);
    final pack = await TaskPackage.pack(
      c,
      store: store,
      controller: _Uyap(store),
      temp: () async => Directory('${dir.path}/tmp'),
      database: () async => db,
    );
    final got = ReceivedCase.fromPaths(pack.paths)!;
    expect(got.hearings.single['tur'], 'Ön inceleme duruşması');
    expect(DateTime.parse('${got.hearings.single['tarih']}'), at);
    expect(got.deadlines.single['baslik'], 'Bilirkişi raporuna itiraz');
    expect(got.notes.single['baslik'], 'Tanık listesi hazırlanacak');
    expect(got.notices, isEmpty);
  });
}
