import 'package:evrak_convert/services/desktop/kwin_palette_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the rule is added once, beside the lawyer\'s own', () {
    const own = '[General]\ncount=1\nrules=abc\n\n[abc]\nDescription=Benim\n';
    final once = KwinPaletteRule.withRule(own, 'Folio hızlı arama');
    expect(once, contains('count=2'));
    expect(once, contains('rules=abc,${KwinPaletteRule.group}'));
    expect(once, contains('[abc]\nDescription=Benim'));
    expect(once, contains('title=Folio hızlı arama'));
    expect(once, contains('placement=5'));
    expect(KwinPaletteRule.withRule(once, 'Folio hızlı arama'), once);
    final empty = KwinPaletteRule.withRule('', 'X');
    expect(
      empty,
      startsWith('[General]\ncount=1\nrules=${KwinPaletteRule.group}'),
    );
  });
}
