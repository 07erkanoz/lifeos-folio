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

  @override
  String get formatTiff => 'TIFF document';

  @override
  String get formatImage => 'Image';

  @override
  String get formatText => 'Text';

  @override
  String get formatRtf => 'Rich Text RTF';

  @override
  String get formatData => 'Data / Text';

  @override
  String get formatUnknown => 'Unknown';

  @override
  String editorFindReplacedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matches replaced.',
      one: '1 match replaced.',
    );
    return '$_temp0';
  }

  @override
  String get editorFindTitle => 'Find and replace';

  @override
  String get editorFindQuery => 'Text to find';

  @override
  String get editorFindMatchCase => 'Match case';

  @override
  String get editorFindWholeWord => 'Whole word';

  @override
  String get editorFindPrompt => 'Search the document';

  @override
  String get editorFindNoMatch => 'No matches found';

  @override
  String editorFindPosition(int current, int total) {
    return 'Match $current of $total';
  }

  @override
  String get editorFindPrevious => 'Previous match';

  @override
  String get editorFindNext => 'Next match';

  @override
  String get editorFindReplace => 'Replace';

  @override
  String get editorFindReplacement => 'Replace with';

  @override
  String get editorFindReplaceAll => 'Replace all';

  @override
  String get editorClose => 'Close';

  @override
  String get editorPageJump => 'Go to page';

  @override
  String editorPageSemantics(int current, int count) {
    return 'Page $current of $count';
  }

  @override
  String get editorPageNumberField => 'Page number';

  @override
  String get editorCancel => 'Cancel';

  @override
  String get editorPageJumpGo => 'Go';

  @override
  String get editorZoomOut => 'Zoom out';

  @override
  String get editorZoomTooltip => 'Zoom · Ctrl + mouse wheel';

  @override
  String editorZoomPercent(int percent) {
    return '$percent%';
  }

  @override
  String get editorZoomIn => 'Zoom in';

  @override
  String get editorZoomReset => 'Reset';

  @override
  String get editorRulerMarginLeft => 'Left margin';

  @override
  String get editorRulerMarginRight => 'Right margin';

  @override
  String get editorRulerMarginTop => 'Top margin';

  @override
  String get editorRulerMarginBottom => 'Bottom margin';

  @override
  String editorRulerMarginTip(String label, String cm) {
    return '$label: $cm cm · Drag to change';
  }

  @override
  String editorRulerTabKindTip(String kind) {
    return 'Tab type: $kind · Click to change';
  }

  @override
  String editorRulerTabStopTip(String kind, String cm) {
    return '$kind tab · $cm cm · Drag down or double-click to remove';
  }

  @override
  String get editorRulerFirstLineIndent => 'First line indent';

  @override
  String get editorRulerLeftIndent => 'Left and hanging indent';

  @override
  String get editorRulerRightIndent => 'Right indent';

  @override
  String get editorTabLeft => 'Left';

  @override
  String get editorTabCentre => 'Center';

  @override
  String get editorTabRight => 'Right';

  @override
  String get editorTabDecimal => 'Decimal';

  @override
  String get editorTabBar => 'Bar';

  @override
  String get editorHeaderPlaceholder =>
      'Header — printed at the top of every page';

  @override
  String get editorFooterPlaceholder =>
      'Footer — printed at the bottom of every page';

  @override
  String get editorRegionRemove => 'REMOVE';

  @override
  String get editorHeaderLabel => 'HEADER';

  @override
  String get editorFooterLabel => 'FOOTER';

  @override
  String editorRegionPrintsFromPage(String page) {
    return 'Printed from page $page on';
  }

  @override
  String get editorHistoryWriteFailed =>
      'Could not write to the document history';

  @override
  String get editorHistoryWriteFailedDetail =>
      'You can still save your document; only this version was not kept.';

  @override
  String get editorUnsavedChangesTitle => 'There are unsaved changes';

  @override
  String get editorShareSavedOnly =>
      'What is shared is the saved version of the document.';

  @override
  String get editorShareSavedVersion => 'Share the saved version';

  @override
  String get editorSaveAndShare => 'Save and share';

  @override
  String get editorReplaceWhatDraft => 'The draft';

  @override
  String get editorReplaceWhatVersion => 'The selected version';

  @override
  String get editorVersionUnreadable => 'The version could not be read.';

  @override
  String get editorVersionOpenFailed => 'Could not open the version';

  @override
  String get editorNotSavedYet => 'This document has not been saved yet';

  @override
  String get editorHistoryFromFirstSave =>
      'The history is kept from the first save on.';

  @override
  String get editorRestoreLabel => 'Load into the editor';

  @override
  String get editorRestoreHint =>
      'The selected version opens in the editor as unsaved changes; the file does not change until you save.';

  @override
  String editorVersionLoaded(String date) {
    return 'The version from $date was loaded into the editor';
  }

  @override
  String get editorSaveToKeep => 'Save to keep it in the file.';

  @override
  String editorCitationLaws(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count statute articles',
      one: '1 statute article',
    );
    return '$_temp0';
  }

  @override
  String editorCitationDecisions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count decisions',
      one: '1 decision',
    );
    return '$_temp0';
  }

  @override
  String editorCitationShowTip(String detail) {
    return '$detail · show the sources';
  }

  @override
  String editorCitationTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sources',
      one: '1 source',
    );
    return '$_temp0';
  }

  @override
  String get editorCitationTitle => 'Sources cited in this document';

  @override
  String get editorCaseLawPanelTitle => 'Search precedents';

  @override
  String get editorClosePanel => 'Close the panel';

  @override
  String get editorOpenInWindow => 'Open in a separate window';

  @override
  String get editorReadAloud => 'Read aloud';

  @override
  String editorTermMeaning(String term) {
    return 'What does “$term” mean?';
  }

  @override
  String get editorAddToDictionary => 'Add to dictionary';

  @override
  String editorSnippetHotkeyUnassigned(int key) {
    return 'Alt+F$key is not assigned to a snippet.';
  }

  @override
  String get editorSnippetHotkeyHint =>
      'You can assign it with Ctrl+Space → Manage my snippets.';

  @override
  String get editorSnippetEmbedsSkipped =>
      'Tables and images in the selection were not added to the snippet.';

  @override
  String get editorSnippetTextOnly =>
      'A snippet keeps only the text and its formatting.';

  @override
  String editorSnippetsAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippets added.',
      one: '1 snippet added.',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenElsewhere => 'This document is open in another window';

  @override
  String get editorOpenElsewhereDetail =>
      'If the same document is edited in two windows, one save overwrites the other. Edit the document in the window where it is open.';

  @override
  String get editorHeldElsewhereBanner =>
      'This document is being edited in another window. Here it can only be read; make your changes in that window.';

  @override
  String get editorRetry => 'Try again';

  @override
  String get editorDictationFailed => 'Dictation did not start';

  @override
  String get editorFormatNothing => 'There was nothing to format';

  @override
  String get editorFormatted => 'Formatted';

  @override
  String get editorUndoHint => 'You can undo it with Ctrl+Z.';

  @override
  String get editorPrintName => 'Document';

  @override
  String get editorPrintFailed => 'Could not print';

  @override
  String get editorInsertImageTitle => 'Insert image';

  @override
  String get editorImageTooLarge =>
      'The image is too large. You can insert up to 12 MB.';

  @override
  String editorImageUnreadable(String name) {
    return 'Could not read the image: $name';
  }

  @override
  String editorImageInsertFailed(String error) {
    return 'Could not insert the image: $error';
  }

  @override
  String get editorDeleteHeaderTitle => 'Delete the header?';

  @override
  String get editorDeleteFooterTitle => 'Delete the footer?';

  @override
  String get editorDeleteRegionBody =>
      'What you wrote will be removed from the document. If you close without saving, the change is not applied.';

  @override
  String get editorDelete => 'Delete';

  @override
  String get editorPageView => 'Page view';

  @override
  String get editorMobileView => 'Mobile view';

  @override
  String get editorSign => 'Sign';

  @override
  String get editorSignWithCard => 'With an e-signature card';

  @override
  String get editorCaseLaw => 'Case law';

  @override
  String get editorMoreTools => 'More tools';

  @override
  String get editorTodaysDate => 'Today\'s date';

  @override
  String get editorSnippets => 'Snippets';

  @override
  String get editorDocumentHistory => 'Document history';

  @override
  String get editorResearch => 'Research';

  @override
  String get editorSearchCaseLaw => 'Search case law';

  @override
  String get editorCompare => 'Compare';

  @override
  String get editorCompareTip => 'Compare with saved versions';

  @override
  String get editorSignCardButton => 'E-signature\ncard';

  @override
  String get editorSignWayCard => 'with an e-signature card';

  @override
  String get editorSignOnlyUdf =>
      'Only UDF documents can be signed. Save it as UDF first.';

  @override
  String editorSignUnavailable(String way) {
    return 'Signing $way is not available on this device';
  }

  @override
  String get editorSigning => 'Signing…';

  @override
  String editorSignAsUdf(String way) {
    return 'Sign as UDF $way';
  }

  @override
  String editorTableSize(int rows, int columns) {
    return '$rows × $columns table';
  }

  @override
  String get editorTable => 'Table';

  @override
  String get editorImage => 'Image';

  @override
  String get editorHeader => 'Header';

  @override
  String get editorFooter => 'Footer';

  @override
  String get editorPageNumbers => 'Page numbers';

  @override
  String get editorLetterhead => 'Letterhead';

  @override
  String get editorDate => 'Date';

  @override
  String get editorTableAndImage => 'Table and image';

  @override
  String get editorHeaderAndFooter => 'Header and footer';

  @override
  String get editorText => 'Text';

  @override
  String get editorSignatureBlock => 'Signature block';

  @override
  String get editorHorizontalRuler => 'Horizontal ruler';

  @override
  String get editorVerticalRuler => 'Vertical ruler';

  @override
  String get editorShortcuts => 'Shortcuts';

  @override
  String get editorView => 'View';

  @override
  String get editorRulers => 'Rulers';

  @override
  String get editorOther => 'Other';

  @override
  String get editorShortcutsTitle => 'Editor shortcuts';

  @override
  String get editorShortcutsList =>
      'Ctrl+S  Save\nCtrl+Shift+S  Save as\nCtrl+Z  Undo\nCtrl+Y / Ctrl+Shift+Z  Redo\nCtrl+B / I / U  Bold / Italic / Underline\nCtrl+A / C / X / V  Select all / Copy / Cut / Paste\nCtrl+F  Find in document\nCtrl+H  Find and replace\nCtrl+P  Print\nCtrl+L / E / R / J  Align left / Center / Align right / Justify\nCtrl+Shift+L / 8  Bulleted list\nCtrl+Shift+7  Numbered list\nCtrl+M / Ctrl+Shift+M  Increase / decrease indent\n\nOn macOS, use ⌘ instead of Ctrl.';

  @override
  String get editorOk => 'OK';

  @override
  String get editorSaveFormatTitle => 'Which format should it be saved in?';

  @override
  String get editorFormatUdf => 'UYAP document (.udf)';

  @override
  String get editorFormatDocx => 'Word document (.docx)';

  @override
  String get editorFormatRtf => 'Rich text (.rtf)';

  @override
  String get editorFormatPdf => 'Printed copy (.pdf)';

  @override
  String get editorContinue => 'Continue';

  @override
  String get editorSignedTitle => 'This document is e-signed';

  @override
  String get editorSignedBody =>
      'The signature covers the document as it was when it was signed; it cannot be carried over to a changed document.\n\n• Save over it: the file is updated with your changes, without a signature. The signed version is kept in the document history; you can go back to it or take a copy of it whenever you like.\n\n• Unsigned copy: the signed file stays as it is, and your changes are written to a new file.';

  @override
  String get editorSaveUnsignedCopy => 'Save an unsigned copy…';

  @override
  String get editorOverwriteSave => 'Save over it';

  @override
  String get editorChangedElsewhereTitle =>
      'The document was changed elsewhere';

  @override
  String get editorChangedElsewhereBody =>
      'This file was changed in another program after you opened it here. If you save, your version is kept as the file; the other version is kept in the document history.';

  @override
  String get editorSaveMine => 'Save my version';

  @override
  String get editorOverwriteSignedTitle => 'Overwrite the signed file?';

  @override
  String get editorOverwriteSignedBody =>
      'The file is updated with your changes, without a signature. The signed version is kept in the document history.';

  @override
  String get editorOverwrite => 'Overwrite';

  @override
  String get editorPdfNoTextNoOcr =>
      'This PDF has no text layer: its text was scanned or turned into shapes when it was printed. The OCR tool needed to read it was not found in this installation.';

  @override
  String get editorPdfNoTextUnreadable =>
      'This PDF has no text layer, and no readable text was found on its pages.';

  @override
  String get editorUnreadable =>
      'The document could not be read or is damaged.';

  @override
  String get editorOcrRead =>
      'This PDF had no text layer; the text was read from the pages (OCR).';

  @override
  String get editorOcrCheck =>
      'Before saving, check the numbers and names in particular.';

  @override
  String get editorBlanksTitle => 'There are unfilled blanks';

  @override
  String editorBlanksBody(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count blanks from snippets are still empty',
      one: '1 blank from a snippet is still empty',
    );
    return '$_temp0: $names.\n\nSave anyway?';
  }

  @override
  String get editorGoBack => 'Go back';

  @override
  String get editorSaveAnyway => 'Save anyway';

  @override
  String get editorUnsignedCopyTitle => 'An unsigned copy will be saved';

  @override
  String get editorUnderstoodSave => 'OK, save';

  @override
  String editorSaveDialogTitle(String ext) {
    return 'Save document ($ext)';
  }

  @override
  String get editorOverwriteHeldDetail =>
      'Overwriting it could lose the work in that window. Save under another name, or close that window first.';

  @override
  String get editorSignedNotOverwritten =>
      'The signed file was not overwritten';

  @override
  String get editorSignedNotOverwrittenDetail =>
      'The signed version could not be kept in the document history. You can save your changes as an unsigned copy.';

  @override
  String get editorNotOverwritten => 'The document was not overwritten';

  @override
  String get editorNotOverwrittenDetail =>
      'The other program\'s version could not be kept in the document history. You can save your changes under another name.';

  @override
  String get editorSaved => 'Saved';

  @override
  String get editorSavedToLocation => 'The document was saved where you chose.';

  @override
  String editorSavedAs(String name) {
    return 'Saved: $name';
  }

  @override
  String get editorSaveAs => 'Save as';

  @override
  String get editorSaveFailed => 'Save error: the document could not be saved';

  @override
  String get editorOcrReading =>
      'This PDF has no text layer; reading the pages (OCR)…';

  @override
  String get editorOcrPerPage => 'This can take a few seconds per page.';

  @override
  String editorOpenFailed(String error) {
    return 'Could not open the document: $error';
  }

  @override
  String get editorRecoverFromHistory => 'Recover from the document history';

  @override
  String get editorFontLoadFailed => 'Could not load the font';

  @override
  String get editorSignUdf => 'E-sign as UDF';

  @override
  String get editorSaveTooltip => 'Save · Ctrl+S';

  @override
  String get snipDeleteTitle => 'Delete this snippet?';

  @override
  String snipDeleteBody(String name) {
    return '“$name” will be removed from your snippets. Documents written with it stay as they are.';
  }

  @override
  String get snipCancel => 'Cancel';

  @override
  String get snipDelete => 'Delete';

  @override
  String get snipExportDialog => 'Export snippets';

  @override
  String snipExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippets exported.',
      one: '1 snippet exported.',
    );
    return '$_temp0';
  }

  @override
  String get snipExportFailed => 'Snippets could not be exported';

  @override
  String get snipImportDialog => 'Import snippets';

  @override
  String get snipImportNone => 'No new snippets; you already have them all.';

  @override
  String snipImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippets added.',
      one: '1 snippet added.',
    );
    return '$_temp0';
  }

  @override
  String get snipImportFailed => 'Snippets could not be imported';

  @override
  String get snipManagerTitle => 'My snippets';

  @override
  String get snipImport => 'Import';

  @override
  String get snipExport => 'Export';

  @override
  String get snipSearchHint => 'Search snippets';

  @override
  String get snipManagerEmpty =>
      'No snippets yet. Add one with \"New snippet\", or select a paragraph in a document and press Ctrl+Space to keep it as a snippet.';

  @override
  String get snipNoMatch => 'No snippets match this search.';

  @override
  String snipUsedTimes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count times',
      one: 'once',
    );
    return '$_temp0';
  }

  @override
  String get snipNew => 'New snippet';

  @override
  String get snipClose => 'Close';

  @override
  String get snipEditTitle => 'Edit snippet';

  @override
  String get snipEmptyBody => 'The snippet text cannot be empty.';

  @override
  String get snipBadKeyword =>
      'The keyword must be 2–20 letters or digits, with no spaces.';

  @override
  String snipKeywordTaken(String keyword, String name) {
    return '“$keyword” is already the keyword of the snippet “$name”.';
  }

  @override
  String snipHotkeyTaken(String key, String name) {
    return 'Alt+F$key is already used by the snippet “$name”.';
  }

  @override
  String get snipUntitled => 'Untitled snippet';

  @override
  String get snipName => 'Name';

  @override
  String get snipKeyword => 'Keyword';

  @override
  String get snipKeywordHint => 'e.g. pet1';

  @override
  String get snipKeywordHelper =>
      'Type it in a document and press Tab to insert the snippet';

  @override
  String get snipHotkey => 'Shortcut';

  @override
  String get snipHotkeyHelper => 'Alt+F4 closes the window';

  @override
  String get snipNoHotkey => 'None';

  @override
  String get snipText => 'Text';

  @override
  String get snipBodyPlaceholder =>
      'The snippet text. Write the blanks to fill in square brackets and capitals, like [CLIENT].';

  @override
  String snipBlanksList(String blanks) {
    return 'Blanks to fill: $blanks';
  }

  @override
  String get snipSave => 'Save';

  @override
  String get snipTableLeftOut => '〔Table — not inserted with the snippet〕';

  @override
  String get snipPaletteHint => 'Search snippets or profile details';

  @override
  String get snipFromProfile => 'From profile';

  @override
  String snipProfileInsertTooltip(String label) {
    return '$label · insert into document';
  }

  @override
  String get snipFillProfile => 'Fill in your profile';

  @override
  String get snipFillProfileDetail =>
      'Insert your name, organization and address here with one click';

  @override
  String get snipKeepSelection => 'Keep selection as a snippet';

  @override
  String get snipHarvestOpen => 'Find snippets in the archive';

  @override
  String get snipHarvestOpenDetail =>
      'Paragraphs that repeat in your documents';

  @override
  String get snipManage => 'Manage my snippets';

  @override
  String get snipManageDetail => 'Name, keyword, Alt+F shortcut, delete';

  @override
  String get snipPaletteNoMatch =>
      'No snippets or profile details match this search.';

  @override
  String get snipPaletteEmptyHarvest =>
      'No snippets yet.\n\nLook above for paragraphs that repeat in your archive, or select a paragraph in the document and press Ctrl+Space again.';

  @override
  String get snipPaletteEmptySelect =>
      'No snippets yet.\n\nSelect a paragraph you often write in the document, then press Ctrl+Space — “Keep selection as a snippet” will appear here.';

  @override
  String get snipPaletteEmptyKeep =>
      'No snippets yet. You can keep your selection as a snippet above.';

  @override
  String snipFromProfileLabel(String label) {
    return 'From profile · $label';
  }

  @override
  String get snipPaletteKeys =>
      '↑ ↓ to choose · Enter to insert · Esc to close';

  @override
  String get snipNameIt => 'Name the snippet';

  @override
  String get snipNameItDetail =>
      'You will find it later by typing the first letters of this name.';

  @override
  String get snipBack => 'Back';

  @override
  String get snipKeep => 'Keep as snippet';

  @override
  String snipFillCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This snippet has $count blanks to fill.',
      one: 'This snippet has 1 blank to fill.',
    );
    return '$_temp0';
  }

  @override
  String get snipFromLawyerProfile => 'From your profile';

  @override
  String get snipLeaveBlank => 'Leave blank';

  @override
  String get snipInsert => 'Insert';

  @override
  String get snipHarvestTitle => 'Paragraphs that repeat in your archive';

  @override
  String get snipHarvestNone =>
      'No paragraph appears word for word in five or more documents. The archive may still be being scanned.';

  @override
  String snipHarvestFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count paragraphs found.',
      one: '1 paragraph found.',
    );
    return '$_temp0 Tick the ones you want to keep as snippets.';
  }

  @override
  String get snipHarvestBlank =>
      'Leave dates, case numbers, IDs and amounts blank';

  @override
  String get snipHarvestBlankDetail =>
      'Parts that belong to one case become blanks to fill, like [TARİH].';

  @override
  String snipHarvestInDocuments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'in $count documents',
      one: 'in 1 document',
    );
    return '$_temp0';
  }

  @override
  String snipHarvestTake(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Keep $count snippets',
      one: 'Keep 1 snippet',
    );
    return '$_temp0';
  }

  @override
  String noteDraftTooltip(String date) {
    return 'Unsaved draft · $date';
  }

  @override
  String get noteDraftTitle => 'Unsaved draft';

  @override
  String noteDraftBody(String name, String date) {
    return 'There is an unsaved draft of “$name” from $date. It may have been left when the app closed unexpectedly.\n\nIf you open it, it comes into the editor as unsaved changes; the file does not change until you save.';
  }

  @override
  String noteDraftMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This document has $count more drafts',
      one: 'This document has 1 more draft',
    );
    return '\n\n$_temp0; all are under «Recoverable drafts» on the home page.';
  }

  @override
  String get noteDraftDelete => 'Delete draft';

  @override
  String get noteCancel => 'Cancel';

  @override
  String get noteDraftOpen => 'Open draft';

  @override
  String get noteDraftDeleteTitle => 'Delete this draft?';

  @override
  String noteDraftDeleteBody(String name, String date) {
    return 'The unsaved draft of “$name” from $date will be deleted for good. The document itself does not change.';
  }

  @override
  String get noteUnsavedTitle => 'There are unsaved changes';

  @override
  String noteUnsavedBody(String what) {
    return 'Once $what is opened in the editor, it replaces your current unsaved changes. If you save first, today’s version stays in the document history too.';
  }

  @override
  String get noteOpenWithoutSaving => 'Open without saving';

  @override
  String get noteSaveFirst => 'Save first';

  @override
  String get speechPreparingVoice => 'Preparing the voice…';

  @override
  String get speechPaused => 'Paused';

  @override
  String get speechReading => 'Reading';

  @override
  String get speechSpeed => 'Reading speed';

  @override
  String get speechResume => 'Resume';

  @override
  String get speechPause => 'Pause';

  @override
  String get speechStopReading => 'Stop reading';

  @override
  String get speechPreparing => 'Preparing…';

  @override
  String get speechTranscribing => 'Transcribing…';

  @override
  String get speechListening => 'Listening, you can speak';

  @override
  String get speechFinish => 'Finish';

  @override
  String get speechTextUnreadable => 'The text could not be read';

  @override
  String get speechNothingToRead => 'There is no text to read';

  @override
  String get speechReadingStopped => 'Reading aloud stopped';

  @override
  String speechDownloadIntro(String need, String size, String offline) {
    return '$need ($size). The model is downloaded only once and kept on your computer. $offline';
  }

  @override
  String speechModelLicense(String license) {
    return 'Model license: $license';
  }

  @override
  String speechDownloadFailed(String error) {
    return 'The download could not be completed. What was downloaded is kept; when you try again, it continues where it left off.\n$error';
  }

  @override
  String get speechCancelDownload => 'Cancel';

  @override
  String get speechCancel => 'Not now';

  @override
  String speechDownload(String size) {
    return 'Download ($size)';
  }

  @override
  String get speechTryAgain => 'Try again';

  @override
  String get noteSecretSwitch => 'Private note · not shared with the office';

  @override
  String get noteSecretSwitchDetail =>
      'Goes only to your own devices. It is left out of tasks, shared files and generated documents.';

  @override
  String get noteSecretMark => 'Private';

  @override
  String get noteSecretRecalled => 'Deleted from the office’s copies.';

  @override
  String get noteSecretRecalling =>
      'Being deleted from the office’s copies; this finishes when the recipients’ devices are turned on.';

  @override
  String get noteSecretSharedTitle => 'This note was shared with the office';

  @override
  String noteSecretSharedBody(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people in the office have this note',
      one: '1 person in the office has this note',
    );
    return '$_temp0 ($names). If you make it private, it is deleted from them too.';
  }

  @override
  String get noteSecretNoRecall =>
      'Exported documents and screenshots cannot be taken back.';

  @override
  String get noteSecretConfirm => 'Make private';

  @override
  String get liveChat => 'Chat';

  @override
  String get liveClosePanel => 'Close panel';

  @override
  String get liveChatEmpty =>
      'Write to each other about the document here. The chat is deleted when sharing ends.';

  @override
  String get liveRemoveQuote => 'Remove quote';

  @override
  String get liveQuoteSelection => 'Quote the selection in the document';

  @override
  String get liveMessageHint => 'Write a message…';

  @override
  String get liveSend => 'Send';

  @override
  String get liveVerification => 'VERIFICATION';

  @override
  String get liveGuest => 'Guest';

  @override
  String get liveVisitorLeft => 'The person who came has left.';

  @override
  String get liveInviteCopied => 'Invitation copied';

  @override
  String get liveInviteMailSubject => 'Live document invitation';

  @override
  String get liveInviteAnother => 'Invite one more person';

  @override
  String get liveNewCode => 'Create a new code';

  @override
  String get livePreparingCode => 'Preparing the invitation code…';

  @override
  String get liveSendCode =>
      'Send the code to the other side. You will be asked when someone wants to join.';

  @override
  String get liveSendWhatsApp => 'Send with WhatsApp';

  @override
  String get liveCopy => 'Copy';

  @override
  String get liveEmail => 'Email';

  @override
  String get liveCopyInvite => 'Copy invitation';

  @override
  String liveCodeValidUntil(String time) {
    return 'Valid until $time, for one person. The document travels encrypted; the server in between cannot see its content.';
  }

  @override
  String get liveWantsToJoin => 'wants to join with the invitation code';

  @override
  String get liveDigitsMatchHost =>
      'If the same number shows on their screen, it is the right person.';

  @override
  String get liveDecline => 'Decline';

  @override
  String get liveLetView => 'View only';

  @override
  String get liveLetEdit => 'Can edit in turn';

  @override
  String liveJoinedName(String name) {
    return '$name joined.';
  }

  @override
  String get liveInviteWithdrawn => 'The invitation was withdrawn.';

  @override
  String get liveCodeExpired => 'The invitation code has expired.';

  @override
  String get liveInviteFailed => 'The invitation could not be set up.';

  @override
  String get liveCancel => 'Cancel';

  @override
  String get liveClose => 'Close';

  @override
  String get liveJoinPrompt =>
      'Type the code you were sent or paste the invitation link.';

  @override
  String get liveJoinName => 'Your name (as the sharer will see it)';

  @override
  String get liveJoin => 'Join';

  @override
  String get liveConnecting => 'Connecting…';

  @override
  String get liveAwaitingApproval => 'Waiting for approval';

  @override
  String get liveOpensOnApproval =>
      'The document opens once the sharer approves.';

  @override
  String get liveDigitsMatchGuest =>
      'The same number shows on the sharer’s screen.';

  @override
  String get liveJoinRefused => 'The sharer did not let you join.';

  @override
  String get liveJoinFailed => 'Could not join.';

  @override
  String get liveTryAgain => 'Try again';

  @override
  String get liveJoinTitle => 'Join a live document';

  @override
  String get liveShareTitle => 'Share live';

  @override
  String get liveOnThisNetwork => 'On this network';

  @override
  String get liveRemote => 'Remote';

  @override
  String get liveRemoteJoined => 'JOINED REMOTELY';

  @override
  String liveTakeBackPen(String name) {
    return 'Take back the pen · $name';
  }

  @override
  String get liveRemoteHint =>
      'The person who gets the code taps the link, or presses Live document in the app and types the code; once you approve, the document opens for them. The document stays with you; they keep nothing once sharing ends.';

  @override
  String get liveNearbyHint =>
      'A window opens in the app of the person you invite; when they press Join, the document opens for them. The document stays with you; they keep nothing once sharing ends. When you give the pen to someone who \"Can edit in turn\", what they write goes into your document.';

  @override
  String get liveStopSharing => 'Stop sharing';

  @override
  String get liveOk => 'OK';

  @override
  String get liveNoDevices =>
      'No device to invite is visible on this network. The app must be open on the other side and on the same Wi-Fi.';

  @override
  String get liveSearching => 'Looking for devices on this network…';

  @override
  String liveNetworkError(String error) {
    return 'Could not connect to the network: $error';
  }

  @override
  String get liveInvited => 'INVITED';

  @override
  String get liveMyDevices => 'MY DEVICES';

  @override
  String get liveOffice => 'OFFICE';

  @override
  String get liveNearby => 'NEARBY DEVICES';

  @override
  String get livePeerJoining => 'waiting for an answer';

  @override
  String get livePeerWatching => 'watching';

  @override
  String get livePeerGone => 'left';

  @override
  String get livePeerUnreachable => 'unreachable';

  @override
  String get livePeerDeclined => 'declined';

  @override
  String get livePeerUnanswered => 'did not answer';

  @override
  String get liveWithdraw => 'Withdraw';

  @override
  String get liveRemovePeer => 'Remove';

  @override
  String get liveInvite => 'Invite';

  @override
  String get liveInviteAgain => 'Invite again';

  @override
  String get liveGivePen => 'Give the pen';

  @override
  String get liveCanView => 'Can view only';

  @override
  String get liveCanEdit => 'Can edit in turn';

  @override
  String liveCodeChip(String code) {
    return 'code $code';
  }

  @override
  String get livePenHere => 'has the pen';

  @override
  String get liveDevice => 'Device';

  @override
  String get liveEnded =>
      'Sharing has ended; the document was not kept on this device.';

  @override
  String get livePenSyncing =>
      'You have the pen · the document is syncing with the sharer, wait a moment';

  @override
  String get livePenYours =>
      'You have the pen · what you write goes into the sharer’s document';

  @override
  String liveSharing(String name) {
    return '$name is sharing';
  }

  @override
  String liveWriting(String name) {
    return '$name is writing';
  }

  @override
  String get liveEditRefused => 'your request to edit was turned down';

  @override
  String get liveYouCanEdit => 'you can edit in turn';

  @override
  String get liveYouCanView => 'you can only view';

  @override
  String get liveReleasePen => 'Release the pen';

  @override
  String get livePenAsked => 'Requested';

  @override
  String get liveAskPen => 'Ask to edit';

  @override
  String get liveStopWatching => 'Stop watching';

  @override
  String get liveDocument => 'Live document';

  @override
  String get liveHubCodePrompt => 'Type the code you were sent:';

  @override
  String get liveHubOrShare => 'OR SHARE A DOCUMENT';

  @override
  String get liveHubPickPrompt =>
      'Choose the document to share. It opens, and the code to send to the other side appears right away.';

  @override
  String get liveHubPickOther => 'Choose another document…';

  @override
  String get liveSharesADocument => ' is sharing a document with you live.';

  @override
  String liveSharesDocument(String title) {
    return ' is sharing “$title” with you live.';
  }

  @override
  String get liveInviteTitle => 'Live sharing invitation';

  @override
  String get liveInviteCanEdit =>
      'You will see the document; when the sharer gives you the pen, you can write too. The document is not kept on this device after sharing ends.';

  @override
  String get liveInviteViewOnly =>
      'You can only view the document. It is not kept on this device after sharing ends.';

  @override
  String get liveBusyConnecting =>
      'Another connection is being set up right now.';

  @override
  String get liveHostUnverified => 'The inviting device could not be verified.';

  @override
  String get liveDocumentDidNotCome =>
      'The sharer accepted, but the document did not arrive.';

  @override
  String get liveSomeUser => 'Someone';

  @override
  String get liveHostWithdrew => 'The sharer withdrew the invitation.';

  @override
  String get liveConnectFailed => 'The connection could not be set up.';

  @override
  String get liveOpeningDocument => 'Opening the document…';

  @override
  String get liveConnectingHost => 'Connecting to the sharer’s device…';

  @override
  String get liveGuestCodeNote =>
      'The same code shows on the sharer’s screen. The document is visible only while this sharing lasts; it is not kept on this device afterwards.';

  @override
  String get tbAddColumn => 'Add column';

  @override
  String get tbAddRow => 'Add row';

  @override
  String get tbAlignCenter => 'Center · Ctrl+E';

  @override
  String get tbAlignLeft => 'Align left · Ctrl+L';

  @override
  String get tbAlignRight => 'Align right · Ctrl+R';

  @override
  String get tbAllFormatting => 'All formatting tools…';

  @override
  String tbAllPages(int count) {
    return 'All pages ($count)';
  }

  @override
  String get tbApply => 'Apply';

  @override
  String get tbAttachToEmail => 'Attach to email';

  @override
  String get tbAttachToEmailHelp =>
      'A new message opens with the file attached';

  @override
  String get tbBlue => 'Blue';

  @override
  String get tbBold => 'Bold · Ctrl+B';

  @override
  String get tbBoldLabel => 'Bold';

  @override
  String get tbBullets => 'Bullets · Ctrl+Shift+L';

  @override
  String get tbCancel => 'Cancel';

  @override
  String get tbChooseFolder => 'Choose folder';

  @override
  String get tbChoosePageToPrint => 'Choose the pages to print.';

  @override
  String get tbChooseTargetFolder => 'Choose the destination folder';

  @override
  String get tbClearFormatting => 'Clear formatting';

  @override
  String get tbClose => 'Close';

  @override
  String get tbCollate => 'Collate';

  @override
  String get tbConvertToPdf => 'Convert to PDF';

  @override
  String tbCopiedTo(String target) {
    return 'Copied: $target';
  }

  @override
  String get tbCopiesLabel => 'copies';

  @override
  String get tbCopyFile => 'Copy file';

  @override
  String get tbCopyFileHelp => 'Paste it into an email, a chat or a folder';

  @override
  String get tbCopyToFolder => 'Copy to folder';

  @override
  String get tbCopyToFolderHelp => 'Choose a USB drive or another folder';

  @override
  String tbCurrentPage(int page) {
    return 'Current page ($page)';
  }

  @override
  String get tbCustomSize => 'Custom size…';

  @override
  String get tbDefaultLetterheadName => 'My letterhead';

  @override
  String get tbDelete => 'Delete';

  @override
  String get tbDeleteColumn => 'Delete column';

  @override
  String get tbDeleteRow => 'Delete row';

  @override
  String get tbDeleteTable => 'Delete table';

  @override
  String get tbDictate => 'Dictate';

  @override
  String get tbDictateShortTip =>
      'Dictate · what you say is typed at the cursor';

  @override
  String get tbDictateTip => 'Types what you say at the cursor';

  @override
  String get tbDocumentHistory => 'Document history';

  @override
  String get tbDrawBorders => 'Draw borders';

  @override
  String get tbEvenPagesOnly => 'Even pages only';

  @override
  String get tbFile => 'File';

  @override
  String get tbFileCopied =>
      'File copied. You can paste it into the target app.';

  @override
  String get tbFileMenu => 'File menu';

  @override
  String get tbFind => 'Find';

  @override
  String get tbFindInDocument => 'Find in document · Ctrl+F';

  @override
  String get tbFindReplace => 'Find and replace · Ctrl+H';

  @override
  String get tbFirstPageOnly => 'First page only';

  @override
  String get tbFirstPageOnlyHelp =>
      'When off, the letterhead is printed at the top of every page.';

  @override
  String get tbFont => 'Font';

  @override
  String tbFontCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fonts',
      one: '1 font',
    );
    return '$_temp0 · System and document fonts';
  }

  @override
  String get tbFontSizePoints => 'Font size (pt)';

  @override
  String get tbFontSizeTitle => 'Font size';

  @override
  String get tbFooter => 'Footer';

  @override
  String get tbGreen => 'Green';

  @override
  String get tbGrey => 'Grey';

  @override
  String get tbGridlinesNotPrinted => 'gridlines are not printed';

  @override
  String get tbGroupEditing => 'Editing';

  @override
  String get tbGroupHistory => 'History';

  @override
  String get tbGroupInsert => 'Insert';

  @override
  String get tbGroupParagraph => 'Paragraph';

  @override
  String get tbGroupStyle => 'Style';

  @override
  String get tbGroupView => 'View';

  @override
  String get tbGroupVoice => 'Voice';

  @override
  String get tbGrowFont => 'Increase font size';

  @override
  String get tbHeader => 'Header';

  @override
  String get tbHeaderFooter => 'Header and footer';

  @override
  String get tbHeaderFooterShort => 'Header/footer';

  @override
  String get tbHorizontalRuler => 'Horizontal ruler';

  @override
  String get tbHowToUsePage => 'How do I use this page?';

  @override
  String get tbImageColumn25 => '25% of column';

  @override
  String get tbImageColumn33 => '33% of column';

  @override
  String get tbImageColumn75 => '75% of column';

  @override
  String get tbImageColumnWidth => 'Column width';

  @override
  String get tbImageHalfColumn => 'Half column';

  @override
  String get tbImageOriginalSize => 'Original size';

  @override
  String get tbImageUndrawable => '〔Picture could not be drawn — kept on save〕';

  @override
  String get tbImageUnreadable => '〔Picture could not be read — kept on save〕';

  @override
  String get tbImageWidth => 'Picture width';

  @override
  String get tbInNewDocuments => 'In new documents';

  @override
  String get tbIndentDecrease => 'Decrease indent · Ctrl+Shift+M';

  @override
  String get tbIndentIncrease => 'Increase indent · Ctrl+M';

  @override
  String get tbInsertTable => 'Insert table';

  @override
  String get tbItalic => 'Italic · Ctrl+I';

  @override
  String get tbJustify => 'Justify · Ctrl+J';

  @override
  String get tbKeyboardShortcuts => 'Keyboard shortcuts';

  @override
  String get tbLetterheadMenu => 'Letterhead…';

  @override
  String get tbLetterheads => 'Letterheads';

  @override
  String get tbLightGrey => 'Light grey';

  @override
  String get tbLineSpacing => 'Line spacing';

  @override
  String tbLineSpacingValue(String value) {
    return '$value lines';
  }

  @override
  String get tbLiveShare => 'Share live…';

  @override
  String get tbMixed => 'Mixed';

  @override
  String get tbMore => 'More';

  @override
  String get tbMoreTools => 'More editing tools';

  @override
  String get tbName => 'Name';

  @override
  String get tbNewDocument => 'New document';

  @override
  String get tbNewWindow => 'New window';

  @override
  String get tbNextPage => 'Next page';

  @override
  String get tbNoFill => 'No fill';

  @override
  String get tbNoFontFound => 'No font found';

  @override
  String get tbNoLetterheads =>
      'No letterheads yet. Design the letterhead in the document\'s header: text, alignment, and a logo with Insert › Picture. Then save it as a letterhead below; it can be added to any document with one click.';

  @override
  String get tbNoRecentDocuments => 'No documents opened yet';

  @override
  String get tbNormalText => 'Normal text';

  @override
  String get tbNotPrinted => 'Not printed';

  @override
  String get tbNumbering => 'Numbered list · Ctrl+Shift+7';

  @override
  String get tbOddAndEvenPages => 'Odd and even pages';

  @override
  String get tbOddPagesOnly => 'Odd pages only';

  @override
  String get tbOk => 'OK';

  @override
  String get tbOneCopyFewer => 'One copy fewer';

  @override
  String get tbOneCopyMore => 'One copy more';

  @override
  String get tbOpen => 'Open…';

  @override
  String get tbPageNumber => 'Page number';

  @override
  String get tbPageNumberBottom => 'Bottom';

  @override
  String get tbPageNumberCenter => 'Center';

  @override
  String get tbPageNumberFont => 'Font';

  @override
  String get tbPageNumberFormat => 'Format';

  @override
  String get tbPageNumberInFooter => 'In footer';

  @override
  String get tbPageNumberInHeader => 'In header';

  @override
  String get tbPageNumberLeft => 'Left';

  @override
  String get tbPageNumberMenu => 'Page number…';

  @override
  String get tbPageNumberNone => 'None';

  @override
  String get tbPageNumberPosition => 'Position';

  @override
  String get tbPageNumberPrefix => 'Text before';

  @override
  String get tbPageNumberPrefixHint => 'Page ';

  @override
  String get tbPageNumberRight => 'Right';

  @override
  String get tbPageNumberSkipFirst => 'Hide on first page';

  @override
  String get tbPageNumberSkipSingle => 'Hide if only one page';

  @override
  String get tbPageNumberStart => 'Start at';

  @override
  String get tbPageNumberTop => 'Top';

  @override
  String get tbPageNumberWithTotal => 'With page count';

  @override
  String get tbPageRange => 'Page range';

  @override
  String get tbPageRangeHint => 'e.g. 1-3, 5, 8-';

  @override
  String tbPageRangeInvalid(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The document has $count pages',
      one: 'The document has 1 page',
    );
    return '$_temp0; check the range.';
  }

  @override
  String get tbPages => 'Pages';

  @override
  String get tbParagraphStyle => 'Paragraph style';

  @override
  String tbPdfPrepareFailed(String error) {
    return 'Could not prepare the PDF: $error';
  }

  @override
  String get tbPdfSaveFailed => 'Could not save the PDF';

  @override
  String get tbPdfSaved => 'PDF saved';

  @override
  String get tbPickSize => 'Choose a size';

  @override
  String get tbPicture => 'Picture';

  @override
  String get tbPageBreakMenu => 'Page break (Ctrl+Enter)';

  @override
  String get tbPointSize => 'Size (pt)';

  @override
  String get tbPointSizeHelp => 'Between 1 and 200, for example 10.5';

  @override
  String tbPreviewFailed(String error) {
    return 'Could not open the preview: $error';
  }

  @override
  String get tbPreviousPage => 'Previous page';

  @override
  String get tbPrint => 'Print';

  @override
  String get tbPrintFailed => 'Could not print';

  @override
  String get tbPrintShortcut => 'Print · Ctrl+P';

  @override
  String tbPrintSummary(int pages, int sheets) {
    String _temp0 = intl.Intl.pluralLogic(
      pages,
      locale: localeName,
      other: '$pages pages',
      one: '1 page',
    );
    String _temp1 = intl.Intl.pluralLogic(
      sheets,
      locale: localeName,
      other: '$sheets A4 sheets',
      one: '1 A4 sheet',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String tbPrintSummaryCopies(int pages, int copies, int sheets) {
    String _temp0 = intl.Intl.pluralLogic(
      pages,
      locale: localeName,
      other: '$pages pages',
      one: '1 page',
    );
    String _temp1 = intl.Intl.pluralLogic(
      sheets,
      locale: localeName,
      other: '$sheets A4 sheets',
      one: '1 A4 sheet',
    );
    return '$_temp0 × $copies copies · $_temp1';
  }

  @override
  String get tbPrinter => 'Printer';

  @override
  String tbPrinterDefault(String name) {
    return '$name  (default)';
  }

  @override
  String get tbPrinterInSystemDialog =>
      'You will choose the printer in the system\'s print dialog.';

  @override
  String get tbProtectedContent => '〔Protected content — kept on save〕';

  @override
  String get tbReadAloud => 'Read aloud';

  @override
  String get tbReadAloudShortTip =>
      'Read aloud · the selection, or from the cursor on';

  @override
  String get tbReadAloudTip => 'Reads the selection, or from the cursor on';

  @override
  String get tbRecent => 'Recent';

  @override
  String get tbRecoverableDrafts => 'Recoverable drafts';

  @override
  String get tbRed => 'Red';

  @override
  String get tbRedo => 'Redo · Ctrl+Y';

  @override
  String get tbRemoveBorders => 'Remove borders';

  @override
  String get tbRename => 'Rename';

  @override
  String get tbRenameLetterhead => 'Rename letterhead';

  @override
  String get tbReplace => 'Replace';

  @override
  String get tbReplaceLetterheadBody =>
      'The letterhead saved under this name will be replaced with the document\'s header.';

  @override
  String tbReplaceLetterheadTitle(String name) {
    return 'Replace \"$name\"?';
  }

  @override
  String tbRibbonTip(String tab) {
    return 'Ribbon: $tab';
  }

  @override
  String tbSample(String sample) {
    return 'Sample: $sample';
  }

  @override
  String get tbSave => 'Save';

  @override
  String get tbSaveAs => 'Save as…';

  @override
  String get tbSaveAsDocx => 'Save as Word (DOCX)';

  @override
  String get tbSaveAsPdf => 'Save as PDF';

  @override
  String get tbSaveAsRtf => 'Save as Rich Text (RTF)';

  @override
  String get tbSaveAsUdf => 'Save as UYAP UDF';

  @override
  String get tbSaveFolderBody =>
      'You choose once; after that, Save writes straight there. Documents you sign are saved there too.';

  @override
  String get tbSaveFolderTitle => 'Where should documents be saved?';

  @override
  String get tbSaveHeaderAsLetterhead => 'Save header as letterhead';

  @override
  String get tbSaveHeaderAsLetterheadEllipsis => 'Save header as letterhead…';

  @override
  String get tbSaveSelectedPagesPdf => 'Save selected pages as PDF';

  @override
  String get tbSavedCopyUsed => 'The copy saved on disk is used.';

  @override
  String get tbSearchFonts => 'Search fonts…';

  @override
  String get tbSelectWholeTable => 'Select whole table';

  @override
  String get tbShadeCell => 'Shade cell';

  @override
  String get tbShadeTable => 'Shade table';

  @override
  String get tbShare => 'Share';

  @override
  String tbShareAsKind(String kind) {
    return 'Share as $kind';
  }

  @override
  String get tbShareAsPdf => 'Share as PDF';

  @override
  String get tbShareAsPdfHelp => 'Opens on any phone or computer';

  @override
  String get tbShareEllipsis => 'Share…';

  @override
  String tbShareFailed(String error) {
    return 'Could not share: $error';
  }

  @override
  String get tbShareMacHelp => 'AirDrop, Messages and installed apps';

  @override
  String get tbShareOriginalHelp => 'The file itself, as it is';

  @override
  String get tbShareSend => 'Share / Send';

  @override
  String get tbShareWindowsHelp => 'Choose from installed sharing apps';

  @override
  String get tbShareWithWindows => 'Share with Windows';

  @override
  String get tbShortcuts => 'Shortcuts';

  @override
  String get tbShrinkFont => 'Decrease font size';

  @override
  String get tbSignUdf => 'E-sign UDF';

  @override
  String get tbSnippets => 'Snippets';

  @override
  String get tbSnippetsShortcut => 'Snippets · Ctrl+Space';

  @override
  String get tbStrikethrough => 'Strikethrough';

  @override
  String get tbSubscript => 'Subscript';

  @override
  String get tbSuperscript => 'Superscript';

  @override
  String get tbSystemPrintDialog => 'System print dialog…';

  @override
  String get tbTabHome => 'Home';

  @override
  String get tbTabInsert => 'Insert';

  @override
  String get tbTabResearch => 'Research';

  @override
  String get tbTabView => 'View';

  @override
  String get tbTable => 'Table';

  @override
  String get tbTableSelectedRelease => 'Table selected — release';

  @override
  String tbTableSize(int rows, int columns) {
    return '$rows × $columns table';
  }

  @override
  String get tbTextAndParagraph => 'Text and paragraph';

  @override
  String get tbUnderline => 'Underline · Ctrl+U';

  @override
  String get tbUndo => 'Undo · Ctrl+Z';

  @override
  String get tbUseInNewDocuments => 'Use in new documents';

  @override
  String get tbVerticalRuler => 'Vertical ruler';

  @override
  String get tbViewRulers => 'View and rulers';

  @override
  String get tbYellow => 'Yellow';

  @override
  String get viewClose => 'Close';

  @override
  String get viewCloseEsc => 'Close · Esc';

  @override
  String get viewCloseEscParen => 'Close (Esc)';

  @override
  String get viewCancel => 'Cancel';

  @override
  String get viewFirstPage => 'First Page';

  @override
  String get viewPreviousPage => 'Previous Page';

  @override
  String get viewNextPage => 'Next Page';

  @override
  String get viewLastPage => 'Last Page';

  @override
  String get viewZoomIn => 'Zoom in';

  @override
  String get viewZoomOut => 'Zoom out';

  @override
  String get viewZoomInKey => 'Zoom in (+)';

  @override
  String get viewZoomOutKey => 'Zoom out (−)';

  @override
  String get viewRotateLeft => 'Rotate 90° left';

  @override
  String get viewRotateRight => 'Rotate 90° right';

  @override
  String get viewRotateRightKey => 'Rotate 90° right (R)';

  @override
  String get viewFit => 'Fit';

  @override
  String get viewFitKey => 'Fit (0)';

  @override
  String viewPreviewFailed(String error) {
    return 'The preview could not be opened: $error';
  }

  @override
  String get viewHighlightSaveFailed => 'The highlight could not be saved';

  @override
  String get viewThisColor => 'This color';

  @override
  String get viewChangeColor => 'Change the color';

  @override
  String get viewDeleteHighlight => 'Delete highlight';

  @override
  String get viewFindInDocument => 'Find in document';

  @override
  String get viewFindKey => 'Find in document (Ctrl+F)';

  @override
  String viewPixels(int width, int height) {
    return '$width × $height px';
  }

  @override
  String get viewSearching => 'searching…';

  @override
  String get viewNotFound => 'not found';

  @override
  String get viewPreviousMatch => 'Previous · Shift+Enter';

  @override
  String get viewNextMatch => 'Next · Enter';

  @override
  String get viewFitPage => 'Fit page';

  @override
  String get viewFitWidth => 'Fit width';

  @override
  String get viewFreeZoom => 'Free zoom';

  @override
  String get viewCitations => 'References · articles and decisions';

  @override
  String get viewHighlightSelection => 'Highlight selection';

  @override
  String get viewSelectToHighlight => 'Select text to highlight';

  @override
  String get viewHighlightColor => 'Highlight color';

  @override
  String get viewPageOpenFailed => 'This page could not be opened.';

  @override
  String viewPageOf(int page, int count) {
    return 'Page $page / $count';
  }

  @override
  String get viewTifToPdf => 'Convert TIF → PDF';

  @override
  String get viewHeicAndroidOnly =>
      'iPhone photos (HEIC) open only on Android for now.';

  @override
  String get viewPhotoDecodeFailed => 'The photo could not be decoded.';

  @override
  String get viewCropFailed => 'Could not crop';

  @override
  String get viewCropUnmeasured =>
      'This image could not be measured, so it cannot be cropped';

  @override
  String get viewCrop => 'Crop';

  @override
  String get viewFullScreenKey => 'Full screen (F, or double-click)';

  @override
  String get viewNextPhoto => 'Next photo (→)';

  @override
  String get viewPreviousPhoto => 'Previous photo (←)';

  @override
  String get viewCropDrag => 'Drag over the part you want to keep';

  @override
  String get viewCropKeepsOriginal =>
      'The original stays as it is; the cropped copy is saved next to it';

  @override
  String viewSvgOpenFailed(String error) {
    return 'The SVG could not be opened: $error';
  }

  @override
  String get viewImageOpenFailed => 'The image could not be opened.';

  @override
  String get viewCopy => 'Copy';

  @override
  String get viewReadAloud => 'Read aloud';

  @override
  String get viewSelectAll => 'Select all';

  @override
  String get viewFormatNotPreviewable => 'This format cannot be previewed.';

  @override
  String get viewImzSaveDialog => 'Save the content of the signed document';

  @override
  String get viewDocumentSaved => 'Document saved';

  @override
  String viewImzIdNumber(String id) {
    return 'Turkish ID no.: $id';
  }

  @override
  String viewImzSignedAt(String date) {
    return 'Signed on: $date';
  }

  @override
  String viewImzIssuer(String issuer) {
    return 'Certificate issued by: $issuer';
  }

  @override
  String get viewImzUnnamedSigner => 'Signer whose name could not be read';

  @override
  String get viewImzValid => 'E-signature is valid';

  @override
  String get viewImzInvalid =>
      'E-signature could not be verified: the document may have changed after signing';

  @override
  String get viewImzCheckedNote =>
      'The signature was checked against the document inside it and the signer’s own certificate. Whether the certificate was issued by an authorized provider and has not been revoked was not checked.';

  @override
  String get viewImzSaveDocument => 'Save document…';

  @override
  String get viewImzUnreadable =>
      'This file could not be read: it is not an e-signature file containing a document, or it is damaged.';

  @override
  String viewImzInsideNotShown(String name) {
    return 'The document inside ($name) cannot be shown here; you can save it and open it.';
  }

  @override
  String get viewOcrTitle => 'Text extracted for search';

  @override
  String get viewOcrNote =>
      'This is not an exact transcript: there may be recognition errors, and boxed sections may mix into the main text. The source document has not changed.';

  @override
  String get viewOcrCopy => 'Copy text';

  @override
  String get viewOcrCopied => 'Text copied to the clipboard.';

  @override
  String get viewOcrReading => 'Reading…';

  @override
  String get viewOcrShowDocument => 'Show document';

  @override
  String get viewOcrShowText => 'Recognized text';

  @override
  String get viewOcrNothingFound => 'No readable text was found';

  @override
  String get viewOcrRun => 'Convert to text';

  @override
  String get viewDraftDeleteFailed => 'The draft could not be deleted';

  @override
  String get viewDeleteAllDraftsTitle => 'Delete all drafts?';

  @override
  String viewDeleteAllDraftsBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unsaved drafts will be permanently deleted.',
      one: '1 unsaved draft will be permanently deleted.',
    );
    return '$_temp0 The documents themselves do not change.';
  }

  @override
  String get viewDeleteAll => 'Delete all';

  @override
  String get viewDraftsDeleteFailed => 'The drafts could not be deleted';

  @override
  String get viewDraftNeverSaved => 'New document, never saved';

  @override
  String viewDraftSourceGone(String source) {
    return 'The source file no longer exists; it opens as a new document\n$source';
  }

  @override
  String get viewDraftsTitle => 'Recoverable drafts';

  @override
  String get viewDraftsNote =>
      'The last state of documents closed without saving is kept on this device. When you open a draft, it comes into the editor as unsaved changes; nothing is written to the file until you save.';

  @override
  String get viewDraftsUnreachable => 'The local drafts could not be reached.';

  @override
  String get viewDraftsEmpty => 'There are no drafts waiting to be recovered.';

  @override
  String get viewDeleteDraft => 'Delete draft';

  @override
  String get viewVersionUnreadable => 'This version could not be read.';

  @override
  String get viewToday => 'Today';

  @override
  String get viewYesterday => 'Yesterday';

  @override
  String get viewSaveVersionCopyDialog => 'Save the version as a copy';

  @override
  String get viewCopyOverOriginal =>
      'A copy cannot be written over the document itself';

  @override
  String viewCopyOverOriginalHint(String label) {
    return 'To bring the document back to this version, use the “$label” button.';
  }

  @override
  String get viewCopySaved => 'Copy saved.';

  @override
  String get viewCopySaveFailed => 'The copy could not be saved';

  @override
  String get viewVersionList => 'Version list';

  @override
  String get viewHistoryTitle => 'Document history';

  @override
  String get viewHistoryNote =>
      'Each time you save, the previous and new versions of the file are kept on this device: the last 20 versions per document, up to 100 MB.';

  @override
  String get viewHistoryUnreachable =>
      'The local history could not be reached.';

  @override
  String get viewHistoryEmpty =>
      'No versions of this document have been kept yet.';

  @override
  String get viewHistoryEmptyHint =>
      'The first time you save the document, the file as it was until then and the new version you saved are listed here.';

  @override
  String get viewSigned => 'E-signed';

  @override
  String get viewSaveCopy => 'Save a copy';

  @override
  String get viewOtherFormatHint =>
      'This version was kept in another format; you can save it as a copy.';

  @override
  String get viewCompareCurrent => 'Compare with current';

  @override
  String get viewPageView => 'Page view';

  @override
  String viewPageViewFailed(String error) {
    return 'The page view could not be prepared: $error';
  }

  @override
  String get viewTypeNotShown =>
      'This kind of document cannot be shown here. Use “Save as copy” to open it as a separate file.';

  @override
  String viewCompareFailed(String error) {
    return 'Could not compare: $error';
  }

  @override
  String get viewCompareUnsupported =>
      'Text cannot be compared in this kind of document; you can look at the version in “Page view”.';

  @override
  String get viewCompareIdentical =>
      'The text of this version is the same as now. Formatting differences such as fonts and spacing are not shown here; see “Page view”.';

  @override
  String viewDiffSummary(int added, int removed) {
    String _temp0 = intl.Intl.pluralLogic(
      added,
      locale: localeName,
      other: '$added words were added',
      one: '1 word was added',
    );
    String _temp1 = intl.Intl.pluralLogic(
      removed,
      locale: localeName,
      other: '$removed words were removed',
      one: '1 word was removed',
    );
    return 'Since this version, $_temp0 and $_temp1.';
  }

  @override
  String get viewAddedLater => 'Added later';

  @override
  String get viewRemovedLater => 'Removed later';

  @override
  String viewUnchangedLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unchanged lines',
      one: '1 unchanged line',
    );
    return '⋯ $_temp0 ⋯';
  }

  @override
  String get viewRestoreVersion => 'Restore this version';

  @override
  String viewAboutProduct(String name) {
    return 'About $name';
  }

  @override
  String get viewWindowActionFailed =>
      'The window action could not be completed';

  @override
  String get viewAbout => 'About';

  @override
  String get viewFullScreen => 'Full screen';

  @override
  String get viewExitFullScreen => 'Exit full screen';

  @override
  String get viewMinimize => 'Minimize';

  @override
  String get viewRestoreSize => 'Restore down';

  @override
  String get viewMaximize => 'Maximize';

  @override
  String get viewHideToTray => 'Hide to tray';

  @override
  String get viewCloseApp => 'Close the app';

  @override
  String get viewAddressOpenFailed => 'The address could not be opened';

  @override
  String viewVersion(String version, String build) {
    return 'Version $version ($build)';
  }

  @override
  String get viewAboutTaglineOfis =>
      'The app that opens, edits and signs documents';

  @override
  String get viewAboutTaglineFolio =>
      'Petition, case and office app for lawyers';

  @override
  String get viewAboutDescOfis =>
      'With Ofis you open, edit and print your UDF, Word, ODT, RTF and PDF documents and sign them with your e-signature card. You check references to statutes and court decisions, find spelling mistakes, have text read aloud and dictate what you want written.';

  @override
  String get viewAboutDescFolio =>
      'With Folio you write your UDF petition, sign it with an e-signature or mobile signature and send it to your case file. You manage your clients, your hearing and deadline calendar, your office’s accounts and your team from the same app.';

  @override
  String get viewAboutDataOfis =>
      'Your data is kept only on your own devices. Ofis has no server that holds your data, and it uses no AI service. When you share live with another office remotely, documents and messages pass encrypted through our relay server; the server cannot see the content and stores nothing.';

  @override
  String get viewAboutDataFolio =>
      'Your data is kept only on your own devices. Folio has no server that holds your data. AI features are optional and stay off unless you turn them on. When you share live with another office remotely, documents and messages pass encrypted through our relay server; the server cannot see the content and stores nothing.';

  @override
  String get viewAgreements => 'AGREEMENTS';

  @override
  String get viewTermsTitle => 'Terms of Use';

  @override
  String get viewTermsSubtitle => 'License to use and responsibilities';

  @override
  String get viewPrivacyTitle => 'Privacy and KVKK Notice';

  @override
  String get viewPrivacySubtitle => 'How your personal data is protected';

  @override
  String get viewLicenseTitle => 'License';

  @override
  String get viewLicenseSubtitle => 'Proprietary software';

  @override
  String get viewOpenSourceLicenses => 'Open source licenses';

  @override
  String get viewComponentsSubtitle => 'Components used in the app';

  @override
  String get viewSupport => 'SUPPORT';

  @override
  String get viewDownloadOther => 'Download to your other devices';

  @override
  String get viewContact => 'Support and contact';

  @override
  String get viewContactSubtitle => 'Write to us with the contact form';

  @override
  String get viewWebsite => 'The app’s website';

  @override
  String viewCopyright(String product) {
    return '© 2026 LifeOS. All rights reserved. $product is proprietary software, not open source.';
  }

  @override
  String get pdfPagesTitle => 'Extract pages';

  @override
  String get pdfPagesHint =>
      'Choose the pages to take into a PDF of their own; their order can be typed in the box below too.';

  @override
  String get pdfPagesRange => 'Pages (for example: 1-3, 5)';

  @override
  String get pdfPagesAll => 'Select all';

  @override
  String get pdfPagesNone => 'Clear selection';

  @override
  String pdfPagesCount(int count) {
    return '$count pages selected';
  }

  @override
  String get pdfPagesBad => 'The page numbers could not be read.';

  @override
  String get pdfSave => 'Save as PDF';

  @override
  String pdfSaved(String name) {
    return '$name saved.';
  }

  @override
  String get pdfOpen => 'Open';

  @override
  String get pdfFailed => 'The PDF could not be made';

  @override
  String get pdfBuildTitle => 'Make a PDF';

  @override
  String get pdfBuildHint =>
      'Add pictures, scans (TIFF) and PDFs and put them in order. Each picture becomes a page; to take only some pages of a PDF or a scan, type their numbers.';

  @override
  String get pdfBuildAdd => 'Add files';

  @override
  String get pdfBuildAllPages => 'All';

  @override
  String get pdfBuildPagesLabel => 'Pages';

  @override
  String pdfBuildPagesOf(int count) {
    return '$count pages';
  }

  @override
  String get pdfBuildPicture => 'Picture · 1 page';

  @override
  String get pdfBuildRemove => 'Remove';

  @override
  String pdfBuildTotal(int count) {
    return 'A PDF of $count pages';
  }

  @override
  String get pdfBuildEmpty => 'No files added yet.';

  @override
  String get pdfSplitTool => 'Extract pages: a PDF of the pages you choose';

  @override
  String get pdfBuildTool => 'Make a PDF: add pictures and PDFs and join them';

  @override
  String get viewPrintKey => 'Print (Ctrl+P)';

  @override
  String get viewSaveAsPdf => 'Save as PDF';

  @override
  String get viewOpenInFolio => 'Open in Folio';

  @override
  String get viewShowInFolder => 'Show in folder';

  @override
  String get viewMore => 'File actions';

  @override
  String get viewThumbnails => 'Page thumbnails';

  @override
  String get ofisMakePdf => 'Make a PDF';

  @override
  String get ofisMakePdfDetail => 'Join pictures and PDFs into one PDF.';

  @override
  String photoOpenFailed(String error) {
    return 'The picture could not be opened: $error';
  }

  @override
  String photoSaveFailed(String error) {
    return 'Could not be saved: $error';
  }

  @override
  String get photoTitle => 'Edit picture';

  @override
  String get photoUndo => 'Undo';

  @override
  String get photoSaveCopy => 'Save a copy';

  @override
  String get photoNote => 'Note';

  @override
  String get photoNoteHint => 'Type here';

  @override
  String get photoAdd => 'Add';

  @override
  String get photoBrightness => 'Brightness';

  @override
  String get photoContrast => 'Contrast';

  @override
  String get photoSharpness => 'Sharpness';

  @override
  String get photoPen => 'Pen';

  @override
  String get photoText => 'Text';

  @override
  String get photoRedactHint =>
      'Drag over what you want covered. It is burnt into the saved picture and cannot be taken off.';

  @override
  String get photoTextHint => 'Click where the note goes.';

  @override
  String get photoDrawHint => 'Drag to draw.';

  @override
  String get photoLookOriginal => 'Original';

  @override
  String get photoLookDocument => 'Document';

  @override
  String get photoLookGray => 'Grey';

  @override
  String get photoLookColorDocument => 'Colour document';

  @override
  String get photoToolCorners => 'Straighten';

  @override
  String get photoToolCrop => 'Crop';

  @override
  String get photoToolRotate => 'Rotate';

  @override
  String get photoToolAdjust => 'Adjust';

  @override
  String get photoToolRedact => 'Redact';

  @override
  String get photoToolDraw => 'Mark up';

  @override
  String get viewEditPicture =>
      'Edit picture: straighten by its corners, crop, adjust, redact, mark up';

  @override
  String get photoTilt => 'Tilt';

  @override
  String get photoTurn => 'Turn 90°';

  @override
  String get photoFlipH => 'Flip horizontally';

  @override
  String get photoFlipV => 'Flip vertically';

  @override
  String get photoTiltReset => 'Reset tilt';
}
