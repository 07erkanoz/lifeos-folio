import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:evrak_convert/ui/widgets/pdf_context_menu.dart';

class _Selection extends Fake implements PdfTextSelectionDelegate {
  bool selected = false;
  bool copyingAllowed = true;
  int copies = 0;
  int selectAllCalls = 0;
  @override
  bool get isCopyAllowed => copyingAllowed;
  @override
  bool get hasSelectedText => selected;
  @override
  bool get isSelectingAllText => selected;
  @override
  Future<bool> copyTextSelection() async {
    copies++;
    return true;
  }

  @override
  Future<void> selectAllText() async {
    selected = true;
    selectAllCalls++;
  }
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('PDF menu works with Flutter localizations in $brightness', (
      tester,
    ) async {
      final selection = _Selection();
      var dismissals = 0;
      Future<void> showMenu() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: brightness,
              platform: TargetPlatform.linux,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Stack(
                  children: [
                    const Positioned.fill(
                      child: ColoredBox(color: Colors.white),
                    ),
                    buildPreviewContextMenu(
                          context,
                          PdfViewerContextMenuBuilderParams(
                            isTextSelectionEnabled: true,
                            anchorA: const Offset(300, 200),
                            textSelectionDelegate: selection,
                            dismissContextMenu: () => dismissals++,
                            contextMenuFor: PdfViewerPart.background,
                          ),
                        ) ??
                        const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await showMenu();
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('Tümünü seç'), findsOneWidget);
      expect(find.text('Kopyala'), findsNothing);
      await tester.tap(find.text('Tümünü seç'));
      expect(selection.selectAllCalls, 1);
      expect(dismissals, 1);
      await showMenu();
      expect(find.text('Kopyala'), findsOneWidget);
      // On the desktop, the selection can be read aloud.
      expect(find.text('Sesli oku'), findsOneWidget);
      await tester.tap(find.text('Kopyala'));
      expect(selection.copies, 1);
      expect(dismissals, 2);
      selection.copyingAllowed = false;
      await showMenu();
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
