import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide BorderStyle;
import 'package:flutter/services.dart' hide UndoManager;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:worksheet/worksheet.dart';

import '../../services/editor/document_history.dart';
import '../../services/editor/editor_drafts.dart';
import '../../services/platform/android_document_save.dart';
import '../../services/platform/atomic_file.dart';
import '../../services/search/search_models.dart';
import '../../services/spreadsheet/formula_locale.dart';
import '../../services/spreadsheet/workbook.dart';
import 'document_versions_window.dart';
import 'draft_prompts.dart';
import 'notice.dart';
import 'spreadsheet_viewer.dart';

/// Numbers, dates and currency the way Turkish reads them.
const _turkish = FormatLocale(
  monthNames: [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ],
  monthAbbr: [
    'Oca',
    'Şub',
    'Mar',
    'Nis',
    'May',
    'Haz',
    'Tem',
    'Ağu',
    'Eyl',
    'Eki',
    'Kas',
    'Ara',
  ],
  dayNames: [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ],
  dayAbbr: ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'],
  decimalSeparator: ',',
  thousandsSeparator: '.',
  currencySymbol: '₺',
  dayFirst: true,
);

const _formats = <(String, String?)>[
  ('Genel', null),
  ('Sayı · 1.234,56', '#,##0.00'),
  ('Tam sayı · 1.235', '#,##0'),
  ('Para · 1.234,56 ₺', '#,##0.00 "₺"'),
  ('Yüzde · %12', '0%'),
  ('Yüzde · %12,34', '0.00%'),
  ('Tarih · 31.12.2026', 'dd.mm.yyyy'),
  ('Tarih ve saat · 31.12.2026 14:30', 'dd.mm.yyyy hh:mm'),
  ('Metin', '@'),
];

const _palette = <Color>[
  Color(0xFF000000),
  Color(0xFF44546A),
  Color(0xFF4472C4),
  Color(0xFFED7D31),
  Color(0xFFA5A5A5),
  Color(0xFFFFC000),
  Color(0xFF5B9BD5),
  Color(0xFF70AD47),
  Color(0xFFFFFFFF),
  Color(0xFFE7E6E6),
  Color(0xFFC00000),
  Color(0xFFFF0000),
  Color(0xFFFFFF00),
  Color(0xFF92D050),
  Color(0xFF00B050),
  Color(0xFF00B0F0),
  Color(0xFF0070C0),
  Color(0xFF002060),
  Color(0xFF7030A0),
  Color(0xFFFCE4D6),
];

/// The controllers one sheet keeps while its workbook is open, so going to
/// another sheet and back keeps the selection and the undo history.
class _Controllers {
  _Controllers() : undo = UndoManager(), edit = EditController() {
    grid = WorksheetController(undoManager: undo);
  }
  final UndoManager undo;
  final EditController edit;
  late final WorksheetController grid;
  void dispose() {
    grid.dispose();
    edit.dispose();
    undo.dispose();
  }
}

/// An .xlsx workbook, edited the way a spreadsheet is: values and formulas
/// in cells, formulas worked out, the cells' font, fill, alignment and number
/// format, merged cells, several sheets. Saved back into the same file, with
/// everything the editor does not touch left as the file had it.
class SpreadsheetEditor extends StatefulWidget {
  final String? path;
  final EditorDraft? draft;
  final DocumentRevision? recovery;
  final ValueChanged<String>? onSaved;
  const SpreadsheetEditor({
    super.key,
    this.path,
    this.draft,
    this.recovery,
    this.onSaved,
  });

  @override
  State<SpreadsheetEditor> createState() => _SpreadsheetEditorState();
}

