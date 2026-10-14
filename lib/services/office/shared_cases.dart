import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../portal/observed.dart';
import '../portal/portal_case.dart';
import '../portal/portal_channel.dart';
import '../clients/client.dart';
import '../portal/portal_database.dart';
import '../sync/hlc.dart';
import '../sync/sync_caps.dart';
import '../sync/sync_generation.dart';
import '../portal/portal_hearing.dart';
import '../uyap/uyap_case_panel_controller.dart';
import '../uyap/uyap_case_store.dart';
import 'office_network.dart';
import 'task_package.dart';

/// Where a case shared with this person, or given with a task, came from:
/// its owner's name and the device that has it.
typedef CaseSource = ({String name, String person, String device});

/// A UYAP case shared with chosen members of the office, person by person
/// (docs/buro.md): its particulars, parties, list of documents, money and
/// hearings kept alike with them whenever they and the owner meet on the
/// network; its documents not. A member opening a document the case's
/// owner has sends for it; one the owner has not, the owner's device
/// fetches from UYAP first, one at a time, and once fetched it is the
/// owner's too. UYAP is asked for what is read, never for all.
///
/// The same holds for a case given with a task: what was not sent with it
/// is asked of the one who gave it.
class SharedCases {
  SharedCases({
    required this.network,
    required this._database,
    this._store,
    this._panel,
  });

  /// The office part the cases go in, and the question a document is
  /// asked by.
  static const part = 'paylasilan-dosya';
  static const documentKind = 'paylasilan-evrak';

  /// A piece of a document: a channel's line holds a megabyte at most.
  static const piece = 512 * 1024;

  final OfficeNetwork network;
  final Future<PortalDatabase> Function() _database;
  final UyapCaseStore? _store;
  final UyapCasePanelController Function(UyapCaseStore store)? _panel;
  UyapCaseStore get store => _store ?? UyapCaseStore.instance;

  static const _sharesKey = 'paylasim';
  static const _everKey = 'paylasim-gecmis';

  /// The meta key a case shared with this person is marked under.
  static String markOf(String caseKey) => 'paylasim-gelen|$caseKey';
  static String _digestOf(String caseKey) => 'paylasim-ozet|$caseKey';

  /// Who stopped sharing [caseKey] with this person, kept after the shared
  /// mark goes: the case stays here, but it never became theirs. Their own
  /// portfolio naming it later clears this (PortalDatabase.mergeCases).
  static String _revokedOf(String caseKey) =>
      PortalDatabase.revokedShareKey(caseKey);

  /// Whether [caseKey] was shared with this person and is no longer: kept
  /// here, but someone else's.
  static bool revoked(PortalDatabase db, String caseKey) =>
      (db.meta(_revokedOf(caseKey)) ?? '').isNotEmpty;

  /// The mark a case shared with this person carries while it is being
  /// kept (see [merge]).
  static const _coming = '*';

  static Map<String, List<String>> _read(PortalDatabase db, String key) {
    try {
      final j = jsonDecode(db.meta(key) ?? '{}');
      if (j is! Map) return {};
      return {
        for (final e in j.entries)
          if (e.value is List)
            '${e.key}': [for (final p in e.value as List) '$p'],
      };
    } catch (_) {
      return {};
    }
  }

  /// The people each of this person's cases is shared with, by case.
  static Map<String, List<String>> shares(PortalDatabase db) =>
      _read(db, _sharesKey);

  /// The people [caseKey] is shared with.
  static List<String> sharedWith(PortalDatabase db, String caseKey) =>
      shares(db)[caseKey] ?? const [];

  /// [caseKey] shared with [people] and no one else; none unshares it.
  /// Those it no longer goes to are told, to forget it.
  static void share(
    PortalDatabase db,
    String caseKey,
    Iterable<String> people,
  ) {
    final all = shares(db);
    final ever = _read(db, _everKey);
    final now = {...people}.toList()..sort();
    if (now.isEmpty) {
      all.remove(caseKey);
    } else {
      all[caseKey] = now;
    }
    ever[caseKey] = {...?ever[caseKey], ...now}.toList()..sort();
    final was = shares(db)[caseKey] ?? const [];
    db.setMeta(_sharesKey, jsonEncode(all));
    db.setMeta(_everKey, jsonEncode(ever));
    // Whom it goes to changed: its account's word anew (R8).
    if (was.join('|') != now.join('|') ||
        db.caseShareVersion(caseKey) == null) {
      db.tickCaseShare(caseKey);
    }
  }

