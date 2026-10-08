import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import 'office_identity.dart';
import 'office_known.dart';
import 'office_peer.dart';

enum OfficeRole {
  manager('Yönetici'),
  lawyer('Avukat'),
  trainee('Stajyer'),
  secretary('Sekreter');

  const OfficeRole(this.label);
  final String label;

  static OfficeRole? of(Object? name) {
    for (final r in values) {
      if (r.name == name) return r;
    }
    return null;
  }
}

/// A member of the office: a device, under the name of its person.
class OfficeMember {
  const OfficeMember({
    required this.deviceId,
    required this.userId,
    required this.publicKey,
    required this.name,
    required this.device,
    required this.platform,
    required this.role,
    required this.since,
    this.founder = false,
    String? person,
  }) : person = person ?? deviceId;

  final String deviceId, userId, publicKey, name, device;

  /// The person it is a device of, by the device they were taken in with:
  /// what a task is given to and a talk is had with. A person's later
  /// devices, which they add themself, share it.
  final String person;

  OfficeMember copyWith({OfficeRole? role}) => OfficeMember(
    deviceId: deviceId,
    userId: userId,
    publicKey: publicKey,
    name: name,
    device: device,
    platform: platform,
    role: role ?? this.role,
    since: since,
    founder: founder,
    person: person,
  );
  final OfficePlatform platform;
  final OfficeRole role;
  final DateTime since;
  final bool founder;

  /// As a known device, so that a member is talked to like one.
  KnownDevice get asKnown => KnownDevice(
    deviceId: deviceId,
    userId: userId,
    publicKey: publicKey,
    name: name,
    device: device,
    platform: platform,
    knownAt: since,
  );
}

/// The office (docs/buro.md, Büro yönetimi): a ledger of signed records,
/// with no server. The founder signs the first, and the office is named by
/// that record's hash; each later one, a member taken in, a role given, a
/// member let go, is signed by a device that is a manager when it comes.
/// Records go from member to member; one whose signature does not hold, or
/// whose signer was no manager, is kept nowhere.
class OfficeLedger {
  OfficeLedger({Future<File> Function()? file}) : _file = file ?? _default;

  static Future<File> _default() async =>
      File(p.join((await folioSupportDirectory()).path, 'buro_defter.json'));

  final Future<File> Function() _file;
  List<Map<String, Object?>> _records = [];
  _State _state = const _State.empty();

  String? get officeId => _state.officeId;
  String get officeName => _state.officeName;
  bool get exists => _state.officeId != null;
  List<OfficeMember> get members =>
      _state.members.values.toList()..sort((a, b) {
        if (a.role != b.role) return a.role.index.compareTo(b.role.index);
        return a.name.compareTo(b.name);
      });
  OfficeMember? member(String deviceId) => _state.members[deviceId];

  /// The person [deviceId] is a device of; itself when it is no member.
  String personOf(String deviceId) =>
      _state.members[deviceId]?.person ?? deviceId;

  /// The office's people, each by the device they were taken in with.
  List<OfficeMember> get people => [
    for (final m in members)
      if (m.person == m.deviceId) m,
  ];

  /// Every device of [person] in the office.
  List<String> devicesOf(String person) => [
    for (final m in _state.members.values)
      if (m.person == person) m.deviceId,
  ];
  bool isManager(String deviceId) =>
      _state.members[deviceId]?.role == OfficeRole.manager;

  /// Whether [deviceId]'s person sees the clients' fees, advances and
  /// costs: a manager, or one a manager let see them.
  bool seesMoney(String deviceId) =>
      isManager(deviceId) || _state.money.contains(personOf(deviceId));

  /// The people a manager let see the money, by their first device.
  Set<String> get moneyPeople => Set.unmodifiable(_state.money);

  /// The records, for sending to another member.
  List<Map<String, Object?>> get records => List.unmodifiable(_records);

