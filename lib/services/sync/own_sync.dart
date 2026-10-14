import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../clients/client.dart';
import '../clients/client_file_sync.dart';
import '../clients/client_files.dart';
import '../office/office_network.dart';
import '../notes/secret_notes.dart';
import '../notes/task_notes.dart';
import '../office/proposals.dart';
import '../office/shared_cases.dart';
import '../office/task_package.dart';
import '../platform/app_directories.dart';
import '../portal/portal_database.dart';
import '../portal/portal_sync.dart';
import '../uets/notice_deadlines.dart';
import '../uyap/uyap_case_store.dart';
import 'settings_sync.dart';
import 'uyap_documents_sync.dart';
import 'uyap_own_sync.dart';

/// Senkron (docs/buro.md): what one person's own devices keep alike when
/// they are on the same network, each part on or off on this device.
class OwnSync extends ChangeNotifier {
  OwnSync({
    OfficeNetwork? network,
    Future<PortalDatabase> Function()? database,
    Future<File> Function()? file,
    SessionHolder? sessions,
    this.phone,
    this.uyapStore,
  }) : _net = network ?? OfficeNetwork.instance,
       _database = database ?? PortalDatabase.shared,
       _file = file ?? _default,
       _sessionsGiven = sessions;

  static Future<File> _default() async =>
      File(p.join((await folioSupportDirectory()).path, 'senkron.json'));

  static final instance = OwnSync();

  final OfficeNetwork _net;
  final Future<PortalDatabase> Function() _database;

  /// The cases' lists given and taken; the computer's own when null.
  final UyapCaseStore? uyapStore;
  final Future<File> Function() _file;

  static const agenda = 'ajanda';
  static const sessionsPart = 'oturumlar';

  /// The lawyer profile, and the snippets, letterheads and choices: one
  /// person's, the same on each of their devices.
  static const profilePart = 'profil';
  static const settingsPart = 'ayarlar';

  /// What UYAP and UETS gave one own device, for the others: UYAP is
  /// asked once for all of them (lib/services/sync/uyap_own_sync.dart).
  static const uyapData = 'uyap';

  /// The clients' cards, minutes and powers with the office's members,
  /// their money with those who may see it. Off until the user turns it
  /// on: what goes to the office is theirs to choose.
  static const officeClients = 'muvekkil-buro';

  /// What was made secret and who in the office holds what of it: on
  /// always, whatever else is, for the taking back to be done from every
  /// own device (docs/senkron-plan.md R7).
  static const noteTracking = 'not-takibi';

  /// The proposals made and decided, and the device deciding: on always,
  /// with the office's members and between the person's own devices
  /// (docs/senkron-plan.md R6).
  static const proposalsPart = 'oneri', ownProposals = 'oneriler';
  static const _optIn = {officeClients};
  final _on = <String>{};

  final SessionHolder? _sessionsGiven;
  late final SessionHolder _sessions = _sessionsGiven ?? _PortalSessions();

  /// The sessions each own device said it holds, by device.
  final held = <String, Set<String>>{};
  Set<String> _mine = const {};

  Set<String> get heldHere => {
    for (final k in PortalSync.sessionKinds)
      if (_sessions.holds(k)) k,
  };

  /// The parts on: all of them until the user turns one off.
  final _off = <String>{};
  bool _started = false;

