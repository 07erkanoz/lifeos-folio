// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get languageName => 'English';

  @override
  String get languageSystem => 'System language';

  @override
  String get languageMenu => 'Language';

  @override
  String ofisNewDocumentTitle(String extension) {
    return 'New document.$extension';
  }

  @override
  String get ofisAbout => 'About LifeOS Ofis';

  @override
  String get ofisDocuments => 'Documents';

  @override
  String get ofisNew => 'New';

  @override
  String get ofisNewTooltip => 'New Word document · Ctrl+N';

  @override
  String get ofisOpen => 'Open';

  @override
  String get ofisOpenTooltip => 'Open a document · Ctrl+O';

  @override
  String get ofisOpenDialog => 'Open a document';

  @override
  String get ofisFileMoved => 'The document was moved or removed';

  @override
  String get ofisCannotOpenType => 'This type of document cannot be opened';

  @override
  String get ofisDraftCannotOpen => 'This draft cannot be opened here';

  @override
  String get ofisEdit => 'Edit';

  @override
  String get ofisHomeTitle => 'Your documents';

  @override
  String get ofisOpenAction => 'Open a document';

  @override
  String get ofisOpenActionDetail =>
      'Word, PDF, RTF, ODT, Markdown, Excel, UDF, .imz';

  @override
  String get ofisNewUdf => 'New UDF document';

  @override
  String get ofisNewUdfDetail => 'In UYAP’s format';

  @override
  String get ofisNewDocx => 'New Word document';

  @override
  String get ofisNewDocxDetail => 'As DOCX';

  @override
  String get ofisDropHere => 'Drop a document here';

  @override
  String get ofisRecent => 'RECENT DOCUMENTS';

  @override
  String get ofisRecentEmpty => 'Documents you open appear here.';

  @override
  String get ofisImzBadge => 'IMZ';

  @override
  String get ofisSignedDocument => 'E-signed document';

  @override
  String whenToday(String clock) {
    return 'Today $clock';
  }

  @override
  String whenYesterday(String clock) {
    return 'Yesterday $clock';
  }

  @override
  String whenDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }
}