  Future<void> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is List) {
          final records = [
            for (final r in json)
              if (r is Map<String, Object?>) r,
          ];
          _state = await _replay(records);
          _records = _state.kept;
        }
      }
    } catch (_) {}
  }

  // One write at a time: two at once raced for the same part file.
  Future<void> _saving = Future.value();

  Future<void> _save() =>
      _saving = _saving.then((_) => _write()).catchError((Object _) {});

  Future<void> _write() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final part = File('${file.path}.part');
    await part.writeAsString(jsonEncode(_records), flush: true);
    await part.rename(file.path);
  }

  static String _canonical(Map<String, Object?> r) {
    final keys = r.keys.where((k) => k != 'sig').toList()..sort();
    return jsonEncode({for (final k in keys) k: r[k]});
  }

  static String idOf(Map<String, Object?> r) => hash.sha256
      .convert(utf8.encode('${_canonical(r)}|${r['sig']}'))
      .toString();

  Future<Map<String, Object?>> _sign(
    OfficeIdentity identity,
    Map<String, Object?> record,
  ) async {
    final r = {
      ...record,
      'imzalayan': identity.deviceId,
      'at': DateTime.now().toUtc().toIso8601String(),
    };
    final sig = await Ed25519().sign(
      utf8.encode(_canonical(r)),
      keyPair: identity.device,
    );
    return {...r, 'sig': base64Encode(sig.bytes)};
  }

  Map<String, Object?> _about(OfficePeer who, String publicKey) => {
    'cihaz': who.deviceId,
    'u': who.userId,
    'dk': publicKey,
    'n': who.name,
    'c': who.device,
    'p': who.platform.name,
  };

  /// Founds an office with this device as its first manager.
  Future<void> found(
    OfficeIdentity identity,
    OfficePeer self,
    String name,
  ) async {
    if (exists) return;
    final r = await _sign(identity, {
      'k': 'kur',
      'ad': name.trim(),
      ..._about(self, base64Encode(identity.devicePublic.bytes)),
      'rol': OfficeRole.manager.name,
    });
    await _apply([r]);
  }

  /// Takes a known device in, with its role.
  Future<String?> admit(
    OfficeIdentity identity,
    KnownDevice device,
    OfficeRole role,
  ) => _change(identity, {
    'k': 'uye',
    'cihaz': device.deviceId,
    'u': device.userId,
    'dk': device.publicKey,
    'n': device.name,
    'c': device.device,
    'p': device.platform.name,
    'rol': role.name,
  });

  Future<String?> setRole(
    OfficeIdentity identity,
    String deviceId,
    OfficeRole role,
  ) => _change(identity, {'k': 'rol', 'cihaz': deviceId, 'rol': role.name});

  /// Lets [deviceId]'s person see the clients' money, or no longer.
  Future<String?> setMoney(
    OfficeIdentity identity,
    String deviceId,
    bool open,
  ) => _change(identity, {'k': 'ucret', 'cihaz': deviceId, 'acik': open});

  Future<String?> remove(OfficeIdentity identity, String deviceId) =>
      _change(identity, {'k': 'cikar', 'cihaz': deviceId});

  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// The recovery code's key: the code is written down, the key never kept.
  static Future<SimpleKeyPair?> _recoveryKey(String code) async {
    final clean = code.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    if (clean.length != 32) return null;
    final bits = StringBuffer();
    for (final c in clean.split('')) {
      final v = _alphabet.indexOf(
        c == 'O'
            ? '0'
            : c == 'I' || c == 'L'
            ? '1'
            : c,
      );
      if (v < 0) return null;
      bits.write(v.toRadixString(2).padLeft(5, '0'));
    }
    final b = bits.toString();
    final bytes = [
      for (var i = 0; i + 8 <= b.length; i += 8)
        int.parse(b.substring(i, i + 8), radix: 2),
    ];
    final seed = hash.sha256.convert([
      ...utf8.encode('folio-buro-kurtarma-1'),
      ...bytes,
    ]).bytes;
    return Ed25519().newKeyPairFromSeed(seed);
  }

  static String _newCode() {
    final r = Random.secure();
    final chars = [for (var i = 0; i < 32; i++) _alphabet[r.nextInt(32)]];
    return [for (var i = 0; i < 32; i += 4) chars.sublist(i, i + 4).join()]
        .join('-');
  }

  /// The founder's recovery code: written down, it brings the founder back
  /// on a new device should all theirs be lost. A new one voids the last.
  Future<String?> makeRecovery(OfficeIdentity identity) async {
    if (!(member(identity.deviceId)?.founder ?? false)) return null;
    final code = _newCode();
    final key = await _recoveryKey(code);
    final r = await _sign(identity, {
      'k': 'kurtarma',
      'up': base64Encode((await key!.extractPublicKey()).bytes),
      // The code it takes the place of, and the recoveries by it that
      // stand: no other by that code ever will.
      'yerine': _state.recoveryId,
      'kalan': [
        for (final k in _records)
          if (k['k'] == 'kurtar') idOf(k),
      ],
      'buro': officeId,
      'onceki': idOf(_records.last),
    });
    final before = _records.length;
    await _apply([r]);
    return _records.length == before ? null : code;
  }

  bool get hasRecovery => _state.recovery != null;

  /// This device, not of the office, comes in as its founder by the
  /// recovery code. Why not, in the user's words, when it cannot.
  Future<String?> recover(
    OfficeIdentity identity,
    OfficePeer self,
    String code,
  ) async {
    if (!exists) return 'Önce büronun bir cihazıyla tanışın.';
    if (member(identity.deviceId) != null) return null;
    if (_state.recovery == null) return 'Bu büronun kurtarma kodu yok.';
    final key = await _recoveryKey(code);
    if (key == null) return 'Kod 32 harf ve rakam olmalı.';
    final record = {
      'k': 'kurtar',
      'kod': _state.recoveryId,
      ..._about(self, base64Encode(identity.devicePublic.bytes)),
      'buro': officeId,
      'onceki': idOf(_records.last),
      'imzalayan': identity.deviceId,
      'at': DateTime.now().toUtc().toIso8601String(),
    };
    final word = await Ed25519().sign(
      utf8.encode(_canonical(record)),
      keyPair: key,
    );
    final withWord = {...record, 'kurtarma': base64Encode(word.bytes)};
    final sig = await Ed25519().sign(
      utf8.encode(_canonical(withWord)),
      keyPair: identity.device,
    );
    final before = _records.length;
    await _apply([
      {...withWord, 'sig': base64Encode(sig.bytes)},
    ]);
    return _records.length == before ? 'Kurtarma kodu tutmadı.' : null;
  }

  /// What a device signs to be taken into [office] as one of [person]'s:
  /// without it no member can add a device that is not theirs.
  static List<int> consentOf(String office, String person, String device) =>
      utf8.encode('folio-buro-kendi-1|$office|$person|$device');

  /// One of this member's own devices, added by the member: the same
  /// person, role and name. Asks no manager; the device must be the
  /// member's own, which the member's Folio has proved (see vouched).
  Future<String?> addOwnDevice(
    OfficeIdentity identity,
    KnownDevice device, {
    required String consent,
    required String certificate,
  }) async {
    if (!exists) return 'Önce bir büro kurun.';
    if (member(identity.deviceId) == null) return 'Bu cihaz büroda değil.';
    if (member(device.deviceId) != null) return null;
    final r = await _sign(identity, {
      'k': 'kendi',
      'cihaz': device.deviceId,
      'dk': device.publicKey,
      'onay': consent,
      // Both devices under one person's key: the member's and the new one's
      // certificates by it, and the key.
      'up': base64Encode(identity.userPublic.bytes),
      'uc': certificate,
      'mc': await identity.userCertificate(),
      'c': device.device,
      'p': device.platform.name,
      'buro': officeId,
      'onceki': idOf(_records.last),
    });
    final before = _records.length;
    await _apply([r]);
    return _records.length == before ? 'Kayıt büroya eklenemedi.' : null;
  }

  /// Signs and keeps a change; why not, in the user's words, when it
  /// cannot be made.
  Future<String?> _change(
    OfficeIdentity identity,
    Map<String, Object?> change,
  ) async {
    if (!exists) return 'Önce bir büro kurun.';
    if (!isManager(identity.deviceId)) {
      return 'Bunu yalnız büronun yöneticisi yapabilir.';
    }
    final subject = _state.members[change['cihaz']];
    if ((subject?.founder ?? false) &&
        !(_state.members[identity.deviceId]?.founder ?? false)) {
      return 'Kurucunun rolünü yalnız kendisi değiştirebilir.';
    }
    final r = await _sign(identity, {
      ...change,
      'buro': officeId,
      // The record it comes after: the order is the chain's, not a clock's.
      'onceki': idOf(_records.last),
    });
    final before = _records.length;
    await _apply([r]);
    if (_records.length == before) {
      return change['k'] == 'cikar' || change['k'] == 'rol'
          ? 'Büronun en az bir yöneticisi kalmalı.'
          : 'Kayıt büroya eklenemedi.';
    }
    return null;
  }

  /// Takes records another member sent; true when anything was new.
  Future<bool> merge(List<Object?> incoming) async {
    final records = [
      for (final r in incoming)
        if (r is Map<String, Object?>)
          // A member of an office takes no other office's founding.
          if (!exists || r['k'] != 'kur' || idOf(r) == officeId) r,
    ];
    if (records.isEmpty) return false;
    final before = _records.length;
    await _apply(records);
    return _records.length != before;
  }

  Future<void> _apply(List<Map<String, Object?>> more) async {
    final seen = {for (final r in _records) idOf(r)};
    final all = [
      ..._records,
      for (final r in more)
        if (seen.add(idOf(r))) r,
    ];
    final next = await _replay(all);
    if (next.kept.length == _records.length &&
        next.officeId == _state.officeId) {
      return;
    }
    _state = next;
    _records = next.kept;
    await _save();
  }

  /// The office as its valid records make it, in the order they were
  /// signed; the founding record of another office is no part of this one.
  static Future<_State> _replay(List<Map<String, Object?>> records) async {
    var all = records;
    for (var round = 0; round < 8; round++) {
      final state = await _replayOnce(all);
      // A recovery by a code stands only while every code made in its
      // place names it as standing: one hung later on any branch by a
      // code made void does not, wherever it sorts, nor what its device
      // did as founder after. The same rule on every device.
      final standing = <String, List<Set<String>>>{};
      for (final r in state.kept) {
        final instead = r['yerine'];
        if (r['k'] != 'kurtarma' || instead is! String) continue;
        (standing[instead] ??= []).add({
          for (final k in (r['kalan'] as List? ?? const [])) '$k',
        });
      }
      final stale = {
        for (final r in state.kept)
          if (r['k'] == 'kurtar' &&
              (standing['${r['kod']}'] ?? const <Set<String>>[]).any(
                (kept) => !kept.contains(idOf(r)),
              ))
            idOf(r),
      };
      if (stale.isEmpty) return state;
      all = [
        for (final r in all)
          if (!stale.contains(idOf(r))) r,
      ];
    }
    return _replayOnce(all);
  }

  static Future<_State> _replayOnce(List<Map<String, Object?>> records) async {
    // Each record's place is how far it is from the founding along the
    // records it says it came after; a record whose predecessor is not here
    // waits outside. Equal places are put by id, the same on every device.
    final ids = {for (final r in records) idOf(r): r};
    final depth = <String, int>{};
    int? placeOf(String id, [int guard = 0]) {
      final known = depth[id];
      if (known != null) return known;
      final r = ids[id];
      if (r == null || guard > records.length) return null;
      if (r['k'] == 'kur') return depth[id] = 0;
      final before = r['onceki'];
      if (before is! String) return null;
      final d = placeOf(before, guard + 1);
      return d == null ? null : depth[id] = d + 1;
    }

    final sorted =
        [
          for (final id in ids.keys)
            if (placeOf(id) != null) ids[id]!,
        ]..sort((a, b) {
          final d = depth[idOf(a)]!.compareTo(depth[idOf(b)]!);
          return d != 0 ? d : idOf(a).compareTo(idOf(b));
        });
    String? office, recovery, recoveryId;
    var name = '';
    final members = <String, OfficeMember>{};
    final money = <String>{};
    final kept = <Map<String, Object?>>[];
    for (final r in sorted) {
      final kind = r['k'];
      if (kind == 'kur') {
        if (office != null) continue;
        final key = r['dk'];
        if (r['imzalayan'] != r['cihaz'] || key is! String) continue;
        if (!await _holds(r, key)) continue;
        if (OfficeIdentity.idOf(base64Decode(key)) != r['cihaz']) continue;
        office = idOf(r);
        name = '${r['ad'] ?? ''}';
        final m = _member(r, OfficeRole.manager, founder: true);
        if (m == null) continue;
        members[m.deviceId] = m;
        kept.add(r);
        continue;
      }
      if (office == null || r['buro'] != office) continue;
      final subject = '${r['cihaz']}';
      if (kind == 'kurtar') {
        // A new device, by the founder's recovery code: the founder again.
        final key = r['dk'], word = r['kurtarma'];
        final founder = members.values.where((m) => m.founder).firstOrNull;
        if (recovery == null || founder == null) continue;
        // By the code that was the latest where it stands.
        if (r['kod'] != recoveryId) continue;
        if (key is! String || word is! String) continue;
        if (r['imzalayan'] != subject || members.containsKey(subject)) continue;
        if (OfficeIdentity.idOf(base64Decode(key)) != subject) continue;
        if (!await _holds(r, key)) continue;
        final plain = {...r}
          ..remove('sig')
          ..remove('kurtarma');
        if (!await OfficeIdentity.signedBy(
          recovery,
          utf8.encode(_canonical(plain)),
          word,
        )) {
          continue;
        }
        members[subject] = OfficeMember(
          deviceId: subject,
          userId: founder.userId,
          publicKey: key,
          name: founder.name,
          device: '${r['c'] ?? ''}',
          platform: OfficePlatform.of('${r['p']}'),
          role: OfficeRole.manager,
          since: DateTime.tryParse('${r['at']}')?.toLocal() ?? DateTime(2026),
          founder: true,
          person: founder.person,
        );
        kept.add(r);
        continue;
      }
      final signer = members[r['imzalayan']];
      if (signer == null) continue;
      if (kind == 'kurtarma') {
        final up = r['up'];
        if (!signer.founder || up is! String) continue;
        // In the place of the code that was the latest where it stands.
        if (r['yerine'] != recoveryId) continue;
        if (!await _holds(r, signer.publicKey)) continue;
        recovery = up;
        recoveryId = idOf(r);
        kept.add(r);
        continue;
      }
      if (kind == 'kendi') {
        // A member's own device, by the member: theirs in all but its key.
        final key = r['dk'];
        if (key is! String || members.containsKey(subject)) continue;
        if (OfficeIdentity.idOf(base64Decode(key)) != subject) continue;
        if (!await _holds(r, signer.publicKey)) continue;
        // The device's own word that it is to be this person's.
        final consent = r['onay'];
        if (consent is! String ||
            !await OfficeIdentity.signedBy(
              key,
              consentOf(office, signer.person, subject),
              consent,
            )) {
          continue;
        }
        // And proof that it is: one person's key vouches for both.
        final up = r['up'], uc = r['uc'], mc = r['mc'];
        if (up is! String || uc is! String || mc is! String) continue;
        final userKey = base64Decode(up);
        // The person's key the member came in under, not one made anew.
        if (OfficeIdentity.idOf(userKey) != signer.userId) continue;
        if (!await OfficeIdentity.vouchedBy(userKey, base64Decode(key), uc) ||
            !await OfficeIdentity.vouchedBy(
              userKey,
              base64Decode(signer.publicKey),
              mc,
            )) {
          continue;
        }
        members[subject] = OfficeMember(
          deviceId: subject,
          userId: signer.userId,
          publicKey: key,
          name: signer.name,
          device: '${r['c'] ?? ''}',
          platform: OfficePlatform.of('${r['p']}'),
          role: signer.role,
          since: DateTime.tryParse('${r['at']}')?.toLocal() ?? DateTime(2026),
          founder: signer.founder,
          person: signer.person,
        );
        kept.add(r);
        continue;
      }
      if (signer.role != OfficeRole.manager) continue;
      if (!await _holds(r, signer.publicKey)) continue;
      final role = OfficeRole.of(r['rol']);
      // The founder is changed by no one but the founder.
      if ((members[subject]?.founder ?? false) && !signer.founder) continue;
      // People, not devices: a manager's phone is no second manager.
      final managers = {
        for (final m in members.values)
          if (m.role == OfficeRole.manager) m.person,
      }.length;
      final person = members[subject]?.person;
      switch (kind) {
        case 'uye':
          final key = r['dk'];
          if (role == null || key is! String) continue;
          if (members.containsKey(subject)) continue;
          if (OfficeIdentity.idOf(base64Decode(key)) != subject) continue;
          final m = _member(r, role);
          if (m == null) continue;
          members[subject] = m;
        case 'rol':
          final m = members[subject];
          if (m == null || role == null) continue;
          if (m.role == OfficeRole.manager &&
              role != OfficeRole.manager &&
              managers < 2) {
            continue;
          }
          // A person's role is theirs on every device.
          for (final d in members.values.toList()) {
            if (d.person == person) {
              members[d.deviceId] = d.copyWith(role: role);
            }
          }
        case 'ucret':
          if (person == null) continue;
          r['acik'] == true ? money.add(person) : money.remove(person);
        case 'cikar':
          final m = members[subject];
          if (m == null) continue;
          final whole = subject == person;
          if (whole && m.role == OfficeRole.manager && managers < 2) continue;
          // Let go of, a person goes with all their devices; one device of
          // theirs, lost or sold, goes alone.
          members.removeWhere(
            (id, d) => id == subject || (whole && d.person == person),
          );
        default:
          continue;
      }
      kept.add(r);
    }
    return _State(office, name, members, kept, recovery, recoveryId, money);
  }

  static OfficeMember? _member(
    Map<String, Object?> r,
    OfficeRole role, {
    bool founder = false,
  }) {
    final id = r['cihaz'], key = r['dk'];
    if (id is! String || key is! String) return null;
    return OfficeMember(
      deviceId: id,
      userId: '${r['u'] ?? ''}',
      publicKey: key,
      name: '${r['n'] ?? ''}',
      device: '${r['c'] ?? ''}',
      platform: OfficePlatform.of('${r['p']}'),
      role: role,
      since: DateTime.tryParse('${r['at']}')?.toLocal() ?? DateTime(2026),
      founder: founder,
    );
  }

  static Future<bool> _holds(Map<String, Object?> r, String publicKey) async {
    final sig = r['sig'];
    if (sig is! String) return false;
    try {
      return await Ed25519().verify(
        utf8.encode(_canonical(r)),
        signature: Signature(
          base64Decode(sig),
          publicKey: SimplePublicKey(
            base64Decode(publicKey),
            type: KeyPairType.ed25519,
          ),
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

class _State {
  const _State(
    this.officeId,
    this.officeName,
    this.members,
    this.kept, [
    this.recovery,
    this.recoveryId,
    this.money = const {},
  ]);
  const _State.empty()
    : officeId = null,
      officeName = '',
      members = const {},
      kept = const [],
      recovery = null,
      recoveryId = null,
      money = const {};
  final String? officeId;

  /// The founder's recovery code's public key, the latest, and its record.
  final String? recovery, recoveryId;
  final String officeName;
  final Map<String, OfficeMember> members;
  final List<Map<String, Object?>> kept;

  /// The people let see the clients' money (besides the managers).
  final Set<String> money;
}
