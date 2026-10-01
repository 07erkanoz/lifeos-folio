import 'package:evrak_convert/services/annotations/pdf_annotation.dart';
import 'package:evrak_convert/services/legal/pdf_citations.dart';
import 'package:evrak_convert/ui/widgets/pdf_viewer_widget.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the wheel over a page that cites a law still scrolls it', (
    tester,
  ) async {
    var viewer = 0, handedOn = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 800,
            height: 600,
            // As pdfrx lays a page out: its scrolling underneath, and the
            // page's overlays beside it on top — not inside it.
            child: Stack(
              key: const ValueKey('page'),
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerSignal: (_) => viewer++,
                  ),
                ),
                Positioned.fill(
                  child: PdfCitationLayer(
                    marks: const [
                      PdfCitation(rects: [NormRect(.1, .1, .4, .15)]),
                    ],
                    quarterTurns: 0,
                    colour: Colors.blue,
                    onTap: (_, _) {},
                    onWheel: (_) => handedOn++,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final page = tester.getTopLeft(find.byKey(const ValueKey('page')));
    Future<void> wheel(Offset at) => tester.sendEventToBinding(
      PointerScrollEvent(position: page + at, scrollDelta: const Offset(0, 40)),
    );

    // Away from the citation the page's own scrolling hears the wheel; the
    // layer used to cover the whole page and keep it for itself.
    await wheel(const Offset(400, 400));
    expect((viewer, handedOn), (1, 0));
    // Over the citation the layer is what is hit, and it hands the wheel on:
    // once, not as well as the viewer.
    await wheel(const Offset(200, 75));
    expect((viewer, handedOn), (1, 1));
  });
}
