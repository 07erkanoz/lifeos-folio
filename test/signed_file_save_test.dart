import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/signing/udf_signing_service.dart';

void main() {
  test(
    'signed output replaces the same path and leaves no generated folder',
    () async {
      final dir = await Directory.systemTemp.createTemp('folio-sign-save-');
      addTearDown(() => dir.delete(recursive: true));
      final original = Uint8List.fromList([1, 2, 3]);
      final output = Uint8List.fromList([1, 2, 3, 4]);
      final file = await File('${dir.path}/test.udf').writeAsBytes(original);
      final result = UdfSigningService.saveSigned(file.path, original, output);
      expect(result, file.path);
      expect(await file.readAsBytes(), output);
      expect(await dir.list().length, 1);
    },
  );
  test(
    'concurrent source modification is preserved when saving signature',
    () async {
      final dir = await Directory.systemTemp.createTemp('folio-sign-conflict-');
      addTearDown(() => dir.delete(recursive: true));
      final file = await File('${dir.path}/test.udf').writeAsBytes([9, 9]);
      expect(
        () => UdfSigningService.saveSigned(
          file.path,
          Uint8List.fromList([1, 2]),
          Uint8List.fromList([3, 4]),
        ),
        throwsStateError,
      );
      expect(await file.readAsBytes(), [9, 9]);
      expect(await dir.list().length, 1);
    },
  );
}
