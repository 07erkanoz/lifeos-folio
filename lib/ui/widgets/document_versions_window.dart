import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../models/evrak_file.dart';
import '../../services/convert/converter_service.dart';
import '../../services/editor/document_history.dart';
import '../../services/editor/text_diff.dart';
import '../../services/pdf/pdf_service.dart';
import '../../services/platform/phone_document_save.dart';
import '../../services/search/text_extractor.dart';
import '../../services/spreadsheet/workbook.dart';
import 'draft_prompts.dart' show draftDate;
import 'notice.dart';
import 'pdf_viewer_widget.dart';

/// The text a stored document reads as, for comparing two versions of it.
/// Null for the kinds of file whose text is not compared, a spreadsheet.
Future<String?> documentText(Uint8List bytes, String format) async {
  final kind = EvrakFormat.fromExtension(format);
  switch (kind) {
    case EvrakFormat.html:
    case EvrakFormat.markdown:
    case EvrakFormat.data:
      // Edited as source, so compared as source.
      return IndexTextExtractor.decodeText(bytes);
    case EvrakFormat.udf:
    case EvrakFormat.docx:
    case EvrakFormat.text:
    case EvrakFormat.rtf:
    case EvrakFormat.doc:
    case EvrakFormat.odt:
      return (await ConverterService.extractDocModel(
        bytes,
        kind,
      ))?.toPlainText();
    case EvrakFormat.spreadsheet:
      // A line per row, a tab between cells, formulas as their results.
      return Workbook.textOf(bytes);
    default:
      return null;
  }
}

/// [documentText] of the file on disk, which is what a preview shows.
Future<String?> documentFileText(String path) async => documentText(
  await File(path).readAsBytes(),
  p.extension(path).replaceFirst('.', ''),
);

/// Opens the history of one document: every version Folio kept of it, each
/// one readable as pages and comparable with the document as it is now.
///
/// Returns the version the reader asked to bring back, and leaves bringing it
/// back to the caller — an editor loads it as an unsaved edit, the preview
/// puts it back in the file.
Future<DocumentRevision?> showDocumentVersions(
  BuildContext context, {
  required String document,
  required String title,
  Future<String?> Function()? currentText,
  String restoreLabel = 'Bu sürümü geri yükle',
  String? restoreHint,
  bool Function(DocumentRevision entry)? canRestore,
}) => showDialog<DocumentRevision>(
  context: context,
  builder: (_) => _VersionsWindow(
    document: document,
    title: title,
    currentText: currentText,
    restoreLabel: restoreLabel,
    restoreHint: restoreHint,
    canRestore: canRestore,
  ),
);

class _VersionsWindow extends StatefulWidget {
  final String document, title, restoreLabel;
  final String? restoreHint;
  final Future<String?> Function()? currentText;
  final bool Function(DocumentRevision entry)? canRestore;
  const _VersionsWindow({
    required this.document,
    required this.title,
    required this.restoreLabel,
    this.restoreHint,
    this.currentText,
    this.canRestore,
  });
  @override
  State<_VersionsWindow> createState() => _VersionsWindowState();
}

class _VersionsWindowState extends State<_VersionsWindow> {
  late final Future<List<DocumentRevision>> _entries = DocumentHistory.instance
      .versions(widget.document)
      .then((entries) {
        if (mounted && entries.isNotEmpty && !_phone) {
          setState(() => _selected ??= entries.first);
        }
        return entries;
      });
  DocumentRevision? _selected;
  late bool _pages = widget.currentText == null;
  bool _saving = false;

  /// The window's own messenger: a notice sent to the app's would appear
  /// underneath this dialog, where nobody sees it.
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  Future<String?>? _current;
  final _bytes = <String, Future<Uint8List>>{};
  final _pdf = <String, Future<Uint8List?>>{};
  final _diffs = <String, Future<TextDiff?>>{};

  bool get _phone => MediaQuery.sizeOf(context).width < 700;

  Future<Uint8List> _read(DocumentRevision entry) => _bytes[entry.id] ??=
      DocumentHistory.instance.read(entry).then(Uint8List.fromList);

