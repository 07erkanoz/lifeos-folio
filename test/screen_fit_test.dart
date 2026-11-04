import 'package:evrak_convert/services/desktop/screen_fit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a window fits a small laptop screen, its dock left free', () {
    expect(
      fitToScreen(const Size(1200, 800), const Size(1280, 800)),
      const Size(1200, 720),
    );
    final small = fitToScreen(const Size(1200, 800), const Size(1366, 768));
    expect(small.height, lessThan(768 - 48));
  });

  test('a large screen keeps the size wanted', () {
    expect(
      fitToScreen(const Size(1200, 800), const Size(1920, 1080)),
      const Size(1200, 800),
    );
  });

  test('never below the minimum, and an unread screen changes nothing', () {
    expect(
      fitToScreen(
        const Size(1200, 800),
        const Size(800, 600),
        minimum: const Size(900, 600),
      ),
      const Size(900, 600),
    );
    expect(
      fitToScreen(const Size(1200, 800), Size.zero),
      const Size(1200, 800),
    );
  });
}
