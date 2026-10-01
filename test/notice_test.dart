import 'package:evrak_convert/ui/theme/app_theme.dart';
import 'package:evrak_convert/ui/widgets/notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a notice with a button still goes away, and a new one replaces '
      'it instead of queueing', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (inner) {
              context = inner;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    var opened = false;
    showNotice(
      context,
      'kırpıntı.png kaydedildi.',
      kind: NoticeKind.success,
      actionLabel: 'Aç',
      onAction: () => opened = true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('kırpıntı.png kaydedildi.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    // Floating, not a strip along the bottom edge.
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).behavior ??
          Theme.of(context).snackBarTheme.behavior,
      SnackBarBehavior.floating,
    );
    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);

    showNotice(context, 'Birinci');
    await tester.pump();
    showNotice(
      context,
      'İkinci',
      detail: 'ayrıntı',
      kind: NoticeKind.error,
      actionLabel: 'Tamam',
    );
    await tester.pumpAndSettle();
    expect(find.text('Birinci'), findsNothing);
    expect(find.text('İkinci'), findsOneWidget);
    expect(find.text('ayrıntı'), findsOneWidget);
    // Flutter keeps a snack bar that has an action until it is closed by
    // hand; a notice leaves by itself all the same.
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
