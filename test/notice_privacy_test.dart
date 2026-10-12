import 'package:evrak_convert/services/platform/system_notices.dart';
import 'package:evrak_convert/services/portal/agenda_reminders.dart';
import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:evrak_convert/services/portal/uyap_notice_alerts.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the phone's notifications would have shown.
class _Told implements SystemNotices {
  final shownTo = <({String title, String body})>[];

  @override
  void Function(String payload)? onOpen;

  @override
  Future<bool> shown({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool ask = true,
  }) async {
    shownTo.add((title: title, body: body));
    return true;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool ask = true,
  }) => shown(id: id, title: title, body: body);

  @override
  Future<void> askLeave() async {}

  @override
  Future<void> prepare() async {}
}

void main() {
  const number = '2025/412';
  const court = 'Antalya 3. Asliye Hukuk Mahkemesi';
  final now = DateTime(2026, 10, 12, 8);

  PortalDatabase withHearing() {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    final at = DateTime(2026, 10, 12, 10, 30);
    db.mergeHearings(PortalChannel.uyapWeb, DateTime(2026), DateTime(2027), [
      PortalHearing(
        key: hearingKey(number, court, at),
        caseKey: caseKey(number, court),
        number: number,
        court: court,
        at: at,
      ),
    ], complete: true);
    return db;
  }

  test('an agenda alarm says what is due, unless the lawyer asked only '
      'for word that something is, or Folio is locked', () async {
    final told = _Told();
    // Shown whole by default, in the background too, Folio not locked.
    var db = withHearing();
    await AgendaReminders.tell(
      db,
      notices: told,
      now: now,
      private: () => false,
    );
    expect(told.shownTo.single.title, 'Bugün duruşma 10:30');
    expect(told.shownTo.single.body, '$number · $court');

    // Locked: only that something is due.
    told.shownTo.clear();
    db = withHearing();
    await AgendaReminders.tell(
      db,
      notices: told,
      now: now,
      private: () => true,
    );
    expect(told.shownTo.single.title, 'LifeOS Folio');
    expect(told.shownTo.single.body, isNot(contains(number)));

    // Asked to leave the details out: the same, unlocked.
    told.shownTo.clear();
    db = withHearing();
    const UyapNoticeAlerts(details: false).save(db);
    expect(UyapNoticeAlerts.of(db).details, isFalse);
    await AgendaReminders.tell(
      db,
      notices: told,
      now: now,
      private: () => false,
    );
    expect(told.shownTo.single.body, isNot(contains(number)));
  });

  test('the details choice is kept, and is on unless turned off', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    expect(UyapNoticeAlerts.of(db).details, isTrue);
    const UyapNoticeAlerts(background: false).save(db);
    expect(UyapNoticeAlerts.of(db).details, isTrue);
    UyapNoticeAlerts.of(db).copyWith(details: false).save(db);
    expect(UyapNoticeAlerts.of(db).details, isFalse);
    expect(UyapNoticeAlerts.of(db).background, isFalse);
  });
}
