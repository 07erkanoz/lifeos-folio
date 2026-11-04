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

  /// No description provided for @ofisNewUdf.
  ///
  /// In tr, this message translates to:
  /// **'Yeni UDF belge'**
  String get ofisNewUdf;

  /// No description provided for @ofisNewUdfDetail.
  ///
  /// In tr, this message translates to:
  /// **'UYAP’ın biçiminde'**
  String get ofisNewUdfDetail;

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
