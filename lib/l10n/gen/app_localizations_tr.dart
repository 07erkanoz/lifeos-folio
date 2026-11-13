// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get languageName => 'Türkçe';

  @override
  String get languageSystem => 'Sistemin dili';

  @override
  String get languageMenu => 'Dil';

  @override
  String ofisNewDocumentTitle(String extension) {
    return 'Yeni belge.$extension';
  }

  @override
  String get ofisAbout => 'LifeOS Ofis hakkında';

  @override
  String get ofisDocuments => 'Belgeler';

  @override
  String get ofisNew => 'Yeni';

  @override
  String get ofisNewTooltip => 'Yeni Word belgesi · Ctrl+N';

  @override
  String get ofisOpen => 'Aç';

  @override
  String get ofisOpenTooltip => 'Belge aç · Ctrl+O';

  @override
  String get ofisOpenDialog => 'Belge aç';

  @override
  String get ofisFileMoved => 'Belge taşınmış veya kaldırılmış';

  @override
  String get ofisCannotOpenType => 'Bu belge türü açılamıyor';

  @override
  String get ofisDraftCannotOpen => 'Bu taslak burada açılamıyor';

  @override
  String get ofisEdit => 'Düzenle';

  @override
  String get ofisHomeTitle => 'Belgeleriniz';

  @override
  String get ofisOpenAction => 'Belge aç';

  @override
  String get ofisOpenActionDetail =>
      'Word, PDF, RTF, ODT, Markdown, Excel, UDF, .imz';

  @override
  String get ofisNewDocx => 'Yeni Word belgesi';

  @override
  String get ofisNewDocxDetail => 'DOCX olarak';

  @override
  String get ofisDropHere => 'Belgeyi buraya sürükleyin';

  @override
  String get ofisRecent => 'SON BELGELER';

  @override
  String get ofisRecentEmpty => 'Açtığınız belgeler burada görünür.';

  @override
  String get ofisImzBadge => 'İMZ';

  @override
  String get ofisSignedDocument => 'E-imzalı belge';

  @override
  String whenToday(String clock) {
    return 'Bugün $clock';
  }

  @override
  String whenYesterday(String clock) {
    return 'Dün $clock';
  }

  @override
  String whenDaysAgo(int days) {
    return '$days gün önce';
  }

  @override
  String get formatTiff => 'TIFF Evrak';

  @override
  String get formatImage => 'Görsel';

  @override
  String get formatText => 'Metin';

  @override
  String get formatRtf => 'Zengin Metin RTF';

  @override
  String get formatData => 'Veri / Metin';

  @override
  String get formatUnknown => 'Bilinmeyen';

  @override
  String editorFindReplacedCount(int count) {
    return '$count eşleşme değiştirildi.';
  }

  @override
  String get editorFindTitle => 'Bul ve değiştir';

  @override
  String get editorFindQuery => 'Aranan metin';

  @override
  String get editorFindMatchCase => 'Büyük/küçük harf';

  @override
  String get editorFindWholeWord => 'Tam sözcük';

  @override
  String get editorFindPrompt => 'Belge içinde arayın';

  @override
  String get editorFindNoMatch => 'Eşleşme bulunamadı';

  @override
  String editorFindPosition(int current, int total) {
    return '$current / $total eşleşme';
  }

  @override
  String get editorFindPrevious => 'Önceki eşleşme';

  @override
  String get editorFindNext => 'Sonraki eşleşme';

  @override
  String get editorFindReplace => 'Değiştir';

  @override
  String get editorFindReplacement => 'Yeni metin';

  @override
  String get editorFindReplaceAll => 'Tümünü değiştir';

  @override
  String get editorClose => 'Kapat';

  @override
  String get editorPageJump => 'Sayfaya git';

  @override
  String editorPageSemantics(int current, int count) {
    return 'Sayfa $current / $count';
  }

  @override
  String get editorPageNumberField => 'Sayfa numarası';

  @override
  String get editorCancel => 'Vazgeç';

  @override
  String get editorPageJumpGo => 'Git';

  @override
  String get editorZoomOut => 'Uzaklaştır';

  @override
  String get editorZoomTooltip => 'Yakınlaştırma · Ctrl + fare tekerleği';

  @override
  String editorZoomPercent(int percent) {
    return '%$percent';
  }

  @override
  String get editorZoomIn => 'Yakınlaştır';

  @override
  String get editorZoomReset => 'Sıfırla';

  @override
  String get editorRulerMarginLeft => 'Sol kenar boşluğu';

  @override
  String get editorRulerMarginRight => 'Sağ kenar boşluğu';

  @override
  String get editorRulerMarginTop => 'Üst kenar boşluğu';

  @override
  String get editorRulerMarginBottom => 'Alt kenar boşluğu';

  @override
  String editorRulerMarginTip(String label, String cm) {
    return '$label: $cm cm · Sürükleyin';
  }

  @override
  String editorRulerTabKindTip(String kind) {
    return 'Sekme türü: $kind · Değiştirmek için tıklayın';
  }

  @override
  String editorRulerTabStopTip(String kind, String cm) {
    return '$kind sekme · $cm cm · Silmek için aşağı sürükleyin ya da çift tıklayın';
  }

  @override
  String get editorRulerFirstLineIndent => 'İlk satır girintisi';

  @override
  String get editorRulerLeftIndent => 'Sol ve asılı girinti';

  @override
  String get editorRulerRightIndent => 'Sağ girinti';

  @override
  String get editorTabLeft => 'Sol';

  @override
  String get editorTabCentre => 'Orta';

  @override
  String get editorTabRight => 'Sağ';

  @override
  String get editorTabDecimal => 'Ondalık';

  @override
  String get editorTabBar => 'Çubuk';

  @override
  String get editorHeaderPlaceholder =>
      'Üst bilgi — her sayfanın başında yazılır';

  @override
  String get editorFooterPlaceholder =>
      'Alt bilgi — her sayfanın sonunda yazılır';

  @override
  String get editorRegionRemove => 'KALDIR';

  @override
  String get editorHeaderLabel => 'ÜST BİLGİ';

  @override
  String get editorFooterLabel => 'ALT BİLGİ';

  @override
  String editorRegionPrintsFromPage(String page) {
    return '$page. sayfadan itibaren basılır';
  }

  @override
  String get editorHistoryWriteFailed => 'Belge geçmişine yazılamadı';

  @override
  String get editorHistoryWriteFailedDetail =>
      'Belgeniz yine de kaydedilebilir; yalnız bu sürüm saklanmadı.';

  @override
  String get editorUnsavedChangesTitle => 'Kaydedilmemiş değişiklikler var';

  @override
  String get editorShareSavedOnly =>
      'Paylaşılan, belgenin kaydedilmiş hâlidir.';

  @override
  String get editorShareSavedVersion => 'Kaydedilmiş hâlini paylaş';

  @override
  String get editorSaveAndShare => 'Kaydet ve paylaş';

  @override
  String get editorReplaceWhatDraft => 'Taslak';

  @override
  String get editorReplaceWhatVersion => 'Seçilen sürüm';

  @override
  String get editorVersionUnreadable => 'Sürüm okunamadı.';

  @override
  String get editorVersionOpenFailed => 'Sürüm açılamadı';

  @override
  String get editorNotSavedYet => 'Bu belge henüz kaydedilmedi';

  @override
  String get editorHistoryFromFirstSave =>
      'Geçmiş, ilk kayıttan itibaren tutulur.';

  @override
  String get editorRestoreLabel => 'Editöre yükle';

  @override
  String get editorRestoreHint =>
      'Seçilen sürüm editöre kaydedilmemiş değişiklik olarak gelir; siz kaydedene kadar dosya değişmez.';

  @override
  String editorVersionLoaded(String date) {
    return '$date sürümü editöre yüklendi';
  }

  @override
  String get editorSaveToKeep => 'Dosyada kalıcı olması için kaydedin.';

  @override
  String editorCitationLaws(int count) {
    return '$count kanun maddesi';
  }

  @override
  String editorCitationDecisions(int count) {
    return '$count karar';
  }

  @override
  String editorCitationShowTip(String detail) {
    return '$detail · dayanakları göster';
  }

  @override
  String editorCitationTotal(int count) {
    return '$count dayanak';
  }

  @override
  String get editorCitationTitle => 'Bu belgenin dayanakları';

  @override
  String get editorCaseLawPanelTitle => 'Emsal karar ara';

  @override
  String get editorClosePanel => 'Paneli kapat';

  @override
  String get editorOpenInWindow => 'Ayrı pencerede aç';

  @override
  String get editorReadAloud => 'Sesli oku';

  @override
  String editorTermMeaning(String term) {
    return '“$term” ne demek?';
  }

  @override
  String get editorAddToDictionary => 'Sözlüğe ekle';

  @override
  String editorSnippetHotkeyUnassigned(int key) {
    return 'Alt+F$key bir kalıba atanmamış.';
  }

  @override
  String get editorSnippetHotkeyHint =>
      'Ctrl+Space → Kalıplarımı yönet ile atayabilirsiniz.';

  @override
  String get editorSnippetEmbedsSkipped =>
      'Seçimdeki tablo ve görseller kalıba alınmadı.';

  @override
  String get editorSnippetTextOnly => 'Kalıp yalnız metni ve biçimini tutar.';

  @override
  String editorSnippetsAdded(int count) {
    return '$count kalıp eklendi.';
  }

  @override
  String get editorOpenElsewhere => 'Bu belge başka bir pencerede açık';

  @override
  String get editorOpenElsewhereDetail =>
      'Aynı belge iki pencerede düzenlenirse biri ötekinin kaydını ezer. Belgeyi açık olduğu pencerede düzenleyin.';

  @override
  String get editorHeldElsewhereBanner =>
      'Bu belge başka bir Folio penceresinde düzenleniyor. Burada yalnız okunabilir; değişiklikleri o pencerede yapın.';

  @override
  String get editorRetry => 'Yeniden dene';

  @override
  String get editorDictationFailed => 'Sesli yazma başlamadı';

  @override
  String get editorFormatNothing => 'Biçimlendirilecek bir şey bulunamadı';

  @override
  String get editorFormatted => 'Biçimlendirildi';

  @override
  String get editorUndoHint => 'Ctrl+Z ile geri alabilirsiniz.';

  @override
  String get editorPrintName => 'Belge';

  @override
  String get editorPrintFailed => 'Yazdırılamadı';

  @override
  String get editorInsertImageTitle => 'Görsel ekle';

  @override
  String get editorImageTooLarge =>
      'Görsel çok büyük — en çok 12 MB eklenebilir.';

  @override
  String editorImageUnreadable(String name) {
    return 'Görsel okunamadı: $name';
  }

  @override
  String editorImageInsertFailed(String error) {
    return 'Görsel eklenemedi: $error';
  }

  @override
  String get editorDeleteHeaderTitle => 'Üst bilgi silinsin mi?';

  @override
  String get editorDeleteFooterTitle => 'Alt bilgi silinsin mi?';

  @override
  String get editorDeleteRegionBody =>
      'Yazdıklarınız belgeden kaldırılacak. Kaydetmeden çıkarsanız değişiklik uygulanmaz.';

  @override
  String get editorDelete => 'Sil';

  @override
  String get editorPageView => 'Sayfa görünümü';

  @override
  String get editorMobileView => 'Mobil görünüm';

  @override
  String get editorSign => 'İmzala';

  @override
  String get editorSignWithCard => 'E-imza kartıyla';

  @override
  String get editorCaseLaw => 'İçtihat';

  @override
  String get editorMoreTools => 'Diğer araçlar';

  @override
  String get editorTodaysDate => 'Bugünün tarihi';

  @override
  String get editorSnippets => 'Kalıp metin';

  @override
  String get editorDocumentHistory => 'Belge geçmişi';

  @override
  String get editorResearch => 'Araştırma';

  @override
  String get editorSearchCaseLaw => 'İçtihat ara';

  @override
  String get editorCompare => 'Karşılaştır';

  @override
  String get editorCompareTip => 'Kaydedilmiş sürümlerle karşılaştır';

  @override
  String get editorSignCardButton => 'E-imza\nkartı';

  @override
  String get editorSignWayCard => 'e-imza kartıyla';

  @override
  String get editorSignOnlyUdf =>
      'Yalnız UDF belgeler imzalanır: önce UDF olarak kaydedin';

  @override
  String editorSignUnavailable(String way) {
    return '$way bu cihazda kullanılamıyor';
  }

  @override
  String get editorSigning => 'İmzalanıyor…';

  @override
  String editorSignAsUdf(String way) {
    return 'UDF olarak $way imzala';
  }

  @override
  String editorTableSize(int rows, int columns) {
    return '$rows × $columns tablo';
  }

  @override
  String get editorTable => 'Tablo';

  @override
  String get editorImage => 'Görsel';

  @override
  String get editorHeader => 'Üst bilgi';

  @override
  String get editorFooter => 'Alt bilgi';

  @override
  String get editorPageNumbers => 'Sayfa numarası';

  @override
  String get editorLetterhead => 'Antet';

  @override
  String get editorDate => 'Tarih';

  @override
  String get editorTableAndImage => 'Tablo ve görsel';

  @override
  String get editorHeaderAndFooter => 'Üst ve alt bilgi';

  @override
  String get editorText => 'Metin';

  @override
  String get editorSignatureBlock => 'İmza bloğu';

  @override
  String get editorHorizontalRuler => 'Yatay cetvel';

  @override
  String get editorVerticalRuler => 'Dikey cetvel';

  @override
  String get editorShortcuts => 'Kısayollar';

  @override
  String get editorView => 'Görünüm';

  @override
  String get editorRulers => 'Cetveller';

  @override
  String get editorOther => 'Diğer';

  @override
  String get editorShortcutsTitle => 'Editör kısayolları';

  @override
  String get editorShortcutsList =>
      'Ctrl+S  Kaydet\nCtrl+Shift+S  Farklı kaydet\nCtrl+Z  Geri al\nCtrl+Y / Ctrl+Shift+Z  Yinele\nCtrl+B / I / U  Kalın / İtalik / Altı çizili\nCtrl+A / C / X / V  Seç / Kopyala / Kes / Yapıştır\nCtrl+F  Belgede bul\nCtrl+H  Bul ve değiştir\nCtrl+P  Yazdır\nCtrl+L / E / R / J  Sola / Ortaya / Sağa / İki yana\nCtrl+Shift+L / 8  Madde işaretleri\nCtrl+Shift+7  Numaralı liste\nCtrl+M / Ctrl+Shift+M  Girintiyi artır / azalt\n\nmacOS’ta Ctrl yerine ⌘ kullanılır.';

  @override
  String get editorOk => 'Tamam';

  @override
  String get editorSaveFormatTitle => 'Hangi biçimde kaydedilsin?';

  @override
  String get editorFormatUdf => 'UYAP belgesi (.udf)';

  @override
  String get editorFormatDocx => 'Word belgesi (.docx)';

  @override
  String get editorFormatRtf => 'Zengin metin (.rtf)';

  @override
  String get editorFormatPdf => 'Yazdırılmış hâli (.pdf)';

  @override
  String get editorContinue => 'Devam';

  @override
  String get editorSignedTitle => 'Bu belge e-imzalı';

  @override
  String get editorSignedBody =>
      'İmza, belgenin imzalandığı andaki içeriğini kapsar; değiştirilmiş belgeye taşınamaz.\n\n• Üzerine kaydet: dosya değişikliklerinizle, imzasız olarak güncellenir. İmzalı hali belge geçmişinde saklanır; istediğinizde ona dönebilir ya da kopyasını alabilirsiniz.\n\n• İmzasız kopya: imzalı dosya olduğu gibi kalır, değişiklikler yeni bir dosyaya yazılır.';

  @override
  String get editorSaveUnsignedCopy => 'İmzasız kopya kaydet…';

  @override
  String get editorOverwriteSave => 'Üzerine kaydet';

  @override
  String get editorChangedElsewhereTitle =>
      'Belge başka bir yerde değiştirildi';

  @override
  String get editorChangedElsewhereBody =>
      'Bu dosya, siz burada açtıktan sonra başka bir programda değiştirilmiş. Kaydederseniz sizin hâliniz geçerli olur; öbür hâli belge geçmişinde saklanır.';

  @override
  String get editorSaveMine => 'Benim hâlimi kaydet';

  @override
  String get editorOverwriteSignedTitle =>
      'İmzalı dosyanın üzerine yazılsın mı?';

  @override
  String get editorOverwriteSignedBody =>
      'Dosya değişikliklerinizle, imzasız olarak güncellenir. İmzalı hali belge geçmişinde saklanır.';

  @override
  String get editorOverwrite => 'Üzerine yaz';

  @override
  String get editorPdfNoTextNoOcr =>
      'Bu PDF’te metin katmanı yok: yazıları taranmış ya da yazdırılırken şekle dönüştürülmüş. Okumak için gereken OCR aracı bu kurulumda bulunamadı.';

  @override
  String get editorPdfNoTextUnreadable =>
      'Bu PDF’te metin katmanı yok ve sayfalarında okunabilir yazı bulunamadı.';

  @override
  String get editorUnreadable => 'Belge okunamadı veya bozuk.';

  @override
  String get editorOcrRead =>
      'Bu PDF’te metin katmanı yoktu; metin sayfalardan okundu (OCR).';

  @override
  String get editorOcrCheck =>
      'Kaydetmeden önce özellikle rakamları ve adları kontrol edin.';

  @override
  String get editorBlanksTitle => 'Doldurulmamış yer var';

  @override
  String editorBlanksBody(int count, String names) {
    return 'Belgede kalıptan gelen $count yer hâlâ boş: $names.\n\nYine de kaydedilsin mi?';
  }

  @override
  String get editorGoBack => 'Geri dön';

  @override
  String get editorSaveAnyway => 'Yine de kaydet';

  @override
  String get editorUnsignedCopyTitle => 'İmzasız kopya kaydedilecek';

  @override
  String get editorUnderstoodSave => 'Anladım, kaydet';

  @override
  String editorSaveDialogTitle(String ext) {
    return 'Evrakı Kaydet ($ext)';
  }

  @override
  String get editorOverwriteHeldDetail =>
      'Üzerine yazmak, o penceredeki çalışmayı kaybettirebilir. Başka bir adla kaydedin ya da önce o pencereyi kapatın.';

  @override
  String get editorSignedNotOverwritten => 'İmzalı dosyanın üzerine yazılmadı';

  @override
  String get editorSignedNotOverwrittenDetail =>
      'İmzalı hali belge geçmişine saklanamadı. Değişiklikleri imzasız kopya olarak kaydedebilirsiniz.';

  @override
  String get editorNotOverwritten => 'Belgenin üzerine yazılmadı';

  @override
  String get editorNotOverwrittenDetail =>
      'Başka programdaki hâli belge geçmişine saklanamadı. Değişikliklerinizi başka bir adla kaydedebilirsiniz.';

  @override
  String get editorSaved => 'Kaydedildi';

  @override
  String get editorSavedToLocation => 'Belge seçtiğiniz konuma kaydedildi.';

  @override
  String editorSavedAs(String name) {
    return 'Başarıyla kaydedildi: $name';
  }

  @override
  String get editorSaveAs => 'Farklı kaydet';

  @override
  String get editorSaveFailed => 'Kaydetme hatası: belge kaydedilemedi';

  @override
  String get editorOcrReading =>
      'Bu PDF’te metin katmanı yok; sayfalar okunuyor (OCR)…';

  @override
  String get editorOcrPerPage => 'Sayfa başına birkaç saniye sürebilir.';

  @override
  String editorOpenFailed(String error) {
    return 'Belge açılamadı: $error';
  }

  @override
  String get editorRecoverFromHistory => 'Belge geçmişinden kurtar';

  @override
  String get editorFontLoadFailed => 'Yazı tipi yüklenemedi';

  @override
  String get editorSignUdf => 'UDF e-imzala';

  @override
  String get editorSaveTooltip => 'Kaydet · Ctrl+S';

  @override
  String get snipDeleteTitle => 'Kalıp silinsin mi?';

  @override
  String snipDeleteBody(String name) {
    return '“$name” kalıplarınızdan kaldırılacak. Bu kalıpla yazılmış belgeler değişmez.';
  }

  @override
  String get snipCancel => 'Vazgeç';

  @override
  String get snipDelete => 'Sil';

  @override
  String get snipExportDialog => 'Kalıpları dışa aktar';

  @override
  String snipExported(int count) {
    return '$count kalıp dışa aktarıldı.';
  }

  @override
  String get snipExportFailed => 'Kalıplar dışa aktarılamadı';

  @override
  String get snipImportDialog => 'Kalıpları içe aktar';

  @override
  String get snipImportNone => 'Yeni kalıp yok; hepsi zaten kalıplarınızda.';

  @override
  String snipImported(int count) {
    return '$count kalıp eklendi.';
  }

  @override
  String get snipImportFailed => 'Kalıplar içe aktarılamadı';

  @override
  String get snipManagerTitle => 'Kalıplarım';

  @override
  String get snipImport => 'İçe aktar';

  @override
  String get snipExport => 'Dışa aktar';

  @override
  String get snipSearchHint => 'Kalıp ara';

  @override
  String get snipManagerEmpty =>
      'Henüz kalıp yok. \"Yeni kalıp\" ile ekleyebilir ya da belgede bir paragrafı seçip Ctrl+Space ile kalıba alabilirsiniz.';

  @override
  String get snipNoMatch => 'Bu aramaya uyan kalıp yok.';

  @override
  String snipUsedTimes(int count) {
    return '$count kez';
  }

  @override
  String get snipNew => 'Yeni kalıp';

  @override
  String get snipClose => 'Kapat';

  @override
  String get snipEditTitle => 'Kalıbı düzenle';

  @override
  String get snipEmptyBody => 'Kalıbın metni boş olamaz.';

  @override
  String get snipBadKeyword =>
      'Anahtar kelime 2–20 harf ya da rakamdan oluşmalı, boşluk olmadan.';

  @override
  String snipKeywordTaken(String keyword, String name) {
    return '“$keyword” zaten “$name” kalıbının anahtar kelimesi.';
  }

  @override
  String snipHotkeyTaken(String key, String name) {
    return 'Alt+F$key zaten “$name” kalıbında.';
  }

  @override
  String get snipUntitled => 'Adsız kalıp';

  @override
  String get snipName => 'Ad';

  @override
  String get snipKeyword => 'Anahtar kelime';

  @override
  String get snipKeywordHint => 'örn. dil1';

  @override
  String get snipKeywordHelper => 'Belgede yazıp Tab’a basınca kalıp gelir';

  @override
  String get snipHotkey => 'Kısayol';

  @override
  String get snipHotkeyHelper => 'Alt+F4 pencereyi kapatır';

  @override
  String get snipNoHotkey => 'Yok';

  @override
  String get snipText => 'Metin';

  @override
  String get snipBodyPlaceholder =>
      'Kalıbın metni. Doldurulacak yerleri [MÜVEKKİL] gibi köşeli parantez ve büyük harfle yazın.';

  @override
  String snipBlanksList(String blanks) {
    return 'Doldurulacak yerler: $blanks';
  }

  @override
  String get snipSave => 'Kaydet';

  @override
  String get snipTableLeftOut => '〔Tablo — kalıpla eklenmez〕';

  @override
  String get snipPaletteHint => 'Kalıp ya da profil bilgisi ara';

  @override
  String get snipFromProfile => 'Profilden';

  @override
  String snipProfileInsertTooltip(String label) {
    return '$label · belgeye ekle';
  }

  @override
  String get snipFillProfile => 'Avukat profilini doldurun';

  @override
  String get snipFillProfileDetail =>
      'Adınız, baronuz, adresiniz buradan tek tıkla eklensin';

  @override
  String get snipKeepSelection => 'Seçimi kalıba al';

  @override
  String get snipHarvestOpen => 'Arşivden kalıp bul';

  @override
  String get snipHarvestOpenDetail => 'Belgelerinizde tekrar eden paragraflar';

  @override
  String get snipManage => 'Kalıplarımı yönet';

  @override
  String get snipManageDetail => 'Ad, anahtar kelime, Alt+F kısayolu, silme';

  @override
  String get snipPaletteNoMatch =>
      'Bu aramaya uyan kalıp ya da profil bilgisi yok.';

  @override
  String get snipPaletteEmptyHarvest =>
      'Henüz kalıp yok.\n\nYukarıdan arşivinizde tekrar eden paragraflara bakabilir, ya da bir paragrafı belgede seçip yeniden Ctrl+Space’e basabilirsiniz.';

  @override
  String get snipPaletteEmptySelect =>
      'Henüz kalıp yok.\n\nSık yazdığınız bir paragrafı belgede seçin, sonra Ctrl+Space’e basın — burada “Seçimi kalıba al” çıkacak.';

  @override
  String get snipPaletteEmptyKeep =>
      'Henüz kalıp yok. Yukarıdan seçiminizi kalıba alabilirsiniz.';

  @override
  String snipFromProfileLabel(String label) {
    return 'Profilden · $label';
  }

  @override
  String get snipPaletteKeys =>
      '↑ ↓ ile seçin · Enter ile yerleştirin · Esc ile kapatın';

  @override
  String get snipNameIt => 'Kalıba ad verin';

  @override
  String get snipNameItDetail =>
      'Sonra bu adın ilk harflerini yazarak bulacaksınız.';

  @override
  String get snipBack => 'Geri';

  @override
  String get snipKeep => 'Kalıba al';

  @override
  String snipFillCount(int count) {
    return 'Bu kalıpta doldurulacak $count yer var.';
  }

  @override
  String get snipFromLawyerProfile => 'Avukat profilinden';

  @override
  String get snipLeaveBlank => 'Boş bırak';

  @override
  String get snipInsert => 'Yerleştir';

  @override
  String get snipHarvestTitle => 'Arşivinizde tekrar eden paragraflar';

  @override
  String get snipHarvestNone =>
      'Beş ya da daha fazla belgede aynen geçen bir paragraf bulunamadı. Arşiv henüz taranıyor olabilir.';

  @override
  String snipHarvestFound(int count) {
    return '$count paragraf bulundu. Kalıba almak istediklerinizi işaretleyin.';
  }

  @override
  String get snipHarvestBlank =>
      'Tarih, esas numarası, kimlik ve tutarları boş bırak';

  @override
  String get snipHarvestBlankDetail =>
      'Bir dosyaya ait olan kısımlar [TARİH] gibi doldurulacak yerlere çevrilir.';

  @override
  String snipHarvestInDocuments(int count) {
    return '$count belgede';
  }

  @override
  String snipHarvestTake(int count) {
    return '$count kalıbı al';
  }

  @override
  String noteDraftTooltip(String date) {
    return 'Kaydedilmemiş taslak · $date';
  }

  @override
  String get noteDraftTitle => 'Kaydedilmemiş taslak';

  @override
  String noteDraftBody(String name, String date) {
    return '“$name” için $date tarihli, kaydedilmemiş bir taslak var. Uygulama beklenmedik biçimde kapandığında kalmış olabilir.\n\nAçarsanız editöre kaydedilmemiş değişiklik olarak gelir; siz kaydedene kadar dosya değişmez.';
  }

  @override
  String noteDraftMore(int count) {
    return '\n\nBu belgenin $count taslağı daha var; hepsi ana sayfadaki «Kurtarılabilir taslaklar»da.';
  }

  @override
  String get noteDraftDelete => 'Taslağı sil';

  @override
  String get noteCancel => 'Vazgeç';

  @override
  String get noteDraftOpen => 'Taslağı aç';

  @override
  String get noteDraftDeleteTitle => 'Taslak silinsin mi?';

  @override
  String noteDraftDeleteBody(String name, String date) {
    return '“$name” için $date tarihli kaydedilmemiş taslak kalıcı olarak silinecek. Belgenin kendisi değişmez.';
  }

  @override
  String get noteUnsavedTitle => 'Kaydedilmemiş değişiklikler var';

  @override
  String noteUnsavedBody(String what) {
    return '$what editöre alınınca şu anki kaydedilmemiş değişiklikler onun yerine geçer. Önce kaydederseniz bugünkü hali de belge geçmişinde kalır.';
  }

  @override
  String get noteOpenWithoutSaving => 'Kaydetmeden aç';

  @override
  String get noteSaveFirst => 'Önce kaydet';

  @override
  String get speechPreparingVoice => 'Ses hazırlanıyor…';

  @override
  String get speechPaused => 'Duraklatıldı';

  @override
  String get speechReading => 'Okunuyor';

  @override
  String get speechSpeed => 'Okuma hızı';

  @override
  String get speechResume => 'Sürdür';

  @override
  String get speechPause => 'Duraklat';

  @override
  String get speechStopReading => 'Okumayı durdur';

  @override
  String get speechPreparing => 'Hazırlanıyor…';

  @override
  String get speechTranscribing => 'Yazıya dökülüyor…';

  @override
  String get speechListening => 'Dinleniyor, konuşabilirsiniz';

  @override
  String get speechFinish => 'Bitir';

  @override
  String get speechTextUnreadable => 'Metin okunamadı';

  @override
  String get speechNothingToRead => 'Okunacak metin yok';

  @override
  String get speechReadingStopped => 'Sesli okuma durdu';

  @override
  String speechDownloadIntro(String need, String size, String offline) {
    return '$need ($size). Model yalnızca bir kez indirilir ve bilgisayarınızda saklanır. $offline';
  }

  @override
  String speechModelLicense(String license) {
    return 'Model lisansı: $license';
  }

  @override
  String speechDownloadFailed(String error) {
    return 'İndirme tamamlanamadı. İndirilen kısım saklandı; yeniden denediğinizde kaldığı yerden devam eder.\n$error';
  }

  @override
  String get speechCancelDownload => 'İptal';

  @override
  String get speechCancel => 'Vazgeç';

  @override
  String speechDownload(String size) {
    return 'İndir ($size)';
  }

  @override
  String get speechTryAgain => 'Yeniden dene';

  @override
  String get noteSecretSwitch => 'Gizli not · büroyla paylaşılmaz';

  @override
  String get noteSecretSwitchDetail =>
      'Yalnız sizin cihazlarınıza gider. Görevlere, paylaşılan dosyaya ve üretilen belgelere girmez.';

  @override
  String get noteSecretMark => 'Gizli';

  @override
  String get noteSecretRecalled => 'Büro kopyalarından silindi.';

  @override
  String get noteSecretRecalling =>
      'Büro kopyalarından siliniyor; alanların cihazı açılınca tamamlanır.';

  @override
  String get noteSecretSharedTitle => 'Not büroyla paylaşılmıştı';

  @override
  String noteSecretSharedBody(int count, String names) {
    return 'Bu not büroda $count kişide var ($names). Gizli yaparsanız onlardan da silinir.';
  }

  @override
  String get noteSecretNoRecall =>
      'Dışarı aktarılmış belge ve ekran görüntüsü geri alınamaz.';

  @override
  String get noteSecretConfirm => 'Gizli yap';

  @override
  String get liveChat => 'Yazışma';

  @override
  String get liveClosePanel => 'Paneli kapat';

  @override
  String get liveChatEmpty =>
      'Belge üzerinde birbirinize buradan yazın. Yazışma paylaşım bitince silinir.';

  @override
  String get liveRemoveQuote => 'Alıntıyı kaldır';

  @override
  String get liveQuoteSelection => 'Belgede seçili olanı alıntıla';

  @override
  String get liveMessageHint => 'Mesaj yazın…';

  @override
  String get liveSend => 'Gönder';

  @override
  String get liveVerification => 'DOĞRULAMA';

  @override
  String get liveGuest => 'Misafir';

  @override
  String get liveVisitorLeft => 'Gelen kişi ayrıldı.';

  @override
  String get liveInviteCopied => 'Davet kopyalandı';

  @override
  String get liveInviteMailSubject => 'Canlı belge daveti';

  @override
  String get liveInviteAnother => 'Bir kişi daha davet et';

  @override
  String get liveNewCode => 'Yeni kod oluştur';

  @override
  String get livePreparingCode => 'Davet kodu hazırlanıyor…';

  @override
  String get liveSendCode =>
      'Kodu karşı tarafa gönderin. Katılmak isteyen olunca size sorulur.';

  @override
  String get liveSendWhatsApp => 'WhatsApp ile gönder';

  @override
  String get liveCopy => 'Kopyala';

  @override
  String get liveEmail => 'E-posta';

  @override
  String get liveCopyInvite => 'Daveti kopyala';

  @override
  String liveCodeValidUntil(String time) {
    return '$time’e kadar geçerli, bir kişi içindir. Belge şifreli gider; aradaki sunucu içeriği göremez.';
  }

  @override
  String get liveWantsToJoin => 'davet koduyla katılmak istiyor';

  @override
  String get liveDigitsMatchHost =>
      'Aynı sayı onun ekranında da görünüyorsa doğru kişidir.';

  @override
  String get liveDecline => 'Reddet';

  @override
  String get liveLetView => 'Yalnız görsün';

  @override
  String get liveLetEdit => 'Sırayla düzenlesin';

  @override
  String liveJoinedName(String name) {
    return '$name katıldı.';
  }

  @override
  String get liveInviteWithdrawn => 'Davet geri alındı.';

  @override
  String get liveCodeExpired => 'Davet kodunun süresi doldu.';

  @override
  String get liveInviteFailed => 'Davet kurulamadı.';

  @override
  String get liveCancel => 'Vazgeç';

  @override
  String get liveClose => 'Kapat';

  @override
  String get liveJoinPrompt =>
      'Size gönderilen kodu yazın ya da davet bağlantısını yapıştırın.';

  @override
  String get liveJoinName => 'Adınız (paylaşana böyle görünür)';

  @override
  String get liveJoin => 'Katıl';

  @override
  String get liveConnecting => 'Bağlanılıyor…';

  @override
  String get liveAwaitingApproval => 'Onay bekleniyor';

  @override
  String get liveOpensOnApproval => 'Paylaşan onaylayınca belge açılır.';

  @override
  String get liveDigitsMatchGuest => 'Paylaşanın ekranında da bu sayı görünür.';

  @override
  String get liveJoinRefused => 'Paylaşan katılmanızı kabul etmedi.';

  @override
  String get liveJoinFailed => 'Katılınamadı.';

  @override
  String get liveTryAgain => 'Yeniden dene';

  @override
  String get liveJoinTitle => 'Canlı belgeye katıl';

  @override
  String get liveShareTitle => 'Canlı paylaş';

  @override
  String get liveOnThisNetwork => 'Bu ağda';

  @override
  String get liveRemote => 'Uzaktan';

  @override
  String get liveRemoteJoined => 'UZAKTAN KATILANLAR';

  @override
  String liveTakeBackPen(String name) {
    return 'Kalemi geri al · $name';
  }

  @override
  String get liveRemoteHint =>
      'Kodu alan kişi bağlantıya dokunur ya da LifeOS Folio’da veya LifeOS Ofis’te Canlı belge’ye basıp kodu yazar; siz onaylayınca belge onda açılır. Belge sizde kalır, paylaşım bitince onda kalmaz.';

  @override
  String get liveNearbyHint =>
      'Davet ettiğiniz kişinin ekranında bir pencere açılır; Katıl’a basınca belge onda açılır. Belge sizde kalır, paylaşım bitince onlarda kalmaz. \"Sırayla düzenleyebilir\" olanlara kalemi verince yazdıkları belgenize işlenir.';

  @override
  String get liveStopSharing => 'Paylaşımı bitir';

  @override
  String get liveOk => 'Tamam';

  @override
  String get liveNoDevices =>
      'Aynı ağda davet edilebilecek bir cihaz görünmüyor. Karşı tarafta LifeOS Folio ya da LifeOS Ofis açık ve aynı Wi-Fi’ye bağlı olmalı.';

  @override
  String get liveSearching => 'Aynı ağdaki cihazlar aranıyor…';

  @override
  String liveNetworkError(String error) {
    return 'Ağa bağlanılamadı: $error';
  }

  @override
  String get liveInvited => 'DAVET EDİLENLER';

  @override
  String get liveMyDevices => 'CİHAZLARIM';

  @override
  String get liveOffice => 'BÜRO';

  @override
  String get liveNearby => 'YAKINDAKİ FOLIO’LAR';

  @override
  String get livePeerJoining => 'yanıt bekleniyor';

  @override
  String get livePeerWatching => 'izliyor';

  @override
  String get livePeerGone => 'ayrıldı';

  @override
  String get livePeerUnreachable => 'ulaşılamadı';

  @override
  String get livePeerDeclined => 'reddetti';

  @override
  String get livePeerUnanswered => 'yanıt vermedi';

  @override
  String get liveWithdraw => 'Geri al';

  @override
  String get liveRemovePeer => 'Çıkar';

  @override
  String get liveInvite => 'Davet et';

  @override
  String get liveInviteAgain => 'Yeniden davet et';

  @override
  String get liveGivePen => 'Kalemi ver';

  @override
  String get liveCanView => 'Yalnız görebilir';

  @override
  String get liveCanEdit => 'Sırayla düzenleyebilir';

  @override
  String liveCodeChip(String code) {
    return 'kod $code';
  }

  @override
  String get livePenHere => 'kalem onda';

  @override
  String get liveDevice => 'Cihaz';

  @override
  String get liveEnded => 'Paylaşım bitti; belge bu cihazda kalmadı.';

  @override
  String get livePenSyncing =>
      'Kalem sizde · belge paylaşanla eşitleniyor, bir an bekleyin';

  @override
  String get livePenYours =>
      'Kalem sizde · yazdıklarınız paylaşanın belgesine işlenir';

  @override
  String liveSharing(String name) {
    return '$name paylaşıyor';
  }

  @override
  String liveWriting(String name) {
    return '$name yazıyor';
  }

  @override
  String get liveEditRefused => 'düzenleme isteğiniz geri çevrildi';

  @override
  String get liveYouCanEdit => 'sırayla düzenleyebilirsiniz';

  @override
  String get liveYouCanView => 'yalnız görebilirsiniz';

  @override
  String get liveReleasePen => 'Kalemi bırak';

  @override
  String get livePenAsked => 'İstendi';

  @override
  String get liveAskPen => 'Düzenlemek iste';

  @override
  String get liveStopWatching => 'İzlemeyi bırak';

  @override
  String get liveDocument => 'Canlı belge';

  @override
  String get liveHubCodePrompt => 'Size gönderilen kodu yazın:';

  @override
  String get liveHubOrShare => 'YA DA BİR BELGEYİ PAYLAŞIN';

  @override
  String get liveHubPickPrompt =>
      'Paylaşacağınız belgeyi seçin. Belge açılır ve karşı tarafa göndereceğiniz kod hemen çıkar.';

  @override
  String get liveHubPickOther => 'Başka belge seç…';

  @override
  String get liveSharesADocument => ' bir belgeyi sizinle canlı paylaşıyor.';

  @override
  String liveSharesDocument(String title) {
    return ' “$title” belgesini sizinle canlı paylaşıyor.';
  }

  @override
  String get liveInviteTitle => 'Canlı paylaşım daveti';

  @override
  String get liveInviteCanEdit =>
      'Belgeyi görürsünüz; paylaşan kalemi verince siz de yazabilirsiniz. Paylaşım bitince belge bu cihazda kalmaz.';

  @override
  String get liveInviteViewOnly =>
      'Belgeyi yalnız görürsünüz. Paylaşım bitince belge bu cihazda kalmaz.';

  @override
  String get liveBusyConnecting => 'Şu an başka bir bağlantı kuruluyor.';

  @override
  String get liveHostUnverified => 'Davet eden cihaz doğrulanamadı.';

  @override
  String get liveDocumentDidNotCome => 'Paylaşan kabul etti ama belge gelmedi.';

  @override
  String get liveSomeUser => 'Bir Folio kullanıcısı';

  @override
  String get liveHostWithdrew => 'Paylaşan daveti geri aldı.';

  @override
  String get liveConnectFailed => 'Bağlantı kurulamadı.';

  @override
  String get liveOpeningDocument => 'Belge açılıyor…';

  @override
  String get liveConnectingHost => 'Paylaşanın cihazına bağlanılıyor…';

  @override
  String get liveGuestCodeNote =>
      'Paylaşanın ekranında da bu kod görünür. Belge yalnız bu paylaşım sürerken görünür; paylaşım bitince bu cihazda kalmaz.';

  @override
  String get tbAddColumn => 'Sütun ekle';

  @override
  String get tbAddRow => 'Satır ekle';

  @override
  String get tbAlignCenter => 'Ortala · Ctrl+E';

  @override
  String get tbAlignLeft => 'Sola hizala · Ctrl+L';

  @override
  String get tbAlignRight => 'Sağa hizala · Ctrl+R';

  @override
  String get tbAllFormatting => 'Tüm biçimlendirme araçları…';

  @override
  String tbAllPages(int count) {
    return 'Tüm sayfalar ($count)';
  }

  @override
  String get tbApply => 'Uygula';

  @override
  String get tbAttachToEmail => 'E-postaya ekle';

  @override
  String get tbAttachToEmailHelp => 'Ekli yeni ileti açılır';

  @override
  String get tbBlue => 'Mavi';

  @override
  String get tbBold => 'Kalın · Ctrl+B';

  @override
  String get tbBoldLabel => 'Kalın';

  @override
  String get tbBullets => 'Madde işaretleri · Ctrl+Shift+L';

  @override
  String get tbCancel => 'Vazgeç';

  @override
  String get tbChooseFolder => 'Klasör seç';

  @override
  String get tbChoosePageToPrint => 'Yazdırılacak sayfayı seçin.';

  @override
  String get tbChooseTargetFolder => 'Gönderilecek klasörü seçin';

  @override
  String get tbClearFormatting => 'Karakter biçimini temizle';

  @override
  String get tbClose => 'Kapat';

  @override
  String get tbCollate => 'Harmanla';

  @override
  String get tbConvertToPdf => 'PDF’e dönüştür';

  @override
  String tbCopiedTo(String target) {
    return 'Kopyalandı: $target';
  }

  @override
  String get tbCopiesLabel => 'kopya';

  @override
  String get tbCopyFile => 'Dosyayı kopyala';

  @override
  String get tbCopyFileHelp => 'E-postaya, sohbete veya klasöre yapıştırın';

  @override
  String get tbCopyToFolder => 'Klasöre kopyala';

  @override
  String get tbCopyToFolderHelp => 'USB bellek veya başka bir klasör seçin';

  @override
  String tbCurrentPage(int page) {
    return 'Geçerli sayfa ($page)';
  }

  @override
  String get tbCustomSize => 'Özel punto…';

  @override
  String get tbDefaultLetterheadName => 'Antetim';

  @override
  String get tbDelete => 'Sil';

  @override
  String get tbDeleteColumn => 'Sütunu sil';

  @override
  String get tbDeleteRow => 'Satırı sil';

  @override
  String get tbDeleteTable => 'Tabloyu sil';

  @override
  String get tbDictate => 'Sesli yaz';

  @override
  String get tbDictateShortTip =>
      'Sesli yaz · söylediğiniz imlecin yerine yazılır';

  @override
  String get tbDictateTip => 'Söylediğinizi imlecin yerine yazar';

  @override
  String get tbDocumentHistory => 'Belge geçmişi';

  @override
  String get tbDrawBorders => 'Çerçeve çiz';

  @override
  String get tbEvenPagesOnly => 'Yalnız çift sayfalar';

  @override
  String get tbFile => 'Dosya';

  @override
  String get tbFileCopied =>
      'Dosya kopyalandı. Hedef uygulamaya yapıştırabilirsiniz.';

  @override
  String get tbFileMenu => 'Dosya menüsü';

  @override
  String get tbFind => 'Bul';

  @override
  String get tbFindInDocument => 'Belgede bul · Ctrl+F';

  @override
  String get tbFindReplace => 'Bul ve değiştir · Ctrl+H';

  @override
  String get tbFirstPageOnly => 'Yalnız ilk sayfada';

  @override
  String get tbFirstPageOnlyHelp =>
      'Kapalıyken antet her sayfanın başında basılır.';

  @override
  String get tbFont => 'Yazı tipi';

  @override
  String tbFontCount(int count) {
    return '$count yazı tipi · Sistem ve belge yazı tipleri';
  }

  @override
  String get tbFontSizePoints => 'Yazı boyutu (punto)';

  @override
  String get tbFontSizeTitle => 'Yazı boyutu';

  @override
  String get tbFooter => 'Alt bilgi';

  @override
  String get tbGreen => 'Yeşil';

  @override
  String get tbGrey => 'Gri';

  @override
  String get tbGridlinesNotPrinted => 'kılavuz çizgiler yazdırılmaz';

  @override
  String get tbGroupEditing => 'Düzenleme';

  @override
  String get tbGroupHistory => 'Geçmiş';

  @override
  String get tbGroupInsert => 'Ekle';

  @override
  String get tbGroupParagraph => 'Paragraf';

  @override
  String get tbGroupStyle => 'Stil';

  @override
  String get tbGroupView => 'Görünüm';

  @override
  String get tbGroupVoice => 'Ses';

  @override
  String get tbGrowFont => 'Yazıyı büyüt';

  @override
  String get tbHeader => 'Üst bilgi';

  @override
  String get tbHeaderFooter => 'Üst bilgi ve alt bilgi';

  @override
  String get tbHeaderFooterShort => 'Üst/alt bilgi';

  @override
  String get tbHorizontalRuler => 'Yatay cetvel';

  @override
  String get tbHowToUsePage => 'Bu sayfa nasıl kullanılır?';

  @override
  String get tbImageColumn25 => 'Sütunun %25\'i';

  @override
  String get tbImageColumn33 => 'Sütunun %33\'ü';

  @override
  String get tbImageColumn75 => 'Sütunun %75\'i';

  @override
  String get tbImageColumnWidth => 'Sütun genişliği';

  @override
  String get tbImageHalfColumn => 'Yarım sütun';

  @override
  String get tbImageOriginalSize => 'Özgün boyut';

  @override
  String get tbImageUndrawable => '〔Görsel çizilemedi — kaydetmede korunur〕';

  @override
  String get tbImageUnreadable => '〔Görsel okunamadı — kaydetmede korunur〕';

  @override
  String get tbImageWidth => 'Görsel genişliği';

  @override
  String get tbInNewDocuments => 'Yeni belgelerde';

  @override
  String get tbIndentDecrease => 'Girintiyi azalt · Ctrl+Shift+M';

  @override
  String get tbIndentIncrease => 'Girintiyi artır · Ctrl+M';

  @override
  String get tbInsertTable => 'Tablo ekle';

  @override
  String get tbItalic => 'İtalik · Ctrl+I';

  @override
  String get tbJustify => 'İki yana yasla · Ctrl+J';

  @override
  String get tbKeyboardShortcuts => 'Klavye kısayolları';

  @override
  String get tbLetterheadMenu => 'Antet…';

  @override
  String get tbLetterheads => 'Antetler';

  @override
  String get tbLightGrey => 'Açık gri';

  @override
  String get tbLineSpacing => 'Satır aralığı';

  @override
  String tbLineSpacingValue(String value) {
    return '$value satır';
  }

  @override
  String get tbLiveShare => 'Canlı paylaş…';

  @override
  String get tbMixed => 'Karışık';

  @override
  String get tbMore => 'Diğer';

  @override
  String get tbMoreTools => 'Diğer düzenleme araçları';

  @override
  String get tbName => 'Adı';

  @override
  String get tbNewDocument => 'Yeni belge';

  @override
  String get tbNewWindow => 'Yeni pencere';

  @override
  String get tbNextPage => 'Sonraki sayfa';

  @override
  String get tbNoFill => 'Dolgu yok';

  @override
  String get tbNoFontFound => 'Yazı tipi bulunamadı';

  @override
  String get tbNoLetterheads =>
      'Henüz antet yok. Anteti belgenin üst bilgisinde tasarlayın: yazı, hizalama ve Ekle › Görsel ile logo. Sonra aşağıdan antet olarak kaydedin; her belgeye tek tıkla eklenir.';

  @override
  String get tbNoRecentDocuments => 'Henüz açılmış belge yok';

  @override
  String get tbNormalText => 'Normal metin';

  @override
  String get tbNotPrinted => 'Yazdırılmayacak';

  @override
  String get tbNumbering => 'Numaralı liste · Ctrl+Shift+7';

  @override
  String get tbOddAndEvenPages => 'Tek ve çift sayfalar';

  @override
  String get tbOddPagesOnly => 'Yalnız tek sayfalar';

  @override
  String get tbOk => 'Tamam';

  @override
  String get tbOneCopyFewer => 'Bir kopya az';

  @override
  String get tbOneCopyMore => 'Bir kopya fazla';

  @override
  String get tbOpen => 'Aç…';

  @override
  String get tbPageNumber => 'Sayfa numarası';

  @override
  String get tbPageNumberBottom => 'Altta';

  @override
  String get tbPageNumberCenter => 'Orta';

  @override
  String get tbPageNumberFont => 'Yazı';

  @override
  String get tbPageNumberFormat => 'Biçimi';

  @override
  String get tbPageNumberInFooter => 'Alt bilgide';

  @override
  String get tbPageNumberInHeader => 'Üst bilgide';

  @override
  String get tbPageNumberLeft => 'Sol';

  @override
  String get tbPageNumberMenu => 'Sayfa numarası…';

  @override
  String get tbPageNumberNone => 'Yok';

  @override
  String get tbPageNumberPosition => 'Yeri';

  @override
  String get tbPageNumberPrefix => 'Ön metin';

  @override
  String get tbPageNumberPrefixHint => 'Sayfa ';

  @override
  String get tbPageNumberRight => 'Sağ';

  @override
  String get tbPageNumberSkipFirst => 'İlk sayfada gösterme';

  @override
  String get tbPageNumberSkipSingle => 'Tek sayfaysa gösterme';

  @override
  String get tbPageNumberStart => 'İlk numara';

  @override
  String get tbPageNumberTop => 'Üstte';

  @override
  String get tbPageNumberWithTotal => 'Toplam sayfayla';

  @override
  String get tbPageRange => 'Sayfa aralığı';

  @override
  String get tbPageRangeHint => 'ör. 1-3, 5, 8-';

  @override
  String tbPageRangeInvalid(int count) {
    return 'Belgede $count sayfa var; aralığı kontrol edin.';
  }

  @override
  String get tbPages => 'Sayfalar';

  @override
  String get tbParagraphStyle => 'Paragraf stili';

  @override
  String tbPdfPrepareFailed(String error) {
    return 'PDF hazırlanamadı: $error';
  }

  @override
  String get tbPdfSaveFailed => 'PDF kaydedilemedi';

  @override
  String get tbPdfSaved => 'PDF kaydedildi';

  @override
  String get tbPickSize => 'Boyut seçin';

  @override
  String get tbPicture => 'Görsel';

  @override
  String get tbPageBreakMenu => 'Sayfa sonu (Ctrl+Enter)';

  @override
  String get tbPointSize => 'Punto';

  @override
  String get tbPointSizeHelp => '1–200 arasında, örneğin 10,5';

  @override
  String tbPreviewFailed(String error) {
    return 'Önizleme açılamadı: $error';
  }

  @override
  String get tbPreviousPage => 'Önceki sayfa';

  @override
  String get tbPrint => 'Yazdır';

  @override
  String get tbPrintFailed => 'Yazdırılamadı';

  @override
  String get tbPrintShortcut => 'Yazdır · Ctrl+P';

  @override
  String tbPrintSummary(int pages, int sheets) {
    return '$pages sayfa · $sheets yaprak A4';
  }

  @override
  String tbPrintSummaryCopies(int pages, int copies, int sheets) {
    return '$pages sayfa × $copies kopya · $sheets yaprak A4';
  }

  @override
  String get tbPrinter => 'Yazıcı';

  @override
  String tbPrinterDefault(String name) {
    return '$name  (varsayılan)';
  }

  @override
  String get tbPrinterInSystemDialog =>
      'Yazıcıyı sistemin yazdırma penceresinde seçeceksiniz.';

  @override
  String get tbProtectedContent => '〔Korunan içerik — kaydetmede korunur〕';

  @override
  String get tbReadAloud => 'Sesli oku';

  @override
  String get tbReadAloudShortTip =>
      'Sesli oku · seçimi ya da imleçten sonrasını';

  @override
  String get tbReadAloudTip => 'Seçimi ya da imleçten sonrasını okur';

  @override
  String get tbRecent => 'Son açılanlar';

  @override
  String get tbRecoverableDrafts => 'Kurtarılabilir taslaklar';

  @override
  String get tbRed => 'Kırmızı';

  @override
  String get tbRedo => 'Yinele · Ctrl+Y';

  @override
  String get tbRemoveBorders => 'Çerçeveyi kaldır';

  @override
  String get tbRename => 'Yeniden adlandır';

  @override
  String get tbRenameLetterhead => 'Anteti yeniden adlandır';

  @override
  String get tbReplace => 'Değiştir';

  @override
  String get tbReplaceLetterheadBody =>
      'Bu adla kayıtlı antet, belgenin üst bilgisiyle değiştirilecek.';

  @override
  String tbReplaceLetterheadTitle(String name) {
    return '\"$name\" değiştirilsin mi?';
  }

  @override
  String tbRibbonTip(String tab) {
    return 'Şerit: $tab';
  }

  @override
  String tbSample(String sample) {
    return 'Örnek: $sample';
  }

  @override
  String get tbSave => 'Kaydet';

  @override
  String get tbSaveAs => 'Farklı kaydet…';

  @override
  String get tbSaveAsDocx => 'Word (DOCX) Olarak Kaydet';

  @override
  String get tbSaveAsPdf => 'PDF olarak kaydet';

  @override
  String get tbSaveAsRtf => 'Zengin Metin (RTF) Olarak Kaydet';

  @override
  String get tbSaveAsUdf => 'UYAP UDF Olarak Kaydet';

  @override
  String get tbSaveFolderBody =>
      'Bir kez seçersiniz; sonra Kaydet doğrudan oraya yazar. İmzaladığınız belgeler de oraya kaydedilir.';

  @override
  String get tbSaveFolderTitle => 'Belgeler nereye kaydedilsin?';

  @override
  String get tbSaveHeaderAsLetterhead => 'Üst bilgiyi antet olarak kaydet';

  @override
  String get tbSaveHeaderAsLetterheadEllipsis =>
      'Üst bilgiyi antet olarak kaydet…';

  @override
  String get tbSaveSelectedPagesPdf => 'Seçili sayfaları PDF olarak kaydet';

  @override
  String get tbSavedCopyUsed => 'Diskte kayıtlı belge kullanılır.';

  @override
  String get tbSearchFonts => 'Yazı tipi ara…';

  @override
  String get tbSelectWholeTable => 'Tüm tabloyu seç';

  @override
  String get tbShadeCell => 'Hücreyi boya';

  @override
  String get tbShadeTable => 'Tabloyu boya';

  @override
  String get tbShare => 'Paylaş';

  @override
  String tbShareAsKind(String kind) {
    return '$kind olarak paylaş';
  }

  @override
  String get tbShareAsPdf => 'PDF olarak paylaş';

  @override
  String get tbShareAsPdfHelp => 'Her telefonda ve bilgisayarda açılır';

  @override
  String get tbShareEllipsis => 'Paylaş…';

  @override
  String tbShareFailed(String error) {
    return 'Paylaşılamadı: $error';
  }

  @override
  String get tbShareMacHelp => 'AirDrop, Mesajlar ve yüklü uygulamalar';

  @override
  String get tbShareOriginalHelp => 'Dosyanın kendisi, olduğu gibi';

  @override
  String get tbShareSend => 'Paylaş / Gönder';

  @override
  String get tbShareWindowsHelp => 'Yüklü paylaşım uygulamalarından seçin';

  @override
  String get tbShareWithWindows => 'Windows ile paylaş';

  @override
  String get tbShortcuts => 'Kısayollar';

  @override
  String get tbShrinkFont => 'Yazıyı küçült';

  @override
  String get tbSignUdf => 'UDF e-imzala';

  @override
  String get tbSnippets => 'Kalıp metin';

  @override
  String get tbSnippetsShortcut => 'Kalıp metin · Ctrl+Boşluk';

  @override
  String get tbStrikethrough => 'Üstü çizili';

  @override
  String get tbSubscript => 'Alt simge';

  @override
  String get tbSuperscript => 'Üst simge';

  @override
  String get tbSystemPrintDialog => 'Sistemin yazdırma penceresi…';

  @override
  String get tbTabHome => 'Giriş';

  @override
  String get tbTabInsert => 'Ekle';

  @override
  String get tbTabResearch => 'Araştırma';

  @override
  String get tbTabView => 'Görünüm';

  @override
  String get tbTable => 'Tablo';

  @override
  String get tbTableSelectedRelease => 'Tablo seçili — bırak';

  @override
  String tbTableSize(int rows, int columns) {
    return '$rows × $columns tablo';
  }

  @override
  String get tbTextAndParagraph => 'Yazı ve paragraf';

  @override
  String get tbUnderline => 'Altı çizili · Ctrl+U';

  @override
  String get tbUndo => 'Geri al · Ctrl+Z';

  @override
  String get tbUseInNewDocuments => 'Yeni belgelerde kullan';

  @override
  String get tbVerticalRuler => 'Dikey cetvel';

  @override
  String get tbViewRulers => 'Görünüm ve cetveller';

  @override
  String get tbYellow => 'Sarı';

  @override
  String get viewClose => 'Kapat';

  @override
  String get viewCloseEsc => 'Kapat · Esc';

  @override
  String get viewCloseEscParen => 'Kapat (Esc)';

  @override
  String get viewCancel => 'Vazgeç';

  @override
  String get viewFirstPage => 'İlk Sayfa';

  @override
  String get viewPreviousPage => 'Önceki Sayfa';

  @override
  String get viewNextPage => 'Sonraki Sayfa';

  @override
  String get viewLastPage => 'Son Sayfa';

  @override
  String get viewZoomIn => 'Yakınlaştır';

  @override
  String get viewZoomOut => 'Uzaklaştır';

  @override
  String get viewZoomInKey => 'Yakınlaştır (+)';

  @override
  String get viewZoomOutKey => 'Uzaklaştır (−)';

  @override
  String get viewRotateLeft => 'Sola 90° döndür';

  @override
  String get viewRotateRight => 'Sağa 90° döndür';

  @override
  String get viewRotateRightKey => 'Sağa 90° döndür (R)';

  @override
  String get viewFit => 'Sığdır';

  @override
  String get viewFitKey => 'Sığdır (0)';

  @override
  String viewPreviewFailed(String error) {
    return 'Önizleme açılamadı: $error';
  }

  @override
  String get viewHighlightSaveFailed => 'Vurgu kaydedilemedi';

  @override
  String get viewThisColor => 'Bu renk';

  @override
  String get viewChangeColor => 'Rengi değiştir';

  @override
  String get viewDeleteHighlight => 'Vurguyu sil';

  @override
  String get viewFindInDocument => 'Belgede bul';

  @override
  String get viewFindKey => 'Belgede bul (Ctrl+F)';

  @override
  String viewPixels(int width, int height) {
    return '$width × $height piksel';
  }

  @override
  String get viewSearching => 'aranıyor…';

  @override
  String get viewNotFound => 'bulunamadı';

  @override
  String get viewPreviousMatch => 'Önceki · Shift+Enter';

  @override
  String get viewNextMatch => 'Sonraki · Enter';

  @override
  String get viewFitPage => 'Sayfaya sığdır';

  @override
  String get viewFitWidth => 'Genişliğe sığdır';

  @override
  String get viewFreeZoom => 'Serbest yakınlaştırma';

  @override
  String get viewCitations => 'Dayanaklar · madde ve kararlar';

  @override
  String get viewHighlightSelection => 'Seçimi vurgula';

  @override
  String get viewSelectToHighlight => 'Vurgulamak için metin seçin';

  @override
  String get viewHighlightColor => 'Vurgu rengi';

  @override
  String get viewPageOpenFailed => 'Bu sayfa açılamadı.';

  @override
  String viewPageOf(int page, int count) {
    return 'Sayfa $page / $count';
  }

  @override
  String get viewTifToPdf => 'TIF → PDF Dönüştür';

  @override
  String get viewHeicAndroidOnly =>
      'iPhone fotoğrafları (HEIC) şimdilik yalnız Android’de açılıyor.';

  @override
  String get viewPhotoDecodeFailed => 'Fotoğraf çözülemedi.';

  @override
  String get viewCropFailed => 'Kırpılamadı';

  @override
  String get viewCropUnmeasured => 'Bu görsel ölçülemedi, kırpılamıyor';

  @override
  String get viewCrop => 'Kırp';

  @override
  String get viewFullScreenKey => 'Tam ekran (F, ya da çift tık)';

  @override
  String get viewNextPhoto => 'Sonraki fotoğraf (→)';

  @override
  String get viewPreviousPhoto => 'Önceki fotoğraf (←)';

  @override
  String get viewCropDrag => 'Saklamak istediğiniz yeri sürükleyin';

  @override
  String get viewCropKeepsOriginal =>
      'Aslı olduğu gibi kalır, kırpılan yanına kaydedilir';

  @override
  String viewSvgOpenFailed(String error) {
    return 'SVG açılamadı: $error';
  }

  @override
  String get viewImageOpenFailed => 'Görsel açılamadı.';

  @override
  String get viewCopy => 'Kopyala';

  @override
  String get viewReadAloud => 'Sesli oku';

  @override
  String get viewSelectAll => 'Tümünü seç';

  @override
  String get viewFormatNotPreviewable => 'Bu biçim önizlenemiyor.';

  @override
  String get viewImzSaveDialog => 'İmzalı belgenin içeriğini kaydet';

  @override
  String get viewDocumentSaved => 'Belge kaydedildi';

  @override
  String viewImzIdNumber(String id) {
    return 'T.C. kimlik no: $id';
  }

  @override
  String viewImzSignedAt(String date) {
    return 'İmza tarihi: $date';
  }

  @override
  String viewImzIssuer(String issuer) {
    return 'Sertifikayı veren: $issuer';
  }

  @override
  String get viewImzUnnamedSigner => 'Adı okunamayan imzacı';

  @override
  String get viewImzValid => 'E-imza geçerli';

  @override
  String get viewImzInvalid =>
      'E-imza doğrulanamadı: belge imzadan sonra değişmiş olabilir';

  @override
  String get viewImzCheckedNote =>
      'İmza, içindeki belgeyle ve imzacının kendi sertifikasıyla denetlendi. Sertifikanın yetkili bir kuruluşça verildiği ve iptal edilmediği ayrıca denetlenmedi.';

  @override
  String get viewImzSaveDocument => 'Belgeyi kaydet…';

  @override
  String get viewImzUnreadable =>
      'Bu dosya okunamadı: içinde belge olan bir e-imza dosyası değil ya da bozuk.';

  @override
  String viewImzInsideNotShown(String name) {
    return 'İçindeki belge ($name) burada gösterilemiyor; kaydedip açabilirsiniz.';
  }

  @override
  String get viewOcrTitle => 'Arama için çıkarılan metin';

  @override
  String get viewOcrNote =>
      'Birebir çeviriyazı değildir: tanıma hataları olabilir ve kutulu bölümler ana metnin arasına karışabilir. Kaynak belge değişmedi.';

  @override
  String get viewOcrCopy => 'Metni kopyala';

  @override
  String get viewOcrCopied => 'Metin panoya kopyalandı.';

  @override
  String get viewOcrReading => 'Okunuyor…';

  @override
  String get viewOcrShowDocument => 'Belgeyi göster';

  @override
  String get viewOcrShowText => 'Okunan metin';

  @override
  String get viewOcrNothingFound => 'Okunabilir yazı bulunamadı';

  @override
  String get viewOcrRun => 'Metne dönüştür';

  @override
  String get viewDraftDeleteFailed => 'Taslak silinemedi';

  @override
  String get viewDeleteAllDraftsTitle => 'Bütün taslaklar silinsin mi?';

  @override
  String viewDeleteAllDraftsBody(int count) {
    return '$count kaydedilmemiş taslak kalıcı olarak silinecek. Belgelerin kendileri değişmez.';
  }

  @override
  String get viewDeleteAll => 'Hepsini sil';

  @override
  String get viewDraftsDeleteFailed => 'Taslaklar silinemedi';

  @override
  String get viewDraftNeverSaved => 'Hiç kaydedilmemiş yeni belge';

  @override
  String viewDraftSourceGone(String source) {
    return 'Kaynak dosya artık yok, yeni belge olarak açılır\n$source';
  }

  @override
  String get viewDraftsTitle => 'Kurtarılabilir taslaklar';

  @override
  String get viewDraftsNote =>
      'Kaydedilmeden kapanan belgelerin son hali bu cihazda saklanır. Bir taslağı açtığınızda editöre kaydedilmemiş değişiklik olarak gelir; siz kaydedene kadar dosyaya yazılmaz.';

  @override
  String get viewDraftsUnreachable => 'Yerel taslaklara ulaşılamadı.';

  @override
  String get viewDraftsEmpty => 'Kurtarılmayı bekleyen taslak yok.';

  @override
  String get viewDeleteDraft => 'Taslağı sil';

  @override
  String get viewVersionUnreadable => 'Bu sürüm okunamadı.';

  @override
  String get viewToday => 'Bugün';

  @override
  String get viewYesterday => 'Dün';

  @override
  String get viewSaveVersionCopyDialog => 'Sürümü kopya olarak kaydet';

  @override
  String get viewCopyOverOriginal =>
      'Kopya belgenin kendisinin üzerine yazılmaz';

  @override
  String viewCopyOverOriginalHint(String label) {
    return 'Belgeyi bu sürüme döndürmek için «$label» düğmesini kullanın.';
  }

  @override
  String get viewCopySaved => 'Kopya kaydedildi.';

  @override
  String get viewCopySaveFailed => 'Kopya kaydedilemedi';

  @override
  String get viewVersionList => 'Sürüm listesi';

  @override
  String get viewHistoryTitle => 'Belge geçmişi';

  @override
  String get viewHistoryNote =>
      'Folio’da her kaydettiğinizde dosyanın önceki ve yeni hali bu cihazda saklanır: belge başına son 20 sürüm, en fazla 100 MB.';

  @override
  String get viewHistoryUnreachable => 'Yerel geçmişe ulaşılamadı.';

  @override
  String get viewHistoryEmpty => 'Bu belgenin henüz saklanmış bir sürümü yok.';

  @override
  String get viewHistoryEmptyHint =>
      'Belgeyi Folio’da ilk kaydettiğinizde, dosyanın o ana kadarki hali ve kaydettiğiniz yeni hali burada listelenir.';

  @override
  String get viewSigned => 'E-imzalı';

  @override
  String get viewSaveCopy => 'Farklı kaydet';

  @override
  String get viewOtherFormatHint =>
      'Bu sürüm başka bir biçimde saklanmış; kopya olarak kaydedebilirsiniz.';

  @override
  String get viewCompareCurrent => 'Şimdikiyle karşılaştır';

  @override
  String get viewPageView => 'Sayfa görünümü';

  @override
  String viewPageViewFailed(String error) {
    return 'Sayfa görünümü hazırlanamadı: $error';
  }

  @override
  String get viewTypeNotShown =>
      'Bu tür bir belge burada gösterilemiyor. «Kopya olarak kaydet» ile ayrı bir dosya olarak açabilirsiniz.';

  @override
  String viewCompareFailed(String error) {
    return 'Karşılaştırılamadı: $error';
  }

  @override
  String get viewCompareUnsupported =>
      'Bu tür bir belgede metin karşılaştırılamıyor; sürümü «Sayfa görünümü»nden inceleyebilirsiniz.';

  @override
  String get viewCompareIdentical =>
      'Bu sürümün metni şu anki haliyle aynı. Yazı tipi, boşluk gibi biçim farkları burada gösterilmez; «Sayfa görünümü»ne bakın.';

  @override
  String viewDiffSummary(int added, int removed) {
    return 'Bu sürümden bu yana $added kelime eklenmiş, $removed kelime silinmiş.';
  }

  @override
  String get viewAddedLater => 'Sonradan eklenen';

  @override
  String get viewRemovedLater => 'Sonradan silinen';

  @override
  String viewUnchangedLines(int count) {
    return '⋯ değişmeyen $count satır ⋯';
  }

  @override
  String get viewRestoreVersion => 'Bu sürümü geri yükle';

  @override
  String viewAboutProduct(String name) {
    return '$name hakkında';
  }

  @override
  String get viewWindowActionFailed => 'Pencere işlemi tamamlanamadı';

  @override
  String get viewAbout => 'Hakkında';

  @override
  String get viewFullScreen => 'Tam ekran';

  @override
  String get viewExitFullScreen => 'Tam ekrandan çık';

  @override
  String get viewMinimize => 'Simge durumuna küçült';

  @override
  String get viewRestoreSize => 'Önceki boyut';

  @override
  String get viewMaximize => 'Ekranı kapla';

  @override
  String get viewHideToTray => 'Tepsiye gizle';

  @override
  String get viewCloseApp => 'Uygulamayı kapat';

  @override
  String get viewAddressOpenFailed => 'Adres açılamadı';

  @override
  String viewVersion(String version, String build) {
    return 'Sürüm $version ($build)';
  }

  @override
  String get viewAboutTaglineOfis =>
      'Belgeleri açan, düzenleyen ve imzalayan uygulama';

  @override
  String get viewAboutTaglineFolio =>
      'Avukatlar için dilekçe, dava ve büro uygulaması';

  @override
  String get viewAboutDescOfis =>
      'Ofis ile UDF, Word, ODT, RTF ve PDF belgelerinizi açar, düzenler, yazdırır ve e-imza kartınızla imzalarsınız. Kanun maddesi ve karar atıflarını denetler, yazım hatalarını bulur, metni sesli okur ve söylediklerinizi yazarsınız.';

  @override
  String get viewAboutDescFolio =>
      'Folio ile UDF dilekçenizi yazar, e-imza ya da mobil imzayla imzalar ve dava dosyanıza gönderirsiniz. Dava dosyalarınızı, e-Tebligat ile gelen tebligatlarınızı ve kanuna göre hesaplanan sürelerinizi izlersiniz. Müvekkillerinizi, duruşma ve süre takviminizi, büronuzun kasasını ve ekibinizi aynı uygulamadan yönetirsiniz.';

  @override
  String get viewAboutDataOfis =>
      'Verileriniz yalnız sizin cihazlarınızda tutulur. Ofis’in verilerinizi tutan bir sunucusu yoktur ve yapay zekâ hizmeti kullanmaz. Başka bir büroyla uzaktan canlı paylaşımda belge ve yazışma şifreli olarak aktarma sunucumuzdan geçer; sunucu içeriği göremez ve hiçbir şey saklamaz.';

  @override
  String get viewAboutDataFolio =>
      'Verileriniz yalnız sizin cihazlarınızda tutulur. Folio’nun verilerinizi tutan bir sunucusu yoktur. Yapay zekâ özellikleri isteğe bağlıdır ve siz açmadıkça kapalıdır; açarsanız seçtiğiniz belge yalnız sizin seçtiğiniz sağlayıcıya, sizin hesabınız ya da API anahtarınızla gider. Başka bir büroyla uzaktan canlı paylaşımda belge ve yazışma şifreli olarak aktarma sunucumuzdan geçer; sunucu içeriği göremez ve hiçbir şey saklamaz.';

  @override
  String get viewAgreements => 'SÖZLEŞMELER';

  @override
  String get viewTermsTitle => 'Kullanım Koşulları';

  @override
  String get viewTermsSubtitle => 'Kullanım izni ve sorumluluklar';

  @override
  String get viewPrivacyTitle => 'Gizlilik ve KVKK Aydınlatma Metni';

  @override
  String get viewPrivacySubtitle => 'Kişisel verileriniz nasıl korunur';

  @override
  String get viewLicenseTitle => 'Lisans';

  @override
  String get viewLicenseSubtitle => 'Tescilli yazılım';

  @override
  String get viewOpenSourceLicenses => 'Açık kaynak lisansları';

  @override
  String get viewComponentsSubtitle => 'Folio’da kullanılan bileşenler';

  @override
  String get viewSupport => 'DESTEK';

  @override
  String get viewDownloadOther => 'Diğer cihazlarınıza indirin';

  @override
  String get viewContact => 'Destek ve iletişim';

  @override
  String get viewContactSubtitle => 'İletişim formuyla bize yazın';

  @override
  String get viewWebsite => 'Folio’nun web sitesi';

  @override
  String viewCopyright(String product) {
    return '© 2026 LifeOS. Tüm hakları saklıdır. $product tescilli bir yazılımdır, açık kaynak değildir.';
  }

  @override
  String get pdfPagesTitle => 'Sayfaları ayır';

  @override
  String get pdfPagesHint =>
      'Ayrı bir PDF\'e alınacak sayfaları seçin; sırasını alttaki kutuya yazarak da verebilirsiniz.';

  @override
  String get pdfPagesRange => 'Sayfalar (örnek: 1-3, 5)';

  @override
  String get pdfPagesAll => 'Tümünü seç';

  @override
  String get pdfPagesNone => 'Seçimi kaldır';

  @override
  String pdfPagesCount(int count) {
    return '$count sayfa seçildi';
  }

  @override
  String get pdfPagesBad => 'Sayfa numaraları anlaşılamadı.';

  @override
  String get pdfSave => 'PDF olarak kaydet';

  @override
  String pdfSaved(String name) {
    return '$name kaydedildi.';
  }

  @override
  String get pdfOpen => 'Aç';

  @override
  String get pdfFailed => 'PDF oluşturulamadı';

  @override
  String get pdfBuildTitle => 'PDF oluştur';

  @override
  String get pdfBuildHint =>
      'Resimleri, taramaları (TIFF) ve PDF\'leri ekleyip sıralayın. Her resim bir sayfa olur; bir PDF\'in ya da taramanın yalnız bazı sayfalarını almak için numaralarını yazın.';

  @override
  String get pdfBuildAdd => 'Dosya ekle';

  @override
  String get pdfBuildAllPages => 'Tümü';

  @override
  String get pdfBuildPagesLabel => 'Sayfalar';

  @override
  String pdfBuildPagesOf(int count) {
    return '$count sayfa';
  }

  @override
  String get pdfBuildPicture => 'Resim · 1 sayfa';

  @override
  String get pdfBuildRemove => 'Çıkar';

  @override
  String pdfBuildTotal(int count) {
    return '$count sayfalık PDF';
  }

  @override
  String get pdfBuildEmpty => 'Henüz dosya eklenmedi.';

  @override
  String get pdfSplitTool =>
      'Sayfaları ayır: seçtiğiniz sayfalardan ayrı bir PDF';

  @override
  String get pdfBuildTool => 'PDF oluştur: resim ve PDF ekleyip birleştirin';

  @override
  String get viewPrintKey => 'Yazdır (Ctrl+P)';

  @override
  String get viewSaveAsPdf => 'PDF olarak kaydet';

  @override
  String get viewOpenInFolio => 'Folio\'da aç';

  @override
  String get viewShowInFolder => 'Klasörde göster';

  @override
  String get viewMore => 'Dosya işlemleri';

  @override
  String get viewThumbnails => 'Sayfa küçük resimleri';

  @override
  String get ofisMakePdf => 'PDF oluştur';

  @override
  String get ofisMakePdfDetail =>
      'Resimleri ve PDF\'leri tek bir PDF\'te birleştirin.';

  @override
  String get ofisLive => 'Canlı belge';

  @override
  String get ofisLiveDetail =>
      'Bir belgeyi canlı paylaşın ya da size gönderilen kodla katılın.';

  @override
  String photoOpenFailed(String error) {
    return 'Resim açılamadı: $error';
  }

  @override
  String photoSaveFailed(String error) {
    return 'Kaydedilemedi: $error';
  }

  @override
  String get photoTitle => 'Resmi düzenle';

  @override
  String get photoUndo => 'Geri al';

  @override
  String get photoSaveCopy => 'Kopya kaydet';

  @override
  String get photoNote => 'Not';

  @override
  String get photoNoteHint => 'Yazın';

  @override
  String get photoAdd => 'Ekle';

  @override
  String get photoBrightness => 'Parlaklık';

  @override
  String get photoContrast => 'Kontrast';

  @override
  String get photoSharpness => 'Netlik';

  @override
  String get photoPen => 'Kalem';

  @override
  String get photoText => 'Metin';

  @override
  String get photoRedactHint =>
      'Kapatmak istediğiniz yerin üzerine sürükleyin. Kayıtta resmin içine işlenir, kaldırılamaz.';

  @override
  String get photoTextHint => 'Notun yerine tıklayın.';

  @override
  String get photoDrawHint => 'Sürükleyerek çizin.';

  @override
  String get photoLookOriginal => 'Orijinal';

  @override
  String get photoLookDocument => 'Belge';

  @override
  String get photoLookGray => 'Gri';

  @override
  String get photoLookColorDocument => 'Renkli belge';

  @override
  String get photoToolCorners => 'Belge düzelt';

  @override
  String get photoToolCrop => 'Kırp';

  @override
  String get photoToolRotate => 'Döndür';

  @override
  String get photoToolAdjust => 'Ayarla';

  @override
  String get photoToolRedact => 'Karart';

  @override
  String get photoToolDraw => 'İşaretle';

  @override
  String get viewEditPicture =>
      'Resmi düzenle: köşelerinden düzelt, kırp, ayarla, karart, işaretle';

  @override
  String get photoTilt => 'Eğim';

  @override
  String get photoTurn => '90° döndür';

  @override
  String get photoFlipH => 'Yatay çevir';

  @override
  String get photoFlipV => 'Dikey çevir';

  @override
  String get photoTiltReset => 'Eğimi sıfırla';
}
