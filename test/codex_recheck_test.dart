// Codex's second review's scenarios (2026-10-09), kept as tests.
import 'package:evrak_convert/services/uets/notice_deadlines.dart';
import 'package:evrak_convert/services/uets/uets_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/document_model.dart';
import 'package:evrak_convert/services/clients/client.dart';
import 'package:evrak_convert/services/clients/client_files.dart';
import 'package:evrak_convert/services/clients/client_file_sync.dart';
import 'package:evrak_convert/services/clients/client_documents.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_deadline.dart';
import 'package:evrak_convert/services/platform/app_directories.dart';
import 'package:evrak_convert/services/platform/folder_zip.dart';
import 'package:evrak_convert/services/uets/notice_documents.dart';
import 'package:archive/archive.dart';

Client card({String person = 'deniz', bool office = true, int year = 2025}) =>
    Client(
      id: 'k1',
      name: 'Ayşe',
      person: person,
      office: office,
      sharedOnce: true,
      updated: DateTime(year),
    );

ClientRecord record(
  String id,
  String person, {
  ClientRecordKind kind = ClientRecordKind.meeting,
  Map<String, Object?> data = const {'konusulanlar': 'original'},
}) => ClientRecord(
  id: id,
  clientId: 'k1',
  kind: kind,
  person: person,
  data: data,
  created: DateTime(2025),
  updated: DateTime(2025),
  by: person,
);

DeadlineRecord deadline(String inputs, String due) => DeadlineRecord(
  id: 'd1',
  noticeId: 'n1',
  caseKey: null,
  ruleId: 'hmk',
  title: 'Süre',
  law: 'HMK',
  startEvent: 'teblig',
  startDay: '2026-10-01',
  rawDay: due,
  dueDay: due,
  state: 'aday',
  ownership: 'olasiBizim',
  reasons: const [],
  evidence: const {},
  engine: 10,
  calendar: 1,
  inputs: inputs,
  updated: DateTime(2026),
);

class BarrierFiles extends ClientFiles {
  BarrierFiles(Directory root) : super(root: () async => root);
  final entered = Completer<void>();
  final resume = Completer<void>();
  int calls = 0;
  @override
  Future<File> placeFor(String clientId, ClientFile f) async {
    if (++calls == 2) {
      entered.complete();
      await resume.future;
    }
    return super.placeFor(clientId, f);
  }
}

