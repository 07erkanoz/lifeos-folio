import 'package:evrak_convert/services/platform/document_intents.dart';
import 'package:evrak_convert/ui/mobile/phone_folder_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(DocumentIntents.channel, null),
  );

  /// The picker opened on an Android phone; what it returned, or threw.
  Future<Object?> pick(WidgetTester tester, String choice) async {
    Object? outcome = 'pending';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              try {
                outcome = await pickPhoneFolder(context, android: true);
              } catch (e) {
                outcome = e;
              }
            },
            child: const Text('Klasör ekle'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Klasör ekle'));
    await tester.pumpAndSettle();
    expect(find.text('İndirilenler'), findsOneWidget);
    expect(find.text('Başka bir klasör seç'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey(choice)));
    await tester.pumpAndSettle();
    return outcome;
  }

  testWidgets('Download is read where it is once all-files access is given', (
    tester,
  ) async {
    final asked = <String>[];
    messenger.setMockMethodCallHandler(DocumentIntents.channel, (call) async {
      asked.add(call.method);
      return '/storage/emulated/0/Download';
    });
    expect(
      await pick(tester, 'folder-downloads'),
      '/storage/emulated/0/Download',
    );
    expect(asked, ['downloadsFolder']);
  });

  testWidgets('Download refused says why, rather than adding nothing', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(
      DocumentIntents.channel,
      (_) async => null,
    );
    final outcome = await pick(tester, 'folder-downloads');
    expect(outcome, isA<DownloadsAccessRefused>());
    expect('$outcome', contains('Tüm dosyalara erişim'));
  });

  testWidgets('another folder goes to the system folder picker', (
    tester,
  ) async {
    final asked = <String>[];
    messenger.setMockMethodCallHandler(DocumentIntents.channel, (call) async {
      asked.add(call.method);
      return '/data/user/0/archives/Belgeler';
    });
    expect(
      await pick(tester, 'folder-other'),
      '/data/user/0/archives/Belgeler',
    );
    expect(asked, ['pickFolder']);
  });
}
