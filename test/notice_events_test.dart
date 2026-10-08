import 'package:evrak_convert/services/portal/observed.dart';
import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_hearing.dart';
import 'package:evrak_convert/services/uets/notice_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the days a paper sets, by the word near each date', () {
    expect(
      noticeEvents(
        'G.D: 1-Taşınmazların yerinde tespiti hususundaki keşfin '
        '04/05/2026 günü saat 10.00\'da yapılmasına, 2-İşbu tutanağın '
        'taraflara tebliğine, 28/04/2026 Katip',
      ),
      [(kind: 'Keşif', at: DateTime(2026, 5, 4, 10))],
    );
    expect(
      noticeEvents(
        'mürafaa duruşmasının 15/12/2025 günü saat 11:15\'a bırakılmasına '
        'tensiben karar verildi.08/12/2025',
      ).single.kind,
      'Mürafaa',
    );
    expect(
      noticeEvents('ÇAĞRI KAĞIDI … 15/10/2026\n13:45\nDuruşma Günü').single.at,
      DateTime(2026, 10, 15, 13, 45),
    );
    // Far into a long text, the words are read at the date's own place.
    expect(
      noticeEvents('${'\n' * 120}İŞBU duruşmanın 15/10/2026 günü saat 13:45')
          .single
          .kind,
      'Duruşma',
    );
    // A decision's or a filing's date sets nothing.
    expect(noticeEvents('24/11/2025 tarihli ihtiyati haciz kararına'), isEmpty);
  });

  test('a day only the papers set stays when UYAP lists the window; one '
      'they set no longer goes, UYAP\'s stay', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    final key = caseKey('2025/80', 'Manavgat 2. Aile Mahkemesi');
    PortalHearing h(DateTime at, PortalChannel c, String kind) => PortalHearing(
      key: hearingKey('2025/80', 'Manavgat 2. Aile Mahkemesi', at),
      caseKey: key,
      number: '2025/80',
      court: 'Manavgat 2. Aile Mahkemesi',
      at: at,
      ids: {c: 'x'},
      kind: Observed(kind, c, DateTime(2026)),
    );
    final kesif = h(DateTime(2026, 11, 4, 10), PortalChannel.uets, 'Keşif');
    final uyap = h(DateTime(2026, 12, 9, 14, 10), PortalChannel.uyapWeb, 'D');
    db.replacePaperHearings({key}, [kesif]);
    db.mergeHearings(
      PortalChannel.uyapWeb,
      DateTime(2026, 10),
      DateTime(2027),
      [uyap],
      complete: true,
    );
    expect(db.hearings().map((x) => x.at), [kesif.at, uyap.at]);
    // A later paper moved the inspection.
    final moved = h(DateTime(2026, 11, 20, 10), PortalChannel.uets, 'Keşif');
    db.replacePaperHearings({key}, [moved]);
    expect(db.hearings().map((x) => x.at), [moved.at, uyap.at]);
  });
}
