import 'dart:async';

import '../../services/platform/android_document_save.dart';

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../services/spreadsheet/xlsx_workbook.dart';
import '../../services/platform/atomic_file.dart';
import '../../services/editor/editor_drafts.dart';
import '../../services/editor/document_history.dart';
import '../../services/search/search_models.dart';
import 'document_versions_window.dart';
import 'draft_prompts.dart';
import 'notice.dart';

class SpreadsheetViewer extends StatefulWidget {
  final String? path;
  final bool readOnly;
  final EditorDraft? draft;
  final DocumentRevision? recovery;
  final ValueChanged<String>? onSaved;
  const SpreadsheetViewer({
    super.key,
    this.path,
    this.readOnly = true,
    this.draft,
    this.recovery,
    this.onSaved,
  });
  @override
  State<SpreadsheetViewer> createState() => _SpreadsheetViewerState();
}

class _SpreadsheetViewerState extends State<SpreadsheetViewer>
    with WidgetsBindingObserver {
  XlsxWorkbook? _book, _baseline;
  final _changes = <String, String>{};
  final _undo = <Map<String, String>>[], _redo = <Map<String, String>>[];
  final _value = TextEditingController(), _search = TextEditingController();
  final _valueFocus = FocusNode(), _searchFocus = FocusNode();
  final _horizontal = ScrollController(), _vertical = ScrollController();
  /// This sheet's own recovery slot; see [DocumentHistory.draftKey].
  final String _draftKey = DocumentHistory.draftKey();
  late final DraftRecovery _recovery;
  DocumentRevision? _leftDraft;
  int _leftDrafts = 0;
  String? _error, _savedPath;
  bool _loading = true, _saving = false, _restored = false;
  int _sheet = 0, _row = 0, _col = 0, _match = -1;
  bool get _dirty => _changes.isNotEmpty || _restored;
  String get _ref => XlsxWorkbook.reference(_row, _col);
  String get _changeKey => '$_sheet:$_ref';
  bool get _editable =>
      !widget.readOnly &&
      !_saving &&
      _book != null &&
      !_book!.signed &&
      !_book!.sheets[_sheet].protected;
  String get _name => p.basename(
    _savedPath ?? widget.path ?? widget.recovery?.name ?? 'Yeni tablo.xlsx',
  );
  static Uint8List _encode((XlsxWorkbook, Map<String, String>) input) =>
      input.$1.write(input.$2);
  Future<Uint8List> _bytes() => compute(_encode, (_book!, Map.of(_changes)));
  @override
  void initState() {
    super.initState();
    if (!widget.readOnly) DocumentHistory.holdDraft(_draftKey);
    _recovery = DraftRecovery(
      write: () async {
        if (!_dirty || _book == null) {
          await DocumentHistory.instance.clearRecovery(_draftKey);
          return;
        }
        await DocumentHistory.instance.capture(
          document: _draftKey,
          name: _name,
          sourcePath: _savedPath ?? widget.path,
          format: 'spreadsheet-draft',
          bytes: await _bytes(),
          kind: 'recovery',
        );
      },
      remove: () => DocumentHistory.instance.clearRecovery(_draftKey),
      onError: (e) => _notice('Taslak kaydedilemedi: $e', NoticeKind.error),
    );
    widget.draft?.changed = () => _dirty;
    widget.draft?.saving = () => _loading || _saving;
    widget.draft?.save = _save;
    widget.draft?.savedPath = () => _savedPath;
    widget.draft?.history = _history;
    widget.draft?.discard = () async {
      if (mounted) {
        setState(() {
          _changes.clear();
          _undo.clear();
          _redo.clear();
          _book = _baseline;
          _restored = false;
          _sheet = 0;
          _row = 0;
          _col = 0;
          _syncValue();
        });
      }
      await _recovery.clear();
    };
    _horizontal.addListener(_refresh);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      if (widget.path != null && await File(widget.path!).exists()) {
        _baseline = await compute(
          XlsxWorkbook.read,
          await File(widget.path!).readAsBytes(),
        );
      }
      _book = _baseline;
      if (widget.recovery != null) {
        _book = await compute(
          XlsxWorkbook.read,
          Uint8List.fromList(
            await DocumentHistory.instance.read(widget.recovery!),
          ),
        );
        _restored = true;
      }
      if (_book == null) {
        throw const FormatException('Excel dosyası bulunamadı.');
      }
      _baseline ??= _book;
      if (mounted) {
        setState(() {
          _loading = false;
          _syncValue();
        });
      }
      final recovery = widget.recovery;
      if (recovery != null) {
        await _takeOver(recovery);
      } else if (!widget.readOnly) {
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

  void _syncValue() {
    _value.text =
        _changes[_changeKey] ?? _book?.sheets[_sheet].cells[_ref]?.input ?? '';
  }

  void _select(int row, int col) {
    setState(() {
      _row = row;
      _col = col;
      _syncValue();
    });
  }

  void _change(String value) {
    if (!_editable) return;
    try {
      _book!.checkEditable(_sheet, _ref);
    } catch (e) {
      _notice('$e');
      _syncValue();
      return;
    }
    final before =
        _changes[_changeKey] ?? _book!.sheets[_sheet].cells[_ref]?.input ?? '';
    if (value == before) return;
    _undo.add(Map.of(_changes));
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
    setState(() {
      if (value == (_book!.sheets[_sheet].cells[_ref]?.input ?? '')) {
        _changes.remove(_changeKey);
      } else {
        _changes[_changeKey] = value;
      }
    });
    _recovery.changed();
  }

  void _undoRedo(bool redo) {
    if (!_editable) return;
    final from = redo ? _redo : _undo, to = redo ? _undo : _redo;
    if (from.isEmpty) return;
    to.add(Map.of(_changes));
    setState(() {
      _changes
        ..clear()
        ..addAll(from.removeLast());
      _syncValue();
    });
    _recovery.changed();
  }

  void _notice(String text, [NoticeKind kind = NoticeKind.info]) {
    if (mounted) showNotice(context, text, kind: kind);
  }

  /// Moves a draft another session left into this sheet's own slot; the old
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

  /// Puts a stored copy — a version or a draft — in the sheet as an unsaved
  /// edit.
  Future<bool> _apply(DocumentRevision entry) async {
    try {
      final book = await compute(
        XlsxWorkbook.read,
        Uint8List.fromList(await DocumentHistory.instance.read(entry)),
      );
      if (!mounted) return false;
      setState(() {
        _book = book;
        _changes.clear();
        _restored = true;
        _sheet = 0;
        _row = 0;
        _col = 0;
        _syncValue();
      });
      _recovery.changed();
      return true;
    } catch (e) {
      _notice('Sürüm açılamadı: $e', NoticeKind.error);
      return false;
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
      if (_dirty) {
        final choice = await confirmReplaceEdits(context, 'Taslak');
        if (choice == null || !mounted) return;
        if (choice == ReplaceChoice.saveFirst && !await _save()) return;
      }
      if (await _apply(draft)) await _takeOver(draft);
    }
    await _findLeftDrafts();
  }

  Future<bool> _save() async {
    if (widget.readOnly || _saving || _book == null || _book!.signed) {
      return false;
    }
    setState(() => _saving = true);
    try {
      final bytes = await _bytes();
      final path = Platform.isAndroid
          ? await AndroidDocumentSave.save(fileName: _name, bytes: bytes)
          : _savedPath ??
                widget.path ??
                await FilePicker.saveFile(
                  fileName: _name,
                  type: FileType.custom,
                  allowedExtensions: ['xlsx'],
                );
      if (path == null) return false;
      if (!Platform.isAndroid) {
        final file = File(path);
        if (await file.exists()) {
          await DocumentHistory.instance.capture(
            document: DocumentHistory.documentKey(path),
            name: p.basename(path),
            sourcePath: path,
            format: 'xlsx',
            bytes: await file.readAsBytes(),
            kind: 'original',
          );
        }
        await replaceFileIfChanged(file, bytes);
      }
      try {
        await DocumentHistory.instance.capture(
          document: DocumentHistory.documentKey(path),
          name: p.basename(path),
          sourcePath: path,
          format: 'xlsx',
          bytes: bytes,
          kind: 'saved',
        );
      } catch (e) {
        _notice(
          'Belge kaydedildi; geçmiş kopyası oluşturulamadı: $e',
          NoticeKind.error,
        );
      }
      final model = await compute(XlsxWorkbook.read, bytes);
      if (!mounted) return false;
      setState(() {
        _savedPath = path;
        _baseline = model;
        _book = model;
        _changes.clear();
        _restored = false;
        _undo.clear();
        _redo.clear();
        _syncValue();
      });
      try {
        await _recovery.clear();
      } catch (e) {
        _notice(
          'Belge kaydedildi; kurtarma kaydı temizlenemedi: $e',
          NoticeKind.error,
        );
      }
      widget.onSaved?.call(path);
      _notice('Excel belgesi kaydedildi.', NoticeKind.success);
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
      restoreLabel: 'Tabloya yükle',
      restoreHint:
          'Seçilen sürüm tabloya kaydedilmemiş değişiklik olarak gelir; siz '
          'kaydedene kadar dosya değişmez.',
    );
    if (!mounted || entry == null) return;
    if (_dirty) {
      final choice = await confirmReplaceEdits(context, 'Seçilen sürüm');
      if (choice == null || !mounted) return;
      if (choice == ReplaceChoice.saveFirst && !await _save()) return;
    }
    await _apply(entry);
  }

  void _findNext() {
    final query = foldSearchText(_search.text);
    if (query.isEmpty || _book == null) return;
    final sheet = _book!.sheets[_sheet];
    final refs = <String>{
      ...sheet.cells.keys,
      ..._changes.keys
          .where((k) => k.startsWith('$_sheet:'))
          .map((k) => k.split(':').last),
    };
    final cells =
        refs.where((ref) {
          final value = _changes['$_sheet:$ref'];
          final cell = sheet.cells[ref];
          return foldSearchText(
            value ?? '${cell?.value ?? ''} ${cell?.input ?? ''}',
          ).contains(query);
        }).toList()..sort((a, b) {
          final x = XlsxWorkbook.coordinates(a),
              y = XlsxWorkbook.coordinates(b);
          return x.$1 == y.$1 ? x.$2.compareTo(y.$2) : x.$1.compareTo(y.$1);
        });
    if (cells.isEmpty) {
      _notice('Bu sayfada eşleşme yok.');
      return;
    }
    _match = (_match + 1) % cells.length;
    final (r, c) = XlsxWorkbook.coordinates(cells[_match]);
    _select(r, c);
    if (_vertical.hasClients) {
      _vertical.jumpTo((r * 36.0).clamp(0, _vertical.position.maxScrollExtent));
    }
    if (_horizontal.hasClients) {
      _horizontal.jumpTo(
        (c * 128.0).clamp(0, _horizontal.position.maxScrollExtent),
      );
    }
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
    if (!widget.readOnly) {
      final clean = !_loading && _error == null && !_dirty;
      (clean ? _recovery.clear() : Future<void>.value()).whenComplete(
        () => DocumentHistory.releaseDraft(_draftKey),
      );
    }
    WidgetsBinding.instance.removeObserver(this);
    widget.draft?.detach();
    _recovery.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    _value.dispose();
    _search.dispose();
    _valueFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Color? _color(String? hex) {
    final value = hex == null ? null : int.tryParse(hex, radix: 16);
    return value == null
        ? null
        : Color(hex!.length == 6 ? value | 0xFF000000 : value);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final colors = Theme.of(context).colorScheme;
    final sheet = _book!.sheets[_sheet];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
            _undoRedo(false),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
            _undoRedo(true),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocus.requestFocus,
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.table_chart_outlined,
                  color: colors.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    decoration: const InputDecoration(
                      hintText: 'Hücrelerde ara…',
                      isDense: true,
                    ),
                    onChanged: (_) => _match = -1,
                    onSubmitted: (_) => _findNext(),
                  ),
                ),
                IconButton(
                  tooltip: 'Sonraki eşleşme',
                  onPressed: _findNext,
                  icon: const Icon(Icons.search_rounded),
                ),
                if (!widget.readOnly) ...[
                  if (_leftDraft != null)
                    LeftDraftButton(
                      draft: _leftDraft!,
                      onPressed: _leftDraftMenu,
                    ),
                  IconButton(
                    tooltip: 'Geri al',
                    onPressed: _undo.isEmpty ? null : () => _undoRedo(false),
                    icon: const Icon(Icons.undo, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Belge geçmişi',
                    onPressed: _history,
                    icon: const Icon(Icons.history, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Kaydet · Ctrl+S',
                    onPressed: _saving || _book!.signed ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    _ref,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _value,
                    focusNode: _valueFocus,
                    readOnly: !_editable,
                    onChanged: _change,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: widget.readOnly
                          ? 'Hücre değeri'
                          : 'Değer veya =formül',
                      prefixText: 'fx  ',
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_changes.isNotEmpty || sheet.protected || _book!.signed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: Text(
                sheet.protected || _book!.signed
                    ? 'Korumalı / imzalı çalışma sayfası salt okunur.'
                    : 'Formül sonuçları Excel’de yeniden hesaplanır.',
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, size) {
                final count = math.min(
                  16384,
                  math.max(sheet.columns + (widget.readOnly ? 0 : 5), 8),
                );
                final first =
                    ((_horizontal.hasClients ? _horizontal.offset : 0) / 128)
                        .floor()
                        .clamp(0, count - 1);
                final last = math.min(
                  count,
                  first + (size.maxWidth / 128).ceil() + 2,
                );
                Widget row(int index) => Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Center(
                        child: Text(
                          index < 0 ? '' : '${index + 1}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                    SizedBox(width: first * 128.0),
                    for (var c = first; c < last; c++)
                      Builder(
                        builder: (_) {
                          final ref = index < 0
                              ? ''
                              : XlsxWorkbook.reference(index, c);
                          final cell = sheet.cells[ref];
                          final value =
                              _changes['$_sheet:$ref'] ??
                              (cell == null
                                  ? ''
                                  : cell.value.isEmpty &&
                                        cell.formula.isNotEmpty
                                  ? cell.input
                                  : cell.value);
                          final selected = index == _row && c == _col;
                          return InkWell(
                            onTap: index < 0 ? null : () => _select(index, c),
                            onDoubleTap: !_editable || index < 0
                                ? null
                                : () {
                                    _select(index, c);
                                    _valueFocus.requestFocus();
                                  },
                            child: Container(
                              width: 128,
                              height: 36,
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: index < 0
                                    ? colors.surfaceContainerHigh
                                    : selected
                                    ? colors.primary.withValues(alpha: .13)
                                    : _color(cell?.fill) ?? colors.surface,
                                border: Border.all(
                                  color: selected
                                      ? colors.primary
                                      : colors.outlineVariant,
                                  width: selected ? 1.4 : .4,
                                ),
                              ),
                              child: Text(
                                index < 0 ? XlsxWorkbook.columnName(c) : value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: cell?.bold == true || index < 0
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color:
                                      _color(cell?.color) ?? colors.onSurface,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                );
                return Scrollbar(
                  controller: _vertical,
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: math.max(size.maxWidth, 48 + count * 128.0),
                      height: size.maxHeight,
                      child: Column(
                        children: [
                          row(-1),
                          Expanded(
                            child: ListView.builder(
                              controller: _vertical,
                              itemExtent: 36,
                              itemCount: math.min(
                                1048576,
                                math.max(
                                  sheet.rows + (widget.readOnly ? 0 : 20),
                                  30,
                                ),
                              ),
                              itemBuilder: (_, r) => row(r),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < _book!.sheets.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    child: ChoiceChip(
                      label: Text(_book!.sheets[i].name),
                      selected: i == _sheet,
                      onSelected: (_) {
                        setState(() {
                          _sheet = i;
                          _row = 0;
                          _col = 0;
                          _match = -1;
                          _syncValue();
                        });
                        if (_vertical.hasClients) _vertical.jumpTo(0);
                        if (_horizontal.hasClients) _horizontal.jumpTo(0);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