  /// Where [caseKey] came from when it is not this person's own: shared
  /// with them, or given with a task. Null for one of their own.
  static CaseSource? sourceOf(PortalDatabase db, String caseKey) {
    for (final key in [markOf(caseKey), ReceivedCase.markOf(caseKey)]) {
      final raw = db.meta(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        final j = jsonDecode(raw);
        if (j is! Map) continue;
        final device = '${j['cihaz'] ?? ''}';
        if (device.isEmpty) continue;
        return (
          name: '${j['ad'] ?? j['veren'] ?? ''}',
          person: '${j['kisi'] ?? ''}',
          device: device,
        );
      } catch (_) {}
    }
    return null;
  }

  /// Whether this person's case [caseKey] may go to [person]: shared with
  /// them, or given to them with a task.
  bool mayHave(PortalDatabase db, String caseKey, String person) {
    if (sharedWith(db, caseKey).contains(person)) return true;
    for (final t in network.tasks.all) {
      if (t.by != network.self?.deviceId &&
          network.ledger.personOf(t.by) != network.me) {
        continue;
      }
      final to = {for (final d in t.assignees.keys) network.ledger.personOf(d)};
      if (to.contains(person) && t.cases.any((c) => c.caseKey == caseKey)) {
        return true;
      }
    }
    return false;
  }

  // The office part.

  /// What goes to [toDevice]'s person: each case shared with them, as a
  /// task's package carries one but with no files; and the cases no
  /// longer shared with them, to forget.
  Future<Object?> export(String toDevice) async {
    final db = await _database();
    final person = network.ledger.personOf(toDevice);
    final cases = <Object?>[];
    final shared = shares(db);
    for (final e in shared.entries) {
      if (!e.value.contains(person)) continue;
      final kase = db.caseOf(e.key);
      if (kase == null) continue;
      final record = await store.load(kase.court, kase.number);
      if (record == null) continue;
      final json = record.toJson()
        ..['dosyalar'] = const <String, String>{}
        ..['onizlemeler'] = const <String, String>{}
        ..['bag'] = null
        // Which documents the owner has: they come at once.
        ..['sahipte'] = [
          for (final d in record.documents)
            for (final x in [d, ...d.attachments])
              if (store.fileOf(record, x.key) != null) x.key,
        ];
      json.addAll(TaskPackage.caseExtras(db, e.key));
      cases.add(json);
    }
    // The case's account in Folio, to one who may see the money and whose
    // Folio keeps it apart (R8); to the others it went to, that it no
    // longer goes. No word to set: whom the case is shared with, and who
    // may see the money, say it.
    final money = network.seesMoney && network.seesMoneyOf(toDevice);
    final keeps =
        network.peerCaps[toDevice]?.contains(SyncCaps.sharedLedger) ?? false;
    final ledgers = <Object?>[];
    if (keeps) {
      for (final e in _read(db, _everKey).entries) {
        if (!e.value.contains(person)) continue;
        // Shared before its account went with it: its word versioned once.
        if (db.caseShareVersion(e.key) == null) db.tickCaseShare(e.key);
        final version = db.caseShareVersion(e.key);
        if (version == null) continue;
        final open = money && (shared[e.key]?.contains(person) ?? false);
        ledgers.add({
          'dosya': e.key,
          'surum': '$version',
          if (open)
            'kayitlar': db.caseLedgerForOffice(e.key, network.me)
          else
            'kapali': true,
        });
      }
    }
    return {
      'dosyalar': cases,
      if (ledgers.isNotEmpty) 'defterler': ledgers,
      'kaldirilan': [
        for (final e in _read(db, _everKey).entries)
          if (e.value.contains(person) &&
              !(shared[e.key]?.contains(person) ?? false))
            e.key,
      ],
    };
  }

