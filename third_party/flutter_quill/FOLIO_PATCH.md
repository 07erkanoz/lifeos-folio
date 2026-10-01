# flutter_quill 11.5.1, Folio yaması

Bu klasör pub.dev'deki `flutter_quill` 11.5.1'in `lib/` klasörüdür; üzerine
yalnız `folio.patch` uygulanmıştır. Uygulama `pubspec.yaml` içindeki
`dependency_overrides` ile bu kopyayı kullanır.

## Neden

Quill bir paragrafın girinti ve boşluklarını yalnız genel stillerden alır.
Word ve UYAP belgeleri ise her paragrafa kendi değerlerini verir. Editör bu
yüzden paragraf öncesi/sonrası boşluğu, ilk satır girintisini ve sağ
girintiyi hiç çizmiyor, sol girintiyi kendi adımına yuvarlıyordu; önizleme
bunları çizdiği için ikisi aynı belgede farklı görünüyordu. 874 gerçek UDF'de
belgelerin %18'inde paragraf boşluğu, %20'sinde sol, %12'sinde ilk satır
girintisi var.

## Ne değişti

- `QuillEditorConfig.lineLayoutBuilder` (`QuillLineLayout? Function(Line)`):
  satırın sol/sağ boşluğunu değiştirir, üst/alt boşluğa ekler ve ilk satır
  girintisi verir. `null` dönen satır eskisi gibi çizilir.
- Düz satırlar (`raw_editor_state.dart`) ve blok içindeki satırlar
  (`text_block.dart`, ör. iki yana yaslı paragraflar) bu kancayı okur.
- `QuillLineLayout.rowHeight`: paragraf işaretinin satırı, piksel olarak.
  Satırın sonuna (sondaki boşlukların önüne) satırın kendi stilinde
  görünmez bir birleştirici konur; UYAP paragraf sonunu da bir parça gibi
  saydığından son satır en az bu kadar olur, boş satır da bununla çizilir.
  Satıra hiç strut verilmez. Strut
  her satırı paragrafın varsayılan boyutuna göre en az yüksekliğe tutuyordu;
  10–11 pt metin bu yüzden fazla aralıklı çıkıyordu. `StrutStyle.disabled`
  da yetmez: 14 px'lik bir yazının satırını taban tutar (punto ölçeğindeki
  12 pt / 14 px satır 15 oluyordu); bir piksellik strut ise imlecin
  yüksekliğini ve yerini kendinden verir. Artık her parça satırını kendi
  stiliyle belirler.

- **Sayfalar** (`widgets/page_geometry.dart`): `QuillEditorConfig.pages`
  verilince satırlar A4 sayfalarına dizilir, UYAP'ın ve basılı sayfanın
  kuralıyla: sayfanın kalanına sığmayan satır bir sonraki sayfaya geçer,
  paragrafın üstündeki boşluk ilk satırıyla gider, altındaki boşluk
  sığmaya sayılmaz. Her çocuğun sayfadaki yeri kısıtlarıyla iner
  (`PagedBoxConstraints`), yeri değişmeyen satır yeniden yerleştirilmez.
  `RenderEditableTextLine` gövdesini yerleştirip satırlarına bakar: ilk
  satır sığmıyorsa bütün satırı iter, sonraki bir satır sığmıyorsa
  `RenderParagraphProxy.pageGaps` ile önüne boşluk açar. Vekil paragrafı
  sayfa sayfa dilimleyerek çizer (dilimler iki satırın harfleri arasından
  kesilir) ve imleç, seçim, tıklama ve dikey ok hareketini boşluklardan
  geçirir. `childAtOffset` artık çocukların yerine bakar; editör son
  sayfanın yazı alanının sonuna kadar uzar.
- **Sayfadaki tablolar** (`QuillPagedHost`, `pagesFromHost`): kısıtlar
  bir satırın içindeki tabloya, tablonun hücresindeki editöre inmez. Satır
  ve uygulamanın tablosu "ev sahibi"dir: altındaki bir nesne sayfalarını
  `pagesFromHost` ile ister, sayfalar ona kendi yerinden bakacak biçimde
  (`QuillPageGeometry.offset`) verilir ve yeri değişince yeniden
  yerleştirilir. Kendi sayfası olmayan (hücredeki) editör sayfalarını böyle
  alır ve son sayfaya uzamaz; sayfalarını kendisi bölen bir tablo taşıyan
  satır bir sonraki sayfaya itilmez.
- İlk satır girintisi boş bir `WidgetSpan`'dir ve paragrafın baştaki
  boşluklarından sonra konur: UYAP o boşlukları ilk satırı doldururken sayar,
  yaslarken yok sayar; Flutter da satırın en başındaki boşluğa aynısını
  yapar. `RenderParagraphProxy` imleç, tıklama, sözcük ve seçim konumlarını
  bu yer tutucuyu atlayarak çevirir; Quill'in geri kalanı belge ofsetlerini
  eskisi gibi görür.
