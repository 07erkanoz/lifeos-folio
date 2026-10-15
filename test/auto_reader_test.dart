import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/sync/auto_reader.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/settings/uyap_auto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which of the person's own computers reads UYAP of itself
/// (docs/uyap-otomatik-okuma-tek-cihaz.md).
void main() {
  const mobile = PortalChannel.uyapMobile, web = PortalChannel.uyapWeb;

  AutoReadPeer peer(
    String id, {
    bool phone = false,
    bool reads = true,
    Set<String> held = const {'mobil', 'web'},
    PortalChannel? job,
  }) => AutoReadPeer(
    id: id,
    name: 'Bilgisayar $id',
    phone: phone,
    reads: reads,
    held: held,
    job: job,
  );

  String? reader(
    PortalChannel channel,
    String me,
    List<AutoReadPeer> peers, {
    PortalChannel? myJob,
    bool takesTheirs = true,
  }) => autoReaderElsewhere(
    channel,
    me: me,
    myJob: myJob,
    peers: peers,
    takesTheirs: takesTheirs,
  );

  test('of two, the same one reads on both: the lower id', () {
    expect(reader(mobile, 'b', [peer('a')]), 'Bilgisayar a');
    expect(reader(mobile, 'a', [peer('b')]), isNull);
  });

  test('the one running the long job on the channel reads it, whatever its '
      'id; on the other channel the order stands', () {
    expect(reader(mobile, 'a', [peer('b', job: mobile)]), 'Bilgisayar b');
    expect(reader(mobile, 'b', [peer('a')], myJob: mobile), isNull);
    expect(reader(web, 'a', [peer('b', job: mobile)]), isNull);
    expect(reader(web, 'b', [peer('a')], myJob: mobile), 'Bilgisayar a');
  });

  test('none is left to a phone, to one not reading of itself, or to one '
      'without the channel\'s session', () {
    expect(reader(mobile, 'b', [peer('a', phone: true)]), isNull);
    expect(reader(mobile, 'b', [peer('a', reads: false)]), isNull);
    expect(
      reader(mobile, 'b', [
        peer('a', held: const {'web'}),
      ]),
      isNull,
    );
    expect(
      reader(web, 'b', [
        peer('a', held: const {'web'}),
      ]),
      'Bilgisayar a',
    );
  });

  test('of several, the first of them all; one left here takes nothing of '
      'theirs and reads itself; UETS is not of this', () {
    final peers = [peer('c'), peer('a'), peer('d', job: web)];
    expect(reader(mobile, 'b', peers), 'Bilgisayar a');
    expect(reader(web, 'b', peers), 'Bilgisayar d');
    expect(reader(mobile, 'b', peers, takesTheirs: false), isNull);
    expect(reader(PortalChannel.uets, 'b', peers), isNull);
  });

  testWidgets('Ayarlar says which computer reads of itself, and what this one '
      'does', (tester) async {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    final sync = PortalSync(
      web: UyapWebService.forTesting(),
      mobile: _Connected(),
      database: () async => db,
      autoReader: (c) => c == mobile ? 'Ofis bilgisayarı' : null,
    );
    addTearDown(sync.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UyapAutoRow(sync: sync)),
      ),
    );
    // Off: nothing said.
    expect(
      find.byKey(const ValueKey('settings-uyap-auto-elsewhere')),
      findsNothing,
    );
    sync.autoFetch = true;
    PortalSync.autoReadersChanged.value++;
    await tester.pump();
    expect(
      find.text(
        'Şu an kendiliğinden okumayı Ofis bilgisayarı yapıyor (UYAP Mobil); '
        'bu bilgisayar onun okuduklarını alır.',
      ),
      findsOneWidget,
    );
  });
}

class _Connected extends UyapMobileApi {
  _Connected() : super.forTesting(Uri.parse('http://127.0.0.1:9/'));

  @override
  bool get connected => true;
}
