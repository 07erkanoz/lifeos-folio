import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('tr'),
  ];

  /// This language's own name, in the language menu.
  ///
  /// In tr, this message translates to:
  /// **'Türkçe'**
  String get languageName;

  /// Language menu: follow the computer's or phone's language.
  ///
  /// In tr, this message translates to:
  /// **'Sistemin dili'**
  String get languageSystem;

  /// Tooltip of the language button.
  ///
  /// In tr, this message translates to:
  /// **'Dil'**
  String get languageMenu;

  /// No description provided for @ofisNewDocumentTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yeni belge.{extension}'**
  String ofisNewDocumentTitle(String extension);

  /// No description provided for @ofisAbout.
  ///
  /// In tr, this message translates to:
  /// **'LifeOS Ofis hakkında'**
  String get ofisAbout;

  /// No description provided for @ofisDocuments.
  ///
  /// In tr, this message translates to:
  /// **'Belgeler'**
  String get ofisDocuments;

  /// No description provided for @ofisNew.
  ///
  /// In tr, this message translates to:
  /// **'Yeni'**
  String get ofisNew;

  /// No description provided for @ofisNewTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Word belgesi · Ctrl+N'**
  String get ofisNewTooltip;

  /// No description provided for @ofisOpen.
  ///
  /// In tr, this message translates to:
  /// **'Aç'**
  String get ofisOpen;

  /// No description provided for @ofisOpenTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Belge aç · Ctrl+O'**
  String get ofisOpenTooltip;

  /// No description provided for @ofisOpenDialog.
  ///
  /// In tr, this message translates to:
  /// **'Belge aç'**
  String get ofisOpenDialog;

  /// No description provided for @ofisFileMoved.
  ///
  /// In tr, this message translates to:
  /// **'Belge taşınmış veya kaldırılmış'**
  String get ofisFileMoved;

  /// No description provided for @ofisCannotOpenType.
  ///
  /// In tr, this message translates to:
  /// **'Bu belge türü açılamıyor'**
  String get ofisCannotOpenType;

  /// No description provided for @ofisDraftCannotOpen.
  ///
  /// In tr, this message translates to:
  /// **'Bu taslak burada açılamıyor'**
  String get ofisDraftCannotOpen;

  /// No description provided for @ofisEdit.
  ///
  /// In tr, this message translates to:
  /// **'Düzenle'**
  String get ofisEdit;

  /// No description provided for @ofisHomeTitle.
  ///
  /// In tr, this message translates to:
  /// **'Belgeleriniz'**
  String get ofisHomeTitle;

  /// No description provided for @ofisOpenAction.
  ///
  /// In tr, this message translates to:
  /// **'Belge aç'**
  String get ofisOpenAction;

  /// No description provided for @ofisOpenActionDetail.
  ///
  /// In tr, this message translates to:
  /// **'Word, PDF, RTF, ODT, Markdown, Excel, UDF, .imz'**
  String get ofisOpenActionDetail;

  /// No description provided for @ofisNewDocx.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Word belgesi'**
  String get ofisNewDocx;

  /// No description provided for @ofisNewDocxDetail.
  ///
  /// In tr, this message translates to:
  /// **'DOCX olarak'**
  String get ofisNewDocxDetail;

  /// No description provided for @ofisDropHere.
  ///
  /// In tr, this message translates to:
  /// **'Belgeyi buraya sürükleyin'**
  String get ofisDropHere;

  /// No description provided for @ofisRecent.
  ///
  /// In tr, this message translates to:
  /// **'SON BELGELER'**
  String get ofisRecent;

  /// No description provided for @ofisRecentEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Açtığınız belgeler burada görünür.'**
  String get ofisRecentEmpty;

  /// No description provided for @ofisImzBadge.
  ///
  /// In tr, this message translates to:
  /// **'İMZ'**
  String get ofisImzBadge;

  /// No description provided for @ofisSignedDocument.
  ///
  /// In tr, this message translates to:
  /// **'E-imzalı belge'**
  String get ofisSignedDocument;

  /// No description provided for @whenToday.
  ///
  /// In tr, this message translates to:
  /// **'Bugün {clock}'**
  String whenToday(String clock);

  /// No description provided for @whenYesterday.
  ///
  /// In tr, this message translates to:
  /// **'Dün {clock}'**
  String whenYesterday(String clock);

  /// No description provided for @whenDaysAgo.
  ///
  /// In tr, this message translates to:
  /// **'{days} gün önce'**
  String whenDaysAgo(int days);

  /// No description provided for @formatTiff.
  ///
  /// In tr, this message translates to:
  /// **'TIFF Evrak'**
  String get formatTiff;

  /// No description provided for @formatImage.
  ///
  /// In tr, this message translates to:
  /// **'Görsel'**
  String get formatImage;

  /// No description provided for @formatText.
  ///
  /// In tr, this message translates to:
  /// **'Metin'**
  String get formatText;

  /// No description provided for @formatRtf.
  ///
  /// In tr, this message translates to:
  /// **'Zengin Metin RTF'**
  String get formatRtf;

  /// No description provided for @formatData.
  ///
  /// In tr, this message translates to:
  /// **'Veri / Metin'**
  String get formatData;

  /// No description provided for @formatUnknown.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen'**
  String get formatUnknown;

  /// No description provided for @editorFindReplacedCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} eşleşme değiştirildi.'**
  String editorFindReplacedCount(int count);

  /// No description provided for @editorFindTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bul ve değiştir'**
  String get editorFindTitle;

  /// No description provided for @editorFindQuery.
  ///
  /// In tr, this message translates to:
  /// **'Aranan metin'**
  String get editorFindQuery;

  /// No description provided for @editorFindMatchCase.
  ///
  /// In tr, this message translates to:
  /// **'Büyük/küçük harf'**
  String get editorFindMatchCase;

  /// No description provided for @editorFindWholeWord.
  ///
  /// In tr, this message translates to:
  /// **'Tam sözcük'**
  String get editorFindWholeWord;

  /// No description provided for @editorFindPrompt.
  ///
  /// In tr, this message translates to:
  /// **'Belge içinde arayın'**
  String get editorFindPrompt;

  /// No description provided for @editorFindNoMatch.
  ///
  /// In tr, this message translates to:
  /// **'Eşleşme bulunamadı'**
  String get editorFindNoMatch;

  /// No description provided for @editorFindPosition.
  ///
  /// In tr, this message translates to:
  /// **'{current} / {total} eşleşme'**
  String editorFindPosition(int current, int total);

  /// No description provided for @editorFindPrevious.
  ///
  /// In tr, this message translates to:
  /// **'Önceki eşleşme'**
  String get editorFindPrevious;

  /// No description provided for @editorFindNext.
  ///
  /// In tr, this message translates to:
  /// **'Sonraki eşleşme'**
  String get editorFindNext;

  /// No description provided for @editorFindReplace.
  ///
  /// In tr, this message translates to:
  /// **'Değiştir'**
  String get editorFindReplace;

  /// No description provided for @editorFindReplacement.
  ///
  /// In tr, this message translates to:
  /// **'Yeni metin'**
  String get editorFindReplacement;

  /// No description provided for @editorFindReplaceAll.
  ///
  /// In tr, this message translates to:
  /// **'Tümünü değiştir'**
  String get editorFindReplaceAll;

  /// No description provided for @editorClose.
  ///
  /// In tr, this message translates to:
  /// **'Kapat'**
  String get editorClose;

  /// No description provided for @editorPageJump.
  ///
  /// In tr, this message translates to:
  /// **'Sayfaya git'**
  String get editorPageJump;

  /// No description provided for @editorPageSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Sayfa {current} / {count}'**
  String editorPageSemantics(int current, int count);

  /// No description provided for @editorPageNumberField.
  ///
  /// In tr, this message translates to:
  /// **'Sayfa numarası'**
  String get editorPageNumberField;

  /// No description provided for @editorCancel.
  ///
  /// In tr, this message translates to:
  /// **'Vazgeç'**
  String get editorCancel;

  /// No description provided for @editorPageJumpGo.
  ///
  /// In tr, this message translates to:
  /// **'Git'**
  String get editorPageJumpGo;

  /// No description provided for @editorZoomOut.
  ///
  /// In tr, this message translates to:
  /// **'Uzaklaştır'**
  String get editorZoomOut;

  /// No description provided for @editorZoomTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Yakınlaştırma · Ctrl + fare tekerleği'**
  String get editorZoomTooltip;

  /// No description provided for @editorZoomPercent.
  ///
  /// In tr, this message translates to:
  /// **'%{percent}'**
  String editorZoomPercent(int percent);

  /// No description provided for @editorZoomIn.
  ///
  /// In tr, this message translates to:
  /// **'Yakınlaştır'**
  String get editorZoomIn;

  /// No description provided for @editorZoomReset.
  ///
  /// In tr, this message translates to:
  /// **'Sıfırla'**
  String get editorZoomReset;

  /// No description provided for @editorRulerMarginLeft.
  ///
  /// In tr, this message translates to:
  /// **'Sol kenar boşluğu'**
  String get editorRulerMarginLeft;

  /// No description provided for @editorRulerMarginRight.
  ///
  /// In tr, this message translates to:
  /// **'Sağ kenar boşluğu'**
  String get editorRulerMarginRight;

  /// No description provided for @editorRulerMarginTop.
  ///
  /// In tr, this message translates to:
  /// **'Üst kenar boşluğu'**
  String get editorRulerMarginTop;

  /// No description provided for @editorRulerMarginBottom.
  ///
  /// In tr, this message translates to:
  /// **'Alt kenar boşluğu'**
  String get editorRulerMarginBottom;

  /// No description provided for @editorRulerMarginTip.
  ///
  /// In tr, this message translates to:
  /// **'{label}: {cm} cm · Sürükleyin'**
  String editorRulerMarginTip(String label, String cm);

  /// No description provided for @editorRulerTabKindTip.
  ///
  /// In tr, this message translates to:
  /// **'Sekme türü: {kind} · Değiştirmek için tıklayın'**
  String editorRulerTabKindTip(String kind);

  /// No description provided for @editorRulerTabStopTip.
  ///
  /// In tr, this message translates to:
  /// **'{kind} sekme · {cm} cm · Silmek için aşağı sürükleyin ya da çift tıklayın'**
  String editorRulerTabStopTip(String kind, String cm);

  /// No description provided for @editorRulerFirstLineIndent.
  ///
  /// In tr, this message translates to:
  /// **'İlk satır girintisi'**
  String get editorRulerFirstLineIndent;

  /// No description provided for @editorRulerLeftIndent.
  ///
  /// In tr, this message translates to:
  /// **'Sol ve asılı girinti'**
  String get editorRulerLeftIndent;

  /// No description provided for @editorRulerRightIndent.
  ///
  /// In tr, this message translates to:
  /// **'Sağ girinti'**
  String get editorRulerRightIndent;

  /// No description provided for @editorTabLeft.
  ///
  /// In tr, this message translates to:
  /// **'Sol'**
  String get editorTabLeft;

  /// No description provided for @editorTabCentre.
  ///
  /// In tr, this message translates to:
  /// **'Orta'**
  String get editorTabCentre;

  /// No description provided for @editorTabRight.
  ///
  /// In tr, this message translates to:
  /// **'Sağ'**
  String get editorTabRight;

  /// No description provided for @editorTabDecimal.
  ///
  /// In tr, this message translates to:
  /// **'Ondalık'**
  String get editorTabDecimal;

  /// No description provided for @editorTabBar.
  ///
  /// In tr, this message translates to:
  /// **'Çubuk'**
  String get editorTabBar;

  /// No description provided for @editorHeaderPlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'Üst bilgi — her sayfanın başında yazılır'**
  String get editorHeaderPlaceholder;

  /// No description provided for @editorFooterPlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'Alt bilgi — her sayfanın sonunda yazılır'**
  String get editorFooterPlaceholder;

  /// No description provided for @editorRegionRemove.
  ///
  /// In tr, this message translates to:
  /// **'KALDIR'**
  String get editorRegionRemove;

  /// No description provided for @editorHeaderLabel.
  ///
  /// In tr, this message translates to:
  /// **'ÜST BİLGİ'**
  String get editorHeaderLabel;

  /// No description provided for @editorFooterLabel.
  ///
  /// In tr, this message translates to:
  /// **'ALT BİLGİ'**
  String get editorFooterLabel;

  /// No description provided for @editorRegionPrintsFromPage.
  ///
  /// In tr, this message translates to:
  /// **'{page}. sayfadan itibaren basılır'**
  String editorRegionPrintsFromPage(String page);

  /// No description provided for @editorHistoryWriteFailed.
  ///
  /// In tr, this message translates to:
  /// **'Belge geçmişine yazılamadı'**
  String get editorHistoryWriteFailed;

  /// No description provided for @editorHistoryWriteFailedDetail.
  ///
  /// In tr, this message translates to:
  /// **'Belgeniz yine de kaydedilebilir; yalnız bu sürüm saklanmadı.'**
  String get editorHistoryWriteFailedDetail;

  /// No description provided for @editorUnsavedChangesTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kaydedilmemiş değişiklikler var'**
  String get editorUnsavedChangesTitle;

  /// No description provided for @editorShareSavedOnly.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşılan, belgenin kaydedilmiş hâlidir.'**
  String get editorShareSavedOnly;

  /// No description provided for @editorShareSavedVersion.
  ///
  /// In tr, this message translates to:
  /// **'Kaydedilmiş hâlini paylaş'**
  String get editorShareSavedVersion;

  /// No description provided for @editorSaveAndShare.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet ve paylaş'**
  String get editorSaveAndShare;

  /// No description provided for @editorReplaceWhatDraft.
  ///
  /// In tr, this message translates to:
  /// **'Taslak'**
  String get editorReplaceWhatDraft;

  /// No description provided for @editorReplaceWhatVersion.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen sürüm'**
  String get editorReplaceWhatVersion;

  /// No description provided for @editorVersionUnreadable.
  ///
  /// In tr, this message translates to:
  /// **'Sürüm okunamadı.'**
  String get editorVersionUnreadable;

  /// No description provided for @editorVersionOpenFailed.
  ///
  /// In tr, this message translates to:
  /// **'Sürüm açılamadı'**
  String get editorVersionOpenFailed;

  /// No description provided for @editorNotSavedYet.
  ///
  /// In tr, this message translates to:
  /// **'Bu belge henüz kaydedilmedi'**
  String get editorNotSavedYet;

  /// No description provided for @editorHistoryFromFirstSave.
  ///
  /// In tr, this message translates to:
  /// **'Geçmiş, ilk kayıttan itibaren tutulur.'**
  String get editorHistoryFromFirstSave;

  /// No description provided for @editorRestoreLabel.
  ///
  /// In tr, this message translates to:
  /// **'Editöre yükle'**
  String get editorRestoreLabel;

  /// No description provided for @editorRestoreHint.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen sürüm editöre kaydedilmemiş değişiklik olarak gelir; siz kaydedene kadar dosya değişmez.'**
  String get editorRestoreHint;

  /// No description provided for @editorVersionLoaded.
  ///
  /// In tr, this message translates to:
  /// **'{date} sürümü editöre yüklendi'**
  String editorVersionLoaded(String date);

  /// No description provided for @editorSaveToKeep.
  ///
  /// In tr, this message translates to:
  /// **'Dosyada kalıcı olması için kaydedin.'**
  String get editorSaveToKeep;

  /// No description provided for @editorCitationLaws.
  ///
  /// In tr, this message translates to:
  /// **'{count} kanun maddesi'**
  String editorCitationLaws(int count);

  /// No description provided for @editorCitationDecisions.
  ///
  /// In tr, this message translates to:
  /// **'{count} karar'**
  String editorCitationDecisions(int count);

  /// No description provided for @editorCitationShowTip.
  ///
  /// In tr, this message translates to:
  /// **'{detail} · dayanakları göster'**
  String editorCitationShowTip(String detail);

  /// No description provided for @editorCitationTotal.
  ///
  /// In tr, this message translates to:
  /// **'{count} dayanak'**
  String editorCitationTotal(int count);

  /// No description provided for @editorCitationTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bu belgenin dayanakları'**
  String get editorCitationTitle;

  /// No description provided for @editorCaseLawPanelTitle.
  ///
  /// In tr, this message translates to:
  /// **'Emsal karar ara'**
  String get editorCaseLawPanelTitle;

  /// No description provided for @editorClosePanel.
  ///
  /// In tr, this message translates to:
  /// **'Paneli kapat'**
  String get editorClosePanel;

  /// No description provided for @editorOpenInWindow.
  ///
  /// In tr, this message translates to:
  /// **'Ayrı pencerede aç'**
  String get editorOpenInWindow;

  /// No description provided for @editorReadAloud.
  ///
  /// In tr, this message translates to:
  /// **'Sesli oku'**
  String get editorReadAloud;

  /// No description provided for @editorTermMeaning.
  ///
  /// In tr, this message translates to:
  /// **'“{term}” ne demek?'**
  String editorTermMeaning(String term);

  /// No description provided for @editorAddToDictionary.
  ///
  /// In tr, this message translates to:
  /// **'Sözlüğe ekle'**
  String get editorAddToDictionary;

  /// No description provided for @editorSnippetHotkeyUnassigned.
  ///
  /// In tr, this message translates to:
  /// **'Alt+F{key} bir kalıba atanmamış.'**
  String editorSnippetHotkeyUnassigned(int key);

  /// No description provided for @editorSnippetHotkeyHint.
  ///
  /// In tr, this message translates to:
  /// **'Ctrl+Space → Kalıplarımı yönet ile atayabilirsiniz.'**
  String get editorSnippetHotkeyHint;

  /// No description provided for @editorSnippetEmbedsSkipped.
  ///
  /// In tr, this message translates to:
  /// **'Seçimdeki tablo ve görseller kalıba alınmadı.'**
  String get editorSnippetEmbedsSkipped;

  /// No description provided for @editorSnippetTextOnly.
  ///
  /// In tr, this message translates to:
  /// **'Kalıp yalnız metni ve biçimini tutar.'**
  String get editorSnippetTextOnly;

  /// No description provided for @editorSnippetsAdded.
  ///
  /// In tr, this message translates to:
  /// **'{count} kalıp eklendi.'**
  String editorSnippetsAdded(int count);

  /// No description provided for @editorOpenElsewhere.
  ///
  /// In tr, this message translates to:
  /// **'Bu belge başka bir pencerede açık'**
  String get editorOpenElsewhere;

  /// No description provided for @editorOpenElsewhereDetail.
  ///
  /// In tr, this message translates to:
  /// **'Aynı belge iki pencerede düzenlenirse biri ötekinin kaydını ezer. Belgeyi açık olduğu pencerede düzenleyin.'**
  String get editorOpenElsewhereDetail;

  /// No description provided for @editorHeldElsewhereBanner.
  ///
  /// In tr, this message translates to:
  /// **'Bu belge başka bir Folio penceresinde düzenleniyor. Burada yalnız okunabilir; değişiklikleri o pencerede yapın.'**
  String get editorHeldElsewhereBanner;

  /// No description provided for @editorRetry.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden dene'**
  String get editorRetry;

  /// No description provided for @editorDictationFailed.
  ///
  /// In tr, this message translates to:
  /// **'Sesli yazma başlamadı'**
  String get editorDictationFailed;

  /// No description provided for @editorFormatNothing.
  ///
  /// In tr, this message translates to:
  /// **'Biçimlendirilecek bir şey bulunamadı'**
  String get editorFormatNothing;

  /// No description provided for @editorFormatted.
  ///
  /// In tr, this message translates to:
  /// **'Biçimlendirildi'**
  String get editorFormatted;

  /// No description provided for @editorUndoHint.
  ///
  /// In tr, this message translates to:
  /// **'Ctrl+Z ile geri alabilirsiniz.'**
  String get editorUndoHint;

  /// No description provided for @editorPrintName.
  ///
  /// In tr, this message translates to:
  /// **'Belge'**
  String get editorPrintName;

  /// No description provided for @editorPrintFailed.
  ///
  /// In tr, this message translates to:
  /// **'Yazdırılamadı'**
  String get editorPrintFailed;

  /// No description provided for @editorInsertImageTitle.
  ///
  /// In tr, this message translates to:
  /// **'Görsel ekle'**
  String get editorInsertImageTitle;

  /// No description provided for @editorImageTooLarge.
  ///
  /// In tr, this message translates to:
  /// **'Görsel çok büyük — en çok 12 MB eklenebilir.'**
  String get editorImageTooLarge;

  /// No description provided for @editorImageUnreadable.
  ///
  /// In tr, this message translates to:
  /// **'Görsel okunamadı: {name}'**
  String editorImageUnreadable(String name);

  /// No description provided for @editorImageInsertFailed.
  ///
  /// In tr, this message translates to:
  /// **'Görsel eklenemedi: {error}'**
  String editorImageInsertFailed(String error);

  /// No description provided for @editorDeleteHeaderTitle.
  ///
  /// In tr, this message translates to:
  /// **'Üst bilgi silinsin mi?'**
  String get editorDeleteHeaderTitle;

  /// No description provided for @editorDeleteFooterTitle.
  ///
  /// In tr, this message translates to:
  /// **'Alt bilgi silinsin mi?'**
  String get editorDeleteFooterTitle;

  /// No description provided for @editorDeleteRegionBody.
  ///
  /// In tr, this message translates to:
  /// **'Yazdıklarınız belgeden kaldırılacak. Kaydetmeden çıkarsanız değişiklik uygulanmaz.'**
  String get editorDeleteRegionBody;

  /// No description provided for @editorDelete.
  ///
  /// In tr, this message translates to:
  /// **'Sil'**
  String get editorDelete;

  /// No description provided for @editorPageView.
  ///
  /// In tr, this message translates to:
  /// **'Sayfa görünümü'**
  String get editorPageView;

  /// No description provided for @editorMobileView.
  ///
  /// In tr, this message translates to:
  /// **'Mobil görünüm'**
  String get editorMobileView;

  /// No description provided for @editorSign.
  ///
  /// In tr, this message translates to:
  /// **'İmzala'**
  String get editorSign;

  /// No description provided for @editorSignWithCard.
  ///
  /// In tr, this message translates to:
  /// **'E-imza kartıyla'**
  String get editorSignWithCard;

  /// No description provided for @editorCaseLaw.
  ///
  /// In tr, this message translates to:
  /// **'İçtihat'**
  String get editorCaseLaw;

  /// No description provided for @editorMoreTools.
  ///
  /// In tr, this message translates to:
  /// **'Diğer araçlar'**
  String get editorMoreTools;

  /// No description provided for @editorTodaysDate.
  ///
  /// In tr, this message translates to:
  /// **'Bugünün tarihi'**
  String get editorTodaysDate;

  /// No description provided for @editorSnippets.
  ///
  /// In tr, this message translates to:
  /// **'Kalıp metin'**
  String get editorSnippets;

  /// No description provided for @editorDocumentHistory.
  ///
  /// In tr, this message translates to:
  /// **'Belge geçmişi'**
  String get editorDocumentHistory;

  /// No description provided for @editorResearch.
  ///
  /// In tr, this message translates to:
  /// **'Araştırma'**
  String get editorResearch;

  /// No description provided for @editorSearchCaseLaw.
  ///
  /// In tr, this message translates to:
  /// **'İçtihat ara'**
  String get editorSearchCaseLaw;

  /// No description provided for @editorCompare.
  ///
  /// In tr, this message translates to:
  /// **'Karşılaştır'**
  String get editorCompare;

  /// No description provided for @editorCompareTip.
  ///
  /// In tr, this message translates to:
  /// **'Kaydedilmiş sürümlerle karşılaştır'**
  String get editorCompareTip;

  /// No description provided for @editorSignCardButton.
  ///
  /// In tr, this message translates to:
  /// **'E-imza\nkartı'**
  String get editorSignCardButton;

  /// No description provided for @editorSignWayCard.
  ///
  /// In tr, this message translates to:
  /// **'e-imza kartıyla'**
  String get editorSignWayCard;

  /// No description provided for @editorSignOnlyUdf.
  ///
  /// In tr, this message translates to:
  /// **'Yalnız UDF belgeler imzalanır: önce UDF olarak kaydedin'**
  String get editorSignOnlyUdf;

  /// No description provided for @editorSignUnavailable.
  ///
  /// In tr, this message translates to:
  /// **'{way} bu cihazda kullanılamıyor'**
  String editorSignUnavailable(String way);

  /// No description provided for @editorSigning.
  ///
  /// In tr, this message translates to:
  /// **'İmzalanıyor…'**
  String get editorSigning;

  /// No description provided for @editorSignAsUdf.
  ///
  /// In tr, this message translates to:
  /// **'UDF olarak {way} imzala'**
  String editorSignAsUdf(String way);

  /// No description provided for @editorTableSize.
  ///
  /// In tr, this message translates to:
  /// **'{rows} × {columns} tablo'**
  String editorTableSize(int rows, int columns);

  /// No description provided for @editorTable.
  ///
  /// In tr, this message translates to:
  /// **'Tablo'**
  String get editorTable;

  /// No description provided for @editorImage.
  ///
  /// In tr, this message translates to:
  /// **'Görsel'**
  String get editorImage;

  /// No description provided for @editorHeader.
  ///
  /// In tr, this message translates to:
  /// **'Üst bilgi'**
  String get editorHeader;

  /// No description provided for @editorFooter.
  ///
  /// In tr, this message translates to:
  /// **'Alt bilgi'**
  String get editorFooter;

  /// No description provided for @editorPageNumbers.
  ///
  /// In tr, this message translates to:
  /// **'Sayfa numarası'**
  String get editorPageNumbers;

  /// No description provided for @editorLetterhead.
  ///
  /// In tr, this message translates to:
  /// **'Antet'**
  String get editorLetterhead;

  /// No description provided for @editorDate.
  ///
  /// In tr, this message translates to:
  /// **'Tarih'**
  String get editorDate;

  /// No description provided for @editorTableAndImage.
  ///
  /// In tr, this message translates to:
  /// **'Tablo ve görsel'**
  String get editorTableAndImage;

  /// No description provided for @editorHeaderAndFooter.
  ///
  /// In tr, this message translates to:
  /// **'Üst ve alt bilgi'**
  String get editorHeaderAndFooter;

  /// No description provided for @editorText.
  ///
  /// In tr, this message translates to:
  /// **'Metin'**
  String get editorText;

  /// No description provided for @editorSignatureBlock.
  ///
  /// In tr, this message translates to:
  /// **'İmza bloğu'**
  String get editorSignatureBlock;

  /// No description provided for @editorHorizontalRuler.
  ///
  /// In tr, this message translates to:
  /// **'Yatay cetvel'**
  String get editorHorizontalRuler;

  /// No description provided for @editorVerticalRuler.
  ///
  /// In tr, this message translates to:
  /// **'Dikey cetvel'**
  String get editorVerticalRuler;

  /// No description provided for @editorShortcuts.
  ///
  /// In tr, this message translates to:
  /// **'Kısayollar'**
  String get editorShortcuts;

  /// No description provided for @editorView.
  ///
  /// In tr, this message translates to:
  /// **'Görünüm'**
  String get editorView;

  /// No description provided for @editorRulers.
  ///
  /// In tr, this message translates to:
  /// **'Cetveller'**
  String get editorRulers;

  /// No description provided for @editorOther.
  ///
  /// In tr, this message translates to:
  /// **'Diğer'**
  String get editorOther;

  /// No description provided for @editorShortcutsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Editör kısayolları'**
  String get editorShortcutsTitle;

  /// No description provided for @editorShortcutsList.
  ///
  /// In tr, this message translates to:
  /// **'Ctrl+S  Kaydet\nCtrl+Shift+S  Farklı kaydet\nCtrl+Z  Geri al\nCtrl+Y / Ctrl+Shift+Z  Yinele\nCtrl+B / I / U  Kalın / İtalik / Altı çizili\nCtrl+A / C / X / V  Seç / Kopyala / Kes / Yapıştır\nCtrl+F  Belgede bul\nCtrl+H  Bul ve değiştir\nCtrl+P  Yazdır\nCtrl+L / E / R / J  Sola / Ortaya / Sağa / İki yana\nCtrl+Shift+L / 8  Madde işaretleri\nCtrl+Shift+7  Numaralı liste\nCtrl+M / Ctrl+Shift+M  Girintiyi artır / azalt\n\nmacOS’ta Ctrl yerine ⌘ kullanılır.'**
  String get editorShortcutsList;

  /// No description provided for @editorOk.
  ///
  /// In tr, this message translates to:
  /// **'Tamam'**
  String get editorOk;

  /// No description provided for @editorSaveFormatTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hangi biçimde kaydedilsin?'**
  String get editorSaveFormatTitle;

  /// No description provided for @editorFormatUdf.
  ///
  /// In tr, this message translates to:
  /// **'UYAP belgesi (.udf)'**
  String get editorFormatUdf;

  /// No description provided for @editorFormatDocx.
  ///
  /// In tr, this message translates to:
  /// **'Word belgesi (.docx)'**
  String get editorFormatDocx;

  /// No description provided for @editorFormatRtf.
  ///
  /// In tr, this message translates to:
  /// **'Zengin metin (.rtf)'**
  String get editorFormatRtf;

  /// No description provided for @editorFormatPdf.
  ///
  /// In tr, this message translates to:
  /// **'Yazdırılmış hâli (.pdf)'**
  String get editorFormatPdf;

  /// No description provided for @editorContinue.
  ///
  /// In tr, this message translates to:
  /// **'Devam'**
  String get editorContinue;

  /// No description provided for @editorSignedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bu belge e-imzalı'**
  String get editorSignedTitle;

  /// No description provided for @editorSignedBody.
  ///
  /// In tr, this message translates to:
  /// **'İmza, belgenin imzalandığı andaki içeriğini kapsar; değiştirilmiş belgeye taşınamaz.\n\n• Üzerine kaydet: dosya değişikliklerinizle, imzasız olarak güncellenir. İmzalı hali belge geçmişinde saklanır; istediğinizde ona dönebilir ya da kopyasını alabilirsiniz.\n\n• İmzasız kopya: imzalı dosya olduğu gibi kalır, değişiklikler yeni bir dosyaya yazılır.'**
  String get editorSignedBody;

  /// No description provided for @editorSaveUnsignedCopy.
  ///
  /// In tr, this message translates to:
  /// **'İmzasız kopya kaydet…'**
  String get editorSaveUnsignedCopy;

  /// No description provided for @editorOverwriteSave.
  ///
  /// In tr, this message translates to:
  /// **'Üzerine kaydet'**
  String get editorOverwriteSave;

  /// No description provided for @editorChangedElsewhereTitle.
  ///
  /// In tr, this message translates to:
  /// **'Belge başka bir yerde değiştirildi'**
  String get editorChangedElsewhereTitle;

  /// No description provided for @editorChangedElsewhereBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu dosya, siz burada açtıktan sonra başka bir programda değiştirilmiş. Kaydederseniz sizin hâliniz geçerli olur; öbür hâli belge geçmişinde saklanır.'**
  String get editorChangedElsewhereBody;

  /// No description provided for @editorSaveMine.
  ///
  /// In tr, this message translates to:
  /// **'Benim hâlimi kaydet'**
  String get editorSaveMine;

  /// No description provided for @editorOverwriteSignedTitle.
  ///
  /// In tr, this message translates to:
  /// **'İmzalı dosyanın üzerine yazılsın mı?'**
  String get editorOverwriteSignedTitle;

  /// No description provided for @editorOverwriteSignedBody.
  ///
  /// In tr, this message translates to:
  /// **'Dosya değişikliklerinizle, imzasız olarak güncellenir. İmzalı hali belge geçmişinde saklanır.'**
  String get editorOverwriteSignedBody;

  /// No description provided for @editorOverwrite.
  ///
  /// In tr, this message translates to:
  /// **'Üzerine yaz'**
  String get editorOverwrite;

  /// No description provided for @editorPdfNoTextNoOcr.
  ///
  /// In tr, this message translates to:
  /// **'Bu PDF’te metin katmanı yok: yazıları taranmış ya da yazdırılırken şekle dönüştürülmüş. Okumak için gereken OCR aracı bu kurulumda bulunamadı.'**
  String get editorPdfNoTextNoOcr;

  /// No description provided for @editorPdfNoTextUnreadable.
  ///
  /// In tr, this message translates to:
  /// **'Bu PDF’te metin katmanı yok ve sayfalarında okunabilir yazı bulunamadı.'**
  String get editorPdfNoTextUnreadable;

  /// No description provided for @editorUnreadable.
  ///
  /// In tr, this message translates to:
  /// **'Belge okunamadı veya bozuk.'**
  String get editorUnreadable;

  /// No description provided for @editorOcrRead.
  ///
  /// In tr, this message translates to:
  /// **'Bu PDF’te metin katmanı yoktu; metin sayfalardan okundu (OCR).'**
  String get editorOcrRead;

  /// No description provided for @editorOcrCheck.
  ///
  /// In tr, this message translates to:
  /// **'Kaydetmeden önce özellikle rakamları ve adları kontrol edin.'**
  String get editorOcrCheck;

  /// No description provided for @editorBlanksTitle.
  ///
  /// In tr, this message translates to:
  /// **'Doldurulmamış yer var'**
  String get editorBlanksTitle;

  /// No description provided for @editorBlanksBody.
  ///
  /// In tr, this message translates to:
  /// **'Belgede kalıptan gelen {count} yer hâlâ boş: {names}.\n\nYine de kaydedilsin mi?'**
  String editorBlanksBody(int count, String names);

  /// No description provided for @editorGoBack.
  ///
  /// In tr, this message translates to:
  /// **'Geri dön'**
  String get editorGoBack;

  /// No description provided for @editorSaveAnyway.
  ///
  /// In tr, this message translates to:
  /// **'Yine de kaydet'**
  String get editorSaveAnyway;

  /// No description provided for @editorUnsignedCopyTitle.
  ///
  /// In tr, this message translates to:
  /// **'İmzasız kopya kaydedilecek'**
  String get editorUnsignedCopyTitle;

  /// No description provided for @editorUnderstoodSave.
  ///
  /// In tr, this message translates to:
  /// **'Anladım, kaydet'**
  String get editorUnderstoodSave;

  /// No description provided for @editorSaveDialogTitle.
  ///
  /// In tr, this message translates to:
  /// **'Evrakı Kaydet ({ext})'**
  String editorSaveDialogTitle(String ext);

  /// No description provided for @editorOverwriteHeldDetail.
  ///
  /// In tr, this message translates to:
  /// **'Üzerine yazmak, o penceredeki çalışmayı kaybettirebilir. Başka bir adla kaydedin ya da önce o pencereyi kapatın.'**
  String get editorOverwriteHeldDetail;

  /// No description provided for @editorSignedNotOverwritten.
  ///
  /// In tr, this message translates to:
  /// **'İmzalı dosyanın üzerine yazılmadı'**
  String get editorSignedNotOverwritten;

  /// No description provided for @editorSignedNotOverwrittenDetail.
  ///
  /// In tr, this message translates to:
  /// **'İmzalı hali belge geçmişine saklanamadı. Değişiklikleri imzasız kopya olarak kaydedebilirsiniz.'**
  String get editorSignedNotOverwrittenDetail;

  /// No description provided for @editorNotOverwritten.
  ///
  /// In tr, this message translates to:
  /// **'Belgenin üzerine yazılmadı'**
  String get editorNotOverwritten;

  /// No description provided for @editorNotOverwrittenDetail.
  ///
  /// In tr, this message translates to:
  /// **'Başka programdaki hâli belge geçmişine saklanamadı. Değişikliklerinizi başka bir adla kaydedebilirsiniz.'**
  String get editorNotOverwrittenDetail;

  /// No description provided for @editorSaved.
  ///
  /// In tr, this message translates to:
  /// **'Kaydedildi'**
  String get editorSaved;

  /// No description provided for @editorSavedToLocation.
  ///
  /// In tr, this message translates to:
  /// **'Belge seçtiğiniz konuma kaydedildi.'**
  String get editorSavedToLocation;

  /// No description provided for @editorSavedAs.
  ///
  /// In tr, this message translates to:
  /// **'Başarıyla kaydedildi: {name}'**
  String editorSavedAs(String name);

  /// No description provided for @editorSaveAs.
  ///
  /// In tr, this message translates to:
  /// **'Farklı kaydet'**
  String get editorSaveAs;

  /// No description provided for @editorSaveFailed.
  ///
  /// In tr, this message translates to:
  /// **'Kaydetme hatası: belge kaydedilemedi'**
  String get editorSaveFailed;

  /// No description provided for @editorOcrReading.
  ///
  /// In tr, this message translates to:
  /// **'Bu PDF’te metin katmanı yok; sayfalar okunuyor (OCR)…'**
  String get editorOcrReading;

  /// No description provided for @editorOcrPerPage.
  ///
  /// In tr, this message translates to:
  /// **'Sayfa başına birkaç saniye sürebilir.'**
  String get editorOcrPerPage;

  /// No description provided for @editorOpenFailed.
  ///
  /// In tr, this message translates to:
  /// **'Belge açılamadı: {error}'**
  String editorOpenFailed(String error);

  /// No description provided for @editorRecoverFromHistory.
  ///
  /// In tr, this message translates to:
  /// **'Belge geçmişinden kurtar'**
  String get editorRecoverFromHistory;

  /// No description provided for @editorFontLoadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Yazı tipi yüklenemedi'**
  String get editorFontLoadFailed;

  /// No description provided for @editorSignUdf.
  ///
  /// In tr, this message translates to:
  /// **'UDF e-imzala'**
  String get editorSignUdf;

  /// No description provided for @editorSaveTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet · Ctrl+S'**
  String get editorSaveTooltip;

  /// No description provided for @snipDeleteTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kalıp silinsin mi?'**
  String get snipDeleteTitle;

  /// No description provided for @snipDeleteBody.
  ///
  /// In tr, this message translates to:
  /// **'“{name}” kalıplarınızdan kaldırılacak. Bu kalıpla yazılmış belgeler değişmez.'**
  String snipDeleteBody(String name);

  /// No description provided for @snipCancel.
  ///
  /// In tr, this message translates to:
  /// **'Vazgeç'**
  String get snipCancel;

  /// No description provided for @snipDelete.
  ///
  /// In tr, this message translates to:
  /// **'Sil'**
  String get snipDelete;

  /// No description provided for @snipExportDialog.
  ///
  /// In tr, this message translates to:
  /// **'Kalıpları dışa aktar'**
  String get snipExportDialog;

  /// No description provided for @snipExported.
  ///
  /// In tr, this message translates to:
  /// **'{count} kalıp dışa aktarıldı.'**
  String snipExported(int count);

  /// No description provided for @snipExportFailed.
  ///
  /// In tr, this message translates to:
  /// **'Kalıplar dışa aktarılamadı'**
  String get snipExportFailed;

  /// No description provided for @snipImportDialog.
  ///
  /// In tr, this message translates to:
  /// **'Kalıpları içe aktar'**
  String get snipImportDialog;

  /// No description provided for @snipImportNone.
  ///
  /// In tr, this message translates to:
  /// **'Yeni kalıp yok; hepsi zaten kalıplarınızda.'**
  String get snipImportNone;

  /// No description provided for @snipImported.
  ///
  /// In tr, this message translates to:
  /// **'{count} kalıp eklendi.'**
  String snipImported(int count);

  /// No description provided for @snipImportFailed.
  ///
  /// In tr, this message translates to:
  /// **'Kalıplar içe aktarılamadı'**
  String get snipImportFailed;

  /// No description provided for @snipManagerTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kalıplarım'**
  String get snipManagerTitle;

  /// No description provided for @snipImport.
  ///
  /// In tr, this message translates to:
  /// **'İçe aktar'**
  String get snipImport;

  /// No description provided for @snipExport.
  ///
  /// In tr, this message translates to:
  /// **'Dışa aktar'**
  String get snipExport;

  /// No description provided for @snipSearchHint.
  ///
  /// In tr, this message translates to:
  /// **'Kalıp ara'**
  String get snipSearchHint;

  /// No description provided for @snipManagerEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Henüz kalıp yok. \"Yeni kalıp\" ile ekleyebilir ya da belgede bir paragrafı seçip Ctrl+Space ile kalıba alabilirsiniz.'**
  String get snipManagerEmpty;

  /// No description provided for @snipNoMatch.
  ///
  /// In tr, this message translates to:
  /// **'Bu aramaya uyan kalıp yok.'**
  String get snipNoMatch;

  /// No description provided for @snipUsedTimes.
  ///
  /// In tr, this message translates to:
  /// **'{count} kez'**
  String snipUsedTimes(int count);

  /// No description provided for @snipNew.
  ///
  /// In tr, this message translates to:
  /// **'Yeni kalıp'**
  String get snipNew;

  /// No description provided for @snipClose.
  ///
  /// In tr, this message translates to:
  /// **'Kapat'**
  String get snipClose;

  /// No description provided for @snipEditTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kalıbı düzenle'**
  String get snipEditTitle;

  /// No description provided for @snipEmptyBody.
  ///
  /// In tr, this message translates to:
  /// **'Kalıbın metni boş olamaz.'**
  String get snipEmptyBody;

  /// No description provided for @snipBadKeyword.
  ///
  /// In tr, this message translates to:
  /// **'Anahtar kelime 2–20 harf ya da rakamdan oluşmalı, boşluk olmadan.'**
  String get snipBadKeyword;

  /// No description provided for @snipKeywordTaken.
  ///
  /// In tr, this message translates to:
  /// **'“{keyword}” zaten “{name}” kalıbının anahtar kelimesi.'**
  String snipKeywordTaken(String keyword, String name);

  /// No description provided for @snipHotkeyTaken.
  ///
  /// In tr, this message translates to:
  /// **'Alt+F{key} zaten “{name}” kalıbında.'**
  String snipHotkeyTaken(String key, String name);

  /// No description provided for @snipUntitled.
  ///
  /// In tr, this message translates to:
  /// **'Adsız kalıp'**
  String get snipUntitled;

  /// No description provided for @snipName.
  ///
  /// In tr, this message translates to:
  /// **'Ad'**
  String get snipName;

  /// No description provided for @snipKeyword.
  ///
  /// In tr, this message translates to:
  /// **'Anahtar kelime'**
  String get snipKeyword;

  /// No description provided for @snipKeywordHint.
  ///
  /// In tr, this message translates to:
  /// **'örn. dil1'**
  String get snipKeywordHint;

  /// No description provided for @snipKeywordHelper.
  ///
  /// In tr, this message translates to:
  /// **'Belgede yazıp Tab’a basınca kalıp gelir'**
  String get snipKeywordHelper;

  /// No description provided for @snipHotkey.
  ///
  /// In tr, this message translates to:
  /// **'Kısayol'**
  String get snipHotkey;

  /// No description provided for @snipHotkeyHelper.
  ///
  /// In tr, this message translates to:
  /// **'Alt+F4 pencereyi kapatır'**
  String get snipHotkeyHelper;

  /// No description provided for @snipNoHotkey.
  ///
  /// In tr, this message translates to:
  /// **'Yok'**
  String get snipNoHotkey;

  /// No description provided for @snipText.
  ///
  /// In tr, this message translates to:
  /// **'Metin'**
  String get snipText;

  /// No description provided for @snipBodyPlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'Kalıbın metni. Doldurulacak yerleri [MÜVEKKİL] gibi köşeli parantez ve büyük harfle yazın.'**
  String get snipBodyPlaceholder;

  /// No description provided for @snipBlanksList.
  ///
  /// In tr, this message translates to:
  /// **'Doldurulacak yerler: {blanks}'**
  String snipBlanksList(String blanks);

  /// No description provided for @snipSave.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet'**
  String get snipSave;

  /// No description provided for @snipTableLeftOut.
  ///
  /// In tr, this message translates to:
  /// **'〔Tablo — kalıpla eklenmez〕'**
  String get snipTableLeftOut;

  /// No description provided for @snipPaletteHint.
  ///
  /// In tr, this message translates to:
  /// **'Kalıp ya da profil bilgisi ara'**
  String get snipPaletteHint;

  /// No description provided for @snipFromProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profilden'**
  String get snipFromProfile;

  /// No description provided for @snipProfileInsertTooltip.
  ///
  /// In tr, this message translates to:
  /// **'{label} · belgeye ekle'**
  String snipProfileInsertTooltip(String label);

  /// No description provided for @snipFillProfile.
  ///
  /// In tr, this message translates to:
  /// **'Avukat profilini doldurun'**
  String get snipFillProfile;

  /// No description provided for @snipFillProfileDetail.
  ///
  /// In tr, this message translates to:
  /// **'Adınız, baronuz, adresiniz buradan tek tıkla eklensin'**
  String get snipFillProfileDetail;

  /// No description provided for @snipKeepSelection.
  ///
  /// In tr, this message translates to:
  /// **'Seçimi kalıba al'**
  String get snipKeepSelection;

  /// No description provided for @snipHarvestOpen.
  ///
  /// In tr, this message translates to:
  /// **'Arşivden kalıp bul'**
  String get snipHarvestOpen;

  /// No description provided for @snipHarvestOpenDetail.
  ///
  /// In tr, this message translates to:
  /// **'Belgelerinizde tekrar eden paragraflar'**
  String get snipHarvestOpenDetail;

  /// No description provided for @snipManage.
  ///
  /// In tr, this message translates to:
  /// **'Kalıplarımı yönet'**
  String get snipManage;

  /// No description provided for @snipManageDetail.
  ///
  /// In tr, this message translates to:
  /// **'Ad, anahtar kelime, Alt+F kısayolu, silme'**
  String get snipManageDetail;

  /// No description provided for @snipPaletteNoMatch.
  ///
  /// In tr, this message translates to:
  /// **'Bu aramaya uyan kalıp ya da profil bilgisi yok.'**
  String get snipPaletteNoMatch;

  /// No description provided for @snipPaletteEmptyHarvest.
  ///
  /// In tr, this message translates to:
  /// **'Henüz kalıp yok.\n\nYukarıdan arşivinizde tekrar eden paragraflara bakabilir, ya da bir paragrafı belgede seçip yeniden Ctrl+Space’e basabilirsiniz.'**
  String get snipPaletteEmptyHarvest;

  /// No description provided for @snipPaletteEmptySelect.
  ///
  /// In tr, this message translates to:
  /// **'Henüz kalıp yok.\n\nSık yazdığınız bir paragrafı belgede seçin, sonra Ctrl+Space’e basın — burada “Seçimi kalıba al” çıkacak.'**
  String get snipPaletteEmptySelect;

  /// No description provided for @snipPaletteEmptyKeep.
  ///
  /// In tr, this message translates to:
  /// **'Henüz kalıp yok. Yukarıdan seçiminizi kalıba alabilirsiniz.'**
  String get snipPaletteEmptyKeep;

  /// No description provided for @snipFromProfileLabel.
  ///
  /// In tr, this message translates to:
  /// **'Profilden · {label}'**
  String snipFromProfileLabel(String label);

  /// No description provided for @snipPaletteKeys.
  ///
  /// In tr, this message translates to:
  /// **'↑ ↓ ile seçin · Enter ile yerleştirin · Esc ile kapatın'**
  String get snipPaletteKeys;

  /// No description provided for @snipNameIt.
  ///
  /// In tr, this message translates to:
  /// **'Kalıba ad verin'**
  String get snipNameIt;

  /// No description provided for @snipNameItDetail.
  ///
  /// In tr, this message translates to:
  /// **'Sonra bu adın ilk harflerini yazarak bulacaksınız.'**
  String get snipNameItDetail;

  /// No description provided for @snipBack.
  ///
  /// In tr, this message translates to:
  /// **'Geri'**
  String get snipBack;

  /// No description provided for @snipKeep.
  ///
  /// In tr, this message translates to:
  /// **'Kalıba al'**
  String get snipKeep;

  /// No description provided for @snipFillCount.
  ///
  /// In tr, this message translates to:
  /// **'Bu kalıpta doldurulacak {count} yer var.'**
  String snipFillCount(int count);

  /// No description provided for @snipFromLawyerProfile.
  ///
  /// In tr, this message translates to:
  /// **'Avukat profilinden'**
  String get snipFromLawyerProfile;

  /// No description provided for @snipLeaveBlank.
  ///
  /// In tr, this message translates to:
  /// **'Boş bırak'**
  String get snipLeaveBlank;

  /// No description provided for @snipInsert.
  ///
  /// In tr, this message translates to:
  /// **'Yerleştir'**
  String get snipInsert;

  /// No description provided for @snipHarvestTitle.
  ///
  /// In tr, this message translates to:
  /// **'Arşivinizde tekrar eden paragraflar'**
  String get snipHarvestTitle;

  /// No description provided for @snipHarvestNone.
  ///
  /// In tr, this message translates to:
  /// **'Beş ya da daha fazla belgede aynen geçen bir paragraf bulunamadı. Arşiv henüz taranıyor olabilir.'**
  String get snipHarvestNone;

  /// No description provided for @snipHarvestFound.
  ///
  /// In tr, this message translates to:
  /// **'{count} paragraf bulundu. Kalıba almak istediklerinizi işaretleyin.'**
  String snipHarvestFound(int count);

  /// No description provided for @snipHarvestBlank.
  ///
  /// In tr, this message translates to:
  /// **'Tarih, esas numarası, kimlik ve tutarları boş bırak'**
  String get snipHarvestBlank;

  /// No description provided for @snipHarvestBlankDetail.
  ///
  /// In tr, this message translates to:
  /// **'Bir dosyaya ait olan kısımlar [TARİH] gibi doldurulacak yerlere çevrilir.'**
  String get snipHarvestBlankDetail;

  /// No description provided for @snipHarvestInDocuments.
  ///
  /// In tr, this message translates to:
  /// **'{count} belgede'**
  String snipHarvestInDocuments(int count);

  /// No description provided for @snipHarvestTake.
  ///
  /// In tr, this message translates to:
  /// **'{count} kalıbı al'**
  String snipHarvestTake(int count);

  /// No description provided for @noteDraftTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Kaydedilmemiş taslak · {date}'**
  String noteDraftTooltip(String date);

  /// No description provided for @noteDraftTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kaydedilmemiş taslak'**
  String get noteDraftTitle;

  /// No description provided for @noteDraftBody.
  ///
  /// In tr, this message translates to:
  /// **'“{name}” için {date} tarihli, kaydedilmemiş bir taslak var. Uygulama beklenmedik biçimde kapandığında kalmış olabilir.\n\nAçarsanız editöre kaydedilmemiş değişiklik olarak gelir; siz kaydedene kadar dosya değişmez.'**
  String noteDraftBody(String name, String date);

  /// No description provided for @noteDraftMore.
  ///
  /// In tr, this message translates to:
  /// **'\n\nBu belgenin {count} taslağı daha var; hepsi ana sayfadaki «Kurtarılabilir taslaklar»da.'**
  String noteDraftMore(int count);

  /// No description provided for @noteDraftDelete.
  ///
  /// In tr, this message translates to:
  /// **'Taslağı sil'**
  String get noteDraftDelete;

  /// No description provided for @noteCancel.
  ///
  /// In tr, this message translates to:
  /// **'Vazgeç'**
  String get noteCancel;

  /// No description provided for @noteDraftOpen.
  ///
  /// In tr, this message translates to:
  /// **'Taslağı aç'**
  String get noteDraftOpen;

  /// No description provided for @noteDraftDeleteTitle.
  ///
  /// In tr, this message translates to:
  /// **'Taslak silinsin mi?'**
  String get noteDraftDeleteTitle;

  /// No description provided for @noteDraftDeleteBody.
  ///
  /// In tr, this message translates to:
  /// **'“{name}” için {date} tarihli kaydedilmemiş taslak kalıcı olarak silinecek. Belgenin kendisi değişmez.'**
  String noteDraftDeleteBody(String name, String date);

  /// No description provided for @noteUnsavedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kaydedilmemiş değişiklikler var'**
  String get noteUnsavedTitle;

  /// No description provided for @noteUnsavedBody.
  ///
  /// In tr, this message translates to:
  /// **'{what} editöre alınınca şu anki kaydedilmemiş değişiklikler onun yerine geçer. Önce kaydederseniz bugünkü hali de belge geçmişinde kalır.'**
  String noteUnsavedBody(String what);

  /// No description provided for @noteOpenWithoutSaving.
  ///
  /// In tr, this message translates to:
  /// **'Kaydetmeden aç'**
  String get noteOpenWithoutSaving;

  /// No description provided for @noteSaveFirst.
  ///
  /// In tr, this message translates to:
  /// **'Önce kaydet'**
  String get noteSaveFirst;

  /// No description provided for @speechPreparingVoice.
  ///
  /// In tr, this message translates to:
  /// **'Ses hazırlanıyor…'**
  String get speechPreparingVoice;

  /// No description provided for @speechPaused.
  ///
  /// In tr, this message translates to:
  /// **'Duraklatıldı'**
  String get speechPaused;

  /// No description provided for @speechReading.
  ///
  /// In tr, this message translates to:
  /// **'Okunuyor'**
  String get speechReading;

  /// No description provided for @speechSpeed.
  ///
  /// In tr, this message translates to:
  /// **'Okuma hızı'**
  String get speechSpeed;

  /// No description provided for @speechResume.
  ///
  /// In tr, this message translates to:
  /// **'Sürdür'**
  String get speechResume;

  /// No description provided for @speechPause.
  ///
  /// In tr, this message translates to:
  /// **'Duraklat'**
  String get speechPause;

  /// No description provided for @speechStopReading.
  ///
  /// In tr, this message translates to:
  /// **'Okumayı durdur'**
  String get speechStopReading;

  /// No description provided for @speechPreparing.
  ///
  /// In tr, this message translates to:
  /// **'Hazırlanıyor…'**
  String get speechPreparing;

  /// No description provided for @speechTranscribing.
  ///
  /// In tr, this message translates to:
  /// **'Yazıya dökülüyor…'**
  String get speechTranscribing;

  /// No description provided for @speechListening.
  ///
  /// In tr, this message translates to:
  /// **'Dinleniyor, konuşabilirsiniz'**
  String get speechListening;

  /// No description provided for @speechFinish.
  ///
  /// In tr, this message translates to:
  /// **'Bitir'**
  String get speechFinish;

  /// No description provided for @speechTextUnreadable.
  ///
  /// In tr, this message translates to:
  /// **'Metin okunamadı'**
  String get speechTextUnreadable;

  /// No description provided for @speechNothingToRead.
  ///
  /// In tr, this message translates to:
  /// **'Okunacak metin yok'**
  String get speechNothingToRead;

  /// No description provided for @speechReadingStopped.
  ///
  /// In tr, this message translates to:
  /// **'Sesli okuma durdu'**
  String get speechReadingStopped;

  /// No description provided for @speechDownloadIntro.
  ///
  /// In tr, this message translates to:
  /// **'{need} ({size}). Model yalnızca bir kez indirilir ve bilgisayarınızda saklanır. {offline}'**
  String speechDownloadIntro(String need, String size, String offline);

  /// No description provided for @speechModelLicense.
  ///
  /// In tr, this message translates to:
  /// **'Model lisansı: {license}'**
  String speechModelLicense(String license);

  /// No description provided for @speechDownloadFailed.
  ///
  /// In tr, this message translates to:
  /// **'İndirme tamamlanamadı. İndirilen kısım saklandı; yeniden denediğinizde kaldığı yerden devam eder.\n{error}'**
  String speechDownloadFailed(String error);

  /// No description provided for @speechCancelDownload.
  ///
  /// In tr, this message translates to:
  /// **'İptal'**
  String get speechCancelDownload;

  /// No description provided for @speechCancel.
  ///
  /// In tr, this message translates to:
  /// **'Vazgeç'**
  String get speechCancel;

  /// No description provided for @speechDownload.
  ///
  /// In tr, this message translates to:
  /// **'İndir ({size})'**
  String speechDownload(String size);

  /// No description provided for @speechTryAgain.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden dene'**
  String get speechTryAgain;

  /// No description provided for @noteSecretSwitch.
  ///
  /// In tr, this message translates to:
  /// **'Gizli not · büroyla paylaşılmaz'**
  String get noteSecretSwitch;

  /// No description provided for @noteSecretSwitchDetail.
  ///
  /// In tr, this message translates to:
  /// **'Yalnız sizin cihazlarınıza gider. Görevlere, paylaşılan dosyaya ve üretilen belgelere girmez.'**
  String get noteSecretSwitchDetail;

  /// No description provided for @noteSecretMark.
  ///
  /// In tr, this message translates to:
  /// **'Gizli'**
  String get noteSecretMark;

  /// No description provided for @noteSecretRecalled.
  ///
  /// In tr, this message translates to:
  /// **'Büro kopyalarından silindi.'**
  String get noteSecretRecalled;

  /// No description provided for @noteSecretRecalling.
  ///
  /// In tr, this message translates to:
  /// **'Büro kopyalarından siliniyor; alanların cihazı açılınca tamamlanır.'**
  String get noteSecretRecalling;

  /// No description provided for @noteSecretSharedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Not büroyla paylaşılmıştı'**
  String get noteSecretSharedTitle;

  /// No description provided for @noteSecretSharedBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu not büroda {count} kişide var ({names}). Gizli yaparsanız onlardan da silinir.'**
  String noteSecretSharedBody(int count, String names);

  /// No description provided for @noteSecretNoRecall.
  ///
  /// In tr, this message translates to:
  /// **'Dışarı aktarılmış belge ve ekran görüntüsü geri alınamaz.'**
  String get noteSecretNoRecall;

  /// No description provided for @noteSecretConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Gizli yap'**
  String get noteSecretConfirm;

  /// No description provided for @liveChat.
  ///
  /// In tr, this message translates to:
  /// **'Yazışma'**
  String get liveChat;

  /// No description provided for @liveClosePanel.
  ///
  /// In tr, this message translates to:
  /// **'Paneli kapat'**
  String get liveClosePanel;

  /// No description provided for @liveChatEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Belge üzerinde birbirinize buradan yazın. Yazışma paylaşım bitince silinir.'**
  String get liveChatEmpty;

  /// No description provided for @liveRemoveQuote.
  ///
  /// In tr, this message translates to:
  /// **'Alıntıyı kaldır'**
  String get liveRemoveQuote;

  /// No description provided for @liveQuoteSelection.
  ///
  /// In tr, this message translates to:
  /// **'Belgede seçili olanı alıntıla'**
  String get liveQuoteSelection;

  /// No description provided for @liveMessageHint.
  ///
  /// In tr, this message translates to:
  /// **'Mesaj yazın…'**
  String get liveMessageHint;

  /// No description provided for @liveSend.
  ///
  /// In tr, this message translates to:
  /// **'Gönder'**
  String get liveSend;

  /// No description provided for @liveVerification.
  ///
  /// In tr, this message translates to:
  /// **'DOĞRULAMA'**
  String get liveVerification;

  /// No description provided for @liveGuest.
  ///
  /// In tr, this message translates to:
  /// **'Misafir'**
  String get liveGuest;

  /// No description provided for @liveVisitorLeft.
  ///
  /// In tr, this message translates to:
  /// **'Gelen kişi ayrıldı.'**
  String get liveVisitorLeft;

  /// No description provided for @liveInviteCopied.
  ///
  /// In tr, this message translates to:
  /// **'Davet kopyalandı'**
  String get liveInviteCopied;

  /// No description provided for @liveInviteMailSubject.
  ///
  /// In tr, this message translates to:
  /// **'Canlı belge daveti'**
  String get liveInviteMailSubject;

  /// No description provided for @liveInviteAnother.
  ///
  /// In tr, this message translates to:
  /// **'Bir kişi daha davet et'**
  String get liveInviteAnother;

  /// No description provided for @liveNewCode.
  ///
  /// In tr, this message translates to:
  /// **'Yeni kod oluştur'**
  String get liveNewCode;

  /// No description provided for @livePreparingCode.
  ///
  /// In tr, this message translates to:
  /// **'Davet kodu hazırlanıyor…'**
  String get livePreparingCode;

  /// No description provided for @liveSendCode.
  ///
  /// In tr, this message translates to:
  /// **'Kodu diğer büroya gönderin. Katılmak isteyen olunca size sorulur.'**
  String get liveSendCode;

  /// No description provided for @liveSendWhatsApp.
  ///
  /// In tr, this message translates to:
  /// **'WhatsApp ile gönder'**
  String get liveSendWhatsApp;

  /// No description provided for @liveCopy.
  ///
  /// In tr, this message translates to:
  /// **'Kopyala'**
  String get liveCopy;

  /// No description provided for @liveEmail.
  ///
  /// In tr, this message translates to:
  /// **'E-posta'**
  String get liveEmail;

  /// No description provided for @liveCopyInvite.
  ///
  /// In tr, this message translates to:
  /// **'Daveti kopyala'**
  String get liveCopyInvite;

  /// No description provided for @liveCodeValidUntil.
  ///
  /// In tr, this message translates to:
  /// **'{time}’e kadar geçerli, bir kişi içindir. Belge şifreli gider; aradaki sunucu içeriği göremez.'**
  String liveCodeValidUntil(String time);

  /// No description provided for @liveWantsToJoin.
  ///
  /// In tr, this message translates to:
  /// **'davet koduyla katılmak istiyor'**
  String get liveWantsToJoin;

  /// No description provided for @liveDigitsMatchHost.
  ///
  /// In tr, this message translates to:
  /// **'Aynı sayı onun ekranında da görünüyorsa doğru kişidir.'**
  String get liveDigitsMatchHost;

  /// No description provided for @liveDecline.
  ///
  /// In tr, this message translates to:
  /// **'Reddet'**
  String get liveDecline;

  /// No description provided for @liveLetView.
  ///
  /// In tr, this message translates to:
  /// **'Yalnız görsün'**
  String get liveLetView;

  /// No description provided for @liveLetEdit.
  ///
  /// In tr, this message translates to:
  /// **'Sırayla düzenlesin'**
  String get liveLetEdit;

  /// No description provided for @liveJoinedName.
  ///
  /// In tr, this message translates to:
  /// **'{name} katıldı.'**
  String liveJoinedName(String name);

  /// No description provided for @liveInviteWithdrawn.
  ///
  /// In tr, this message translates to:
  /// **'Davet geri alındı.'**
  String get liveInviteWithdrawn;

  /// No description provided for @liveCodeExpired.
  ///
  /// In tr, this message translates to:
  /// **'Davet kodunun süresi doldu.'**
  String get liveCodeExpired;

  /// No description provided for @liveInviteFailed.
  ///
  /// In tr, this message translates to:
  /// **'Davet kurulamadı.'**
  String get liveInviteFailed;

  /// No description provided for @liveCancel.
  ///
  /// In tr, this message translates to:
  /// **'Vazgeç'**
  String get liveCancel;

  /// No description provided for @liveClose.
  ///
  /// In tr, this message translates to:
  /// **'Kapat'**
  String get liveClose;

  /// No description provided for @liveJoinPrompt.
  ///
  /// In tr, this message translates to:
  /// **'Size gönderilen kodu yazın ya da davet bağlantısını yapıştırın.'**
  String get liveJoinPrompt;

  /// No description provided for @liveJoinName.
  ///
  /// In tr, this message translates to:
  /// **'Adınız (paylaşana böyle görünür)'**
  String get liveJoinName;

  /// No description provided for @liveJoin.
  ///
  /// In tr, this message translates to:
  /// **'Katıl'**
  String get liveJoin;

  /// No description provided for @liveConnecting.
  ///
  /// In tr, this message translates to:
  /// **'Bağlanılıyor…'**
  String get liveConnecting;

  /// No description provided for @liveAwaitingApproval.
  ///
  /// In tr, this message translates to:
  /// **'Onay bekleniyor'**
  String get liveAwaitingApproval;

  /// No description provided for @liveOpensOnApproval.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşan onaylayınca belge açılır.'**
  String get liveOpensOnApproval;

  /// No description provided for @liveDigitsMatchGuest.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşanın ekranında da bu sayı görünür.'**
  String get liveDigitsMatchGuest;

  /// No description provided for @liveJoinRefused.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşan katılmanızı kabul etmedi.'**
  String get liveJoinRefused;

  /// No description provided for @liveJoinFailed.
  ///
  /// In tr, this message translates to:
  /// **'Katılınamadı.'**
  String get liveJoinFailed;

  /// No description provided for @liveTryAgain.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden dene'**
  String get liveTryAgain;

  /// No description provided for @liveJoinTitle.
  ///
  /// In tr, this message translates to:
  /// **'Canlı belgeye katıl'**
  String get liveJoinTitle;

  /// No description provided for @liveShareTitle.
  ///
  /// In tr, this message translates to:
  /// **'Canlı paylaş'**
  String get liveShareTitle;

  /// No description provided for @liveOnThisNetwork.
  ///
  /// In tr, this message translates to:
  /// **'Bu ağda'**
  String get liveOnThisNetwork;

  /// No description provided for @liveRemote.
  ///
  /// In tr, this message translates to:
  /// **'Uzaktan'**
  String get liveRemote;

  /// No description provided for @liveRemoteJoined.
  ///
  /// In tr, this message translates to:
  /// **'UZAKTAN KATILANLAR'**
  String get liveRemoteJoined;

  /// No description provided for @liveTakeBackPen.
  ///
  /// In tr, this message translates to:
  /// **'Kalemi geri al · {name}'**
  String liveTakeBackPen(String name);

  /// No description provided for @liveRemoteHint.
  ///
  /// In tr, this message translates to:
  /// **'Kodu alan kişi bağlantıya dokunur ya da Folio’da Canlı belge’ye basıp kodu yazar; siz onaylayınca belge onda açılır. Belge sizde kalır, paylaşım bitince onda kalmaz.'**
  String get liveRemoteHint;

  /// No description provided for @liveNearbyHint.
  ///
  /// In tr, this message translates to:
  /// **'Davet ettiğiniz kişinin Folio’sunda bir pencere açılır; Katıl’a basınca belge onda açılır. Belge sizde kalır, paylaşım bitince onlarda kalmaz. \"Sırayla düzenleyebilir\" olanlara kalemi verince yazdıkları belgenize işlenir.'**
  String get liveNearbyHint;

  /// No description provided for @liveStopSharing.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşımı bitir'**
  String get liveStopSharing;

  /// No description provided for @liveOk.
  ///
  /// In tr, this message translates to:
  /// **'Tamam'**
  String get liveOk;

  /// No description provided for @liveNoDevices.
  ///
  /// In tr, this message translates to:
  /// **'Aynı ağda davet edilebilecek bir cihaz görünmüyor. Karşı tarafta Folio açık ve aynı Wi-Fi’ye bağlı olmalı.'**
  String get liveNoDevices;

  /// No description provided for @liveSearching.
  ///
  /// In tr, this message translates to:
  /// **'Aynı ağdaki cihazlar aranıyor…'**
  String get liveSearching;

  /// No description provided for @liveNetworkError.
  ///
  /// In tr, this message translates to:
  /// **'Ağa bağlanılamadı: {error}'**
  String liveNetworkError(String error);

  /// No description provided for @liveInvited.
  ///
  /// In tr, this message translates to:
  /// **'DAVET EDİLENLER'**
  String get liveInvited;

  /// No description provided for @liveMyDevices.
  ///
  /// In tr, this message translates to:
  /// **'CİHAZLARIM'**
  String get liveMyDevices;

  /// No description provided for @liveOffice.
  ///
  /// In tr, this message translates to:
  /// **'BÜRO'**
  String get liveOffice;

  /// No description provided for @liveNearby.
  ///
  /// In tr, this message translates to:
  /// **'YAKINDAKİ FOLIO’LAR'**
  String get liveNearby;

  /// No description provided for @livePeerJoining.
  ///
  /// In tr, this message translates to:
  /// **'yanıt bekleniyor'**
  String get livePeerJoining;

  /// No description provided for @livePeerWatching.
  ///
  /// In tr, this message translates to:
  /// **'izliyor'**
  String get livePeerWatching;

  /// No description provided for @livePeerGone.
  ///
  /// In tr, this message translates to:
  /// **'ayrıldı'**
  String get livePeerGone;

  /// No description provided for @livePeerUnreachable.
  ///
  /// In tr, this message translates to:
  /// **'ulaşılamadı'**
  String get livePeerUnreachable;

  /// No description provided for @livePeerDeclined.
  ///
  /// In tr, this message translates to:
  /// **'reddetti'**
  String get livePeerDeclined;

  /// No description provided for @livePeerUnanswered.
  ///
  /// In tr, this message translates to:
  /// **'yanıt vermedi'**
  String get livePeerUnanswered;

  /// No description provided for @liveWithdraw.
  ///
  /// In tr, this message translates to:
  /// **'Geri al'**
  String get liveWithdraw;

  /// No description provided for @liveRemovePeer.
  ///
  /// In tr, this message translates to:
  /// **'Çıkar'**
  String get liveRemovePeer;

  /// No description provided for @liveInvite.
  ///
  /// In tr, this message translates to:
  /// **'Davet et'**
  String get liveInvite;

  /// No description provided for @liveInviteAgain.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden davet et'**
  String get liveInviteAgain;

  /// No description provided for @liveGivePen.
  ///
  /// In tr, this message translates to:
  /// **'Kalemi ver'**
  String get liveGivePen;

  /// No description provided for @liveCanView.
  ///
  /// In tr, this message translates to:
  /// **'Yalnız görebilir'**
  String get liveCanView;

  /// No description provided for @liveCanEdit.
  ///
  /// In tr, this message translates to:
  /// **'Sırayla düzenleyebilir'**
  String get liveCanEdit;

  /// No description provided for @liveCodeChip.
  ///
  /// In tr, this message translates to:
  /// **'kod {code}'**
  String liveCodeChip(String code);

  /// No description provided for @livePenHere.
  ///
  /// In tr, this message translates to:
  /// **'kalem onda'**
  String get livePenHere;

  /// No description provided for @liveDevice.
  ///
  /// In tr, this message translates to:
  /// **'Cihaz'**
  String get liveDevice;

  /// No description provided for @liveEnded.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşım bitti; belge bu cihazda kalmadı.'**
  String get liveEnded;

  /// No description provided for @livePenSyncing.
  ///
  /// In tr, this message translates to:
  /// **'Kalem sizde · belge paylaşanla eşitleniyor, bir an bekleyin'**
  String get livePenSyncing;

  /// No description provided for @livePenYours.
  ///
  /// In tr, this message translates to:
  /// **'Kalem sizde · yazdıklarınız paylaşanın belgesine işlenir'**
  String get livePenYours;

  /// No description provided for @liveSharing.
  ///
  /// In tr, this message translates to:
  /// **'{name} paylaşıyor'**
  String liveSharing(String name);

  /// No description provided for @liveWriting.
  ///
  /// In tr, this message translates to:
  /// **'{name} yazıyor'**
  String liveWriting(String name);

  /// No description provided for @liveEditRefused.
  ///
  /// In tr, this message translates to:
  /// **'düzenleme isteğiniz geri çevrildi'**
  String get liveEditRefused;

  /// No description provided for @liveYouCanEdit.
  ///
  /// In tr, this message translates to:
  /// **'sırayla düzenleyebilirsiniz'**
  String get liveYouCanEdit;

  /// No description provided for @liveYouCanView.
  ///
  /// In tr, this message translates to:
  /// **'yalnız görebilirsiniz'**
  String get liveYouCanView;

  /// No description provided for @liveReleasePen.
  ///
  /// In tr, this message translates to:
  /// **'Kalemi bırak'**
  String get liveReleasePen;

  /// No description provided for @livePenAsked.
  ///
  /// In tr, this message translates to:
  /// **'İstendi'**
  String get livePenAsked;

  /// No description provided for @liveAskPen.
  ///
  /// In tr, this message translates to:
  /// **'Düzenlemek iste'**
  String get liveAskPen;

  /// No description provided for @liveStopWatching.
  ///
  /// In tr, this message translates to:
  /// **'İzlemeyi bırak'**
  String get liveStopWatching;

  /// No description provided for @liveDocument.
  ///
  /// In tr, this message translates to:
  /// **'Canlı belge'**
  String get liveDocument;

  /// No description provided for @liveHubCodePrompt.
  ///
  /// In tr, this message translates to:
  /// **'Size gönderilen kodu yazın:'**
  String get liveHubCodePrompt;

  /// No description provided for @liveHubOrShare.
  ///
  /// In tr, this message translates to:
  /// **'YA DA BİR BELGEYİ PAYLAŞIN'**
  String get liveHubOrShare;

  /// No description provided for @liveHubPickPrompt.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşacağınız belgeyi seçin. Belge açılır ve diğer büroya göndereceğiniz kod hemen çıkar.'**
  String get liveHubPickPrompt;

  /// No description provided for @liveHubPickOther.
  ///
  /// In tr, this message translates to:
  /// **'Başka belge seç…'**
  String get liveHubPickOther;

  /// No description provided for @liveSharesADocument.
  ///
  /// In tr, this message translates to:
  /// **' bir belgeyi sizinle canlı paylaşıyor.'**
  String get liveSharesADocument;

  /// No description provided for @liveSharesDocument.
  ///
  /// In tr, this message translates to:
  /// **' “{title}” belgesini sizinle canlı paylaşıyor.'**
  String liveSharesDocument(String title);

  /// No description provided for @liveInviteTitle.
  ///
  /// In tr, this message translates to:
  /// **'Canlı paylaşım daveti'**
  String get liveInviteTitle;

  /// No description provided for @liveInviteCanEdit.
  ///
  /// In tr, this message translates to:
  /// **'Belgeyi görürsünüz; paylaşan kalemi verince siz de yazabilirsiniz. Paylaşım bitince belge bu cihazda kalmaz.'**
  String get liveInviteCanEdit;

  /// No description provided for @liveInviteViewOnly.
  ///
  /// In tr, this message translates to:
  /// **'Belgeyi yalnız görürsünüz. Paylaşım bitince belge bu cihazda kalmaz.'**
  String get liveInviteViewOnly;

  /// No description provided for @liveBusyConnecting.
  ///
  /// In tr, this message translates to:
  /// **'Şu an başka bir bağlantı kuruluyor.'**
  String get liveBusyConnecting;

  /// No description provided for @liveHostUnverified.
  ///
  /// In tr, this message translates to:
  /// **'Davet eden cihaz doğrulanamadı.'**
  String get liveHostUnverified;

  /// No description provided for @liveDocumentDidNotCome.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşan kabul etti ama belge gelmedi.'**
  String get liveDocumentDidNotCome;

  /// No description provided for @liveSomeUser.
  ///
  /// In tr, this message translates to:
  /// **'Bir Folio kullanıcısı'**
  String get liveSomeUser;

  /// No description provided for @liveHostWithdrew.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşan daveti geri aldı.'**
  String get liveHostWithdrew;

  /// No description provided for @liveConnectFailed.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı kurulamadı.'**
  String get liveConnectFailed;

  /// No description provided for @liveOpeningDocument.
  ///
  /// In tr, this message translates to:
  /// **'Belge açılıyor…'**
  String get liveOpeningDocument;

  /// No description provided for @liveConnectingHost.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşanın cihazına bağlanılıyor…'**
  String get liveConnectingHost;

  /// No description provided for @liveGuestCodeNote.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşanın ekranında da bu kod görünür. Belge yalnız bu paylaşım sürerken görünür; paylaşım bitince bu cihazda kalmaz.'**
  String get liveGuestCodeNote;

  /// No description provided for @tbAddColumn.
  ///
  /// In tr, this message translates to:
  /// **'Sütun ekle'**
  String get tbAddColumn;

  /// No description provided for @tbAddRow.
  ///
  /// In tr, this message translates to:
  /// **'Satır ekle'**
  String get tbAddRow;

  /// No description provided for @tbAlignCenter.
  ///
  /// In tr, this message translates to:
  /// **'Ortala · Ctrl+E'**
  String get tbAlignCenter;

  /// No description provided for @tbAlignLeft.
  ///
  /// In tr, this message translates to:
  /// **'Sola hizala · Ctrl+L'**
  String get tbAlignLeft;

  /// No description provided for @tbAlignRight.
  ///
  /// In tr, this message translates to:
  /// **'Sağa hizala · Ctrl+R'**
  String get tbAlignRight;

  /// No description provided for @tbAllFormatting.
  ///
  /// In tr, this message translates to:
  /// **'Tüm biçimlendirme araçları…'**
  String get tbAllFormatting;

  /// No description provided for @tbAllPages.
  ///
  /// In tr, this message translates to:
  /// **'Tüm sayfalar ({count})'**
  String tbAllPages(int count);

  /// No description provided for @tbApply.
  ///
  /// In tr, this message translates to:
  /// **'Uygula'**
  String get tbApply;

  /// No description provided for @tbAttachToEmail.
  ///
  /// In tr, this message translates to:
  /// **'E-postaya ekle'**
  String get tbAttachToEmail;

  /// No description provided for @tbAttachToEmailHelp.
  ///
  /// In tr, this message translates to:
  /// **'Ekli yeni ileti açılır'**
  String get tbAttachToEmailHelp;

  /// No description provided for @tbBlue.
  ///
  /// In tr, this message translates to:
  /// **'Mavi'**
  String get tbBlue;

  /// No description provided for @tbBold.
  ///
  /// In tr, this message translates to:
  /// **'Kalın · Ctrl+B'**
  String get tbBold;

  /// No description provided for @tbBoldLabel.
  ///
  /// In tr, this message translates to:
  /// **'Kalın'**
  String get tbBoldLabel;

  /// No description provided for @tbBullets.
  ///
  /// In tr, this message translates to:
  /// **'Madde işaretleri · Ctrl+Shift+L'**
  String get tbBullets;

  /// No description provided for @tbCancel.
  ///
  /// In tr, this message translates to:
  /// **'Vazgeç'**
  String get tbCancel;

  /// No description provided for @tbChooseFolder.
  ///
  /// In tr, this message translates to:
  /// **'Klasör seç'**
  String get tbChooseFolder;

  /// No description provided for @tbChoosePageToPrint.
  ///
  /// In tr, this message translates to:
  /// **'Yazdırılacak sayfayı seçin.'**
  String get tbChoosePageToPrint;

  /// No description provided for @tbChooseTargetFolder.
  ///
  /// In tr, this message translates to:
  /// **'Gönderilecek klasörü seçin'**
  String get tbChooseTargetFolder;

  /// No description provided for @tbClearFormatting.
  ///
  /// In tr, this message translates to:
  /// **'Karakter biçimini temizle'**
  String get tbClearFormatting;

  /// No description provided for @tbClose.
  ///
  /// In tr, this message translates to:
  /// **'Kapat'**
  String get tbClose;

  /// No description provided for @tbCollate.
  ///
  /// In tr, this message translates to:
  /// **'Harmanla'**
  String get tbCollate;

  /// No description provided for @tbConvertToPdf.
  ///
  /// In tr, this message translates to:
  /// **'PDF’e dönüştür'**
  String get tbConvertToPdf;

  /// No description provided for @tbCopiedTo.
  ///
  /// In tr, this message translates to:
  /// **'Kopyalandı: {target}'**
  String tbCopiedTo(String target);

  /// No description provided for @tbCopiesLabel.
  ///
  /// In tr, this message translates to:
  /// **'kopya'**
  String get tbCopiesLabel;

  /// No description provided for @tbCopyFile.
  ///
  /// In tr, this message translates to:
  /// **'Dosyayı kopyala'**
  String get tbCopyFile;

  /// No description provided for @tbCopyFileHelp.
  ///
  /// In tr, this message translates to:
  /// **'E-postaya, sohbete veya klasöre yapıştırın'**
  String get tbCopyFileHelp;

  /// No description provided for @tbCopyToFolder.
  ///
  /// In tr, this message translates to:
  /// **'Klasöre kopyala'**
  String get tbCopyToFolder;

  /// No description provided for @tbCopyToFolderHelp.
  ///
  /// In tr, this message translates to:
  /// **'USB bellek veya başka bir klasör seçin'**
  String get tbCopyToFolderHelp;

  /// No description provided for @tbCurrentPage.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli sayfa ({page})'**
  String tbCurrentPage(int page);

  /// No description provided for @tbCustomSize.
  ///
  /// In tr, this message translates to:
  /// **'Özel punto…'**
  String get tbCustomSize;

  /// No description provided for @tbDefaultLetterheadName.
  ///
  /// In tr, this message translates to:
  /// **'Antetim'**
  String get tbDefaultLetterheadName;

  /// No description provided for @tbDelete.
  ///
  /// In tr, this message translates to:
  /// **'Sil'**
  String get tbDelete;

  /// No description provided for @tbDeleteColumn.
  ///
  /// In tr, this message translates to:
  /// **'Sütunu sil'**
  String get tbDeleteColumn;

  /// No description provided for @tbDeleteRow.
  ///
  /// In tr, this message translates to:
  /// **'Satırı sil'**
  String get tbDeleteRow;

  /// No description provided for @tbDeleteTable.
  ///
  /// In tr, this message translates to:
  /// **'Tabloyu sil'**
  String get tbDeleteTable;

  /// No description provided for @tbDictate.
  ///
  /// In tr, this message translates to:
  /// **'Sesli yaz'**
  String get tbDictate;

  /// No description provided for @tbDictateShortTip.
  ///
  /// In tr, this message translates to:
  /// **'Sesli yaz · söylediğiniz imlecin yerine yazılır'**
  String get tbDictateShortTip;

  /// No description provided for @tbDictateTip.
  ///
  /// In tr, this message translates to:
  /// **'Söylediğinizi imlecin yerine yazar'**
  String get tbDictateTip;

  /// No description provided for @tbDocumentHistory.
  ///
  /// In tr, this message translates to:
  /// **'Belge geçmişi'**
  String get tbDocumentHistory;

  /// No description provided for @tbDrawBorders.
  ///
  /// In tr, this message translates to:
  /// **'Çerçeve çiz'**
  String get tbDrawBorders;

  /// No description provided for @tbEvenPagesOnly.
  ///
  /// In tr, this message translates to:
  /// **'Yalnız çift sayfalar'**
  String get tbEvenPagesOnly;

  /// No description provided for @tbFile.
  ///
  /// In tr, this message translates to:
  /// **'Dosya'**
  String get tbFile;

  /// No description provided for @tbFileCopied.
  ///
  /// In tr, this message translates to:
  /// **'Dosya kopyalandı. Hedef uygulamaya yapıştırabilirsiniz.'**
  String get tbFileCopied;

  /// No description provided for @tbFileMenu.
  ///
  /// In tr, this message translates to:
  /// **'Dosya menüsü'**
  String get tbFileMenu;

  /// No description provided for @tbFind.
  ///
  /// In tr, this message translates to:
  /// **'Bul'**
  String get tbFind;

  /// No description provided for @tbFindInDocument.
  ///
  /// In tr, this message translates to:
  /// **'Belgede bul · Ctrl+F'**
  String get tbFindInDocument;

  /// No description provided for @tbFindReplace.
  ///
  /// In tr, this message translates to:
  /// **'Bul ve değiştir · Ctrl+H'**
  String get tbFindReplace;

  /// No description provided for @tbFirstPageOnly.
  ///
  /// In tr, this message translates to:
  /// **'Yalnız ilk sayfada'**
  String get tbFirstPageOnly;

  /// No description provided for @tbFirstPageOnlyHelp.
  ///
  /// In tr, this message translates to:
  /// **'Kapalıyken antet her sayfanın başında basılır.'**
  String get tbFirstPageOnlyHelp;

  /// No description provided for @tbFont.
  ///
  /// In tr, this message translates to:
  /// **'Yazı tipi'**
  String get tbFont;

  /// No description provided for @tbFontCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} yazı tipi · Sistem ve belge yazı tipleri'**
  String tbFontCount(int count);

  /// No description provided for @tbFontSizePoints.
  ///
  /// In tr, this message translates to:
  /// **'Yazı boyutu (punto)'**
  String get tbFontSizePoints;

  /// No description provided for @tbFontSizeTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yazı boyutu'**
  String get tbFontSizeTitle;

  /// No description provided for @tbFooter.
  ///
  /// In tr, this message translates to:
  /// **'Alt bilgi'**
  String get tbFooter;

  /// No description provided for @tbGreen.
  ///
  /// In tr, this message translates to:
  /// **'Yeşil'**
  String get tbGreen;

  /// No description provided for @tbGrey.
  ///
  /// In tr, this message translates to:
  /// **'Gri'**
  String get tbGrey;

  /// No description provided for @tbGridlinesNotPrinted.
  ///
  /// In tr, this message translates to:
  /// **'kılavuz çizgiler yazdırılmaz'**
  String get tbGridlinesNotPrinted;

  /// No description provided for @tbGroupEditing.
  ///
  /// In tr, this message translates to:
  /// **'Düzenleme'**
  String get tbGroupEditing;

  /// No description provided for @tbGroupHistory.
  ///
  /// In tr, this message translates to:
  /// **'Geçmiş'**
  String get tbGroupHistory;

  /// No description provided for @tbGroupInsert.
  ///
  /// In tr, this message translates to:
  /// **'Ekle'**
  String get tbGroupInsert;

  /// No description provided for @tbGroupParagraph.
  ///
  /// In tr, this message translates to:
  /// **'Paragraf'**
  String get tbGroupParagraph;

  /// No description provided for @tbGroupStyle.
  ///
  /// In tr, this message translates to:
  /// **'Stil'**
  String get tbGroupStyle;

  /// No description provided for @tbGroupView.
  ///
  /// In tr, this message translates to:
  /// **'Görünüm'**
  String get tbGroupView;

  /// No description provided for @tbGroupVoice.
  ///
  /// In tr, this message translates to:
  /// **'Ses'**
  String get tbGroupVoice;

  /// No description provided for @tbGrowFont.
  ///
  /// In tr, this message translates to:
  /// **'Yazıyı büyüt'**
  String get tbGrowFont;

  /// No description provided for @tbHeader.
  ///
  /// In tr, this message translates to:
  /// **'Üst bilgi'**
  String get tbHeader;

  /// No description provided for @tbHeaderFooter.
  ///
  /// In tr, this message translates to:
  /// **'Üst bilgi ve alt bilgi'**
  String get tbHeaderFooter;

  /// No description provided for @tbHeaderFooterShort.
  ///
  /// In tr, this message translates to:
  /// **'Üst/alt bilgi'**
  String get tbHeaderFooterShort;

  /// No description provided for @tbHorizontalRuler.
  ///
  /// In tr, this message translates to:
  /// **'Yatay cetvel'**
  String get tbHorizontalRuler;

  /// No description provided for @tbHowToUsePage.
  ///
  /// In tr, this message translates to:
  /// **'Bu sayfa nasıl kullanılır?'**
  String get tbHowToUsePage;

  /// No description provided for @tbImageColumn25.
  ///
  /// In tr, this message translates to:
  /// **'Sütunun %25\'i'**
  String get tbImageColumn25;

  /// No description provided for @tbImageColumn33.
  ///
  /// In tr, this message translates to:
  /// **'Sütunun %33\'ü'**
  String get tbImageColumn33;

  /// No description provided for @tbImageColumn75.
  ///
  /// In tr, this message translates to:
  /// **'Sütunun %75\'i'**
  String get tbImageColumn75;

  /// No description provided for @tbImageColumnWidth.
  ///
  /// In tr, this message translates to:
  /// **'Sütun genişliği'**
  String get tbImageColumnWidth;

  /// No description provided for @tbImageHalfColumn.
  ///
  /// In tr, this message translates to:
  /// **'Yarım sütun'**
  String get tbImageHalfColumn;

  /// No description provided for @tbImageOriginalSize.
  ///
  /// In tr, this message translates to:
  /// **'Özgün boyut'**
  String get tbImageOriginalSize;

  /// No description provided for @tbImageUndrawable.
  ///
  /// In tr, this message translates to:
  /// **'〔Görsel çizilemedi — kaydetmede korunur〕'**
  String get tbImageUndrawable;

  /// No description provided for @tbImageUnreadable.
  ///
  /// In tr, this message translates to:
  /// **'〔Görsel okunamadı — kaydetmede korunur〕'**
  String get tbImageUnreadable;

  /// No description provided for @tbImageWidth.
  ///
  /// In tr, this message translates to:
  /// **'Görsel genişliği'**
  String get tbImageWidth;

  /// No description provided for @tbInNewDocuments.
  ///
  /// In tr, this message translates to:
  /// **'Yeni belgelerde'**
  String get tbInNewDocuments;

  /// No description provided for @tbIndentDecrease.
  ///
  /// In tr, this message translates to:
  /// **'Girintiyi azalt · Ctrl+Shift+M'**
  String get tbIndentDecrease;

  /// No description provided for @tbIndentIncrease.
  ///
  /// In tr, this message translates to:
  /// **'Girintiyi artır · Ctrl+M'**
  String get tbIndentIncrease;

  /// No description provided for @tbInsertTable.
  ///
  /// In tr, this message translates to:
  /// **'Tablo ekle'**
  String get tbInsertTable;

  /// No description provided for @tbItalic.
  ///
  /// In tr, this message translates to:
  /// **'İtalik · Ctrl+I'**
  String get tbItalic;

  /// No description provided for @tbJustify.
  ///
  /// In tr, this message translates to:
  /// **'İki yana yasla · Ctrl+J'**
  String get tbJustify;

  /// No description provided for @tbKeyboardShortcuts.
  ///
  /// In tr, this message translates to:
  /// **'Klavye kısayolları'**
  String get tbKeyboardShortcuts;

  /// No description provided for @tbLetterheadMenu.
  ///
  /// In tr, this message translates to:
  /// **'Antet…'**
  String get tbLetterheadMenu;

  /// No description provided for @tbLetterheads.
  ///
  /// In tr, this message translates to:
  /// **'Antetler'**
  String get tbLetterheads;

  /// No description provided for @tbLightGrey.
  ///
  /// In tr, this message translates to:
  /// **'Açık gri'**
  String get tbLightGrey;

  /// No description provided for @tbLineSpacing.
  ///
  /// In tr, this message translates to:
  /// **'Satır aralığı'**
  String get tbLineSpacing;

  /// No description provided for @tbLineSpacingValue.
  ///
  /// In tr, this message translates to:
  /// **'{value} satır'**
  String tbLineSpacingValue(String value);

  /// No description provided for @tbLiveShare.
  ///
  /// In tr, this message translates to:
  /// **'Canlı paylaş…'**
  String get tbLiveShare;

  /// No description provided for @tbMixed.
  ///
  /// In tr, this message translates to:
  /// **'Karışık'**
  String get tbMixed;

  /// No description provided for @tbMore.
  ///
  /// In tr, this message translates to:
  /// **'Diğer'**
  String get tbMore;

  /// No description provided for @tbMoreTools.
  ///
  /// In tr, this message translates to:
  /// **'Diğer düzenleme araçları'**
  String get tbMoreTools;

  /// No description provided for @tbName.
  ///
  /// In tr, this message translates to:
  /// **'Adı'**
  String get tbName;

  /// No description provided for @tbNewDocument.
  ///
  /// In tr, this message translates to:
  /// **'Yeni belge'**
  String get tbNewDocument;

  /// No description provided for @tbNewWindow.
  ///
  /// In tr, this message translates to:
  /// **'Yeni pencere'**
  String get tbNewWindow;

  /// No description provided for @tbNextPage.
  ///
  /// In tr, this message translates to:
  /// **'Sonraki sayfa'**
  String get tbNextPage;

  /// No description provided for @tbNoFill.
  ///
  /// In tr, this message translates to:
  /// **'Dolgu yok'**
  String get tbNoFill;

  /// No description provided for @tbNoFontFound.
  ///
  /// In tr, this message translates to:
  /// **'Yazı tipi bulunamadı'**
  String get tbNoFontFound;

  /// No description provided for @tbNoLetterheads.
  ///
  /// In tr, this message translates to:
  /// **'Henüz antet yok. Anteti belgenin üst bilgisinde tasarlayın: yazı, hizalama ve Ekle › Görsel ile logo. Sonra aşağıdan antet olarak kaydedin; her belgeye tek tıkla eklenir.'**
  String get tbNoLetterheads;

  /// No description provided for @tbNoRecentDocuments.
  ///
  /// In tr, this message translates to:
  /// **'Henüz açılmış belge yok'**
  String get tbNoRecentDocuments;

  /// No description provided for @tbNormalText.
  ///
  /// In tr, this message translates to:
  /// **'Normal metin'**
  String get tbNormalText;

  /// No description provided for @tbNotPrinted.
  ///
  /// In tr, this message translates to:
  /// **'Yazdırılmayacak'**
  String get tbNotPrinted;

  /// No description provided for @tbNumbering.
  ///
  /// In tr, this message translates to:
  /// **'Numaralı liste · Ctrl+Shift+7'**
  String get tbNumbering;

  /// No description provided for @tbOddAndEvenPages.
  ///
  /// In tr, this message translates to:
  /// **'Tek ve çift sayfalar'**
  String get tbOddAndEvenPages;

  /// No description provided for @tbOddPagesOnly.
  ///
  /// In tr, this message translates to:
  /// **'Yalnız tek sayfalar'**
  String get tbOddPagesOnly;

  /// No description provided for @tbOk.
  ///
  /// In tr, this message translates to:
  /// **'Tamam'**
  String get tbOk;

  /// No description provided for @tbOneCopyFewer.
  ///
  /// In tr, this message translates to:
  /// **'Bir kopya az'**
  String get tbOneCopyFewer;

  /// No description provided for @tbOneCopyMore.
  ///
  /// In tr, this message translates to:
  /// **'Bir kopya fazla'**
  String get tbOneCopyMore;

  /// No description provided for @tbOpen.
  ///
  /// In tr, this message translates to:
  /// **'Aç…'**
  String get tbOpen;

  /// No description provided for @tbPageNumber.
  ///
  /// In tr, this message translates to:
  /// **'Sayfa numarası'**
  String get tbPageNumber;

  /// No description provided for @tbPageNumberBottom.
  ///
  /// In tr, this message translates to:
  /// **'Altta'**
  String get tbPageNumberBottom;

  /// No description provided for @tbPageNumberCenter.
  ///
  /// In tr, this message translates to:
  /// **'Orta'**
  String get tbPageNumberCenter;

  /// No description provided for @tbPageNumberFont.
  ///
  /// In tr, this message translates to:
  /// **'Yazı'**
  String get tbPageNumberFont;

  /// No description provided for @tbPageNumberFormat.
  ///
  /// In tr, this message translates to:
  /// **'Biçimi'**
  String get tbPageNumberFormat;

  /// No description provided for @tbPageNumberInFooter.
  ///
  /// In tr, this message translates to:
  /// **'Alt bilgide'**
  String get tbPageNumberInFooter;

  /// No description provided for @tbPageNumberInHeader.
  ///
  /// In tr, this message translates to:
  /// **'Üst bilgide'**
  String get tbPageNumberInHeader;

  /// No description provided for @tbPageNumberLeft.
  ///
  /// In tr, this message translates to:
  /// **'Sol'**
  String get tbPageNumberLeft;

  /// No description provided for @tbPageNumberMenu.
  ///
  /// In tr, this message translates to:
  /// **'Sayfa numarası…'**
  String get tbPageNumberMenu;

  /// No description provided for @tbPageNumberNone.
  ///
  /// In tr, this message translates to:
  /// **'Yok'**
  String get tbPageNumberNone;

  /// No description provided for @tbPageNumberPosition.
  ///
  /// In tr, this message translates to:
  /// **'Yeri'**
  String get tbPageNumberPosition;

  /// No description provided for @tbPageNumberPrefix.
  ///
  /// In tr, this message translates to:
  /// **'Ön metin'**
  String get tbPageNumberPrefix;

  /// No description provided for @tbPageNumberPrefixHint.
  ///
  /// In tr, this message translates to:
  /// **'Sayfa '**
  String get tbPageNumberPrefixHint;

  /// No description provided for @tbPageNumberRight.
  ///
  /// In tr, this message translates to:
  /// **'Sağ'**
  String get tbPageNumberRight;

  /// No description provided for @tbPageNumberSkipFirst.
  ///
  /// In tr, this message translates to:
  /// **'İlk sayfada gösterme'**
  String get tbPageNumberSkipFirst;

  /// No description provided for @tbPageNumberSkipSingle.
  ///
  /// In tr, this message translates to:
  /// **'Tek sayfaysa gösterme'**
  String get tbPageNumberSkipSingle;

  /// No description provided for @tbPageNumberStart.
  ///
  /// In tr, this message translates to:
  /// **'İlk numara'**
  String get tbPageNumberStart;

  /// No description provided for @tbPageNumberTop.
  ///
  /// In tr, this message translates to:
  /// **'Üstte'**
  String get tbPageNumberTop;

  /// No description provided for @tbPageNumberWithTotal.
  ///
  /// In tr, this message translates to:
  /// **'Toplam sayfayla'**
  String get tbPageNumberWithTotal;

  /// No description provided for @tbPageRange.
  ///
  /// In tr, this message translates to:
  /// **'Sayfa aralığı'**
  String get tbPageRange;

  /// No description provided for @tbPageRangeHint.
  ///
  /// In tr, this message translates to:
  /// **'ör. 1-3, 5, 8-'**
  String get tbPageRangeHint;

  /// No description provided for @tbPageRangeInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Belgede {count} sayfa var; aralığı kontrol edin.'**
  String tbPageRangeInvalid(int count);

  /// No description provided for @tbPages.
  ///
  /// In tr, this message translates to:
  /// **'Sayfalar'**
  String get tbPages;

  /// No description provided for @tbParagraphStyle.
  ///
  /// In tr, this message translates to:
  /// **'Paragraf stili'**
  String get tbParagraphStyle;

  /// No description provided for @tbPdfPrepareFailed.
  ///
  /// In tr, this message translates to:
  /// **'PDF hazırlanamadı: {error}'**
  String tbPdfPrepareFailed(String error);

  /// No description provided for @tbPdfSaveFailed.
  ///
  /// In tr, this message translates to:
  /// **'PDF kaydedilemedi'**
  String get tbPdfSaveFailed;

  /// No description provided for @tbPdfSaved.
  ///
  /// In tr, this message translates to:
  /// **'PDF kaydedildi'**
  String get tbPdfSaved;

  /// No description provided for @tbPickSize.
  ///
  /// In tr, this message translates to:
  /// **'Boyut seçin'**
  String get tbPickSize;

  /// No description provided for @tbPicture.
  ///
  /// In tr, this message translates to:
  /// **'Görsel'**
  String get tbPicture;

  /// No description provided for @tbPageBreakMenu.
  ///
  /// In tr, this message translates to:
  /// **'Sayfa sonu (Ctrl+Enter)'**
  String get tbPageBreakMenu;

  /// No description provided for @tbPointSize.
  ///
  /// In tr, this message translates to:
  /// **'Punto'**
  String get tbPointSize;

  /// No description provided for @tbPointSizeHelp.
  ///
  /// In tr, this message translates to:
  /// **'1–200 arasında, örneğin 10,5'**
  String get tbPointSizeHelp;

  /// No description provided for @tbPreviewFailed.
  ///
  /// In tr, this message translates to:
  /// **'Önizleme açılamadı: {error}'**
  String tbPreviewFailed(String error);

  /// No description provided for @tbPreviousPage.
  ///
  /// In tr, this message translates to:
  /// **'Önceki sayfa'**
  String get tbPreviousPage;

  /// No description provided for @tbPrint.
  ///
  /// In tr, this message translates to:
  /// **'Yazdır'**
  String get tbPrint;

  /// No description provided for @tbPrintFailed.
  ///
  /// In tr, this message translates to:
  /// **'Yazdırılamadı'**
  String get tbPrintFailed;

  /// No description provided for @tbPrintShortcut.
  ///
  /// In tr, this message translates to:
  /// **'Yazdır · Ctrl+P'**
  String get tbPrintShortcut;

  /// No description provided for @tbPrintSummary.
  ///
  /// In tr, this message translates to:
  /// **'{pages} sayfa · {sheets} yaprak A4'**
  String tbPrintSummary(int pages, int sheets);

  /// No description provided for @tbPrintSummaryCopies.
  ///
  /// In tr, this message translates to:
  /// **'{pages} sayfa × {copies} kopya · {sheets} yaprak A4'**
  String tbPrintSummaryCopies(int pages, int copies, int sheets);

  /// No description provided for @tbPrinter.
  ///
  /// In tr, this message translates to:
  /// **'Yazıcı'**
  String get tbPrinter;

  /// No description provided for @tbPrinterDefault.
  ///
  /// In tr, this message translates to:
  /// **'{name}  (varsayılan)'**
  String tbPrinterDefault(String name);

  /// No description provided for @tbPrinterInSystemDialog.
  ///
  /// In tr, this message translates to:
  /// **'Yazıcıyı sistemin yazdırma penceresinde seçeceksiniz.'**
  String get tbPrinterInSystemDialog;

  /// No description provided for @tbProtectedContent.
  ///
  /// In tr, this message translates to:
  /// **'〔Korunan içerik — kaydetmede korunur〕'**
  String get tbProtectedContent;

  /// No description provided for @tbReadAloud.
  ///
  /// In tr, this message translates to:
  /// **'Sesli oku'**
  String get tbReadAloud;

  /// No description provided for @tbReadAloudShortTip.
  ///
  /// In tr, this message translates to:
  /// **'Sesli oku · seçimi ya da imleçten sonrasını'**
  String get tbReadAloudShortTip;

  /// No description provided for @tbReadAloudTip.
  ///
  /// In tr, this message translates to:
  /// **'Seçimi ya da imleçten sonrasını okur'**
  String get tbReadAloudTip;

  /// No description provided for @tbRecent.
  ///
  /// In tr, this message translates to:
  /// **'Son açılanlar'**
  String get tbRecent;

  /// No description provided for @tbRecoverableDrafts.
  ///
  /// In tr, this message translates to:
  /// **'Kurtarılabilir taslaklar'**
  String get tbRecoverableDrafts;

  /// No description provided for @tbRed.
  ///
  /// In tr, this message translates to:
  /// **'Kırmızı'**
  String get tbRed;

  /// No description provided for @tbRedo.
  ///
  /// In tr, this message translates to:
  /// **'Yinele · Ctrl+Y'**
  String get tbRedo;

  /// No description provided for @tbRemoveBorders.
  ///
  /// In tr, this message translates to:
  /// **'Çerçeveyi kaldır'**
  String get tbRemoveBorders;

  /// No description provided for @tbRename.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden adlandır'**
  String get tbRename;

  /// No description provided for @tbRenameLetterhead.
  ///
  /// In tr, this message translates to:
  /// **'Anteti yeniden adlandır'**
  String get tbRenameLetterhead;

  /// No description provided for @tbReplace.
  ///
  /// In tr, this message translates to:
  /// **'Değiştir'**
  String get tbReplace;

  /// No description provided for @tbReplaceLetterheadBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu adla kayıtlı antet, belgenin üst bilgisiyle değiştirilecek.'**
  String get tbReplaceLetterheadBody;

  /// No description provided for @tbReplaceLetterheadTitle.
  ///
  /// In tr, this message translates to:
  /// **'\"{name}\" değiştirilsin mi?'**
  String tbReplaceLetterheadTitle(String name);

  /// No description provided for @tbRibbonTip.
  ///
  /// In tr, this message translates to:
  /// **'Şerit: {tab}'**
  String tbRibbonTip(String tab);

  /// No description provided for @tbSample.
  ///
  /// In tr, this message translates to:
  /// **'Örnek: {sample}'**
  String tbSample(String sample);

  /// No description provided for @tbSave.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet'**
  String get tbSave;

  /// No description provided for @tbSaveAs.
  ///
  /// In tr, this message translates to:
  /// **'Farklı kaydet…'**
  String get tbSaveAs;

  /// No description provided for @tbSaveAsDocx.
  ///
  /// In tr, this message translates to:
  /// **'Word (DOCX) Olarak Kaydet'**
  String get tbSaveAsDocx;

  /// No description provided for @tbSaveAsPdf.
  ///
  /// In tr, this message translates to:
  /// **'PDF olarak kaydet'**
  String get tbSaveAsPdf;

  /// No description provided for @tbSaveAsRtf.
  ///
  /// In tr, this message translates to:
  /// **'Zengin Metin (RTF) Olarak Kaydet'**
  String get tbSaveAsRtf;

  /// No description provided for @tbSaveAsUdf.
  ///
  /// In tr, this message translates to:
  /// **'UYAP UDF Olarak Kaydet'**
  String get tbSaveAsUdf;

  /// No description provided for @tbSaveFolderBody.
  ///
  /// In tr, this message translates to:
  /// **'Bir kez seçersiniz; sonra Kaydet doğrudan oraya yazar. İmzaladığınız belgeler de oraya kaydedilir.'**
  String get tbSaveFolderBody;

  /// No description provided for @tbSaveFolderTitle.
  ///
  /// In tr, this message translates to:
  /// **'Belgeler nereye kaydedilsin?'**
  String get tbSaveFolderTitle;

  /// No description provided for @tbSaveHeaderAsLetterhead.
  ///
  /// In tr, this message translates to:
  /// **'Üst bilgiyi antet olarak kaydet'**
  String get tbSaveHeaderAsLetterhead;

  /// No description provided for @tbSaveHeaderAsLetterheadEllipsis.
  ///
  /// In tr, this message translates to:
  /// **'Üst bilgiyi antet olarak kaydet…'**
  String get tbSaveHeaderAsLetterheadEllipsis;

  /// No description provided for @tbSaveSelectedPagesPdf.
  ///
  /// In tr, this message translates to:
  /// **'Seçili sayfaları PDF olarak kaydet'**
  String get tbSaveSelectedPagesPdf;

  /// No description provided for @tbSavedCopyUsed.
  ///
  /// In tr, this message translates to:
  /// **'Diskte kayıtlı belge kullanılır.'**
  String get tbSavedCopyUsed;

  /// No description provided for @tbSearchFonts.
  ///
  /// In tr, this message translates to:
  /// **'Yazı tipi ara…'**
  String get tbSearchFonts;

  /// No description provided for @tbSelectWholeTable.
  ///
  /// In tr, this message translates to:
  /// **'Tüm tabloyu seç'**
  String get tbSelectWholeTable;

  /// No description provided for @tbShadeCell.
  ///
  /// In tr, this message translates to:
  /// **'Hücreyi boya'**
  String get tbShadeCell;

  /// No description provided for @tbShadeTable.
  ///
  /// In tr, this message translates to:
  /// **'Tabloyu boya'**
  String get tbShadeTable;

  /// No description provided for @tbShare.
  ///
  /// In tr, this message translates to:
  /// **'Paylaş'**
  String get tbShare;

  /// No description provided for @tbShareAsKind.
  ///
  /// In tr, this message translates to:
  /// **'{kind} olarak paylaş'**
  String tbShareAsKind(String kind);

  /// No description provided for @tbShareAsPdf.
  ///
  /// In tr, this message translates to:
  /// **'PDF olarak paylaş'**
  String get tbShareAsPdf;

  /// No description provided for @tbShareAsPdfHelp.
  ///
  /// In tr, this message translates to:
  /// **'Her telefonda ve bilgisayarda açılır'**
  String get tbShareAsPdfHelp;

  /// No description provided for @tbShareEllipsis.
  ///
  /// In tr, this message translates to:
  /// **'Paylaş…'**
  String get tbShareEllipsis;

  /// No description provided for @tbShareFailed.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşılamadı: {error}'**
  String tbShareFailed(String error);

  /// No description provided for @tbShareMacHelp.
  ///
  /// In tr, this message translates to:
  /// **'AirDrop, Mesajlar ve yüklü uygulamalar'**
  String get tbShareMacHelp;

  /// No description provided for @tbShareOriginalHelp.
  ///
  /// In tr, this message translates to:
  /// **'Dosyanın kendisi, olduğu gibi'**
  String get tbShareOriginalHelp;

  /// No description provided for @tbShareSend.
  ///
  /// In tr, this message translates to:
  /// **'Paylaş / Gönder'**
  String get tbShareSend;

  /// No description provided for @tbShareWindowsHelp.
  ///
  /// In tr, this message translates to:
  /// **'Yüklü paylaşım uygulamalarından seçin'**
  String get tbShareWindowsHelp;

  /// No description provided for @tbShareWithWindows.
  ///
  /// In tr, this message translates to:
  /// **'Windows ile paylaş'**
  String get tbShareWithWindows;

  /// No description provided for @tbShortcuts.
  ///
  /// In tr, this message translates to:
  /// **'Kısayollar'**
  String get tbShortcuts;

  /// No description provided for @tbShrinkFont.
  ///
  /// In tr, this message translates to:
  /// **'Yazıyı küçült'**
  String get tbShrinkFont;

  /// No description provided for @tbSignUdf.
  ///
  /// In tr, this message translates to:
  /// **'UDF e-imzala'**
  String get tbSignUdf;

  /// No description provided for @tbSnippets.
  ///
  /// In tr, this message translates to:
  /// **'Kalıp metin'**
  String get tbSnippets;

  /// No description provided for @tbSnippetsShortcut.
  ///
  /// In tr, this message translates to:
  /// **'Kalıp metin · Ctrl+Boşluk'**
  String get tbSnippetsShortcut;

  /// No description provided for @tbStrikethrough.
  ///
  /// In tr, this message translates to:
  /// **'Üstü çizili'**
  String get tbStrikethrough;

  /// No description provided for @tbSubscript.
  ///
  /// In tr, this message translates to:
  /// **'Alt simge'**
  String get tbSubscript;

  /// No description provided for @tbSuperscript.
  ///
  /// In tr, this message translates to:
  /// **'Üst simge'**
  String get tbSuperscript;

  /// No description provided for @tbSystemPrintDialog.
  ///
  /// In tr, this message translates to:
  /// **'Sistemin yazdırma penceresi…'**
  String get tbSystemPrintDialog;

  /// No description provided for @tbTabHome.
  ///
  /// In tr, this message translates to:
  /// **'Giriş'**
  String get tbTabHome;

  /// No description provided for @tbTabInsert.
  ///
  /// In tr, this message translates to:
  /// **'Ekle'**
  String get tbTabInsert;

  /// No description provided for @tbTabResearch.
  ///
  /// In tr, this message translates to:
  /// **'Araştırma'**
  String get tbTabResearch;

  /// No description provided for @tbTabView.
  ///
  /// In tr, this message translates to:
  /// **'Görünüm'**
  String get tbTabView;

  /// No description provided for @tbTable.
  ///
  /// In tr, this message translates to:
  /// **'Tablo'**
  String get tbTable;

  /// No description provided for @tbTableSelectedRelease.
  ///
  /// In tr, this message translates to:
  /// **'Tablo seçili — bırak'**
  String get tbTableSelectedRelease;

  /// No description provided for @tbTableSize.
  ///
  /// In tr, this message translates to:
  /// **'{rows} × {columns} tablo'**
  String tbTableSize(int rows, int columns);

  /// No description provided for @tbTextAndParagraph.
  ///
  /// In tr, this message translates to:
  /// **'Yazı ve paragraf'**
  String get tbTextAndParagraph;

  /// No description provided for @tbUnderline.
  ///
  /// In tr, this message translates to:
  /// **'Altı çizili · Ctrl+U'**
  String get tbUnderline;

  /// No description provided for @tbUndo.
  ///
  /// In tr, this message translates to:
  /// **'Geri al · Ctrl+Z'**
  String get tbUndo;

  /// No description provided for @tbUseInNewDocuments.
  ///
  /// In tr, this message translates to:
  /// **'Yeni belgelerde kullan'**
  String get tbUseInNewDocuments;

  /// No description provided for @tbVerticalRuler.
  ///
  /// In tr, this message translates to:
  /// **'Dikey cetvel'**
  String get tbVerticalRuler;

  /// No description provided for @tbViewRulers.
  ///
  /// In tr, this message translates to:
  /// **'Görünüm ve cetveller'**
  String get tbViewRulers;

  /// No description provided for @tbYellow.
  ///
  /// In tr, this message translates to:
  /// **'Sarı'**
  String get tbYellow;

  /// No description provided for @viewClose.
  ///
  /// In tr, this message translates to:
  /// **'Kapat'**
  String get viewClose;

  /// No description provided for @viewCloseEsc.
  ///
  /// In tr, this message translates to:
  /// **'Kapat · Esc'**
  String get viewCloseEsc;

  /// No description provided for @viewCloseEscParen.
  ///
  /// In tr, this message translates to:
  /// **'Kapat (Esc)'**
  String get viewCloseEscParen;

  /// No description provided for @viewCancel.
  ///
  /// In tr, this message translates to:
  /// **'Vazgeç'**
  String get viewCancel;

  /// No description provided for @viewFirstPage.
  ///
  /// In tr, this message translates to:
  /// **'İlk Sayfa'**
  String get viewFirstPage;

  /// No description provided for @viewPreviousPage.
  ///
  /// In tr, this message translates to:
  /// **'Önceki Sayfa'**
  String get viewPreviousPage;

  /// No description provided for @viewNextPage.
  ///
  /// In tr, this message translates to:
  /// **'Sonraki Sayfa'**
  String get viewNextPage;

  /// No description provided for @viewLastPage.
  ///
  /// In tr, this message translates to:
  /// **'Son Sayfa'**
  String get viewLastPage;

  /// No description provided for @viewZoomIn.
  ///
  /// In tr, this message translates to:
  /// **'Yakınlaştır'**
  String get viewZoomIn;

  /// No description provided for @viewZoomOut.
  ///
  /// In tr, this message translates to:
  /// **'Uzaklaştır'**
  String get viewZoomOut;

  /// No description provided for @viewZoomInKey.
  ///
  /// In tr, this message translates to:
  /// **'Yakınlaştır (+)'**
  String get viewZoomInKey;

  /// No description provided for @viewZoomOutKey.
  ///
  /// In tr, this message translates to:
  /// **'Uzaklaştır (−)'**
  String get viewZoomOutKey;

  /// No description provided for @viewRotateLeft.
  ///
  /// In tr, this message translates to:
  /// **'Sola 90° döndür'**
  String get viewRotateLeft;

  /// No description provided for @viewRotateRight.
  ///
  /// In tr, this message translates to:
  /// **'Sağa 90° döndür'**
  String get viewRotateRight;

  /// No description provided for @viewRotateRightKey.
  ///
  /// In tr, this message translates to:
  /// **'Sağa 90° döndür (R)'**
  String get viewRotateRightKey;

  /// No description provided for @viewFit.
  ///
  /// In tr, this message translates to:
  /// **'Sığdır'**
  String get viewFit;

  /// No description provided for @viewFitKey.
  ///
  /// In tr, this message translates to:
  /// **'Sığdır (0)'**
  String get viewFitKey;

  /// No description provided for @viewPreviewFailed.
  ///
  /// In tr, this message translates to:
  /// **'Önizleme açılamadı: {error}'**
  String viewPreviewFailed(String error);

  /// No description provided for @viewHighlightSaveFailed.
  ///
  /// In tr, this message translates to:
  /// **'Vurgu kaydedilemedi'**
  String get viewHighlightSaveFailed;

  /// No description provided for @viewThisColor.
  ///
  /// In tr, this message translates to:
  /// **'Bu renk'**
  String get viewThisColor;

  /// No description provided for @viewChangeColor.
  ///
  /// In tr, this message translates to:
  /// **'Rengi değiştir'**
  String get viewChangeColor;

  /// No description provided for @viewDeleteHighlight.
  ///
  /// In tr, this message translates to:
  /// **'Vurguyu sil'**
  String get viewDeleteHighlight;

  /// No description provided for @viewFindInDocument.
  ///
  /// In tr, this message translates to:
  /// **'Belgede bul'**
  String get viewFindInDocument;

  /// No description provided for @viewFindKey.
  ///
  /// In tr, this message translates to:
  /// **'Belgede bul (Ctrl+F)'**
  String get viewFindKey;

  /// No description provided for @viewPixels.
  ///
  /// In tr, this message translates to:
  /// **'{width} × {height} piksel'**
  String viewPixels(int width, int height);

  /// No description provided for @viewSearching.
  ///
  /// In tr, this message translates to:
  /// **'aranıyor…'**
  String get viewSearching;

  /// No description provided for @viewNotFound.
  ///
  /// In tr, this message translates to:
  /// **'bulunamadı'**
  String get viewNotFound;

  /// No description provided for @viewPreviousMatch.
  ///
  /// In tr, this message translates to:
  /// **'Önceki · Shift+Enter'**
  String get viewPreviousMatch;

  /// No description provided for @viewNextMatch.
  ///
  /// In tr, this message translates to:
  /// **'Sonraki · Enter'**
  String get viewNextMatch;

  /// No description provided for @viewFitPage.
  ///
  /// In tr, this message translates to:
  /// **'Sayfaya sığdır'**
  String get viewFitPage;

  /// No description provided for @viewFitWidth.
  ///
  /// In tr, this message translates to:
  /// **'Genişliğe sığdır'**
  String get viewFitWidth;

  /// No description provided for @viewFreeZoom.
  ///
  /// In tr, this message translates to:
  /// **'Serbest yakınlaştırma'**
  String get viewFreeZoom;

  /// No description provided for @viewCitations.
  ///
  /// In tr, this message translates to:
  /// **'Dayanaklar · madde ve kararlar'**
  String get viewCitations;

  /// No description provided for @viewHighlightSelection.
  ///
  /// In tr, this message translates to:
  /// **'Seçimi vurgula'**
  String get viewHighlightSelection;

  /// No description provided for @viewSelectToHighlight.
  ///
  /// In tr, this message translates to:
  /// **'Vurgulamak için metin seçin'**
  String get viewSelectToHighlight;

  /// No description provided for @viewHighlightColor.
  ///
  /// In tr, this message translates to:
  /// **'Vurgu rengi'**
  String get viewHighlightColor;

  /// No description provided for @viewPageOpenFailed.
  ///
  /// In tr, this message translates to:
  /// **'Bu sayfa açılamadı.'**
  String get viewPageOpenFailed;

  /// No description provided for @viewPageOf.
  ///
  /// In tr, this message translates to:
  /// **'Sayfa {page} / {count}'**
  String viewPageOf(int page, int count);

  /// No description provided for @viewTifToPdf.
  ///
  /// In tr, this message translates to:
  /// **'TIF → PDF Dönüştür'**
  String get viewTifToPdf;

  /// No description provided for @viewHeicAndroidOnly.
  ///
  /// In tr, this message translates to:
  /// **'iPhone fotoğrafları (HEIC) şimdilik yalnız Android’de açılıyor.'**
  String get viewHeicAndroidOnly;

  /// No description provided for @viewPhotoDecodeFailed.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraf çözülemedi.'**
  String get viewPhotoDecodeFailed;

  /// No description provided for @viewCropFailed.
  ///
  /// In tr, this message translates to:
  /// **'Kırpılamadı'**
  String get viewCropFailed;

  /// No description provided for @viewCropUnmeasured.
  ///
  /// In tr, this message translates to:
  /// **'Bu görsel ölçülemedi, kırpılamıyor'**
  String get viewCropUnmeasured;

  /// No description provided for @viewCrop.
  ///
  /// In tr, this message translates to:
  /// **'Kırp'**
  String get viewCrop;

  /// No description provided for @viewFullScreenKey.
  ///
  /// In tr, this message translates to:
  /// **'Tam ekran (F, ya da çift tık)'**
  String get viewFullScreenKey;

  /// No description provided for @viewNextPhoto.
  ///
  /// In tr, this message translates to:
  /// **'Sonraki fotoğraf (→)'**
  String get viewNextPhoto;

  /// No description provided for @viewPreviousPhoto.
  ///
  /// In tr, this message translates to:
  /// **'Önceki fotoğraf (←)'**
  String get viewPreviousPhoto;

  /// No description provided for @viewCropDrag.
  ///
  /// In tr, this message translates to:
  /// **'Saklamak istediğiniz yeri sürükleyin'**
  String get viewCropDrag;

  /// No description provided for @viewCropKeepsOriginal.
  ///
  /// In tr, this message translates to:
  /// **'Aslı olduğu gibi kalır, kırpılan yanına kaydedilir'**
  String get viewCropKeepsOriginal;

  /// No description provided for @viewSvgOpenFailed.
  ///
  /// In tr, this message translates to:
  /// **'SVG açılamadı: {error}'**
  String viewSvgOpenFailed(String error);

  /// No description provided for @viewImageOpenFailed.
  ///
  /// In tr, this message translates to:
  /// **'Görsel açılamadı.'**
  String get viewImageOpenFailed;

  /// No description provided for @viewCopy.
  ///
  /// In tr, this message translates to:
  /// **'Kopyala'**
  String get viewCopy;

  /// No description provided for @viewReadAloud.
  ///
  /// In tr, this message translates to:
  /// **'Sesli oku'**
  String get viewReadAloud;

  /// No description provided for @viewSelectAll.
  ///
  /// In tr, this message translates to:
  /// **'Tümünü seç'**
  String get viewSelectAll;

  /// No description provided for @viewFormatNotPreviewable.
  ///
  /// In tr, this message translates to:
  /// **'Bu biçim önizlenemiyor.'**
  String get viewFormatNotPreviewable;

  /// No description provided for @viewImzSaveDialog.
  ///
  /// In tr, this message translates to:
  /// **'İmzalı belgenin içeriğini kaydet'**
  String get viewImzSaveDialog;

  /// No description provided for @viewDocumentSaved.
  ///
  /// In tr, this message translates to:
  /// **'Belge kaydedildi'**
  String get viewDocumentSaved;

  /// No description provided for @viewImzIdNumber.
  ///
  /// In tr, this message translates to:
  /// **'T.C. kimlik no: {id}'**
  String viewImzIdNumber(String id);

  /// No description provided for @viewImzSignedAt.
  ///
  /// In tr, this message translates to:
  /// **'İmza tarihi: {date}'**
  String viewImzSignedAt(String date);

  /// No description provided for @viewImzIssuer.
  ///
  /// In tr, this message translates to:
  /// **'Sertifikayı veren: {issuer}'**
  String viewImzIssuer(String issuer);

  /// No description provided for @viewImzUnnamedSigner.
  ///
  /// In tr, this message translates to:
  /// **'Adı okunamayan imzacı'**
  String get viewImzUnnamedSigner;

  /// No description provided for @viewImzValid.
  ///
  /// In tr, this message translates to:
  /// **'E-imza geçerli'**
  String get viewImzValid;

  /// No description provided for @viewImzInvalid.
  ///
  /// In tr, this message translates to:
  /// **'E-imza doğrulanamadı: belge imzadan sonra değişmiş olabilir'**
  String get viewImzInvalid;

  /// No description provided for @viewImzCheckedNote.
  ///
  /// In tr, this message translates to:
  /// **'İmza, içindeki belgeyle ve imzacının kendi sertifikasıyla denetlendi. Sertifikanın yetkili bir kuruluşça verildiği ve iptal edilmediği ayrıca denetlenmedi.'**
  String get viewImzCheckedNote;

  /// No description provided for @viewImzSaveDocument.
  ///
  /// In tr, this message translates to:
  /// **'Belgeyi kaydet…'**
  String get viewImzSaveDocument;

  /// No description provided for @viewImzUnreadable.
  ///
  /// In tr, this message translates to:
  /// **'Bu dosya okunamadı: içinde belge olan bir e-imza dosyası değil ya da bozuk.'**
  String get viewImzUnreadable;

  /// No description provided for @viewImzInsideNotShown.
  ///
  /// In tr, this message translates to:
  /// **'İçindeki belge ({name}) burada gösterilemiyor; kaydedip açabilirsiniz.'**
  String viewImzInsideNotShown(String name);

  /// No description provided for @viewOcrTitle.
  ///
  /// In tr, this message translates to:
  /// **'Arama için çıkarılan metin'**
  String get viewOcrTitle;

  /// No description provided for @viewOcrNote.
  ///
  /// In tr, this message translates to:
  /// **'Birebir çeviriyazı değildir: tanıma hataları olabilir ve kutulu bölümler ana metnin arasına karışabilir. Kaynak belge değişmedi.'**
  String get viewOcrNote;

  /// No description provided for @viewOcrCopy.
  ///
  /// In tr, this message translates to:
  /// **'Metni kopyala'**
  String get viewOcrCopy;

  /// No description provided for @viewOcrCopied.
  ///
  /// In tr, this message translates to:
  /// **'Metin panoya kopyalandı.'**
  String get viewOcrCopied;

  /// No description provided for @viewOcrReading.
  ///
  /// In tr, this message translates to:
  /// **'Okunuyor…'**
  String get viewOcrReading;

  /// No description provided for @viewOcrShowDocument.
  ///
  /// In tr, this message translates to:
  /// **'Belgeyi göster'**
  String get viewOcrShowDocument;

  /// No description provided for @viewOcrShowText.
  ///
  /// In tr, this message translates to:
  /// **'Okunan metin'**
  String get viewOcrShowText;

  /// No description provided for @viewOcrNothingFound.
  ///
  /// In tr, this message translates to:
  /// **'Okunabilir yazı bulunamadı'**
  String get viewOcrNothingFound;

  /// No description provided for @viewOcrRun.
  ///
  /// In tr, this message translates to:
  /// **'Metne dönüştür'**
  String get viewOcrRun;

  /// No description provided for @viewDraftDeleteFailed.
  ///
  /// In tr, this message translates to:
  /// **'Taslak silinemedi'**
  String get viewDraftDeleteFailed;

  /// No description provided for @viewDeleteAllDraftsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bütün taslaklar silinsin mi?'**
  String get viewDeleteAllDraftsTitle;

  /// No description provided for @viewDeleteAllDraftsBody.
  ///
  /// In tr, this message translates to:
  /// **'{count} kaydedilmemiş taslak kalıcı olarak silinecek. Belgelerin kendileri değişmez.'**
  String viewDeleteAllDraftsBody(int count);

  /// No description provided for @viewDeleteAll.
  ///
  /// In tr, this message translates to:
  /// **'Hepsini sil'**
  String get viewDeleteAll;

  /// No description provided for @viewDraftsDeleteFailed.
  ///
  /// In tr, this message translates to:
  /// **'Taslaklar silinemedi'**
  String get viewDraftsDeleteFailed;

  /// No description provided for @viewDraftNeverSaved.
  ///
  /// In tr, this message translates to:
  /// **'Hiç kaydedilmemiş yeni belge'**
  String get viewDraftNeverSaved;

  /// No description provided for @viewDraftSourceGone.
  ///
  /// In tr, this message translates to:
  /// **'Kaynak dosya artık yok, yeni belge olarak açılır\n{source}'**
  String viewDraftSourceGone(String source);

  /// No description provided for @viewDraftsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kurtarılabilir taslaklar'**
  String get viewDraftsTitle;

  /// No description provided for @viewDraftsNote.
  ///
  /// In tr, this message translates to:
  /// **'Kaydedilmeden kapanan belgelerin son hali bu cihazda saklanır. Bir taslağı açtığınızda editöre kaydedilmemiş değişiklik olarak gelir; siz kaydedene kadar dosyaya yazılmaz.'**
  String get viewDraftsNote;

  /// No description provided for @viewDraftsUnreachable.
  ///
  /// In tr, this message translates to:
  /// **'Yerel taslaklara ulaşılamadı.'**
  String get viewDraftsUnreachable;

  /// No description provided for @viewDraftsEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Kurtarılmayı bekleyen taslak yok.'**
  String get viewDraftsEmpty;

  /// No description provided for @viewDeleteDraft.
  ///
  /// In tr, this message translates to:
  /// **'Taslağı sil'**
  String get viewDeleteDraft;

  /// No description provided for @viewVersionUnreadable.
  ///
  /// In tr, this message translates to:
  /// **'Bu sürüm okunamadı.'**
  String get viewVersionUnreadable;

  /// No description provided for @viewToday.
  ///
  /// In tr, this message translates to:
  /// **'Bugün'**
  String get viewToday;

  /// No description provided for @viewYesterday.
  ///
  /// In tr, this message translates to:
  /// **'Dün'**
  String get viewYesterday;

  /// No description provided for @viewSaveVersionCopyDialog.
  ///
  /// In tr, this message translates to:
  /// **'Sürümü kopya olarak kaydet'**
  String get viewSaveVersionCopyDialog;

  /// No description provided for @viewCopyOverOriginal.
  ///
  /// In tr, this message translates to:
  /// **'Kopya belgenin kendisinin üzerine yazılmaz'**
  String get viewCopyOverOriginal;

  /// No description provided for @viewCopyOverOriginalHint.
  ///
  /// In tr, this message translates to:
  /// **'Belgeyi bu sürüme döndürmek için «{label}» düğmesini kullanın.'**
  String viewCopyOverOriginalHint(String label);

  /// No description provided for @viewCopySaved.
  ///
  /// In tr, this message translates to:
  /// **'Sürümün kopyası kaydedildi'**
  String get viewCopySaved;

  /// No description provided for @viewCopySaveFailed.
  ///
  /// In tr, this message translates to:
  /// **'Kopya kaydedilemedi'**
  String get viewCopySaveFailed;

  /// No description provided for @viewVersionList.
  ///
  /// In tr, this message translates to:
  /// **'Sürüm listesi'**
  String get viewVersionList;

  /// No description provided for @viewHistoryTitle.
  ///
  /// In tr, this message translates to:
  /// **'Belge geçmişi'**
  String get viewHistoryTitle;

  /// No description provided for @viewHistoryNote.
  ///
  /// In tr, this message translates to:
  /// **'Folio’da her kaydettiğinizde dosyanın önceki ve yeni hali bu cihazda saklanır: belge başına son 20 sürüm, en fazla 100 MB.'**
  String get viewHistoryNote;

  /// No description provided for @viewHistoryUnreachable.
  ///
  /// In tr, this message translates to:
  /// **'Yerel geçmişe ulaşılamadı.'**
  String get viewHistoryUnreachable;

  /// No description provided for @viewHistoryEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Bu belgenin henüz saklanmış bir sürümü yok.'**
  String get viewHistoryEmpty;

  /// No description provided for @viewHistoryEmptyHint.
  ///
  /// In tr, this message translates to:
  /// **'Belgeyi Folio’da ilk kaydettiğinizde, dosyanın o ana kadarki hali ve kaydettiğiniz yeni hali burada listelenir.'**
  String get viewHistoryEmptyHint;

  /// No description provided for @viewSigned.
  ///
  /// In tr, this message translates to:
  /// **'E-imzalı'**
  String get viewSigned;

  /// No description provided for @viewSaveCopy.
  ///
  /// In tr, this message translates to:
  /// **'Kopya olarak kaydet…'**
  String get viewSaveCopy;

  /// No description provided for @viewOtherFormatHint.
  ///
  /// In tr, this message translates to:
  /// **'Bu sürüm başka bir biçimde saklanmış; kopya olarak kaydedebilirsiniz.'**
  String get viewOtherFormatHint;

  /// No description provided for @viewCompareCurrent.
  ///
  /// In tr, this message translates to:
  /// **'Şimdikiyle karşılaştır'**
  String get viewCompareCurrent;

  /// No description provided for @viewPageView.
  ///
  /// In tr, this message translates to:
  /// **'Sayfa görünümü'**
  String get viewPageView;

  /// No description provided for @viewPageViewFailed.
  ///
  /// In tr, this message translates to:
  /// **'Sayfa görünümü hazırlanamadı: {error}'**
  String viewPageViewFailed(String error);

  /// No description provided for @viewTypeNotShown.
  ///
  /// In tr, this message translates to:
  /// **'Bu tür bir belge burada gösterilemiyor. «Kopya olarak kaydet» ile ayrı bir dosya olarak açabilirsiniz.'**
  String get viewTypeNotShown;

  /// No description provided for @viewCompareFailed.
  ///
  /// In tr, this message translates to:
  /// **'Karşılaştırılamadı: {error}'**
  String viewCompareFailed(String error);

  /// No description provided for @viewCompareUnsupported.
  ///
  /// In tr, this message translates to:
  /// **'Bu tür bir belgede metin karşılaştırılamıyor; sürümü «Sayfa görünümü»nden inceleyebilirsiniz.'**
  String get viewCompareUnsupported;

  /// No description provided for @viewCompareIdentical.
  ///
  /// In tr, this message translates to:
  /// **'Bu sürümün metni şu anki haliyle aynı. Yazı tipi, boşluk gibi biçim farkları burada gösterilmez; «Sayfa görünümü»ne bakın.'**
  String get viewCompareIdentical;

  /// No description provided for @viewDiffSummary.
  ///
  /// In tr, this message translates to:
  /// **'Bu sürümden bu yana {added} kelime eklenmiş, {removed} kelime silinmiş.'**
  String viewDiffSummary(int added, int removed);

  /// No description provided for @viewAddedLater.
  ///
  /// In tr, this message translates to:
  /// **'Sonradan eklenen'**
  String get viewAddedLater;

  /// No description provided for @viewRemovedLater.
  ///
  /// In tr, this message translates to:
  /// **'Sonradan silinen'**
  String get viewRemovedLater;

  /// No description provided for @viewUnchangedLines.
  ///
  /// In tr, this message translates to:
  /// **'⋯ değişmeyen {count} satır ⋯'**
  String viewUnchangedLines(int count);

  /// No description provided for @viewRestoreVersion.
  ///
  /// In tr, this message translates to:
  /// **'Bu sürümü geri yükle'**
  String get viewRestoreVersion;

  /// No description provided for @viewAboutProduct.
  ///
  /// In tr, this message translates to:
  /// **'{name} hakkında'**
  String viewAboutProduct(String name);

  /// No description provided for @viewWindowActionFailed.
  ///
  /// In tr, this message translates to:
  /// **'Pencere işlemi tamamlanamadı'**
  String get viewWindowActionFailed;

  /// No description provided for @viewAbout.
  ///
  /// In tr, this message translates to:
  /// **'Hakkında'**
  String get viewAbout;

  /// No description provided for @viewFullScreen.
  ///
  /// In tr, this message translates to:
  /// **'Tam ekran'**
  String get viewFullScreen;

  /// No description provided for @viewExitFullScreen.
  ///
  /// In tr, this message translates to:
  /// **'Tam ekrandan çık'**
  String get viewExitFullScreen;

  /// No description provided for @viewMinimize.
  ///
  /// In tr, this message translates to:
  /// **'Simge durumuna küçült'**
  String get viewMinimize;

  /// No description provided for @viewRestoreSize.
  ///
  /// In tr, this message translates to:
  /// **'Önceki boyut'**
  String get viewRestoreSize;

  /// No description provided for @viewMaximize.
  ///
  /// In tr, this message translates to:
  /// **'Ekranı kapla'**
  String get viewMaximize;

  /// No description provided for @viewHideToTray.
  ///
  /// In tr, this message translates to:
  /// **'Tepsiye gizle'**
  String get viewHideToTray;

  /// No description provided for @viewCloseApp.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamayı kapat'**
  String get viewCloseApp;

  /// No description provided for @viewAddressOpenFailed.
  ///
  /// In tr, this message translates to:
  /// **'Adres açılamadı'**
  String get viewAddressOpenFailed;

  /// No description provided for @viewVersion.
  ///
  /// In tr, this message translates to:
  /// **'Sürüm {version} ({build})'**
  String viewVersion(String version, String build);

  /// No description provided for @viewAboutTaglineOfis.
  ///
  /// In tr, this message translates to:
  /// **'Belgeleri açan, düzenleyen ve imzalayan uygulama'**
  String get viewAboutTaglineOfis;

  /// No description provided for @viewAboutTaglineFolio.
  ///
  /// In tr, this message translates to:
  /// **'Avukatlar için dilekçe, dava ve büro uygulaması'**
  String get viewAboutTaglineFolio;

  /// No description provided for @viewAboutDescOfis.
  ///
  /// In tr, this message translates to:
  /// **'Ofis ile UDF, Word, ODT, RTF ve PDF belgelerinizi açar, düzenler, yazdırır ve e-imza kartınızla imzalarsınız. Kanun maddesi ve karar atıflarını denetler, yazım hatalarını bulur, metni sesli okur ve söylediklerinizi yazarsınız.'**
  String get viewAboutDescOfis;

  /// No description provided for @viewAboutDescFolio.
  ///
  /// In tr, this message translates to:
  /// **'Folio ile UDF dilekçenizi yazar, e-imza ya da mobil imzayla imzalar ve dava dosyanıza gönderirsiniz. Müvekkillerinizi, duruşma ve süre takviminizi, büronuzun kasasını ve ekibinizi aynı uygulamadan yönetirsiniz.'**
  String get viewAboutDescFolio;

  /// No description provided for @viewAboutDataOfis.
  ///
  /// In tr, this message translates to:
  /// **'Verileriniz yalnız sizin cihazlarınızda tutulur. Ofis’in verilerinizi tutan bir sunucusu yoktur ve yapay zekâ hizmeti kullanmaz. Başka bir büroyla uzaktan canlı paylaşımda belge ve yazışma şifreli olarak aktarma sunucumuzdan geçer; sunucu içeriği göremez ve hiçbir şey saklamaz.'**
  String get viewAboutDataOfis;

  /// No description provided for @viewAboutDataFolio.
  ///
  /// In tr, this message translates to:
  /// **'Verileriniz yalnız sizin cihazlarınızda tutulur. Folio’nun verilerinizi tutan bir sunucusu yoktur. Yapay zekâ özellikleri isteğe bağlıdır ve siz açmadıkça kapalıdır. Başka bir büroyla uzaktan canlı paylaşımda belge ve yazışma şifreli olarak aktarma sunucumuzdan geçer; sunucu içeriği göremez ve hiçbir şey saklamaz.'**
  String get viewAboutDataFolio;

  /// No description provided for @viewAgreements.
  ///
  /// In tr, this message translates to:
  /// **'SÖZLEŞMELER'**
  String get viewAgreements;

  /// No description provided for @viewTermsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kullanım Koşulları'**
  String get viewTermsTitle;

  /// No description provided for @viewTermsSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Kullanım izni ve sorumluluklar'**
  String get viewTermsSubtitle;

  /// No description provided for @viewPrivacyTitle.
  ///
  /// In tr, this message translates to:
  /// **'Gizlilik ve KVKK Aydınlatma Metni'**
  String get viewPrivacyTitle;

  /// No description provided for @viewPrivacySubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Kişisel verileriniz nasıl korunur'**
  String get viewPrivacySubtitle;

  /// No description provided for @viewLicenseTitle.
  ///
  /// In tr, this message translates to:
  /// **'Lisans'**
  String get viewLicenseTitle;

  /// No description provided for @viewLicenseSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Tescilli yazılım'**
  String get viewLicenseSubtitle;

  /// No description provided for @viewOpenSourceLicenses.
  ///
  /// In tr, this message translates to:
  /// **'Açık kaynak lisansları'**
  String get viewOpenSourceLicenses;

  /// No description provided for @viewComponentsSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Folio’da kullanılan bileşenler'**
  String get viewComponentsSubtitle;

  /// No description provided for @viewSupport.
  ///
  /// In tr, this message translates to:
  /// **'DESTEK'**
  String get viewSupport;

  /// No description provided for @viewDownloadOther.
  ///
  /// In tr, this message translates to:
  /// **'Diğer cihazlarınıza indirin'**
  String get viewDownloadOther;

  /// No description provided for @viewContact.
  ///
  /// In tr, this message translates to:
  /// **'Destek ve iletişim'**
  String get viewContact;

  /// No description provided for @viewContactSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'İletişim formuyla bize yazın'**
  String get viewContactSubtitle;

  /// No description provided for @viewWebsite.
  ///
  /// In tr, this message translates to:
  /// **'Folio’nun web sitesi'**
  String get viewWebsite;

  /// No description provided for @viewCopyright.
  ///
  /// In tr, this message translates to:
  /// **'© 2026 LifeOS. Tüm hakları saklıdır. {product} tescilli bir yazılımdır, açık kaynak değildir.'**
  String viewCopyright(String product);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
