import 'package:evrak_convert/services/portal/hearing_sync.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const web = PortalChannel.uyapWeb;
  const mobile = PortalChannel.uyapMobile;
  final asked = DateTime.utc(2026, 10, 6, 8);

  Map<String, Object?> row({
    String at = '06.10.2026 09:20:00',
    String number = '2025/412',
    String kind = 'Ön İnceleme Duruşması',
    String id = '1001',
  }) => {
    'tarihSaat': at,
    'kayitId': id,
    'dosyaNo': number,
    'yerelBirimAd': 'Antalya 3. Asliye Hukuk Mahkemesi',
    'islemTuruAciklama': kind,
    'dosyaTaraflari': [
      {'adi': 'Ayşe K.', 'rol': 'Davacı'},
    ],
  };

  test('one reader serves both portals, and the same hearing meets', () {
    final fromWeb = parseHearing(row(), web, asked)!;
    final fromMobile = parseHearing(
      row(kind: 'Duruşma', id: 'Zm9v', number: '2025/412 - 1'),
      mobile,
      asked,
    )!;
    expect(fromWeb.key, fromMobile.key);
    expect(fromWeb.at, DateTime(2026, 10, 6, 9, 20));
    final merged = fromWeb.merge(fromMobile);
    expect(merged.kind!.value, 'Ön İnceleme Duruşması');
    expect(merged.ids, {web: '1001', mobile: 'Zm9v'});
  });

  test('a row without a time, number or court is left out', () {
    expect(parseHearing(row(at: ''), web, asked), isNull);
    expect(parseHearing(row(number: ''), web, asked), isNull);
    expect(parseHearing({...row(), 'yerelBirimAd': null}, web, asked), isNull);
  });

  test('the mobile API’s judge note and e-hearing link are kept', () {
    final one = parseHearing(
      {
        ...row(),
        'izinliHakimList': '<b>Hâkim</b>&nbsp;notu',
        'token': 'https://edurusma.example/abc',
      },
      mobile,
      asked,
    )!;
    expect(one.judgeNote!.value, 'Hâkim notu');
    expect(one.isEHearing, isTrue);
  });

  test('the range goes in windows of at most 29 days, ends included', () {
    final windows = hearingWindows(
      DateTime(2026, 9, 6),
      DateTime(2027, 1, 4),
    ).toList();
    for (final (a, b) in windows) {
      expect(b.difference(a).inDays, lessThan(29));
    }
    expect(windows.first.$1, DateTime(2026, 9, 6));
    expect(windows.last.$2, DateTime(2027, 1, 4));
    for (var i = 1; i < windows.length; i++) {
      expect(windows[i].$1, windows[i - 1].$2.add(const Duration(days: 1)));
    }
  });

  test(
    'a failed window makes the answer incomplete and removes nothing',
    () async {
      final db = PortalDatabase.memory();
      addTearDown(db.dispose);
      final now = DateTime(2026, 10, 6);
      var calls = 0;
      var result = await syncHearings(web, db, (a, b) async {
        calls++;
        return a.isAfter(now) || a == DateTime(2026, 9, 6) ? [row()] : [];
      }, now: now);
      expect(result.complete, isTrue);
      expect(calls, greaterThan(3));
      expect(db.hearings(), hasLength(1));

      // The next answer has the hearing's window failing: it stays.
      result = await syncHearings(web, db, (a, b) async {
        if (a.isAfter(now)) throw StateError('ağ hatası');
        return [];
      }, now: now);
      expect(result.complete, isFalse);
      expect(db.hearings(), hasLength(1));

      // A complete answer that lists it at another time moves it.
      result = await syncHearings(web, db, (a, b) async {
        return a == DateTime(2026, 9, 6)
            ? [row(at: '07.10.2026 10:00:00')]
            : [];
      }, now: now);
      expect(result.complete, isTrue);
      expect(db.hearings().single.at, DateTime(2026, 10, 7, 10));
    },
  );

  test('a lost session stops asking', () async {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    var calls = 0;
    final result = await syncHearings(web, db, (a, b) async {
      calls++;
      throw StateError('UYAP oturumu sona erdi.');
    }, now: DateTime(2026, 10, 6));
    expect(calls, 1);
    expect(result.complete, isFalse);
  });
}
