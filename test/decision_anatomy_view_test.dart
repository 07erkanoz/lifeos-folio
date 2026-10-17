import 'package:evrak_convert/services/legal/case_law.dart';
import 'package:evrak_convert/services/legal/decision_anatomy.dart';
import 'package:evrak_convert/ui/widgets/citation_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _text = '''
9. Hukuk Dairesi 2025/9394 E. , 2026/696 K.
"İçtihat Metni"MAHKEMESİ : Trabzon Bölge Adliye Mahkemesi 5. Hukuk Dairesi
SAYISI : 2024/1375 E., 2025/1715 K.
İLK DERECE MAHKEMESİ : Trabzon 2. İş Mahkemesi
SAYISI : 2022/269 E., 2024/87 K.
I. DAVA
Davacı vekili dava dilekçesinde; müvekkilinin kıdem tazminatının ödenmediğini ileri sürerek tahsilini talep etmiştir.
II. CEVAP
Davalı vekili cevap dilekçesinde; davanın reddini istemiştir.
III. İLK DERECE MAHKEMESİ KARARI
İlk Derece Mahkemesinin kararı ile davanın kısmen kabulüne karar verilmiştir.
IV. İSTİNAF
Bölge Adliye Mahkemesince istinaf başvurusunun esastan reddine karar verilmiştir.
V. TEMYİZ
B. Değerlendirme ve Gerekçe
Uyuşmazlık, kıdem tazminatı alacağının hesaplanmasına ilişkindir.
Mülga 1475 sayılı İş Kanunu'nun 14/2 hükmü işçinin aynı işverene bağlı olarak çalıştığı sürelerin kıdem hesabı yönünden birleştirileceğini hükme bağlamıştır.
Fasılalı çalışmada bir döneme ilişkin kıdem tazminatının eksik ödendiği belirlendiği takdirde o dönem bakımından tasfiyeden söz edilmesi mümkün değildir.
Bu hususlar gözetilmeksizin yazılı şekilde hüküm kurulması hatalı olup bozmayı gerektirmiştir.
VI. KARAR
Açıklanan sebeplerle;
1. Temyiz olunan Bölge Adliye Mahkemesi kararının ORTADAN KALDIRILMASINA,
2. İlk Derece Mahkemesi kararının BOZULMASINA,
02.02.2026 tarihinde oy birliğiyle karar verildi.''';

/// The same decision with a great deal of text before its reasoning, so
/// that what is pointed at is off screen until it is gone to.
String get _long => _text.replaceFirst(
  'II. CEVAP',
  '${'Davacı vekili ayrıca ayrıntılı açıklamalarda bulunmuştur. ' * 6}\n' * 40 +
      'II. CEVAP',
);

Decision _decision(String text) => Decision(
  court: '9. Hukuk Dairesi',
  esas: '2025/9394',
  karar: '2026/696',
  date: '02.02.2026',
  text: text,
);

Future<void> _open(WidgetTester tester, String text) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final decision = _decision(text);
  await tester.pumpWidget(
    MaterialApp(
      home: CitationPreviewScreen(
        data: decisionFound(decision),
        query: 'kıdem tazminatı',
        readAnatomy: (d, query) async =>
            DecisionAnatomy.of(d.text, query: query),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a found decision is shown with its anatomy above it', (
    tester,
  ) async {
    await _open(tester, _text);
    expect(find.text('Karar anatomisi'), findsOneWidget);
    expect(find.text('Bozma'), findsWidgets);
    expect(find.textContaining('Trabzon 2. İş Mahkemesi'), findsWidgets);
    expect(find.textContaining('Uyuşmazlık, kıdem tazminatı'), findsWidgets);
    // A quotation from the decision, said to be one: never a "binding
    // principle" the app has drawn out of it.
    expect(find.text('Karardan öne çıkan bölüm (alıntı)'), findsOneWidget);
    expect(find.textContaining('ilke'), findsNothing);
    expect(find.textContaining('Fasılalı çalışmada'), findsWidgets);
  });

  testWidgets('pressing a quotation goes to it in the text', (tester) async {
    await _open(tester, _long);
    final quote = find.byKey(const ValueKey('anatomy-highlight-0'));
    expect(quote, findsOneWidget);
    final marked = find.byKey(const ValueKey('decision-paragraph-marked'));
    expect(marked, findsNothing);

    await tester.ensureVisible(quote);
    await tester.tap(quote);
    await tester.pumpAndSettle();

    expect(marked, findsOneWidget);
    final paragraph = tester.widget<Text>(
      find.descendant(of: marked, matching: find.byType(Text)),
    );
    expect(paragraph.textSpan!.toPlainText(), contains('Fasılalı çalışmada'));
    // Brought onto the screen.
    final top = tester.getTopLeft(marked).dy;
    expect(top, inInclusiveRange(0, 800));
  });

  testWidgets('a decision with nothing to read in it shows no anatomy', (
    tester,
  ) async {
    await _open(tester, 'Kısa bir metin.');
    expect(find.text('Karar anatomisi'), findsNothing);
  });
}
