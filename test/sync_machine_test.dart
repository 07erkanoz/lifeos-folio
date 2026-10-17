import 'dart:io';

import 'package:evrak_convert/services/platform/machine_identity.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/sync/sync_generation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a database carried to another computer takes an id of its own '
      'there; on its own computer it keeps its id', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    final first = SyncClock.localDeviceId(db);
    // Its first opening that knows of computers: this one's.
    expect(SyncClock.adoptMachine(db, 'ofis'), isFalse);
    expect(SyncClock.localDeviceId(db), first);
    expect(SyncClock.adoptMachine(db, 'ofis'), isFalse);
    expect(SyncClock.localDeviceId(db), first);
    // Not known which computer: nothing concluded.
    expect(SyncClock.adoptMachine(db, null), isFalse);
    expect(SyncClock.localDeviceId(db), first);
    // Copied to the laptop.
    expect(SyncClock.adoptMachine(db, 'dizustu'), isTrue);
    final there = SyncClock.localDeviceId(db);
    expect(there, isNot(first));
    expect(there, hasLength(12));
    // Its versions are written as the laptop's.
    expect(SyncClock.of(db).tick().toString(), contains(there));
    expect(SyncClock.adoptMachine(db, 'dizustu'), isFalse);
    expect(SyncClock.localDeviceId(db), there);
  });

  test('the computer is read as the system names it, the same each time, '
      'kept as a hash', () {
    final id = MachineIdentity.current();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      expect(id, isNotNull);
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    }
    expect(MachineIdentity.current(), id);
  });
}