- `QuillLineLayout.hanging` ve `.width`: asılı girinti (UYAP'ın `Hanging`
  özniteliği; ilk satır dışındaki satırlar bu kadar içeriden başlar).
  Flutter bir paragrafa satır satır girinti veremediği için
  `text/hanging_indent.dart` satırı bir `TextPainter` ile `width`
  genişliğinde dizer, ilk satırdan sonraki her satırın başladığı yeri bulur
  ve oraya girinti genişliğinde bir kutu ile görünmeyecek kadar küçük bir bölünmez boşluk
  koyar (kutu satır sonunda kalamasın diye). `width` yoksa (tablo hücresi,
  üst/alt bilgi) asılı girinti çizilmez.
- `QuillLineLayout.leading`: bir liste satırının numarası ya da madde
  işareti yerine uygulamanın çizdiği bileşen. Uygulama listeyi UYAP gibi
  sıradan paragraf olarak dizer ve işareti girinti boşluğuna kendisi çizer.
- `QuillLineLayout.rows`: uygulamanın basılı sayfa kurallarıyla bulduğu
  satır başları. Satır yalnız oralarda kırılsın diye başka her sözcük ve
  sekme önüne birleştirici, satır başlarına sıfır genişlikli boşluk konur.
  Flutter birleştiriciye rağmen her boşlukta kırabildiği için, UYAP'ın
  aşağı aldığı ama Flutter'ın sondaki boşluğu taşırarak yukarıda tutacağı
  sözcüğün ardındaki boşluk uygulamada bölünmez boşluk olarak çizilir.
- Aynı dosya satırın UYAP gibi yalnız boşluklarda kırılmasını sağlar:
  sözcük içindeki `/`, tire, `!` ve `?`'den sonra ve boşluksuz gelen açılış
  parantezinden önce görünmez sözcük birleştirici (U+2060; "Manavgat/" ile
  "Antalya", "ettiği," ile "(Sanıklar" ayrılmasın); boşluktan sonra gelen
  `/ : ; , . ! ? ) ] }` öncesine ve açılış parantezinden sonraki
  boşlukların ardına sıfır genişlikli boşluk (U+200B; Unicode LB13/LB14
  "No:33 /Z01"i, "NEDENLER :"u ve "Kiracı ( taahhüt…"ü birlikte aşağı
  atıyordu).
- Asılı girintinin satır sonları, satırın yerleşimini belirleyen her şeyden
  (metin, yazı tipi, boyut, kutu genişlikleri, genişlik) üretilen bir
  anahtarla `_TextLineState`'te saklanır; Quill her tuşta bütün satırları
  yeniden kurduğu için her seferinde yeniden ölçülmez.
- Eklenen tüm karakterler (`LineInsertion` listesi) `RichTextProxy
  .insertions` ile vekile verilir; imleç, seçim, tıklama ve sözcük konumları
  bunlar atlanarak belge ofsetlerine çevrilir.

- Sağ tık menüsü farenin tıklandığı yerde açılır (`EditorState
  .contextMenuRequestPosition`). Klavyeyle açılan menünün konumu seçimden,
  her nokta editörün tam dönüşümünden geçirilerek hesaplanır: Flutter'ın
  `TextSelectionToolbarAnchors.fromSelection`'ı seçimin yerel, ölçeklenmemiş
  konumunu editörün ekrandaki köşesine ekliyordu; sayfa büyütülünce menü
  yukarıda, küçültülünce ekran dışında çıkıyordu.
- Kendisi kaydırmayan (`scrollable: false`) bir editörde imleç hareket
  edince çevreleyen kaydırma görünümlerinden `showOnScreen` ile imlecin
  satırını görünür tutması istenir. Quill bunu yalnız kendi kaydırma alanı
  varken yapıyordu; aşağı okla imleç sayfanın altından kayboluyordu.

- Fareyle sürükleyerek seçim, editörde odak yoksa klavyeyi alır; Flutter'ın
  kendi metin alanları gibi. Quill yalnız tıklamada istiyordu: odak başka
  yerdeyken sürüklenen metin seçili görünüyor, Delete ve Ctrl+B hiçbir
  yere ulaşmıyordu.

Uygulama tarafı: `lib/ui/widgets/editor_line_layout.dart`,
`lib/ui/widgets/editor_tab_spans.dart`, `lib/ui/widgets/editor_pages.dart`;
testler: `test/editor_line_layout_test.dart`,
`test/editor_hanging_indent_test.dart`, `test/editor_pages_test.dart`,
`test/editor_page_breaks_test.dart`.

## Quill yükseltilirken

1. Yeni sürümün `lib/` klasörünü buraya kopyalayın.
2. `git apply third_party/flutter_quill/folio.patch` (bu klasörde çalıştırın);
   tutmayan parça olursa elle uygulayın ve `folio.patch`'i yeniden üretin.
3. `flutter test test/editor_line_layout_test.dart
   test/editor_hanging_indent_test.dart` ve tüm test paketi.

`folio.patch`'i yeniden üretmek için pub önbelleğindeki saf `lib/`'i (`a/`)
ve bu klasördekini (`b/`) yan yana koyup
`git diff --no-index --no-prefix a/lib b/lib` alın; yeni dosyaların başlık
satırındaki `b/lib/…`'i `a/lib/…` yapın. Saf kopyaya uygulanınca bu klasörü
birebir vermeli.

Bu klasörde `flutter pub get` / `flutter analyze` çalıştırmayın: paketin
yerelleştirme üreteci `lib/src/l10n` dosyalarını yeniden yazar.
