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
  String get ofisNewUdf => 'Yeni UDF belge';

  @override
  String get ofisNewUdfDetail => 'UYAP’ın biçiminde';

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
}