class _SpreadsheetEditorState extends State<SpreadsheetEditor>
    with WidgetsBindingObserver {
  final String _draftKey = DocumentHistory.draftKey();
  late final DraftRecovery _recovery;
  Workbook? _book;
  final _controllers = <int, _Controllers>{};
  int _sheet = 0;
  String? _error, _savedPath;
  bool _loading = true, _saving = false;
  DocumentRevision? _leftDraft;
  int _leftDrafts = 0;
  final _formula = TextEditingController();
  final _formulaFocus = FocusNode(debugLabel: 'formula-bar');
  final _find = TextEditingController();
  final _findFocus = FocusNode(debugLabel: 'sheet-find');
  _Controllers? _listened;

  String get _name => p.basename(
    _savedPath ?? widget.path ?? widget.recovery?.name ?? 'Yeni tablo.xlsx',
  );
  WorkbookSheet? get _current =>
      _book == null || _book!.sheets.isEmpty ? null : _book!.sheets[_sheet];
  _Controllers get _grid => _controllers.putIfAbsent(_sheet, _Controllers.new);
  bool get _changed => _book?.changed.value ?? false;
  bool get _readOnly =>
      _book == null || _book!.signed || (_current?.protected ?? true);

  @override
  void initState() {
    super.initState();
    DocumentHistory.holdDraft(_draftKey);
    _recovery = DraftRecovery(
      write: _writeRecovery,
      remove: () => DocumentHistory.instance.clearRecovery(_draftKey),
      onError: (e) => _notice('Taslak kaydedilemedi: $e', NoticeKind.error),
    );
    WidgetsBinding.instance.addObserver(this);
    widget.draft?.changed = () => _changed;
    widget.draft?.saving = () => _loading || _saving;
    widget.draft?.save = _save;
    widget.draft?.savedPath = () => _savedPath;
    widget.draft?.history = _history;
    widget.draft?.discard = _discard;
    _load();
  }

  void _notice(String text, [NoticeKind kind = NoticeKind.info]) {
    if (mounted) showNotice(context, text, kind: kind);
  }

  Future<void> _load() async {
    try {
      final recovery = widget.recovery;
      final Uint8List bytes;
      if (recovery != null) {
        bytes = Uint8List.fromList(
          await DocumentHistory.instance.read(recovery),
        );
      } else if (widget.path != null) {
        bytes = await File(widget.path!).readAsBytes();
      } else {
        throw const FormatException('Excel dosyası bulunamadı.');
      }
      final book = await Workbook.read(bytes, changed: recovery != null);
      if (!mounted) {
        book.dispose();
        return;
      }
      setState(() {
        _adopt(book);
        _loading = false;
      });
      if (recovery != null) {
        await _takeOver(recovery);
      } else {
        unawaited(_findLeftDrafts());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  /// Puts [book] in the editor in place of the one open, if any.
  void _adopt(Workbook book) {
    _book?.edits.removeListener(_edited);
    _book?.dispose();
    for (final controllers in _controllers.values) {
      controllers.dispose();
    }
    _controllers.clear();
    _listened = null;
    _book = book;
    _sheet = 0;
    book.edits.addListener(_edited);
  }

  void _edited() {
    _recovery.changed();
    if (mounted) setState(() {});
  }

  /// A workbook read from other bytes — a version, a draft — as an unsaved
  /// edit of this one.
  Future<bool> _open(List<int> bytes) async {
    try {
      final book = await Workbook.read(
        Uint8List.fromList(bytes),
        changed: true,
      );
      if (!mounted) {
        book.dispose();
        return false;
      }
      setState(() => _adopt(book));
      _recovery.changed();
      return true;
    } catch (e) {
      _notice('Açılamadı: $e', NoticeKind.error);
      return false;
    }
  }

  Future<void> _writeRecovery() async {
    final book = _book;
    if (book == null || !book.changed.value) {
      await DocumentHistory.instance.clearRecovery(_draftKey);
      return;
    }
    await DocumentHistory.instance.capture(
      document: _draftKey,
      name: _name,
      sourcePath: _savedPath ?? widget.path,
      format: 'spreadsheet-draft',
      bytes: await book.write(),
      kind: 'recovery',
    );
  }

  /// Moves a draft another session left into this editor's slot; the old
  /// one goes only once the new one is written.
  Future<void> _takeOver(DocumentRevision draft) async {
    if (draft.document == _draftKey || !await _recovery.flush()) return;
    try {
      await DocumentHistory.instance.clearRecovery(draft.document);
    } catch (e) {
      _notice('Eski taslak silinemedi: $e', NoticeKind.error);
    }
  }

  Future<void> _findLeftDrafts() async {
    final path = widget.path;
    if (path == null) return;
    try {
      final drafts = await DocumentHistory.instance.recoveriesFor(path);
      if (!mounted) return;
      setState(() {
        _leftDraft = drafts.firstOrNull;
        _leftDrafts = drafts.length;
      });
    } catch (_) {
      // The sheet opens either way; the homepage still lists the drafts.
    }
  }

  Future<void> _leftDraftMenu() async {
    final draft = _leftDraft;
    if (draft == null) return;
    final action = await askLeftDraft(context, draft, _leftDrafts);
    if (action == null || !mounted) return;
    if (action == LeftDraftAction.delete) {
      try {
        await DocumentHistory.instance.clearRecovery(draft.document);
      } catch (e) {
        _notice('Taslak silinemedi: $e', NoticeKind.error);
      }
    } else {
      if (_changed && !await _replaceEdits('Taslak')) return;
      if (await _open(await DocumentHistory.instance.read(draft))) {
        await _takeOver(draft);
      }
    }
    await _findLeftDrafts();
  }

  Future<bool> _replaceEdits(String what) async {
    final choice = await confirmReplaceEdits(context, what);
    if (choice == null || !mounted) return false;
    return choice == ReplaceChoice.replace || await _save();
  }

  Future<void> _discard() async {
    await _recovery.clear();
    final path = widget.path;
    if (path == null || !await File(path).exists()) {
      _book?.markSaved();
      return;
    }
    try {
      final book = await Workbook.read(await File(path).readAsBytes());
      if (!mounted) {
        book.dispose();
        return;
      }
      setState(() => _adopt(book));
    } catch (e) {
      _notice('Belge yeniden okunamadı: $e', NoticeKind.error);
    }
  }

  Future<void> _capture(String path, List<int> bytes, String kind) =>
      DocumentHistory.instance.capture(
        document: DocumentHistory.documentKey(path),
        name: p.basename(path),
        sourcePath: path,
        format: 'xlsx',
        bytes: bytes,
        kind: kind,
      );

  Future<bool> _save() async {
    final book = _book;
    if (book == null || book.signed || _saving) return false;
    setState(() => _saving = true);
    try {
      final edits = book.edits.value;
      final bytes = await book.write();
      final path = Platform.isAndroid
          ? await AndroidDocumentSave.save(fileName: _name, bytes: bytes)
          : _savedPath ??
                widget.path ??
                await FilePicker.saveFile(
                  dialogTitle: 'Excel belgesini kaydet',
                  fileName: _name,
                  type: FileType.custom,
                  allowedExtensions: ['xlsx'],
                );
      if (path == null || !mounted) return false;
      if (!Platform.isAndroid) {
        final file = File(path);
        if (await file.exists()) {
          try {
            await _capture(path, await file.readAsBytes(), 'original');
          } catch (e) {
            _notice(
              'Önceki hali belge geçmişine yazılamadı: $e',
              NoticeKind.error,
            );
          }
        }
        await replaceFileIfChanged(file, bytes);
      }
      try {
        await _capture(path, bytes, 'saved');
      } catch (_) {
        // Saved all the same; the history is a convenience.
      }
      _savedPath = path;
      // Edits made while the file was being written are not in it.
      if (book.edits.value == edits) {
        book.markSaved();
        await _recovery.clear();
      }
      widget.onSaved?.call(path);
      if (mounted) {
        showNotice(
          context,
          Platform.isAndroid
              ? 'Excel belgesi kaydedildi.'
              : 'Kaydedildi: ${p.basename(path)}',
          detail: Platform.isAndroid ? null : p.dirname(path),
          kind: NoticeKind.success,
        );
      }
      return true;
    } catch (e) {
      _notice('Excel kaydedilemedi: $e', NoticeKind.error);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _history() async {
    final path = _savedPath ?? widget.path;
    if (path == null) {
      _notice('Bu tablo henüz kaydedilmedi; geçmiş ilk kayıttan itibaren tutulur.');
      return;
    }
    final entry = await showDocumentVersions(
      context,
      document: DocumentHistory.documentKey(path),
      title: p.basename(path),
      currentText: () async => _book?.text(),
      restoreLabel: 'Tabloya yükle',
      restoreHint:
          'Seçilen sürüm tabloya kaydedilmemiş değişiklik olarak gelir; siz '
          'kaydedene kadar dosya değişmez.',
    );
    if (!mounted || entry == null) return;
    if (_changed && !await _replaceEdits('Seçilen sürüm')) return;
    await _open(await DocumentHistory.instance.read(entry));
  }

  // --- Formatting, cell by cell, with undo --------------------------------

  /// The cells of [range] a change is applied to: all of them in a selection
  /// of ordinary size, and only the filled ones in a whole column or row.
  Iterable<CellCoordinate> _cells(WorkbookSheet sheet, CellRange range) {
    if (range.cellCount <= 20000) return range.cells;
    return {
      for (final entry in sheet.raw.getCellsInRange(range)) entry.key,
      for (final entry in sheet.raw.getStylesInRange(range)) entry.key,
    };
  }

  void _record(String label, void Function(WorkbookSheet, CellCoordinate) f) {
    final sheet = _current;
    final range = _grid.grid.selectedRange;
    if (sheet == null || range == null || _readOnly) return;
    final selection = (
      _grid.grid.selectionController.anchor,
      _grid.grid.selectionController.focus,
    );
    final before = UndoSnapshot.capture(sheet.raw, range);
    for (final coord in _cells(sheet, range)) {
      f(sheet, coord);
    }
    final after = UndoSnapshot.capture(sheet.raw, range);
    _grid.undo.push(
      UndoEntry(
        label: label,
        affectedRange: range,
        cellsBefore: before.$1,
        mergesBefore: before.$2,
        selectionBefore: selection,
        cellsAfter: after.$1,
        mergesAfter: after.$2,
        selectionAfter: selection,
      ),
    );
    setState(() {});
  }

  static TextStyle _cellText(List<TextSpan>? spans) {
    if (spans == null || spans.isEmpty) return const TextStyle();
    return spans.first.style ?? const TextStyle();
  }

  /// [spans] with [change] applied to the whole cell's text. A cell without
  /// runs of its own gets one empty span, which styles whatever the cell
  /// shows — a number keeps its format and a formula keeps showing its result.
  static List<TextSpan> _restyled(
    List<TextSpan>? spans,
    TextStyle Function(TextStyle) change,
  ) {
    if (spans == null ||
        spans.isEmpty ||
        (spans.length == 1 && (spans.single.text ?? '').isEmpty)) {
      return [TextSpan(text: '', style: change(_cellText(spans)))];
    }
    return [
      for (final span in spans)
        TextSpan(text: span.text, style: change(span.style ?? const TextStyle())),
    ];
  }

  void _font(
    String label,
    bool Function(TextStyle) has,
    TextStyle Function(TextStyle, bool on) set,
    void Function() whileEditing,
  ) {
    final grid = _grid;
    if (grid.edit.isEditing) {
      whileEditing();
      grid.edit.requestEditorFocus();
      return;
    }
    final sheet = _current, range = grid.grid.selectedRange;
    if (sheet == null || range == null) return;
    final all = _cells(sheet, range).every(
      (coord) => has(_cellText(sheet.raw.getRichText(coord))),
    );
    _record(
      label,
      (sheet, coord) => sheet.raw.setRichText(
        coord,
        _restyled(sheet.raw.getRichText(coord), (s) => set(s, !all)),
      ),
    );
  }

  void _bold() => _font(
    'Kalın',
    (s) => s.fontWeight == FontWeight.bold,
    (s, on) => s.copyWith(fontWeight: on ? FontWeight.bold : FontWeight.normal),
    () => _grid.edit.toggleBold(),
  );

  void _italic() => _font(
    'İtalik',
    (s) => s.fontStyle == FontStyle.italic,
    (s, on) => s.copyWith(fontStyle: on ? FontStyle.italic : FontStyle.normal),
    () => _grid.edit.toggleItalic(),
  );

  void _underline() => _font(
    'Altı çizili',
    (s) => s.decoration?.contains(TextDecoration.underline) == true,
    (s, on) => s.copyWith(
      decoration: on ? TextDecoration.underline : TextDecoration.none,
    ),
    () => _grid.edit.toggleUnderline(),
  );

  void _textColor(Color? color) => _record(
    'Yazı rengi',
    (sheet, coord) => sheet.raw.setRichText(
      coord,
      _restyled(
        sheet.raw.getRichText(coord),
        (s) => TextStyle(
          fontWeight: s.fontWeight,
          fontStyle: s.fontStyle,
          decoration: s.decoration,
          fontSize: s.fontSize,
          fontFamily: s.fontFamily,
          color: color,
        ),
      ),
    ),
  );

  static CellStyle _style(
    CellStyle? s, {
    Color? fill,
    bool clearFill = false,
    CellTextAlignment? align,
    bool? wrap,
  }) => CellStyle(
    backgroundColor: clearFill ? null : fill ?? s?.backgroundColor,
    textAlignment: align ?? s?.textAlignment,
    verticalAlignment: s?.verticalAlignment,
    borders: s?.borders,
    wrapText: wrap ?? s?.wrapText,
  );

  void _fill(Color? color) => _record(
    'Dolgu rengi',
    (sheet, coord) => sheet.raw.setStyle(
      coord,
      _style(sheet.raw.getStyle(coord), fill: color, clearFill: color == null),
    ),
  );

  void _align(CellTextAlignment align) => _record(
    'Hizalama',
    (sheet, coord) =>
        sheet.raw.setStyle(coord, _style(sheet.raw.getStyle(coord), align: align)),
  );

  void _wrap() {
    final sheet = _current, range = _grid.grid.selectedRange;
    if (sheet == null || range == null) return;
    final all = _cells(
      sheet,
      range,
    ).every((coord) => sheet.raw.getStyle(coord)?.wrapText == true);
    _record(
      'Metni kaydır',
      (sheet, coord) =>
          sheet.raw.setStyle(coord, _style(sheet.raw.getStyle(coord), wrap: !all)),
    );
  }

  void _numberFormat(String? code) => _record(
    'Sayı biçimi',
    (sheet, coord) => sheet.raw.setFormat(
      coord,
      code == null
          ? null
          : CellFormat(type: _formatType(code), formatCode: code),
    ),
  );

  static CellFormatType _formatType(String code) => code == '@'
      ? CellFormatType.text
      : code.contains('%')
      ? CellFormatType.percentage
      : code.contains('yyyy')
      ? CellFormatType.date
      : CellFormatType.number;

  // --- Formula bar ----------------------------------------------------------

  void _selectionChanged() {
    if (!mounted) return;
    if (!_formulaFocus.hasFocus) _formula.text = _rawText();
    setState(() {});
  }

  String _rawText() {
    final sheet = _current, focus = _grid.grid.focusCell;
    if (sheet == null || focus == null) return '';
    final value = sheet.raw.getCell(focus);
    if (value == null) return '';
    if (value.isNumber) {
      final number = value.rawValue as double;
      return number == number.truncateToDouble() && number.abs() < 1e15
          ? '${number.toInt()}'
          : '$number'.replaceAll('.', ',');
    }
    if (value.isFormula) return value.rawValue as String;
    return value.displayValue;
  }

  /// What was typed in the formula bar, read the Turkish way: a comma for
  /// decimals, a dot between thousands.
  static CellValue? _parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('=')) return CellValue.formula(excelFormula(trimmed));
    if (RegExp(r'^-?(\d{1,3}(\.\d{3})+|\d+)(,\d+)?$').hasMatch(trimmed)) {
      return CellValue.number(
        double.parse(trimmed.replaceAll('.', '').replaceAll(',', '.')),
      );
    }
    return CellValue.parse(trimmed);
  }

  void _commitFormula() {
    final sheet = _current, focus = _grid.grid.focusCell;
    if (sheet == null || focus == null || _readOnly) return;
    final value = _parse(_formula.text);
    final range = CellRange.single(focus);
    final selection = (focus, focus);
    final before = UndoSnapshot.capture(sheet.raw, range);
    sheet.display.setCell(focus, value);
    final after = UndoSnapshot.capture(sheet.raw, range);
    _grid.undo.push(
      UndoEntry(
        label: 'Düzenle',
        affectedRange: range,
        cellsBefore: before.$1,
        mergesBefore: before.$2,
        selectionBefore: selection,
        cellsAfter: after.$1,
        mergesAfter: after.$2,
        selectionAfter: selection,
      ),
    );
  }

  // --- Find ------------------------------------------------------------------

  void _findNext() {
    final sheet = _current;
    final query = foldSearchText(_find.text.trim());
    if (sheet == null || query.isEmpty) return;
    final hits = [
      for (final entry in sheet.raw.getCellsInRange(
        CellRange(0, 0, sheet.rowCount - 1, sheet.columnCount - 1),
      ))
        if (foldSearchText(
          '${sheet.display.getCell(entry.key)?.displayValue ?? ''} '
          '${entry.value.displayValue}',
        ).contains(query))
          entry.key,
    ]..sort((a, b) => a.row == b.row ? a.column - b.column : a.row - b.row);
    if (hits.isEmpty) {
      _notice('Bu sayfada eşleşme yok.');
      return;
    }
    final focus = _grid.grid.focusCell;
    final next = hits.firstWhere(
      (c) =>
          focus == null ||
          c.row > focus.row ||
          (c.row == focus.row && c.column > focus.column),
      orElse: () => hits.first,
    );
    _grid.grid.invokeAction(GoToCellIntent(next));
  }

  // --- Status -----------------------------------------------------------------

  String? _status() {
    final sheet = _current, range = _grid.grid.selectedRange;
    if (sheet == null || range == null || range.cellCount < 2) return null;
    var sum = 0.0, count = 0, numbers = 0;
    for (final entry in sheet.raw.getCellsInRange(range)) {
      count++;
      final shown = sheet.display.getCell(entry.key);
      if (shown != null && shown.isNumber) {
        numbers++;
        sum += shown.rawValue as double;
      }
    }
    if (count == 0) return null;
    final format = NumberFormat('#,##0.##', 'tr_TR');
    if (numbers == 0) return 'Dolu hücre: $count';
    return 'Toplam: ${format.format(sum)} · '
        'Ortalama: ${format.format(sum / numbers)} · Sayı: $numbers';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _recovery.flush();
    }
  }

  @override
  void dispose() {
    final clean = !_loading && _error == null && !_changed;
    (clean ? _recovery.clear() : Future<void>.value()).whenComplete(
      () => DocumentHistory.releaseDraft(_draftKey),
    );
    WidgetsBinding.instance.removeObserver(this);
    widget.draft?.detach();
    _recovery.dispose();
    _listened?.grid.removeListener(_selectionChanged);
    _book?.edits.removeListener(_edited);
    for (final controllers in _controllers.values) {
      controllers.dispose();
    }
    _book?.dispose();
    _formula.dispose();
    _formulaFocus.dispose();
    _find.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  // --- Building -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      // A workbook excel_plus cannot read — it is strict about styles.xml —
      // still opens, in the plain editor that patches the file in place.
      return Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: const Text(
              'Bu dosya gelişmiş tablo editöründe açılamadı; basit editörle '
              'açıldı. Hücre değerleri ve formüller düzenlenebilir.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: SpreadsheetViewer(
              path: widget.path,
              readOnly: false,
              draft: widget.draft,
              recovery: widget.recovery,
              onSaved: widget.onSaved,
            ),
          ),
        ],
      );
    }
    final book = _book!;
    final sheet = _current;
    if (sheet == null) {
      return const Center(child: Text('Bu çalışma kitabında görünen sayfa yok.'));
    }
    final grid = _grid;
    if (!identical(_listened, grid)) {
      _listened?.grid.removeListener(_selectionChanged);
      grid.grid.addListener(_selectionChanged);
      _listened = grid;
      _formula.text = _rawText();
    }
    final colors = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _findFocus.requestFocus,
      },
      child: Column(
        children: [
          _toolbar(book, colors),
          if (book.signed || sheet.protected)
            Container(
              width: double.infinity,
              color: colors.primary.withValues(alpha: .08),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                book.signed
                    ? 'Bu çalışma kitabı dijital olarak imzalı; her değişiklik '
                          'imzayı bozacağı için yalnızca görüntülenir.'
                    : 'Bu sayfa korumalı; düzenleme kapalı.',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          _formulaBar(colors),
          const Divider(height: 1),
          Expanded(child: _worksheet(context, book, sheet, grid)),
          const Divider(height: 1),
          _footer(book, colors),
        ],
      ),
    );
  }

  Widget _worksheet(
    BuildContext context,
    Workbook book,
    WorkbookSheet sheet,
    _Controllers grid,
  ) {
    final colors = Theme.of(context).colorScheme;
    return WorksheetTheme(
      // Cells stay paper white in either theme, as the file will print.
      data: WorksheetThemeData(
        cellBackgroundColor: Colors.white,
        textColor: const Color(0xFF1F1F1F),
        fontFamily: Platform.isWindows ? 'Calibri' : 'LiberationSans',
        fontSize: 14.5,
        gridlineColor: const Color(0xFFE1E3E6),
        defaultRowHeight: 22,
        defaultColumnWidth: 72,
        rowHeaderWidth: 46,
        columnHeaderHeight: 22,
        selectionStyle: SelectionStyle(
          fillColor: colors.primary.withValues(alpha: .10),
          borderColor: colors.primary,
          borderWidth: 1,
          focusFillColor: Colors.transparent,
          focusBorderColor: colors.primary,
          focusBorderWidth: 2,
          fillHandleColor: colors.primary,
        ),
        headerStyle: const HeaderStyle(
          backgroundColor: Color(0xFFF3F4F6),
          selectedBackgroundColor: Color(0xFFDCE3EA),
          textColor: Color(0xFF55595F),
          selectedTextColor: Color(0xFF1F2A33),
          borderColor: Color(0xFFD7DADF),
          fontSize: 12,
        ),
      ),
      child: Worksheet(
        key: ValueKey('sheet-${identityHashCode(book)}-$_sheet'),
        data: sheet.display,
        rawData: sheet.raw,
        controller: grid.grid,
        editController: grid.edit,
        rowCount: sheet.rowCount,
        columnCount: sheet.columnCount,
        customColumnWidths: sheet.columnWidths,
        customRowHeights: sheet.rowHeights,
        onResizeColumn: _readOnly ? null : sheet.resizeColumn,
        onResizeRow: _readOnly ? null : sheet.resizeRow,
        readOnly: _readOnly,
        formatLocale: _turkish,
        freezeConfig: sheet.freeze,
        actions: {
          ToggleBoldIntent: CallbackAction<ToggleBoldIntent>(
            onInvoke: (_) => _bold(),
          ),
          ToggleItalicIntent: CallbackAction<ToggleItalicIntent>(
            onInvoke: (_) => _italic(),
          ),
          ToggleUnderlineIntent: CallbackAction<ToggleUnderlineIntent>(
            onInvoke: (_) => _underline(),
          ),
        },
      ),
    );
  }

  Widget _toolbar(Workbook book, ColorScheme colors) {
    final grid = _grid;
    final editable = !_readOnly;
    Widget button(
      IconData icon,
      String tooltip,
      VoidCallback? onPressed, {
      bool selected = false,
      Key? key,
    }) => IconButton(
      key: key,
      tooltip: tooltip,
      isSelected: selected,
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      visualDensity: VisualDensity.compact,
    );
    Widget gap() => Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: colors.outlineVariant,
    );
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: ListenableBuilder(
                listenable: grid.undo,
                builder: (context, _) => Row(
                  children: [
                    Icon(Icons.table_chart_outlined, color: colors.primary, size: 20),
                    const SizedBox(width: 8),
                    button(
                      Icons.undo,
                      'Geri al · Ctrl+Z',
                      editable && grid.undo.canUndo ? grid.grid.undo : null,
                    ),
                    button(
                      Icons.redo,
                      'Yinele · Ctrl+Y',
                      editable && grid.undo.canRedo ? grid.grid.redo : null,
                    ),
                    gap(),
                    button(
                      Icons.format_bold,
                      'Kalın · Ctrl+B',
                      editable ? _bold : null,
                      key: const ValueKey('sheet-bold'),
                    ),
                    button(Icons.format_italic, 'İtalik · Ctrl+I', editable ? _italic : null),
                    button(
                      Icons.format_underline,
                      'Altı çizili · Ctrl+U',
                      editable ? _underline : null,
                    ),
                    _colorMenu(
                      icon: Icons.format_color_text_rounded,
                      tooltip: 'Yazı rengi',
                      none: 'Otomatik',
                      onPick: editable ? _textColor : null,
                    ),
                    _colorMenu(
                      icon: Icons.format_color_fill_rounded,
                      tooltip: 'Dolgu rengi',
                      none: 'Dolgu yok',
                      onPick: editable ? _fill : null,
                    ),
                    gap(),
                    button(
                      Icons.format_align_left,
                      'Sola hizala',
                      editable ? () => _align(CellTextAlignment.left) : null,
                    ),
                    button(
                      Icons.format_align_center,
                      'Ortala',
                      editable ? () => _align(CellTextAlignment.center) : null,
                    ),
                    button(
                      Icons.format_align_right,
                      'Sağa hizala',
                      editable ? () => _align(CellTextAlignment.right) : null,
                    ),
                    button(Icons.wrap_text_rounded, 'Metni kaydır', editable ? _wrap : null),
                    gap(),
                    button(
                      Icons.call_merge_rounded,
                      'Hücreleri birleştir',
                      editable
                          ? () => grid.grid.invokeAction(const MergeCellsIntent())
                          : null,
                    ),
                    button(
                      Icons.call_split_rounded,
                      'Birleştirmeyi kaldır',
                      editable
                          ? () => grid.grid.invokeAction(const UnmergeCellsIntent())
                          : null,
                    ),
                    PopupMenuButton<String?>(
                      tooltip: 'Sayı biçimi',
                      enabled: editable,
                      onSelected: _numberFormat,
                      icon: const Icon(Icons.onetwothree_rounded, size: 22),
                      itemBuilder: (_) => [
                        for (final (label, code) in _formats)
                          PopupMenuItem(value: code, child: Text(label)),
                      ],
                    ),
                    gap(),
                    SizedBox(
                      width: 170,
                      height: 32,
                      child: TextField(
                        controller: _find,
                        focusNode: _findFocus,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Sayfada bul · Ctrl+F',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          prefixIcon: Icon(Icons.search_rounded, size: 17),
                          prefixIconConstraints: BoxConstraints(minWidth: 30),
                        ),
                        onSubmitted: (_) {
                          _findNext();
                          _findFocus.requestFocus();
                        },
                      ),
                    ),
                    gap(),
                    button(Icons.zoom_out_rounded, 'Uzaklaştır', grid.grid.zoomOut),
                    ListenableBuilder(
                      listenable: grid.grid,
                      builder: (context, _) => TextButton(
                        onPressed: grid.grid.resetZoom,
                        child: Text('%${(grid.grid.zoom * 100).round()}'),
                      ),
                    ),
                    button(Icons.zoom_in_rounded, 'Yakınlaştır', grid.grid.zoomIn),
                  ],
                ),
              ),
            ),
          ),
          if (_leftDraft != null)
            LeftDraftButton(draft: _leftDraft!, onPressed: _leftDraftMenu),
          button(Icons.history_rounded, 'Belge geçmişi', _history),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: button(
              _saving ? Icons.hourglass_top_rounded : Icons.save_outlined,
              'Kaydet · Ctrl+S',
              book.signed || _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorMenu({
    required IconData icon,
    required String tooltip,
    required String none,
    required void Function(Color?)? onPick,
  }) => PopupMenuButton<int>(
    tooltip: tooltip,
    enabled: onPick != null,
    icon: Icon(icon, size: 19),
    onSelected: (i) => onPick?.call(i < 0 ? null : _palette[i]),
    itemBuilder: (context) => [
      PopupMenuItem<int>(value: -1, child: Text(none)),
      PopupMenuItem<int>(
        enabled: false,
        child: SizedBox(
          width: 190,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _palette.length; i++)
                InkWell(
                  onTap: () => Navigator.pop(context, i),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 30,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _palette[i],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0x33000000)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _formulaBar(ColorScheme colors) {
    final focus = _grid.grid.focusCell;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Container(
            width: 72,
            alignment: Alignment.center,
            child: Text(
              focus?.toNotation() ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Container(width: 1, height: 22, color: colors.outlineVariant),
          const SizedBox(width: 8),
          Text(
            'fx',
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const ValueKey('formula-bar'),
              controller: _formula,
              focusNode: _formulaFocus,
              enabled: !_readOnly && focus != null,
              style: const TextStyle(fontSize: 13.5),
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
                hintText:
                    'Değer ya da formül · =TOPLA(A1:A5) ve =SUM(A1:A5) ikisi '
                    'de olur',
              ),
              onSubmitted: (_) => _commitFormula(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(Workbook book, ColorScheme colors) {
    final status = _status();
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  for (var i = 0; i < book.sheets.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ChoiceChip(
                        label: Text(book.sheets[i].name),
                        selected: i == _sheet,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _sheet = i),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                status,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ),
          if (_changed)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                'Kaydedilmedi',
                style: TextStyle(fontSize: 12, color: colors.primary),
              ),
            ),
        ],
      ),
    );
  }
}
