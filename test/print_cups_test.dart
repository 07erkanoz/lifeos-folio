import 'dart:io';
import 'dart:typed_data';

import 'package:evrak_convert/services/print/print_job.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';

// On Linux a PDF goes to CUPS as it is, the printer's queue named: the
// plugin's own drawing of it printed blank pages.
void main() {
  tearDown(() {
    PrintJob.runForTesting = null;
    PrintJob.linuxForTesting = null;
  });

  test(
    'sent with lp to the printer chosen, the file there while it is',
    () async {
      PrintJob.linuxForTesting = true;
      List<String>? said;
      var there = false;
      PrintJob.runForTesting = (program, args) async {
        said = args;
        there =
            File(args.last).existsSync() &&
            File(args.last).readAsBytesSync().length == 4;
        return ProcessResult(1, 0, '', '');
      };
      final sent = await PrintJob.send(
        Uint8List.fromList([37, 80, 68, 70]),
        name: 'Sınav.pdf',
        printer: const Printer(url: 'Canon_MF216n'),
      );
      expect(sent, isTrue);
      expect(
        said,
        containsAllInOrder(['-d', 'Canon_MF216n', '-t', 'Sınav.pdf']),
      );
      expect(there, isTrue);
      expect(File(said!.last).existsSync(), isFalse);
    },
  );

  test('a printer saying no is said so', () async {
    PrintJob.linuxForTesting = true;
    PrintJob.runForTesting = (program, args) async =>
        ProcessResult(1, 1, '', 'lp: The printer or class does not exist.');
    expect(
      () => PrintJob.send(
        Uint8List(4),
        name: 'x.pdf',
        printer: const Printer(url: 'yok'),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
