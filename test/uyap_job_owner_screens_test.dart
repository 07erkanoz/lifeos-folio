import 'dart:io';

import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/portal/uyap_job.dart';
import 'package:evrak_convert/services/portal/uyap_job_owner.dart';
import 'package:evrak_convert/services/sync/hlc.dart';
import 'package:evrak_convert/services/uyap/uyap_case_store.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/portfolio/uyap_setup_dialog.dart';
import 'package:evrak_convert/ui/portfolio/uyap_status_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The home computer's screens while the office computer runs the job
/// (docs/uyap-is-sahipligi.md): shown, not run, here.
void main() {
  late Directory root;
  late PortalDatabase db;
  late UyapCaseStore store;
  late UyapCaseStore real;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('folio-is-sahibi-');
    db = PortalDatabase.memory();
    real = UyapCaseStore.instance;
    store = UyapCaseStore(
      directory: Directory('${root.path}/destek'),
      settings: UyapSettings(
        directory: Directory('${root.path}/destek'),
        home: '${root.path}/ev',
      ),
    );
    UyapCaseStore.instance = store;
  });
  tearDown(() async {
    UyapCaseStore.instance = real;
    db.dispose();
    await root.delete(recursive: true);
  });

  /// The office computer's setup at its parties, one case of two read,
  /// said [ago] to run.
  Map<String, Object?> runningAtOffice({Duration ago = Duration.zero}) {
    final at = DateTime.now().toUtc().subtract(ago);
    return {
      ...UyapJobClaim.start(
        UyapJob(
          kind: UyapJobKind.setup,
          channel: PortalChannel.uyapMobile,
          stage: UyapJobStage.parties,
          started: at,
        ),
        owner: 'ofis',
        ownerName: 'Ofis bilgisayarı',
        version: Hlc(at.millisecondsSinceEpoch, 0, 'ofis'),
      ).toJson(),
      'ilerleme': {'asama': 'parties', 'bitti': 1, 'toplam': 2},
    };
  }

  Future<PortalSync> atHome(
    WidgetTester tester,
    Map<String, Object?> office, {
    bool direct = true,
  }) async {
    final sync = PortalSync(
      web: UyapWebService.forTesting(),
      mobile: UyapMobileApi.forTesting(Uri.parse('http://127.0.0.1:9/')),
      database: () async => db,
      deviceName: 'Ev bilgisayarı',
    );
    addTearDown(sync.dispose);
    await tester.runAsync(() => sync.mergeJob(office, direct: direct));
    return sync;
  }

  testWidgets('the setup shows the other\'s job read-only, with its device '
      'and when it was last heard of; taking it over is asked first while it '
      'runs there', (tester) async {
    final sync = await atHome(tester, runningAtOffice());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UyapSetupDialog(sync: sync, database: db),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('uyap-setup-take-over')), findsOne);
    expect(find.byKey(const ValueKey('uyap-setup-pause')), findsNothing);
    expect(find.byKey(const ValueKey('uyap-setup-resume')), findsNothing);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(
      find.textContaining(
        'başka bilgisayarınızda sürüyor: Ofis bilgisayarı · son haber az önce',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('uyap-setup-take-over')));
    await tester.pumpAndSettle();
    expect(find.text('Bu bilgisayarda devralınsın mı?'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(sync.jobClaim.value!.owner, 'ofis');
  });

  testWidgets('heard of no more, the setup says it may be off or on another '
      'network', (tester) async {
    final sync = await atHome(
      tester,
      runningAtOffice(ago: const Duration(hours: 3)),
      direct: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UyapSetupDialog(sync: sync, database: db),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.textContaining(
        'Ofis bilgisayarı · son haber 3 sa önce. O bilgisayar kapalı ya da '
        'başka bir ağda olabilir.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('uyap-setup-take-over')), findsOne);
  });

  testWidgets('UYAP durumu names the device running it and offers no '
      'filling of its own meanwhile', (tester) async {
    final sync = await atHome(tester, runningAtOffice());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UyapStatusDialog(sync: sync, database: db, store: store),
        ),
      ),
    );
    for (
      var i = 0;
      i < 40 && find.text('Son kayıtlar').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(
      find.textContaining(
        'Ofis bilgisayarı · UYAP Mobil · taraflar 1/2 · sürüyor · son haber '
        'az önce',
      ),
      findsOneWidget,
    );
    expect(find.text('Ayrıntı ya da bu bilgisayarda devral'), findsOne);
    expect(find.byKey(const ValueKey('uyap-status-fill')), findsNothing);
  });

  test('"son haber" in the lawyer\'s words', () {
    final now = DateTime(2026, 10, 16, 12);
    expect(
      lastWordText(now.subtract(const Duration(seconds: 20)), now),
      'az önce',
    );
    expect(
      lastWordText(now.subtract(const Duration(minutes: 5)), now),
      '5 dk önce',
    );
    expect(
      lastWordText(now.subtract(const Duration(hours: 3)), now),
      '3 sa önce',
    );
    expect(
      lastWordText(now.subtract(const Duration(days: 2)), now),
      '2 gün önce',
    );
  });
}