  bool isOn(String part) =>
      _optIn.contains(part) ? _on.contains(part) : !_off.contains(part);

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final file = await _file();
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString());
        if (j is Map) {
          _off.addAll([
            for (final s in (j['kapali'] as List? ?? const [])) '$s',
          ]);
          _on.addAll([for (final s in (j['acik'] as List? ?? const [])) '$s']);
        }
      }
    } catch (_) {}
    await _apply();
    _startSessions();
    // A phone leaves UYAP to a computer of the person's on the network that
    // holds a session and gives what it reads; the lawyer's own asking is
    // done here all the same.
    PortalSync.deferToComputer = () =>
        _isPhone &&
        isOn(uyapData) &&
        _net.ownOnline.any(
          (peer) =>
              !_phones.contains(peer.deviceId) &&
              _reads.contains(peer.deviceId) &&
              (held[peer.deviceId]?.contains('mobil') ?? false),
        );
    // Read anew here: the others are given it a moment later.
    PortalSync.uyapChanged = () {
      if (isOn(uyapData)) _net.ownChanged();
      // A case shared with the office read anew: to those it is shared
      // with too.
      _net.officeChanged();
    };
    // An own device found before these were set is made alike now.
    unawaited(_net.syncOwn());
  }

  void _startSessions() {
    _net.ownParts[sessionsPart] = OwnPart(
      export: () async => {
        'cihaz': _net.self?.deviceId,
        'telefon': _isPhone,
        'acik': heldHere.toList(),
        // Whether this one reads UYAP of itself and gives what it reads:
        // a phone leaves UYAP only to such a computer.
        'oto': (PortalSync.started?.autoFetch ?? false) && isOn(uyapData),
        // UYAP Mobil's latest tokens: the other goes on with them, not
        // with a refresh token this one may have spent.
        'mobil': ?_sessions.sessionOf('mobil'),
      },
      merge: (theirs) async {
        if (theirs is! Map || theirs['cihaz'] is! String) return false;
        final id = theirs['cihaz'] as String;
        held[id] = {
          for (final k in (theirs['acik'] as List? ?? const [])) '$k',
        };
        if (theirs['telefon'] == true) _phones.add(id);
        if (theirs['oto'] == true) {
          _reads.add(id);
        } else {
          _reads.remove(id);
        }
        _sessions.keepMobileAlike(theirs['mobil']);
        notifyListeners();
        return false;
      },
    );
    // Another own device asks for a session: shared, kept here too.
    _net.ownAnswers['oturum-ver'] = (asked) async {
      final data = _sessions.sessionOf('${asked['kanal']}');
      return (
        data == null
            ? <String, Object?>{'bos': true}
            : <String, Object?>{'oturum': data},
        null,
      );
    };
    // A phone renews UYAP Mobil through a computer of the person's.
    _net.ownAnswers['jeton-tazele'] = (asked) async =>
        (<String, Object?>{'jeton': await _sessions.freshMobile()}, null);
    if (_isPhone) _sessions.renewMobileThrough(_renewThroughComputer);
    _sessions.listenMobileTokens(_net.ownChanged);
    // Another own device gives one.
    _net.ownAnswers['oturum-al'] = (asked) async {
      final ok = await _sessions.takeSession(
        '${asked['kanal']}',
        asked['oturum'],
      );
      if (ok) _changedHere();
      return (<String, Object?>{'aldim': ok}, null);
    };
    _sessions.listen(() {
      final now = heldHere;
      if (now.length == _mine.length && now.containsAll(_mine)) return;
      _mine = now;
      _changedHere();
    });
    _mine = heldHere;
  }

  /// The person's own devices that said they are phones.
  final _phones = <String>{};

  /// The own devices that said they read UYAP of themselves and give it.
  final _reads = <String>{};

  /// Whether this device is a phone; by the platform when not said.
  final bool? phone;
  bool get _isPhone =>
      phone ??
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// A computer of the person's on the network that holds UYAP Mobil's
  /// session renews it for this phone: one refresh token, one spender.
  Future<Map<String, Object?>?> _renewThroughComputer() async {
    for (final peer in _net.ownOnline) {
      if (_phones.contains(peer.deviceId)) continue;
      if (!(held[peer.deviceId]?.contains('mobil') ?? false)) continue;
      final answer = await _net.askOwn(peer.deviceId, 'jeton-tazele');
      final tokens = answer?['jeton'];
      if (tokens is Map) return tokens.cast<String, Object?>();
    }
    return null;
  }

  void _changedHere() {
    notifyListeners();
    _net.ownChanged();
  }

  /// "Bu cihazda da aç": the session of [kind] [deviceId] has, opened
  /// here too; it stays open there. Why not, in the user's words.
  Future<String?> take(String deviceId, String kind) async {
    final answer = await _net.askOwn(
      deviceId,
      'oturum-ver',
      body: {'kanal': kind},
    );
    if (answer == null) return 'Cihaza ulaşılamadı. Aynı ağda ve açık mı?';
    if (answer['bos'] == true) return 'O cihazda bu oturum açık değil.';
    if (!await _sessions.takeSession(kind, answer['oturum'])) {
      return 'Oturum açılamadı; süresi dolmuş olabilir.';
    }
    _changedHere();
    return null;
  }

  /// "Öbür cihazla paylaş": the session of [kind] opened on [deviceId] too;
  /// it stays open here.
  Future<String?> give(String deviceId, String kind) async {
    final data = _sessions.sessionOf(kind);
    if (data == null) return 'Bu cihazda bu oturum açık değil.';
    final answer = await _net.askOwn(
      deviceId,
      'oturum-al',
      body: {'kanal': kind, 'oturum': data},
    );
    if (answer == null) return 'Cihaza ulaşılamadı. Aynı ağda ve açık mı?';
    if (answer['aldim'] != true) {
      return 'Oturum paylaşılamadı; süresi dolmuş olabilir.';
    }
    (held[deviceId] ??= {}).add(kind);
    _changedHere();
    return null;
  }

  Future<void> turn(String part, bool on) async {
    if (_optIn.contains(part)) {
      on ? _on.add(part) : _on.remove(part);
    } else {
      on ? _off.remove(part) : _off.add(part);
    }
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'kapali': _off.toList(), 'acik': _on.toList()}),
      );
    } catch (_) {}
    await _apply();
    notifyListeners();
    if (on) unawaited(_net.syncOwn());
  }

  final _settings = SettingsSync();

  /// UYAP's downloaded documents, given to an own device that asks.
  late final documents = UyapDocumentsSync(network: _net, store: uyapStore);

  /// The cases shared with the office's members, person by person; what
  /// they ask of them, answered.
  late final shared = SharedCases(
    network: _net,
    database: _database,
    store: uyapStore,
  );

  Future<void> _apply() async {
    // Only what the lawyer chose to share goes: on wherever there is an
    // office.
    _net.officeParts[SharedCases.part] = OfficePart(
      export: shared.export,
      merge: shared.merge,
    );
    _net.officeAnswers[SharedCases.documentKind] = shared.answer;
    for (final (part, files) in [
      (profilePart, const [SettingsSync.profile]),
      (settingsPart, SettingsSync.settings),
    ]) {
      if (isOn(part)) {
        _net.ownParts[part] = OwnPart(
          export: () => _settings.export(files),
          merge: (theirs) => _settings.merge(theirs, files),
        );
      } else {
        _net.ownParts.remove(part);
      }
    }
    if (isOn(uyapData)) {
      final uyap = UyapOwnSync(
        database: _database,
        store: uyapStore,
        ask: (deviceId, body) =>
            _net.askOwn(deviceId, UyapOwnSync.kind, body: body),
      );
      _net.ownParts[uyapData] = OwnPart(
        export: () async => uyap.summary(_net.self?.deviceId ?? ''),
        merge: uyap.merge,
      );
      _net.ownAnswers[UyapOwnSync.kind] = (asked) async =>
          (await uyap.answer(asked), null);
      // The documents themselves only when asked: a phone being set up.
      final docs = documents;
      _net.ownAnswers[UyapDocumentsSync.kind] = (asked) async =>
          (await docs.answer(asked), null);
      _net.ownFiles[UyapDocumentsSync.kind] = (t) async {
        if (await docs.came(t) > 0) PortalSync.started?.notifyListeners();
      };
    } else {
      _net.ownParts.remove(uyapData);
      _net.ownAnswers.remove(UyapOwnSync.kind);
      _net.ownAnswers.remove(UyapDocumentsSync.kind);
      _net.ownFiles.remove(UyapDocumentsSync.kind);
    }
    if (isOn(agenda)) {
      final db = await _database();
      _net.ownParts[agenda] = OwnPart(
        export: () async => db.agendaExport(),
        merge: (theirs) async {
          final changed = db.agendaMerge(theirs);
          unawaited(_forgetRemovedFiles(db));
          // The clients' files the records name, from whichever own
          // device has them.
          if (changed) unawaited(_fetchOwnFiles(db));
          // A deadline chosen, or whom the lawyer acts for, on another
          // device: those notices' deadlines made again here.
          if (db.mergedNotices.isNotEmpty) {
            refreshNoticeDeadlines(
              db,
              parties: NoticeDeadlineContext.parties,
              lawyer: NoticeDeadlineContext.lawyer,
              only: db.mergedNotices,
            );
          }
          // The agenda's pages read it again.
          if (changed) PortalSync.started?.notifyListeners();
          return changed;
        },
      );
    } else {
      _net.ownParts.remove(agenda);
    }
    if (isOn(officeClients)) {
      final db = await _database();
      _net.officeParts[officeClients] = OfficePart(
        // Money only between two who may both see it.
        export: (to) async {
          final sent = db.clientsOfficeExport(
            money: _net.seesMoney && _net.seesMoneyOf(to),
            me: _net.me,
          );
          // Who may hold each note from now on, for its taking back: every
          // device of its person's; told to this person's own at once.
          final person = _personOf(to);
          if (SecretNotes.recordCardHolds(
            db,
            sent,
            to,
            person,
            devices: _net.ledger.devicesOf(person),
          )) {
            _net.ownChanged();
          }
          return sent;
        },
        merge: (theirs, from) async {
          if (theirs is! Map) return false;
          final money = _net.seesMoney && _net.seesMoneyOf(from);
          final changed = db.clientsOfficeMerge(
            theirs.cast<String, Object?>(),
            money: money,
            me: _net.me,
            // Who the sender is, by the office's ledger: its person, not
            // what the message says of itself.
            from: _net.ledger.member(from) == null
                ? ''
                : _net.ledger.personOf(from),
          );
          unawaited(_forgetRemovedFiles(db));
          if (changed) {
            unawaited(
              ClientFileSync(db: db)
                  .fetchMissing(
                    (body) =>
                        _net.askOffice(from, ClientFileSync.kind, body: body),
                    may: (r) =>
                        ((db.clientCard(r.clientId)?.office ?? false) ||
                            r.clientId == officeCashId) &&
                        (!r.kind.financial || money),
                  )
                  .catchError((Object _) => 0),
            );
          }
          return changed;
        },
      );
      // A file asked by a member: only of a client shared, its money's
      // only to one who may see it.
      _net.officeAnswers[ClientFileSync.kind] = (asked, from) async {
        final db = await _database();
        return ClientFileSync(db: db).answer(
          asked,
          may: (r) =>
              ((db.clientCard(r.clientId)?.office ?? false) ||
                  r.clientId == officeCashId) &&
              (!r.kind.financial || (_net.seesMoney && _net.seesMoneyOf(from))),
        );
      };
    } else {
      _net.officeParts.remove(officeClients);
      _net.officeAnswers.remove(ClientFileSync.kind);
    }
    // An own device asks for a file: the same person's, all of them.
    _net.ownAnswers[ClientFileSync.kind] = (asked) async {
      final db = await _database();
      return (
        await ClientFileSync(db: db).answer(asked, may: _ownMay) ??
            <String, Object?>{'bos': true},
        null,
      );
    };
    await _noteParts();
    // The money others wrote comes from own devices only while it may.
    PortalDatabase.clientMoneyAllowed = () => _net.seesMoney;
    PortalDatabase.clientPerson = () => _net.me;
    // The notes' tracking and the tasks' notes are on always: every change
    // is told to both.
    PortalDatabase.changed = () {
      _net.ownChanged();
      _net.officeChanged();
    };
    _watchMoney();
  }

  /// The office person of [device], by the office's ledger; empty for one
  /// not of it.
  String _personOf(String device) =>
      _net.ledger.member(device) == null ? '' : _net.ledger.personOf(device);

  /// The tasks' notes with the office's members, and the notes' tracking
  /// with the person's own devices (R7).
  Future<void> _noteParts() async {
    final db = await _database();
    final notes = TaskNotes(
      db: db,
      me: () => _net.me,
      tasks: () => _net.tasks.all,
      personOf: _personOf,
      received: _net.packages.receivedPaths,
      // Who may hold what, to the person's other devices at once.
      onTracking: _net.ownChanged,
      devicesOf: _net.ledger.devicesOf,
    );
    _net.officeParts[TaskNotes.part] = OfficePart(
      export: (to) async => notes.export(to),
      merge: (theirs, from) async {
        final changed = await notes.merge(theirs, from);
        if (changed) PortalSync.started?.notifyListeners();
        return changed;
      },
    );
    _net.packageCame = notes.came;
    _net.prepareTaskFiles = (paths, caseKey) =>
        _withoutNotes(db, paths, caseKey);
    _net.ownParts[noteTracking] = OwnPart(
      export: () async => db.noteTrackingExport(),
      merge: (theirs) async {
        final changed = db.noteTrackingMerge(theirs);
        // A note made secret on another own device: taken back of the
        // office from here too, at once; and a giver's notes come here
        // from another own device, their older packages here cleaned.
        if (changed) {
          _net.officeChanged();
          await notes.cleanKnown();
        }
        return changed;
      },
    );
    await _net.packages.load();
    await _carryTaskNotes(db, _net.packages);
    await notes.cleanLeft();
    ProposalService proposals() => ProposalService(
      db,
      me: _net.me,
      device: _net.self?.deviceId ?? '',
      myName: _net.self?.name ?? '',
    );
    _net.officeParts[proposalsPart] = OfficePart(
      // Of money only between two who may both see it (R11).
      export: (to) async => proposals().officeExport(
        _personOf(to),
        money: _net.seesMoney && _net.seesMoneyOf(to),
      ),
      merge: (theirs, from) async {
        final changed = proposals().officeMerge(
          theirs,
          _personOf(from),
          money: _net.seesMoney && _net.seesMoneyOf(from),
        );
        if (changed) {
          _net.ownChanged();
          PortalSync.started?.notifyListeners();
        }
        return changed;
      },
    );
    _net.ownParts[ownProposals] = OwnPart(
      export: () async => proposals().ownExport(),
      merge: (theirs) async {
        final changed = proposals().ownMerge(theirs);
        if (changed) {
          _net.officeChanged();
          PortalSync.started?.notifyListeners();
        }
        return changed;
      },
    );
  }

  /// [paths], a task's case's files, its details made as this Folio makes
  /// them: none of the agenda's notes in them, the notices' deadlines as
  /// they are now. False when one could not be read or written.
  Future<bool> _withoutNotes(
    PortalDatabase db,
    List<String> paths,
    String caseKey,
  ) async {
    var ok = true;
    for (final path in paths) {
      final name = p.basename(path);
      if (!name.startsWith('dosya') || !name.endsWith('.json')) continue;
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        final j = jsonDecode(await file.readAsString());
        if (j is! Map || !j.containsKey('evrakAdlari')) continue;
        if (j[TaskNotes.format] != null && !j.containsKey('notlar')) continue;
        j
          ..remove('notlar')
          ..addAll(TaskPackage.caseExtras(db, caseKey));
        final part = File('$path.yeni');
        await part.writeAsString(jsonEncode(j), flush: true);
        await part.rename(path);
      } catch (_) {
        ok = false;
      }
    }
    return ok;
  }

  /// Once, from a Folio before the tasks' notes went apart: the packages
  /// given here, made without their notes before they go again, and each
  /// device they went to taken as holding them; those that came here, to
  /// be cleaned of their giver's notes once they come apart.
  Future<void> _carryTaskNotes(PortalDatabase db, TaskPackages packages) async {
    const done = 'gorev_notlari_gocu';
    if (db.meta(done) == '1') return;
    for (final key in {...packages.delivered, ...packages.pending.keys}) {
      final parts = key.split('|');
      if (parts.length != 3) continue;
      final scope = '${parts[0]}|${parts[1]}';
      db.recordHold(
        'eski:$scope',
        parts[2],
        _personOf(parts[2]),
        'gorev:$scope',
      );
    }
    // Each package given here, made without its notes: tried again at the
    // next start where one could not be, and checked again before it goes.
    var all = true;
    for (final e in packages.sources.entries) {
      if (!await _withoutNotes(db, e.value, e.key.split('|').last)) all = false;
    }
    for (final e in packages.pending.entries) {
      if (!await _withoutNotes(db, e.value, e.key.split('|')[1])) all = false;
    }
    for (final key in packages.receivedKeys) {
      final parts = key.split('|');
      if (parts.length != 2) continue;
      if (db.taskNotesCleaning(parts[0], parts[1]) == null) {
        db.setTaskNotesCleaning(parts[0], parts[1], 'bekliyor');
      }
    }
    if (all) db.setMeta(done, '1');
  }

  Future<void> _fetchOwnFiles(PortalDatabase db) async {
    for (final peer in _net.ownOnline.toList()) {
      try {
        await ClientFileSync(db: db).fetchMissing(
          (body) => _net.askOwn(peer.deviceId, ClientFileSync.kind, body: body),
          may: _ownMay,
        );
      } catch (_) {}
    }
  }

  /// What an own device has of a record's files: the money others wrote
  /// only while this person may see it.
  bool _ownMay(ClientRecord r) =>
      !r.kind.financial || _net.seesMoney || r.person == _net.me;

  /// The files of the records taken off here (unshared, the money no
  /// longer let), gone too where no other record names them.
  Future<void> _forgetRemovedFiles(PortalDatabase db) async {
    if (db.removedClientRecords.isEmpty) return;
    final gone = [...db.removedClientRecords];
    db.removedClientRecords.clear();
    final still = {
      for (final r in db.allClientRecords())
        for (final f in clientFilesOf(r)) '${r.clientId}|${f.sha256}',
    };
    final files = ClientFiles();
    for (final r in gone) {
      for (final f in clientFilesOf(r)) {
        if (still.contains('${r.clientId}|${f.sha256}')) continue;
        await files.forget(r.clientId, f);
      }
    }
  }

  bool _watching = false;
  bool? _sawMoney;

  /// Let no longer see the money, the money others wrote is forgotten
  /// here; what this person wrote stays.
  void _watchMoney() {
    if (_watching) return;
    _watching = true;
    void check() {
      final sees = _net.seesMoney;
      if (_sawMoney == sees) return;
      _sawMoney = sees;
      if (sees) return;
      unawaited(
        _database().then((db) async {
          db.forgetClientMoney(keepPerson: _net.me);
          await _forgetRemovedFiles(db);
        }),
      );
    }

    _net.addListener(check);
    check();
  }
}

