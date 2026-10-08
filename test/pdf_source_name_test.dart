import 'package:evrak_convert/ui/widgets/pdf_viewer_widget.dart';
import 'package:flutter_test/flutter_test.dart';

// The viewer keeps documents by their source's name; two documents given
// as bytes must never share one, or the first is shown for the second.
void main() {
  test('documents given as bytes are named by their content', () {
    final a = PdfViewerWidget.sourceNameOf([1, 2, 3], null);
    final b = PdfViewerWidget.sourceNameOf([1, 2, 4], null);
    expect(a, isNot(b));
    expect(PdfViewerWidget.sourceNameOf([1, 2, 3], null), a);
  });
}
