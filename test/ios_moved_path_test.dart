import 'package:evrak_convert/services/platform/app_directories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a path kept under an earlier iPhone app folder names the folder '
      'Folio has now; one outside it is kept as it is', () {
    const now =
        '/var/mobile/Containers/Data/Application/'
        '11111111-2222-3333-4444-555555555555';
    const before =
        '/private/var/mobile/Containers/Data/Application/'
        'ABCDEF01-2345-6789-ABCD-EF0123456789';
    expect(
      movedPath('$before/Documents/UYAP/2024-318/karar.udf', now),
      '$now/Documents/UYAP/2024-318/karar.udf',
    );
    expect(movedPath('$now/Documents/a.pdf', now), '$now/Documents/a.pdf');
    const outside =
        '/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/a';
    expect(movedPath(outside, now), outside);
  });
}
