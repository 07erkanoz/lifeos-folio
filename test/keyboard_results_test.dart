import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/models/evrak_file.dart';
import 'package:evrak_convert/services/search/search_models.dart';
import 'package:evrak_convert/ui/library/search_results.dart';

void main() {
  testWidgets(
    'preview arrows open selected row without Enter, coalescing held keys',
    (tester) async {
      final focus = FocusNode();
      final opened = <String>[];
      final hits = List.generate(
        5,
        (i) => SearchHit(
          file: EvrakFile(
            path: '/test/$i.txt',
            name: '$i.txt',
            format: EvrakFormat.text,
            sizeInBytes: 1,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchResults(
              focusNode: focus,
              hits: hits,
              query: '',
              selectedPath: hits.first.file.path,
              compact: true,
              hoverPreview: false,
              onOpen: (file) => opened.add(file.path),
              loadMore: () {},
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 120));
      expect(opened, ['/test/1.txt']);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 120));
      expect(opened, ['/test/1.txt', '/test/3.txt']);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 120));
      expect(opened.last, '/test/2.txt');
      // A pending preview cannot open after keyboard focus leaves the list.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      focus.unfocus();
      await tester.pump(const Duration(milliseconds: 120));
      expect(opened.last, '/test/2.txt');
      await tester.pumpWidget(const SizedBox.shrink());
      focus.dispose();
    },
  );
}