void registerTests() {
  test('an authenticated member cannot overwrite another author record', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.saveClient(card());
    db.saveClientRecord(record('g1', 'deniz'));
    final forged = record(
      'g1',
      'deniz',
    ).copyWith(person: 'selin', data: {'konusulanlar': 'forged'});
    db.clientsOfficeMerge(
      {
        'muvekkilKayitlari': [forged.toJson()],
      },
      money: false,
      me: 'deniz',
      from: 'selin',
    );
    expect(db.clientRecord('g1')!.text('konusulanlar'), 'original');
    expect(db.clientRecord('g1')!.person, 'deniz');
  });

  test('a delayed owner packet cannot undo a newer revocation', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    final old = card();
    db.saveClient(old);
    db.clientsOfficeMerge(
      {
        'muvekkiller': [card(office: false, year: 2026).toJson()],
      },
      money: false,
      me: 'selin',
      from: 'deniz',
    );
    // Kept as a mark of its unsharing, nothing of the person in it.
    expect(db.clientCard('k1')!.removed, isTrue);
    db.clientsOfficeMerge(
      {
        'muvekkiller': [old.toJson()],
      },
      money: false,
      me: 'selin',
      from: 'deniz',
    );
    expect(db.clientCard('k1')!.removed, isTrue);
    expect(db.clientCard('k1')!.name, '');
  });

  test('a member cannot claim a private card whose legacy owner is empty', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.saveClient(card(person: '', office: false));
    db.clientsOfficeMerge(
      {
        'muvekkiller': [card(person: 'selin', year: 2030).toJson()],
      },
      money: false,
      me: 'deniz',
      from: 'selin',
    );
    expect(db.clientCard('k1')!.office, isFalse);
    expect(db.clientCard('k1')!.person, '');
  });

  test(
    'legacy attachment files remain readable after storage format change',
    () async {
      final root = await Directory.systemTemp.createTemp('folio-legacy-');
      addTearDown(() => root.delete(recursive: true));
      final old = File('${root.path}/k1/rapor.pdf');
      await old.parent.create(recursive: true);
      await old.writeAsBytes([1, 2, 3]);
      final f = (
        name: 'rapor.pdf',
        path: 'k1/rapor.pdf',
        sha256: sha256.convert([1, 2, 3]).toString(),
      );
      expect(
        await ClientFiles(root: () async => root).locate('k1', f),
        isNotNull,
      );
    },
  );

  test('revocation removes the legacy physical attachment too', () async {
    final root = await Directory.systemTemp.createTemp('folio-legacy-delete-');
    addTearDown(() => root.delete(recursive: true));
    final old = File('${root.path}/k1/rapor.pdf');
    await old.parent.create(recursive: true);
    await old.writeAsBytes([1, 2, 3]);
    final f = (
      name: 'rapor.pdf',
      path: 'k1/rapor.pdf',
      sha256: sha256.convert([1, 2, 3]).toString(),
    );
    await ClientFiles(root: () async => root).forget('k1', f);
    expect(await old.exists(), isFalse);
  });

  test(
    'same content under two filenames reaches both attachment targets',
    () async {
      final db = PortalDatabase.memory();
      addTearDown(db.dispose);
      final root = await Directory.systemTemp.createTemp('folio-names-');
      addTearDown(() => root.delete(recursive: true));
      final sha = sha256.convert([1, 2, 3]).toString();
      final a = (name: 'a.pdf', path: '', sha256: sha);
      final b = (name: 'b.pdf', path: '', sha256: sha);
      db.saveClientRecord(
        record(
          'a',
          'deniz',
          data: {
            'ekler': [clientFileJson(a)],
          },
        ),
      );
      db.saveClientRecord(
        record(
          'b',
          'deniz',
          data: {
            'ekler': [clientFileJson(b)],
          },
        ),
      );
      final files = ClientFiles(root: () async => root);
      await ClientFileSync(db: db, files: files).fetchMissing(
        (_) async => {
          'parca': base64Encode([1, 2, 3]),
          'son': true,
          'boy': 3,
        },
      );
      expect(await files.locate('k1', a), isNotNull);
      expect(await files.locate('k1', b), isNotNull);
    },
  );

  test('an old confirmation exports the historical confirmed day', () {
    final source = PortalDatabase.memory();
    final target = PortalDatabase.memory();
    addTearDown(source.dispose);
    addTearDown(target.dispose);
    final old = deadline('old-input', '2026-11-01');
    source.replaceNoticeDeadlines('n1', [old]);
    source.saveDeadlineUser(
      DeadlineUser(
        deadlineId: 'd1',
        confirmedInputs: 'old-input',
        confirmedAt: DateTime(2026),
      ),
    );
    expect(source.deadline('d1')!.confirmedDay, '2026-11-01');
    target.replaceNoticeDeadlines('n1', [deadline('new-input', '2026-11-09')]);
    target.agendaMerge(source.agendaExport());
    expect(target.deadline('d1')!.confirmedDay, '2026-11-01');
    expect(target.deadline('d1')!.day, '2026-11-01');
  });

  test(
    'document generation rejects a remote client id escaping the root',
    () async {
      final root = await Directory.systemTemp.createTemp('folio-doc-path-');
      addTearDown(() => root.delete(recursive: true));
      var rejected = false;
      try {
        await writeClientDocument(
          Directory('${root.path}/clients'),
          '../outside',
          'sozlesme',
          DocModel(blocks: const []),
        );
      } catch (e) {
        rejected = e is ArgumentError;
      }
      expect(rejected, isTrue);
      expect(
        await File('${root.path}/outside/belgeler/sozlesme.udf').exists(),
        isFalse,
      );
    },
  );

  test(
    'an existing client directory link cannot redirect an attachment write',
    () async {
      final root = await Directory.systemTemp.createTemp('folio-link-');
      addTearDown(() => root.delete(recursive: true));
      final clients = Directory('${root.path}/clients')..createSync();
      final outside = Directory('${root.path}/outside')..createSync();
      await Link('${clients.path}/k1').create(outside.path);
      final files = ClientFiles(root: () async => clients);
      try {
        await files.keepBytes('k1', 'a.pdf', Uint8List.fromList([1, 2, 3]));
      } catch (_) {}
      expect(await outside.list().isEmpty, isTrue);
    },
  );

  test(
    'revocation during final path resolution cannot recreate a removed file',
    () async {
      final db = PortalDatabase.memory();
      addTearDown(db.dispose);
      final root = await Directory.systemTemp.createTemp('folio-revoke-write-');
      addTearDown(() => root.delete(recursive: true));
      final sha = sha256.convert([1, 2, 3]).toString();
      final f = (name: 'dekont.pdf', path: '', sha256: sha);
      db.saveClientRecord(
        record(
          'm1',
          'deniz',
          kind: ClientRecordKind.fee,
          data: {
            'ekler': [clientFileJson(f)],
          },
        ),
      );
      final files = BarrierFiles(root);
      var allowed = true;
      final fetching = ClientFileSync(db: db, files: files).fetchMissing(
        (_) async => {
          'parca': base64Encode([1, 2, 3]),
          'son': true,
          'boy': 3,
        },
        may: (_) => allowed,
      );
      await files.entered.future;
      allowed = false;
      db.forgetClientMoney(keepPerson: 'selin');
      await files.forget('k1', f);
      files.resume.complete();
      await fetching;
      expect(db.clientRecord('m1'), isNull);
      expect(await files.locate('k1', f), isNull);
    },
  );
}