  /// What [fromDevice]'s person shares with this one: kept as cases of
  /// this device's, marked as theirs; those they no longer share,
  /// unmarked. True when anything changed.
  Future<bool> merge(Object? theirs, String fromDevice) async {
    if (theirs is! Map) return false;
    final db = await _database();
    final person = network.ledger.personOf(fromDevice);
    final name = network.ledger.member(fromDevice)?.name ?? '';
    var changed = false;
    for (final raw in theirs['dosyalar'] as List? ?? const []) {
      if (raw is! Map) continue;
      final json = raw.cast<String, Object?>();
      final got = ReceivedCase(json, const []);
      if (got.court.isEmpty || got.number.isEmpty) continue;
      final key = caseKey(got.number, got.court);
      // A case of this person's own is theirs, not the other's. One shared
      // before and no longer is not their own: shared again, it is taken.
      final mine =
          db.caseOf(key) != null &&
          sourceOf(db, key) == null &&
          !revoked(db, key);
      if (mine) continue;
      final digest = sha256.convert(utf8.encode(jsonEncode(json))).toString();
      final mark = jsonEncode({
        'ad': name,
        'kisi': person,
        'cihaz': fromDevice,
      });
      if (db.meta(_digestOf(key)) == digest && db.meta(markOf(key)) == mark) {
        continue;
      }
      // Marked as coming while it is kept: the person's own portfolio
      // naming the case meanwhile takes the mark away (mergeCases), and
      // then the case is theirs, not marked the other's when this resumes.
      db.setMeta(_revokedOf(key), _coming);
      await adopt(db, got);
      changed = true;
      if (!revoked(db, key)) continue;
      db.setMeta(markOf(key), mark);
      db.setMeta(_digestOf(key), digest);
      db.setMeta(_revokedOf(key), '');
    }
    // Their account of each case shared, kept apart, read only; none to one
    // who may not see the money (R8, R11).
    final money = network.seesMoney && network.seesMoneyOf(fromDevice);
    for (final raw in theirs['defterler'] as List? ?? const []) {
      if (raw is! Map || raw['dosya'] is! String) continue;
      final version = Hlc.tryParse(raw['surum']);
      if (version == null || person.isEmpty) continue;
      SyncClock.observe(db, version);
      if (db.takeSharedLedger(
        person,
        raw['dosya'] as String,
        version,
        closed: raw['kapali'] == true || !money,
        ownerName: name,
        records: [
          for (final j in raw['kayitlar'] as List? ?? const [])
            ?ClientRecord.fromJson(j),
        ],
      )) {
        changed = true;
      }
    }
    for (final key in theirs['kaldirilan'] as List? ?? const []) {
      final source = sourceOf(db, '$key');
      if (source == null || source.person != person) continue;
      db.setMeta(markOf('$key'), '');
      db.setMeta(_digestOf('$key'), '');
      // Kept with who it was, for the archive's label (case page).
      db.setMeta(
        _revokedOf('$key'),
        jsonEncode({'kisi': person, 'ad': source.name}),
      );
      changed = true;
    }
    return changed;
  }

  /// [got] kept on this device: in Dava Dosyalarım with its record and
  /// hearings, its documents those already here.
  Future<void> adopt(PortalDatabase db, ReceivedCase got) async {
    try {
      await store.adoptReceived(got.details, const {});
    } catch (_) {}
    db.mergeCases([PortalCase.create(number: got.number, court: got.court)]);
    final now = DateTime.now();
    final came = [
      for (final h in got.hearings)
        if (DateTime.tryParse('${h['tarih']}') case final at?)
          PortalHearing.create(
            number: got.number,
            court: got.court,
            at: at,
            kind: '${h['tur'] ?? ''}'.isEmpty
                ? null
                : Observed(
                    '${h['tur']}',
                    PortalChannel.uyapWeb,
                    now,
                    complete: false,
                  ),
          ),
    ];
    if (came.isNotEmpty) {
      final days = came.map((h) => h.at).toList()..sort();
      db.mergeHearings(
        PortalChannel.uyapWeb,
        days.first,
        days.last,
        came,
        complete: false,
      );
    }
  }

  // A document asked for.

  /// Documents being fetched from UYAP for someone, one at a time.
  final _fetching = <String>{};
  Future<void> _queue = Future.value();

