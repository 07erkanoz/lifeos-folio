import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:evrak_convert/services/portal/portal_sync.dart';
import 'package:evrak_convert/services/portal/uyap_job.dart';
import 'package:evrak_convert/services/uyap/uyap_mobile_api.dart';
import 'package:evrak_convert/services/uyap/uyap_web_service.dart';
import 'package:evrak_convert/ui/portfolio/uyap_setup_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PortalDatabase db;
  late PortalSync sync;

  setUp(() {
    db = PortalDatabase.memory();
    sync = PortalSync(
      web: UyapWebService.forTesting(),
      mobile: UyapMobileApi.forTesting(Uri.parse('http://127.0.0.1:9/')),
      database: () async => db,
    );
  });
  tearDown(() {
    sync.dispose();
    db.dispose();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UyapSetupDialog(sync: sync, database: db),
        ),
      ),
    );
    await tester.pump();
  }

  UyapJob job(UyapJobKind kind, UyapJobStage stage, {UyapJobStop? stopped}) =>
      UyapJob(
        kind: kind,
        channel: kind == UyapJobKind.setup
            ? PortalChannel.uyapMobile
            : PortalChannel.uyapWeb,
        stage: stage,
        started: DateTime(2026, 10, 14),
        stopped: stopped,
      );

  testWidgets('with no job it offers UYAP Mobil first, recommended, the web '
      'beside it, and later', (tester) async {
    await open(tester);
    expect(find.text('Dosyalarınızı UYAP’tan getirelim'), findsOneWidget);
    expect(find.text('Önerilen'), findsOneWidget);
    expect(find.byKey(const ValueKey('uyap-setup-mobile')), findsOneWidget);
    expect(find.byKey(const ValueKey('uyap-setup-web')), findsOneWidget);
    expect(find.byKey(const ValueKey('uyap-setup-later')), findsOneWidget);
  });

  testWidgets('running, it shows each stage and how far it has come, and '
      'pauses; stopped by the session it says it goes on', (tester) async {
    sync.job.value = job(UyapJobKind.setup, UyapJobStage.parties);
    sync.jobProgress.value = const UyapJobProgress(
      UyapJobStage.parties,
      318,
      563,
    );
    await open(tester);
    expect(find.text('Taraflar ve müvekkiller'), findsOneWidget);
    expect(find.text('318 / 563'), findsOneWidget);
    expect(find.text('sırada'), findsOneWidget);
    expect(find.byKey(const ValueKey('uyap-setup-pause')), findsOneWidget);
    sync.job.value = job(
      UyapJobKind.setup,
      UyapJobStage.parties,
      stopped: UyapJobStop.session,
    );
    await tester.pump();
    expect(find.textContaining('oturumu kapandı'), findsOneWidget);
    expect(find.byKey(const ValueKey('uyap-setup-resume')), findsOneWidget);
  });

  testWidgets('the setup done, it offers the web\'s completion', (
    tester,
  ) async {
    sync.job.value = job(UyapJobKind.setup, UyapJobStage.done);
    await open(tester);
    expect(
      find.byKey(const ValueKey('uyap-setup-web-complete')),
      findsOneWidget,
    );
    expect(find.textContaining('Yargıtay'), findsOneWidget);
  });
}
