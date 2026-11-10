import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../services/pdf/pdf_tools.dart';
import '../../services/tiff/tiff_service.dart';
import '../../services/platform/app_language.dart';
import '../../services/platform/editor_window.dart';
import 'notice.dart';

/// Asks where to keep [bytes] as a PDF, named [name] to begin with, and
/// writes them there; the path, or null when the lawyer gave up.
Future<String?> savePdfAs(
  BuildContext context,
  Uint8List bytes,
  String name,
) async {
  final title = context.l.pdfSave;
  var path = await FilePicker.saveFile(
    dialogTitle: title,
    fileName: name,
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
  if (path == null) return null;
  if (p.extension(path).toLowerCase() != '.pdf') path = '$path.pdf';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

/// Says the PDF at [path] was made, with a way straight to it: a window
/// of its own.
void pdfMade(BuildContext context, String path) => showNotice(
  context,
  context.l.pdfSaved(p.basename(path)),
  kind: NoticeKind.success,
  actionLabel: context.l.pdfOpen,
  onAction: () => unawaited(PreviewWindow.open(path)),
);

/// Chosen pages of a PDF taken out as a PDF of their own: the pages as
/// small pictures to press, and a box their numbers can be typed in, in
/// the order wanted.
class PdfPagesDialog extends StatefulWidget {
  const PdfPagesDialog({super.key, required this.path});

  final String path;

  /// The path of the PDF made, or null.
  static Future<String?> show(BuildContext context, String path) =>
      showDialog<String>(
        context: context,
        builder: (_) => PdfPagesDialog(path: path),
      );

  @override
  State<PdfPagesDialog> createState() => _PdfPagesDialogState();
}

class _PdfPagesDialogState extends State<PdfPagesDialog> {
  PdfDocument? _document;
  Object? _error;
  final _chosen = <int>[];
  final _field = TextEditingController();
  bool _bad = false, _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await pdfrxFlutterInitialize();
      final document = await PdfDocument.openFile(widget.path);
      if (!mounted) {
        await document.dispose();
        return;
      }
      setState(() => _document = document);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _field.dispose();
    unawaited(_document?.dispose());
    super.dispose();
  }

  int get _count => _document?.pages.length ?? 0;

  /// The pages chosen as text: ranges when they are in order, one by one
  /// when the lawyer chose another order.
  void _write() {
    final sorted = [..._chosen]..sort();
    final inOrder = List.generate(
      _chosen.length,
      (i) => _chosen[i] == sorted[i],
    ).every((same) => same);
    _field.text = inOrder ? PdfTools.formatRanges(_chosen) : _chosen.join(', ');
    _bad = false;
  }

  void _toggle(int page) => setState(() {
    _chosen.contains(page) ? _chosen.remove(page) : _chosen.add(page);
    _write();
  });

  void _typed(String text) => setState(() {
    if (text.trim().isEmpty) {
      _chosen.clear();
      _bad = false;
      return;
    }
    final pages = PdfTools.parseRanges(text, _count);
    _bad = pages == null;
    if (pages != null) {
      _chosen
        ..clear()
        ..addAll(pages);
    }
  });

  Future<void> _save() async {
    if (_chosen.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await PdfTools.extract(
        await File(widget.path).readAsBytes(),
        _chosen,
      );
      if (!mounted) return;
      final base = p.basenameWithoutExtension(widget.path);
      final saved = await savePdfAs(
        context,
        bytes,
        '$base (${PdfTools.formatRanges(_chosen).replaceAll(', ', ',')}).pdf',
      );
      if (!mounted) return;
      if (saved == null) {
        setState(() => _busy = false);
        return;
      }
      Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showNotice(
        context,
        context.l.pdfFailed,
        detail: '$e',
        kind: NoticeKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final document = _document;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.call_split_rounded, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.l.pdfPagesTitle,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l.tbCancel,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                context.l.pdfPagesHint,
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _error != null
                    ? Center(child: Text('$_error'))
                    : document == null
                    ? const Center(child: CircularProgressIndicator())
                    : GridView.builder(
                        key: const ValueKey('pdf-pages-grid'),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 150,
                              childAspectRatio: .66,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: _count,
                        itemBuilder: (context, i) => _PageTile(
                          document: document,
                          page: i + 1,
                          order: _chosen.indexOf(i + 1),
                          onTap: () => _toggle(i + 1),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('pdf-pages-range'),
                      controller: _field,
                      onChanged: _typed,
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        labelText: context.l.pdfPagesRange,
                        errorText: _bad ? context.l.pdfPagesBad : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: document == null
                        ? null
                        : () => setState(() {
                            _chosen
                              ..clear()
                              ..addAll([for (var i = 1; i <= _count; i++) i]);
                            _write();
                          }),
                    child: Text(context.l.pdfPagesAll),
                  ),
                  TextButton(
                    onPressed: _chosen.isEmpty
                        ? null
                        : () => setState(() {
                            _chosen.clear();
                            _write();
                          }),
                    child: Text(context.l.pdfPagesNone),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l.pdfPagesCount(_chosen.length),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l.tbCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const ValueKey('pdf-pages-save'),
                    onPressed: _chosen.isEmpty || _bad || _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                    label: Text(context.l.pdfSave),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A page as a small picture: pressed, it is chosen, and says which place
/// it has among those chosen.
class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.document,
    required this.page,
    required this.order,
    required this.onTap,
  });

  final PdfDocument document;
  final int page, order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chosen = order >= 0;
    return InkWell(
      key: ValueKey('pdf-page-$page'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: chosen ? scheme.primary : scheme.outlineVariant,
                      width: chosen ? 2.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: PdfPageView(
                      document: document,
                      pageNumber: page,
                      backgroundColor: Colors.white,
                      decoration: const BoxDecoration(color: Colors.white),
                    ),
                  ),
                ),
                if (chosen)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor: scheme.primary,
                      child: Text(
                        '${order + 1}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$page',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: chosen ? FontWeight.w700 : FontWeight.w400,
              color: chosen ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Part {
  _Part(this.path);

  final String path;
  final pages = TextEditingController();

  /// A PDF's pages; null for a picture, or until it is counted.
  int? count;
  bool bad = false;

  /// Whether it has pages to choose from: a PDF, or a TIFF's scan.
  bool get isPdf => PdfPart(path).paged;

  /// What goes into the PDF made, or null when its pages cannot be read.
  PdfPart? get part {
    if (!isPdf) return PdfPart(path);
    final text = pages.text.trim();
    if (text.isEmpty) return PdfPart(path);
    final chosen = PdfTools.parseRanges(text, count ?? 0);
    return chosen == null ? null : PdfPart(path, pages: chosen);
  }

  int get pageCount {
    if (!isPdf) return 1;
    return part?.pages?.length ?? count ?? 0;
  }
}

/// A PDF put together from pictures and PDFs: added, put in order by
/// dragging, a PDF's pages chosen by their numbers, and kept as one file.
class PdfBuilderDialog extends StatefulWidget {
  const PdfBuilderDialog({super.key, this.initial = const []});

  final List<String> initial;

  /// The path of the PDF made, or null.
  static Future<String?> show(
    BuildContext context, {
    List<String> initial = const [],
  }) => showDialog<String>(
    context: context,
    builder: (_) => PdfBuilderDialog(initial: initial),
  );

  /// Replaced under test, where no file dialog opens.
  @visibleForTesting
  static Future<List<String>?> Function()? pickForTesting;

  @override
  State<PdfBuilderDialog> createState() => _PdfBuilderDialogState();
}

class _PdfBuilderDialogState extends State<PdfBuilderDialog> {
  final _parts = <_Part>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _take(widget.initial);
  }

  @override
  void dispose() {
    for (final part in _parts) {
      part.pages.dispose();
    }
    super.dispose();
  }

  void _take(List<String> paths) {
    for (final path in paths) {
      if (!PdfPart.supports(path)) continue;
      final part = _Part(path);
      _parts.add(part);
      if (part.isPdf) unawaited(_count(part));
    }
  }

  Future<void> _count(_Part part) async {
    try {
      final int count;
      if (PdfPart(part.path).isTiff) {
        count = await TiffService.pageCount(
          await File(part.path).readAsBytes(),
        );
      } else {
        await pdfrxFlutterInitialize();
        final document = await PdfDocument.openFile(part.path);
        count = document.pages.length;
        await document.dispose();
      }
      if (mounted) setState(() => part.count = count);
    } catch (_) {
      if (mounted) setState(() => part.count = 0);
    }
  }

  Future<void> _add() async {
    final List<String>? paths;
    if (PdfBuilderDialog.pickForTesting case final pick?) {
      paths = await pick();
    } else {
      final picked = await FilePicker.pickFiles(
        dialogTitle: context.l.pdfBuildAdd,
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const [
          'pdf', 'tif', 'tiff', 'jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', //
        ],
      );
      paths = [
        for (final file in picked?.files ?? const <PlatformFile>[]) ?file.path,
      ];
    }
    if (paths == null || paths.isEmpty || !mounted) return;
    setState(() => _take(paths!));
  }

  int get _total => _parts.fold(0, (sum, part) => sum + part.pageCount);

  bool get _ready =>
      _parts.isNotEmpty &&
      _parts.every((part) => part.part != null) &&
      _total > 0;

  Future<void> _save() async {
    if (!_ready || _busy) return;
    setState(() => _busy = true);
    try {
      final first = p.basenameWithoutExtension(_parts.first.path);
      final bytes = await PdfTools.build([
        for (final part in _parts) part.part!,
      ], title: first);
      if (!mounted) return;
      final saved = await savePdfAs(
        context,
        bytes,
        _parts.length == 1 ? '$first.pdf' : '$first ve diğerleri.pdf',
      );
      if (!mounted) return;
      if (saved == null) {
        setState(() => _busy = false);
        return;
      }
      Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showNotice(
        context,
        context.l.pdfFailed,
        detail: '$e',
        kind: NoticeKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.picture_as_pdf_rounded, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.l.pdfBuildTitle,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l.tbCancel,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                context.l.pdfBuildHint,
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _parts.isEmpty
                    ? Center(
                        child: Text(
                          context.l.pdfBuildEmpty,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ReorderableListView.builder(
                        key: const ValueKey('pdf-build-list'),
                        buildDefaultDragHandles: false,
                        itemCount: _parts.length,
                        onReorderItem: (from, to) => setState(() {
                          _parts.insert(to, _parts.removeAt(from));
                        }),
                        itemBuilder: (context, i) => _row(i, scheme),
                      ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('pdf-build-add'),
                    onPressed: _busy ? null : _add,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(context.l.pdfBuildAdd),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _parts.isEmpty ? '' : context.l.pdfBuildTotal(_total),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('pdf-build-save'),
                    onPressed: _ready && !_busy ? _save : null,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                    label: Text(context.l.pdfSave),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(int i, ColorScheme scheme) {
    final part = _parts[i];
    return Container(
      key: ValueKey('pdf-build-${part.path}-${identityHashCode(part)}'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: i,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.drag_indicator_rounded, size: 20),
            ),
          ),
          SizedBox(
            width: 44,
            height: 56,
            child: part.isPdf
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      Icons.picture_as_pdf_outlined,
                      color: scheme.primary,
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.file(
                      File(part.path),
                      fit: BoxFit.cover,
                      cacheWidth: 132,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.basename(part.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  part.isPdf
                      ? (part.count == null
                            ? '…'
                            : context.l.pdfBuildPagesOf(part.count!))
                      : context.l.pdfBuildPicture,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (part.isPdf)
            SizedBox(
              width: 150,
              child: TextField(
                controller: part.pages,
                onChanged: (_) => setState(() {
                  part.bad = part.part == null;
                }),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  labelText: context.l.pdfBuildPagesLabel,
                  hintText: context.l.pdfBuildAllPages,
                  errorText: part.bad ? '1-3, 5' : null,
                ),
              ),
            ),
          IconButton(
            tooltip: context.l.pdfBuildRemove,
            onPressed: () => setState(() {
              _parts.removeAt(i).pages.dispose();
            }),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
