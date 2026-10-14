import 'dart:math';

import 'package:evrak_convert/ui/widgets/text_marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'many marks are looked up near the run, the same spans as one by one',
    () {
      final random = Random(7);
      final marks = [
        for (var i = 0; i < 400; i++)
          TextMark(
            start: random.nextInt(5000),
            length: 1 + random.nextInt(12),
            style: TextStyle(fontSize: (i % 7).toDouble() + 1),
          ),
      ];
      String said(List<InlineSpan>? spans) => spans == null
          ? '-'
          : [
              for (final s in spans.cast<TextSpan>())
                '${s.text}@${s.style?.fontSize}',
            ].join('|');
      for (var i = 0; i < 300; i++) {
        final start = random.nextInt(5000);
        final text = 'x' * (1 + random.nextInt(60));
        final end = start + text.length;
        // One by one, as the splitter took them: a list too short to index,
        // the marks reaching here alone, in the order given.
        final near = [
          for (final m in marks)
            if (m.end > start && m.start < end) m,
        ];
        expect(
          said(markedSpans(text, start, null, marks)),
          said(near.length < 32 ? markedSpans(text, start, null, near) : null),
          reason: '$start..$end',
        );
      }
    },
  );
}