  Future<Uint8List?> _pagesOf(DocumentRevision entry) =>
      _pdf[entry.id] ??= _read(entry).then((bytes) async {
        final kind = EvrakFormat.fromExtension(entry.format);
        if (![
          EvrakFormat.udf,
          EvrakFormat.docx,
          EvrakFormat.text,
          EvrakFormat.rtf,
          EvrakFormat.doc,
          EvrakFormat.odt,
          EvrakFormat.html,
          EvrakFormat.markdown,
        ].contains(kind)) {
          return null;
        }
        final model = await ConverterService.extractDocModel(bytes, kind);
        if (model == null) throw const FormatException('Bu sürüm okunamadı.');
        return PdfService.modelToPdfBytes(
          model,
          title: p.basenameWithoutExtension(entry.name),
        );
      });

  Future<TextDiff?> _diffOf(DocumentRevision entry) =>
      _diffs[entry.id] ??= () async {
        final current = await (_current ??= widget.currentText!());
        if (current == null) return null;
        final before = await documentText(await _read(entry), entry.format);
        if (before == null) return null;
        return compute(diffTexts, (before, current));
      }();

  String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).ceil()} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  String _day(DateTime date) {
    final d = date.toLocal();
    final today = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final gap = DateTime(today.year, today.month, today.day).difference(day);
    if (gap.inDays == 0) return 'Bugün';
    if (gap.inDays == 1) return 'Dün';
    return draftDate(date).split(' ').first;
  }

  String _time(DateTime date) {
    final d = date.toLocal();
    String two(int n) => '$n'.padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  IconData _icon(DocumentRevision entry) => switch (entry.kind) {
    'original' => Icons.history_edu_outlined,
    'before-sign' || 'signed' => Icons.draw_outlined,
    'before-restore' || 'restored' => Icons.settings_backup_restore_rounded,
    _ => Icons.save_outlined,
  };

  Future<void> _saveCopy(DocumentRevision entry) async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = _messenger.currentState;
    void show(SnackBar bar) => messenger
      ?..clearSnackBars()
      ..showSnackBar(bar);
    try {
      final bytes = await _read(entry);
      final stamp = draftDate(entry.created).replaceAll(':', '.');
      final name =
          '${p.basenameWithoutExtension(entry.name)} ($stamp).${entry.format}';
      final path = PhoneDocumentSave.here
          ? await PhoneDocumentSave.save(fileName: name, bytes: bytes)
          : await FilePicker.saveFile(
              dialogTitle: 'Sürümü kopya olarak kaydet',
              fileName: name,
              type: FileType.custom,
              allowedExtensions: [entry.format],
            );
      if (path == null) return;
      if (!PhoneDocumentSave.here) {
        final source = entry.sourcePath;
        if (source != null &&
            (p.equals(p.absolute(path), p.absolute(source)) ||
                (await File(path).exists() &&
                    await File(source).exists() &&
                    await FileSystemEntity.identical(path, source)))) {
          show(
            noticeBar(
              'Kopya belgenin kendisinin üzerine yazılmaz',
              detail:
                  'Belgeyi bu sürüme döndürmek için «${widget.restoreLabel}» '
                  'düğmesini kullanın.',
              kind: NoticeKind.error,
            ),
          );
          return;
        }
        await File(path).writeAsBytes(bytes, flush: true);
      }
      show(
        noticeBar(
          'Sürümün kopyası kaydedildi',
          detail: PhoneDocumentSave.here ? null : path,
          kind: NoticeKind.success,
        ),
      );
    } catch (e) {
      show(
        noticeBar('Kopya kaydedilemedi', detail: '$e', kind: NoticeKind.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
          child: Row(
            children: [
              if (_phone && _selected != null)
                IconButton(
                  tooltip: 'Sürüm listesi',
                  onPressed: () => setState(() => _selected = null),
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              else
                Icon(Icons.history_rounded, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Belge geçmişi',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Kapat · Esc',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Text(
            'Folio’da her kaydettiğinizde dosyanın önceki ve yeni hali bu '
            'cihazda saklanır: belge başına son 20 sürüm, en fazla 100 MB.',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<DocumentRevision>>(
            future: _entries,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Yerel geçmişe ulaşılamadı.'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final entries = snapshot.data!;
              if (entries.isEmpty) return _empty(colors);
              if (_phone) {
                return _selected == null
                    ? _list(entries, colors)
                    : _detail(_selected!, colors);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 300, child: _list(entries, colors)),
                  VerticalDivider(width: 1, color: colors.outlineVariant),
                  Expanded(
                    child: _selected == null
                        ? const SizedBox.shrink()
                        : _detail(_selected!, colors),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
    final framed = ScaffoldMessenger(
      key: _messenger,
      child: Scaffold(backgroundColor: Colors.transparent, body: content),
    );
    if (_phone) return Dialog.fullscreen(child: framed);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(1100, size.width - 48),
        height: math.min(780, size.height - 48),
        child: framed,
      ),
    );
  }

  Widget _empty(ColorScheme colors) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            size: 40,
            color: colors.outline,
          ),
          const SizedBox(height: 12),
          const Text(
            'Bu belgenin henüz saklanmış bir sürümü yok.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Belgeyi Folio’da ilk kaydettiğinizde, dosyanın o ana kadarki hali '
            've kaydettiğiniz yeni hali burada listelenir.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    ),
  );

  Widget _list(List<DocumentRevision> entries, ColorScheme colors) {
    final rows = <Widget>[];
    String? day;
    for (final entry in entries) {
      final label = _day(entry.created);
      if (label != day) {
        day = label;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      rows.add(
        ListTile(
          key: ValueKey('version-${entry.id}'),
          selected: entry.id == _selected?.id,
          selectedTileColor: colors.primary.withValues(alpha: .08),
          dense: true,
          leading: Icon(_icon(entry), size: 20),
          title: Row(
            children: [
              Text(_time(entry.created)),
              if (entry.signed) ...[
                const SizedBox(width: 8),
                _chip('E-imzalı', colors),
              ],
            ],
          ),
          subtitle: Text(
            '${entry.kindLabel}\n'
            '${entry.format.toUpperCase()} · ${_size(entry.size)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => setState(() => _selected = entry),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.only(bottom: 12), children: rows);
  }

  Widget _chip(String text, ColorScheme colors) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: colors.primary.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text, style: TextStyle(fontSize: 10.5, color: colors.primary)),
  );

  Widget _detail(DocumentRevision entry, ColorScheme colors) {
    final restorable = widget.canRestore?.call(entry) ?? true;
    final compare = widget.currentText != null;
    final restore = FilledButton.icon(
      key: const ValueKey('restore-version'),
      onPressed: restorable ? () => Navigator.pop(context, entry) : null,
      icon: const Icon(Icons.settings_backup_restore_rounded, size: 17),
      label: Text(widget.restoreLabel),
    );
    final actions = [
      OutlinedButton.icon(
        onPressed: _saving ? null : () => _saveCopy(entry),
        icon: const Icon(Icons.file_copy_outlined, size: 17),
        label: const Text('Kopya olarak kaydet…'),
      ),
      const SizedBox(width: 8),
      if (restorable)
        restore
      else
        Tooltip(
          message:
              'Bu sürüm başka bir biçimde saklanmış; kopya olarak '
              'kaydedebilirsiniz.',
          child: restore,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            spacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${draftDate(entry.created)} · ${entry.kindLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${entry.format.toUpperCase()} · ${_size(entry.size)}'
                    '${entry.signed ? ' · E-imzalı' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Row(mainAxisSize: MainAxisSize.min, children: actions),
            ],
          ),
        ),
        if (widget.restoreHint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Text(
              widget.restoreHint!,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ),
        Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                enabled: compare,
                icon: const Icon(Icons.compare_arrows_rounded, size: 17),
                label: const Text('Şimdikiyle karşılaştır'),
              ),
              const ButtonSegment(
                value: true,
                icon: Icon(Icons.article_outlined, size: 17),
                label: Text('Sayfa görünümü'),
              ),
            ],
            selected: {_pages || !compare},
            onSelectionChanged: (value) =>
                setState(() => _pages = value.single),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey('${entry.id}-${_pages || !compare}'),
            child: _pages || !compare
                ? _pagesView(entry, colors)
                : _diffView(entry, colors),
          ),
        ),
      ],
    );
  }

  Widget _pagesView(DocumentRevision entry, ColorScheme colors) =>
      FutureBuilder<Uint8List?>(
        future: _pagesOf(entry),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _message('Sayfa görünümü hazırlanamadı: ${snapshot.error}');
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final pdf = snapshot.data;
          if (pdf != null) return PdfViewerWidget(bytes: pdf);
          return FutureBuilder<String?>(
            future: _read(entry)
                .then((bytes) => documentText(bytes, entry.format)),
            builder: (context, text) {
              if (text.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (text.data == null) {
                return _message(
                  'Bu tür bir belge burada gösterilemiyor. «Kopya olarak '
                  'kaydet» ile ayrı bir dosya olarak açabilirsiniz.',
                );
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: SelectableText(
                  text.data!,
                  style: const TextStyle(
                    fontFamily: 'LiberationMono',
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              );
            },
          );
        },
      );

  Widget _message(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );

  Widget _diffView(DocumentRevision entry, ColorScheme colors) =>
      FutureBuilder<TextDiff?>(
        future: _diffOf(entry),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _message('Karşılaştırılamadı: ${snapshot.error}');
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final diff = snapshot.data;
          if (diff == null) {
            return _message(
              'Bu tür bir belgede metin karşılaştırılamıyor; sürümü «Sayfa '
              'görünümü»nden inceleyebilirsiniz.',
            );
          }
          if (diff.identical) {
            return _message(
              'Bu sürümün metni şu anki haliyle aynı. Yazı tipi, boşluk gibi '
              'biçim farkları burada gösterilmez; «Sayfa görünümü»ne bakın.',
            );
          }
          final dark = Theme.of(context).brightness == Brightness.dark;
          final added = dark
              ? Colors.green.shade900.withValues(alpha: .6)
              : Colors.green.shade100;
          final removed = dark
              ? Colors.red.shade900.withValues(alpha: .6)
              : Colors.red.shade100;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Bu sürümden bu yana ${diff.addedWords} kelime '
                      'eklenmiş, ${diff.removedWords} kelime silinmiş.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    _legend('Sonradan eklenen', added, colors),
                    _legend('Sonradan silinen', removed, colors),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                  child: SelectableText.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.55,
                        color: colors.onSurface,
                      ),
                      children: _spans(diff, added, removed, colors),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );

  Widget _legend(String text, Color color, ColorScheme colors) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        text,
        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
      ),
    ],
  );

  List<InlineSpan> _spans(
    TextDiff diff,
    Color added,
    Color removed,
    ColorScheme colors,
  ) {
    final spans = <InlineSpan>[];
    final pieces = diff.pieces;
    for (var i = 0; i < pieces.length; i++) {
      final piece = pieces[i];
      switch (piece.kind) {
        case DiffKind.added:
          spans.add(
            TextSpan(
              text: piece.text,
              style: TextStyle(backgroundColor: added),
            ),
          );
        case DiffKind.removed:
          spans.add(
            TextSpan(
              text: piece.text,
              style: TextStyle(
                backgroundColor: removed,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          );
        case DiffKind.same:
          spans.addAll(
            _context(
              piece.text,
              after: i > 0,
              before: i < pieces.length - 1,
              colors: colors,
            ),
          );
      }
    }
    return spans;
  }

  /// Unchanged text, cut down to the lines on either side of a change: in a
  /// thirty-page filing with two edits, the edits are what is being looked
  /// for.
  List<InlineSpan> _context(
    String text, {
    required bool after,
    required bool before,
    required ColorScheme colors,
  }) {
    const keep = 2;
    final lines = text.split('\n');
    final head = after ? keep : 0, tail = before ? keep : 0;
    if (lines.length <= head + tail + 2) return [TextSpan(text: text)];
    final hidden = lines.length - head - tail;
    return [
      if (head > 0) TextSpan(text: '${lines.take(head).join('\n')}\n'),
      TextSpan(
        text: '⋯ değişmeyen $hidden satır ⋯\n',
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: colors.outline,
        ),
      ),
      if (tail > 0) TextSpan(text: lines.skip(lines.length - tail).join('\n')),
    ];
  }
}
