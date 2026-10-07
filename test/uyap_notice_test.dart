import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/uyap_notice.dart';
import 'package:flutter_test/flutter_test.dart';

// UYAP's notifications from both channels: kept apart, shown as one, tied
// to their case. The rows are made up, after the shape of live ones
// (Banaozel's measurements).
void main() {
  Map<String, Object?> mobile(
    String id,
    String title,
    String at, {
    String body = '',
    Object? read,
  }) => {
    'bildirimId': id,
    'mesajId': 'm$id',
    'baslik': title,
    'gonderilmeTarihi': at,
    'mesaj': body,
    'okundumu': read,
  };

  Map<String, Object?> web(
    int id,
    String title,
    String at,
    String body, {
    bool read = false,
  }) => {
    'bildirimId': id,
    'mesajId': id + 1,
    'baslik': title,
    'mesaj': body,
    'gonderilmeTarihi': at,
    'okunduMu': read,
    'dosyaId': 'xyz',
  };

  const decision =
      'Antalya 3. Asliye Hukuk Mahkemesi Biriminde Bulunan 2024/318 sayılı '
      'dosyaya gerekçeli karar eklenmiştir.';

  test('UYAP’s times, both channels’', () {
    expect(
      parseUyapNoticeTime('14/05/2026 13:39'),
      DateTime(2026, 5, 14, 13, 39),
    );
    expect(
      parseUyapNoticeTime('Mar 3, 2026 1:05:47 PM'),
      DateTime(2026, 3, 3, 13, 5, 47),
    );
    expect(
      parseUyapNoticeTime('Oct 7, 2026 12:10:00 AM'),
      DateTime(2026, 10, 7, 0, 10),
    );
    expect(
      parseUyapNoticeTime('07.10.2026 09:18:05'),
      DateTime(2026, 10, 7, 9, 18, 5),
    );
    expect(parseUyapNoticeTime(''), isNull);
  });

  test('the case a body names, in the three ways UYAP writes it', () {
    expect(uyapNoticeCase(decision), (
      number: '2024/318',
      court: 'Antalya 3. Asliye Hukuk Mahkemesi',
    ));
    expect(
      uyapNoticeCase(
        "Antalya 6. İcra Dairesi'nin 2025/4410 Esas sayılı dosyasında "
        'tahsilat yapılmıştır.',
      ),
      (number: '2025/4410', court: 'Antalya 6. İcra Dairesi'),
    );
    expect(
      uyapNoticeCase(
        'Manavgat 2. Asliye Hukuk Mahkemesi birimi, 2025/201 dosyasında '
        'bilirkişi raporu kaydedilmiştir.',
      ),
      (number: '2025/201', court: 'Manavgat 2. Asliye Hukuk Mahkemesi'),
    );
    // None named, or too little before the number: no case guessed.
    expect(uyapNoticeCase('Kurum adına vekil kaydı yapıldı.'), isNull);
    expect(uyapNoticeCase('2024/318 dosyası kesinleşti.'), isNull);
  });

  test('the kind, from the title', () {
    expect(UyapNoticeKind.of('Gerekçeli Karar'), UyapNoticeKind.decision);
    expect(
      UyapNoticeKind.of('İcra Dosyası Borç Reddiyatı'),
      UyapNoticeKind.money,
    );
    expect(
      UyapNoticeKind.of('İstinaf Başvurusu Kaydedilmesi'),
      UyapNoticeKind.appeal,
    );
    expect(
      UyapNoticeKind.of('Hukuk Dava Dosyası Kesinleşmesi'),
      UyapNoticeKind.finality,
    );
    expect(
      UyapNoticeKind.of('Bilirkişi Raporu Kaydedilmesi'),
      UyapNoticeKind.report,
    );
    expect(
      UyapNoticeKind.of('Harç Tahsil Müzekkere Kaydı'),
      UyapNoticeKind.money,
    );
    expect(UyapNoticeKind.of('Vekil Kaydı'), UyapNoticeKind.party);
    expect(UyapNoticeKind.of('İnfaza Gönderilmesi'), UyapNoticeKind.other);
  });

  test('the two channels keep their own rows; neither writes over the '
      'other, nor an answer without a body over a body', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    final fromMobile = db.saveUyapNotices([
      UyapNoticeRow.fromMobile(
        mobile('0Npv+xBHg==', 'Gerekçeli Karar', '07/10/2026 14:05'),
      )!,
    ]);
    expect(fromMobile, hasLength(1));
    db.setUyapNoticeBody('0Npv+xBHg==', decision);
    final fromWeb = db.saveUyapNotices([
      UyapNoticeRow.fromWeb(
        web(604451740, 'Gerekçeli Karar', 'Oct 7, 2026 2:05:31 PM', decision),
      )!,
    ]);
    expect(fromWeb, hasLength(1));
    // UYAP Mobil's list again, with no body: what was kept stays.
    expect(
      db.saveUyapNotices([
        UyapNoticeRow.fromMobile(
          mobile('0Npv+xBHg==', 'Gerekçeli Karar', '07/10/2026 14:05'),
        )!,
      ]),
      isEmpty,
    );
    final rows = db.uyapNoticeRows();
    expect(rows, hasLength(2));
    expect(rows.every((r) => r.body == decision), isTrue);
    // Shown once, tied to its case, with both channels named.
    final key = caseKey('2024/318', 'Antalya 3. Asliye Hukuk Mahkemesi');
    final shown = mergeUyapNotices(rows, caseKeys: {key});
    expect(shown, hasLength(1));
    expect(shown.single.sources, {
      UyapNoticeSource.mobile,
      UyapNoticeSource.web,
    });
    expect(shown.single.caseKey, key);
    expect(shown.single.sentAt, DateTime(2026, 10, 7, 14, 5, 31));
  });

  test('a body not yet fetched still pairs the two; two different '
      'notices in one minute stay two', () {
    final rows = [
      UyapNoticeRow.fromMobile(
        mobile('a', 'Gerekçeli Karar', '07/10/2026 14:05'),
      )!,
      UyapNoticeRow.fromWeb(
        web(1, 'Gerekçeli Karar', 'Oct 7, 2026 2:05:31 PM', decision),
      )!,
      UyapNoticeRow.fromWeb(
        web(2, 'Vekil Kaydı', 'Oct 7, 2026 2:05:10 PM', 'Bir vekil kaydı.'),
      )!,
      UyapNoticeRow.fromWeb(
        web(3, 'Vekil Kaydı', 'Oct 7, 2026 2:05:40 PM', 'Başka bir kayıt.'),
      )!,
    ];
    final shown = mergeUyapNotices(rows);
    expect(shown, hasLength(3));
    expect(
      shown.where((n) => n.title == 'Gerekçeli Karar').single.rows,
      hasLength(2),
    );
  });

  test('a case named a little otherwise is found when it is the only one', () {
    final keys = {
      caseKey('2025/4410', 'Antalya 6. İcra Dairesi'),
      caseKey('2025/4410', 'Manavgat 1. İcra Dairesi'),
      caseKey('2024/318', 'Antalya 3. Asliye Hukuk Mahkemesi'),
    };
    final row = UyapNoticeRow.fromWeb(
      web(
        9,
        'İcra Dosyası Borç Tahsilatı',
        'Oct 7, 2026 11:42:00 AM',
        "Antalya 6. İcra Dairesi'nin 2025/4410 Esas sayılı dosyasında "
            'tahsilat yapılmıştır.',
      ),
    )!;
    expect(
      mergeUyapNotices([row], caseKeys: keys).single.caseKey,
      caseKey('2025/4410', 'Antalya 6. İcra Dairesi'),
    );
    // The same number at two courts and the court not named as either:
    // no case.
    final vague = UyapNoticeRow.fromWeb(
      web(
        10,
        'Borç Tahsilatı',
        'Oct 7, 2026 11:43:00 AM',
        'İcra Dairesi biriminde bulunan 2025/4410 sayılı dosya.',
      ),
    )!;
    expect(mergeUyapNotices([vague], caseKeys: keys).single.caseKey, isNull);
  });

  test('read: UYAP’s word, unless the lawyer’s; on both rows of one', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.saveUyapNotices([
      UyapNoticeRow.fromMobile(
        mobile('a', 'Gerekçeli Karar', '07/10/2026 14:05', read: 'H'),
      )!,
      UyapNoticeRow.fromWeb(
        web(
          1,
          'Gerekçeli Karar',
          'Oct 7, 2026 2:05:31 PM',
          decision,
          read: true,
        ),
      )!,
    ]);
    var shown = db.uyapNotices().single;
    // Read on the portal: read here.
    expect(shown.read, isTrue);
    db.setUyapNoticeRead(shown.rows, false);
    shown = db.uyapNotices().single;
    expect(shown.read, isFalse);
    expect(shown.rows.every((r) => r.localRead == false), isTrue);
    // UYAP's next answer does not undo the lawyer's word.
    db.saveUyapNotices([
      UyapNoticeRow.fromWeb(
        web(
          1,
          'Gerekçeli Karar',
          'Oct 7, 2026 2:05:31 PM',
          decision,
          read: true,
        ),
      )!,
    ]);
    expect(db.uyapNotices().single.read, isFalse);
  });
}