/// The portals' sessions as Senkron moves them (see [PortalSync]).
abstract interface class SessionHolder {
  bool holds(String kind);
  Map<String, Object?>? sessionOf(String kind);
  Future<bool> takeSession(String kind, Object? kept);

  /// Told when a session opens or ends here.
  void listen(VoidCallback changed);

  /// UYAP Mobil's tokens, renewed when about to end, for one that asks.
  Future<Map<String, Object?>?> freshMobile();

  /// Another own device's tokens for the shared session, when newer.
  bool keepMobileAlike(Object? theirs);

  /// Who renews UYAP Mobil for this device; null for itself.
  void renewMobileThrough(Future<Map<String, Object?>?> Function()? ask);

  /// Told when UYAP Mobil's tokens change here.
  void listenMobileTokens(VoidCallback changed);
}

/// Folio's own sessions, once Folio started them: a test never wakes the
/// lawyer's sessions.
class _PortalSessions implements SessionHolder {
  PortalSync? get _sync => PortalSync.started;

  @override
  bool holds(String kind) => _sync?.holds(kind) ?? false;
  @override
  Map<String, Object?>? sessionOf(String kind) => _sync?.sessionOf(kind);
  @override
  Future<bool> takeSession(String kind, Object? kept) async =>
      await _sync?.takeSession(kind, kept) ?? false;
  @override
  void listen(VoidCallback changed) => _sync?.addListener(changed);
  @override
  Future<Map<String, Object?>?> freshMobile() async =>
      await _sync?.freshMobile();
  @override
  bool keepMobileAlike(Object? theirs) =>
      _sync?.keepMobileAlike(theirs) ?? false;
  @override
  void renewMobileThrough(Future<Map<String, Object?>?> Function()? ask) =>
      _sync?.renewMobileThrough(ask);
  @override
  void listenMobileTokens(VoidCallback changed) =>
      PortalSync.mobileTokensChanged = changed;
}