  /// What [fromDevice] asked of a case of this person's: a piece of the
  /// document when it is here; else that it is being fetched from UYAP,
  /// or why it cannot be. Null when the case is not theirs to have.
  Future<Map<String, Object?>?> answer(
    Map<String, Object?> asked,
    String fromDevice,
  ) async {
    final db = await _database();
    final key = '${asked['dosya'] ?? ''}';
    final docKey = '${asked['evrak'] ?? ''}';
    final from = asked['bas'] is int ? asked['bas'] as int : 0;
    if (!mayHave(db, key, network.ledger.personOf(fromDevice))) return null;
    final kase = db.caseOf(key);
    if (kase == null) return null;
    final record = await store.load(kase.court, kase.number);
    if (record == null) return null;
    final doc = [
      for (final d in record.documents) ...[d, ...d.attachments],
    ].where((d) => d.key == docKey).firstOrNull;
    if (doc == null) return null;
    final file = store.fileOf(record, docKey);
    if (file != null) {
      final size = await file.length();
      final raf = await file.open();
      try {
        await raf.setPosition(from);
        final bytes = await raf.read(piece);
        return {
          'parca': base64Encode(bytes),
          'boy': size,
          'son': from + bytes.length >= size,
          'ad': file.uri.pathSegments.last,
        };
      } finally {
        await raf.close();
      }
    }
    final panel = (_panel ?? _defaultPanel)(store);
    if (!panel.connected) {
      return {'bekle': true, 'neden': 'uyap'};
    }
    final job = '$key|$docKey';
    if (_fetching.add(job)) {
      // One after another, with UYAP's pause between: never all at once.
      _queue = _queue.then((_) async {
        try {
          await panel.show(record);
          await panel.download([docKey]);
          await Future<void>.delayed(panel.pause);
        } catch (_) {
        } finally {
          _fetching.remove(job);
        }
      });
    }
    return {'bekle': true, 'neden': 'indiriliyor'};
  }

  static UyapCasePanelController _defaultPanel(UyapCaseStore store) =>
      UyapCasePanelController(store: store);

  /// [docKey] of a case shared with this person or given with a task,
  /// brought from the device it came from and kept as though fetched here.
  /// [onWait] hears why it waits: "indiriliyor" while that device fetches
  /// it from UYAP, "uyap" while it has no UYAP session, "kapali" while it
  /// cannot be reached. Null when it did not come.
  Future<File?> fetch(
    String caseKey,
    String docKey, {
    void Function(String why)? onWait,
    Duration patience = const Duration(minutes: 3),
    Duration every = const Duration(seconds: 3),
  }) async {
    final db = await _database();
    final source = sourceOf(db, caseKey);
    final kase = db.caseOf(caseKey);
    if (source == null || kase == null) return null;
    var record = await store.load(kase.court, kase.number);
    if (record == null) return null;
    final doc = [
      for (final d in record.documents) ...[d, ...d.attachments],
    ].where((d) => d.key == docKey).firstOrNull;
    if (doc == null) return null;
    if (store.fileOf(record, docKey) case final here?) return here;
    // The device it came from first, then any of its owner's.
    final devices = {
      source.device,
      if (source.person.isNotEmpty) ...network.ledger.devicesOf(source.person),
    };
    final until = DateTime.now().add(patience);
    while (DateTime.now().isBefore(until)) {
      final bytes = BytesBuilder(copy: false);
      String? waiting = 'kapali';
      for (final device in devices) {
        if (!network.isOnline(device)) continue;
        bytes.clear();
        waiting = null;
        for (var guard = 0; guard < 400; guard++) {
          final a = await network.askOffice(
            device,
            documentKind,
            body: {'dosya': caseKey, 'evrak': docKey, 'bas': bytes.length},
          );
          if (a == null) {
            waiting = 'kapali';
            break;
          }
          if (a['bekle'] == true) {
            waiting = '${a['neden'] ?? 'indiriliyor'}';
            break;
          }
          if (a['parca'] is! String) {
            waiting = 'kapali';
            break;
          }
          bytes.add(base64Decode(a['parca'] as String));
          if (a['son'] == true) {
            record = await store.load(kase.court, kase.number) ?? record;
            final (_, file) = await store.save(record!, doc, bytes.takeBytes());
            return file;
          }
        }
        if (waiting == 'indiriliyor') break;
      }
      onWait?.call(waiting ?? 'kapali');
      await Future<void>.delayed(every);
    }
    return null;
  }
}