List<DeadlineRecord> enforcement(
  String filename, {
  DateTime? read,
  String unit = 'Ankara 1. İcra Dairesi',
}) => noticeDeadlines(
  KeptNotice(
    UetsMessage(
      id: 'n',
      subject: '$unit [2026/100]',
      sent: DateTime.utc(2026, 10, 1),
      read: read,
    ),
  ),
  manifest: (
    state: 'alindi',
    fetchedAt: null,
    parts: [(id: 'p', name: filename)],
  ),
  now: DateTime(2026, 10, 2),
);
void main() {
  registerTests();
  test('IİK16 unread notice has a usable served fallback, no exception', () {
    expect(enforcement('Satis_Ilani.pdf').single.startDay, '2026-10-06');
  });
  test(
    'IİK16 late reading uses the earlier served day in the actual calculation',
    () {
      final r = enforcement(
        'Satis_Ilani.pdf',
        read: DateTime.utc(2026, 10, 9),
      ).single;
      expect(r.startDay, '2026-10-06');
      expect(r.dueDay, '2026-10-13');
    },
  );
  test('an enforcement office named Müdürlüğü keeps its tensip deadline', () {
    expect(
      enforcement(
        'Tensip_Zapti.pdf',
        read: DateTime.utc(2026, 10, 2),
        unit: 'Ankara 1. İcra Müdürlüğü',
      ).length,
      1,
    );
  });
  test(
    'new inferred clients from case parties invalidate the client index',
    () {
      final db = PortalDatabase.memory();
      addTearDown(db.dispose);
      final before = db.clientsRevision;
      db.saveCaseParties('case', [
        const UyapParty('Ayşe Karaca', 'Davacı', 'Av. Deniz Kaya', 'Kişi'),
      ], source: 'uyap');
      expect(
        db.clientEntries(lawyer: 'Av. Deniz Kaya').single.name,
        'Ayşe Karaca',
      );
      expect(db.clientsRevision > before, isTrue);
    },
  );
  test('a tensip with the office identified in package metadata keeps its deadline', () {
    final d = NoticeDocument(
      noticeId: 'n',
      seq: 1,
      name: 'dosyaBilgileriV1.xml',
      path: '',
      digest: '',
      state: 'ustveri',
      reader: 1,
      readAt: DateTime(2026),
      text: const NoticeCaseFile(
        unitName: 'Ankara 1. İcra Dairesi',
        number: '2026/100',
      ).toJson(),
    );
    final out = noticeDeadlines(
      KeptNotice(
        UetsMessage(
          id: 'n',
          subject: '2026/100 sayılı dosya',
          sent: DateTime.utc(2026, 10, 1),
          read: DateTime.utc(2026, 10, 2),
        ),
      ),
      manifest: (
        state: 'alindi',
        fetchedAt: null,
        parts: [(id: 'p', name: 'Tensip_Zapti.pdf')],
      ),
      documents: [d],
      now: DateTime(2026, 10, 2),
    );
    expect(out.length, 1);
  });
  test('a card with a known different owner is protected', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.saveClient(card());
    db.clientsOfficeMerge(
      {
        'muvekkiller': [card(person: 'selin', year: 2030).toJson()],
      },
      money: false,
      me: 'deniz',
      from: 'selin',
    );
    expect(db.clientCard('k1')!.person, 'deniz');
  });
  test('revocation export contains no private client fields', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.saveClient(
      card(office: false)
          .copyWith(phone: '555', idNo: '12345', note: 'private'),
    );
    final sent =
        (db.clientsOfficeExport(money: false, me: 'deniz')['muvekkiller']
                    as List)
                .single
            as Map;
    expect(sent['id'], 'k1');
    expect(sent['ad'], '');
    expect(sent.containsKey('kimlik'), isFalse);
    expect(sent.containsKey('telefon'), isFalse);
    expect(sent.containsKey('not'), isFalse);
  });
  test('new attachments are verified before serving', () async {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    final root = await Directory.systemTemp.createTemp('folio-new-file-');
    addTearDown(() => root.delete(recursive: true));
    final files = ClientFiles(root: () async => root);
    final f = await files.keepBytes(
      'k1',
      'a.pdf',
      Uint8List.fromList([1, 2, 3]),
    );
    db.saveClientRecord(
      record(
        'a',
        'deniz',
        data: {
          'ekler': [clientFileJson(f)],
        },
      ),
    );
    final sync = ClientFileSync(db: db, files: files);
    expect(
      await sync.answer({'sha256': f.sha256}, may: (_) => true),
      isNotNull,
    );
    final disk = (await files.locate('k1', f))!;
    await disk.writeAsBytes([4, 5, 6]);
    expect(await sync.answer({'sha256': f.sha256}, may: (_) => true), isNull);
  });
  test('attachment writes reject a traversing client id', () async {
    final root = await Directory.systemTemp.createTemp('folio-id-check-');
    addTearDown(() => root.delete(recursive: true));
    var rejected = false;
    try {
      await ClientFiles(root: () async => root)
          .keepBytes('../outside', 'a.pdf', Uint8List(1));
    } catch (e) {
      rejected = e is ArgumentError;
    }
    expect(rejected, isTrue);
  });
  test('a new explicit confirmation synchronizes its day', () {
    final source = PortalDatabase.memory(), target = PortalDatabase.memory();
    addTearDown(source.dispose);
    addTearDown(target.dispose);
    source.replaceNoticeDeadlines('n1', [deadline('old-input', '2026-11-01')]);
    source.saveDeadlineUser(
      DeadlineUser(
        deadlineId: 'd1',
        confirmedInputs: 'old-input',
        confirmedAt: DateTime(2026),
        confirmedDay: '2026-11-01',
      ),
    );
    target.replaceNoticeDeadlines('n1', [deadline('new-input', '2026-11-09')]);
    target.agendaMerge(source.agendaExport());
    expect(target.deadline('d1')!.confirmedDay, '2026-11-01');
  });
  test('the Mac keeps its existing old folder', () async {
    final root = await Directory.systemTemp.createTemp('folio-mac-check-');
    addTearDown(() => root.delete(recursive: true));
    final current = Directory('${root.path}/com.lifeos.folio')..createSync();
    expect((await macDataFolder(current)).path, current.path);
    final old = Directory('${root.path}/com.erkanoz.evrakConvert')
      ..createSync();
    expect((await macDataFolder(current)).path, old.path);
  });
  test('ZIP extraction skips traversal and symbolic links', () async {
    final root = await Directory.systemTemp.createTemp('folio-zip-check-');
    addTearDown(() => root.delete(recursive: true));
    final link = ArchiveFile.bytes('link', utf8.encode('../'))
      ..symbolicLink = '../'
      ..mode = 0xa1ff;
    final archive = Archive()
      ..add(ArchiveFile.bytes('../outside.txt', [1]))
      ..add(link)
      ..add(ArchiveFile.bytes('link/outside2.txt', [2]))
      ..add(ArchiveFile.bytes('ok/a.txt', [3]));
    final zipBytes = ZipEncoder().encode(archive);
    // ZipEncoder labels entries as DOS; a real Unix symlink uses creator OS 3.
    for (var i = 0; i + 5 < zipBytes.length; i++) {
      if (zipBytes[i] == 0x50 &&
          zipBytes[i + 1] == 0x4b &&
          zipBytes[i + 2] == 0x01 &&
          zipBytes[i + 3] == 0x02)
        zipBytes[i + 5] = 3;
    }
    expect(
      ZipDecoder().decodeBytes(zipBytes).findFile('link')!.isSymbolicLink,
      isTrue,
    );
    final zip = File('${root.path}/incoming.zip')..writeAsBytesSync(zipBytes);
    final out = await unzipFolder(zip.path);
    expect(File('${root.path}/outside.txt').existsSync(), isFalse);
    expect(File('${root.path}/outside2.txt').existsSync(), isFalse);
    expect(File('$out/ok/a.txt').existsSync(), isTrue);
  });
}
