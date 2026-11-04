import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';

import '../../services/platform/phone_document_save.dart';
import '../../services/print/print_job.dart';
import '../../services/print/print_selection.dart';
import '../../services/platform/app_language.dart';
import 'notice.dart';
import 'folio_select.dart';

/// The print screen, as Word lays one out: what to print and where on the
/// left, the pages as they will come out on the right.
///
/// The document is printed from its PDF — the preview's, which is the page
/// UYAP prints — so what is shown is what comes out of the printer, and a
/// range of pages is those pages exactly.
class PrintScreen extends StatefulWidget {
  const PrintScreen({
    super.key,
    required this.pdf,
    required this.name,
    this.startPage = 1,
    this.document,
  });

  final Uint8List pdf;

  /// The document's name, which the print queue shows.
  final String name;

  /// The page the preview opens on, and that "Geçerli sayfa" prints.
  final int startPage;

  /// The PDF, opened already; for tests, where it cannot be opened here.
  @visibleForTesting
  final PdfDocument? document;

  /// Opens the print screen over [context]; true when the document went to
  /// the printer.
  static Future<bool> show(
    BuildContext context, {
    required Uint8List pdf,
    required String name,
    int startPage = 1,
  }) async {
    final printed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        final phone = size.width < 760;
        return Dialog(
          insetPadding: phone ? EdgeInsets.zero : const EdgeInsets.all(28),
          clipBehavior: Clip.antiAlias,
          shape: phone
              ? const RoundedRectangleBorder()
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: SizedBox(
            width: phone ? size.width : 1100,
            height: phone ? size.height : 760,
            child: PrintScreen(pdf: pdf, name: name, startPage: startPage),
          ),
        );
      },
    );
    return printed ?? false;
  }

  @override
  State<PrintScreen> createState() => _PrintScreenState();
}

class _PrintScreenState extends State<PrintScreen> {
  PdfDocument? _document;
  int _pageCount = 0;
  late int _page = widget.startPage;
  String? _openError;

  List<Printer> _printers = const [];

  /// Null: the system's own print dialog.
  Printer? _printer;

  PrintPages _which = PrintPages.all;
  final _range = TextEditingController();
  PrintParity _parity = PrintParity.all;
  int _copies = 1;
  bool _collate = true;
  bool _busy = false;

  final _focus = FocusNode(debugLabel: 'print-screen');

  @override
  void initState() {
    super.initState();
    _open();
    PrintJob.printers().then((printers) {
      if (!mounted) return;
      setState(() {
        _printers = printers;
        _printer = printers.firstOrNull;
      });
    });
  }

  Future<void> _open() async {
    try {
      final document =
          widget.document ??
          await () async {
            await pdfrxFlutterInitialize();
            return PdfDocument.openData(widget.pdf);
          }();
      if (!mounted) return;
      setState(() {
        _document = document;
        _pageCount = document.pages.length;
        _page = _page.clamp(1, _pageCount);
      });
    } catch (e) {
      if (mounted) setState(() => _openError = '$e');
    }
  }

  @override
  void dispose() {
    if (widget.document == null) _document?.dispose();
    _range.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<int>? get _pages => _pageCount == 0
      ? null
      : PrintSelection.pages(
          pageCount: _pageCount,
          which: _which,
          current: _page,
          range: _range.text,
          parity: _parity,
        );

  Future<Uint8List> _chosenPdf(List<int> sheets) async {
    // All of it, once, in order: the document as it is.
    final whole =
        sheets.length == _pageCount &&
        [for (var i = 0; i < sheets.length; i++) sheets[i] == i + 1]
            .every((x) => x);
    return whole ? widget.pdf : PrintJob.extract(widget.pdf, sheets);
  }

  Future<void> _print() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final pdf = await _chosenPdf(
        PrintSelection.sheets(pages, copies: _copies, collate: _collate),
      );
      final sent = await PrintJob.send(
        pdf,
        name: widget.name,
        printer: _printer,
      );
      if (mounted && sent) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          context.l.tbPrintFailed,
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePdf() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty || _busy) return;
    setState(() => _busy = true);
    final title = context.l.tbSaveAsPdf;
    try {
      final pdf = await _chosenPdf(pages);
      final base = widget.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      final fileName = '$base.pdf';
      final path = PhoneDocumentSave.here
          ? await PhoneDocumentSave.save(fileName: fileName, bytes: pdf)
          : await FilePicker.saveFile(
              dialogTitle: title,
              fileName: fileName,
              type: FileType.custom,
              allowedExtensions: const ['pdf'],
            );
      if (path == null) return;
      if (!PhoneDocumentSave.here) {
        await File(path).writeAsBytes(pdf, flush: true);
      }
      if (mounted) {
        showNotice(context, context.l.tbPdfSaved, kind: NoticeKind.success);
      }
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          context.l.tbPdfSaveFailed,
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _turn(int by) {
    if (_pageCount == 0) return;
    setState(() => _page = (_page + by).clamp(1, _pageCount));
  }

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 760;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _turn(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _turn(-1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _turn(1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _turn(-1),
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: phone
            ? Column(
                children: [
                  Expanded(flex: 5, child: _preview(context)),
                  const Divider(height: 1),
                  Expanded(flex: 6, child: _settings(context, phone: true)),
                ],
              )
            : Row(
                children: [
                  SizedBox(width: 340, child: _settings(context, phone: false)),
                  const VerticalDivider(width: 1),
                  Expanded(child: _preview(context)),
                ],
              ),
      ),
    );
  }

  Widget _settings(BuildContext context, {required bool phone}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pages = _pages;
    final invalid = _which == PrintPages.custom && _range.text.isNotEmpty
        ? pages == null
        : false;
    final sheets = pages == null
        ? 0
        : PrintSelection.sheets(pages, copies: _copies).length;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    return Material(
      color: scheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        children: [
          Row(
            children: [
              Icon(Icons.print_outlined, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l.tbPrint,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: context.l.tbClose,
                onPressed: () => Navigator.pop(context, false),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    key: const ValueKey('print-go'),
                    onPressed:
                        pages == null ||
                            pages.isEmpty ||
                            _busy ||
                            _document == null
                        ? null
                        : _print,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print),
                    label: Text(
                      context.l.tbPrint,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _copiesField(context),
            ],
          ),
          label(context.l.tbPrinter),
          if (_printers.isEmpty)
            Text(
              context.l.tbPrinterInSystemDialog,
              style: theme.textTheme.bodySmall,
            )
          else
            FolioSelect<Printer?>(
              key: const ValueKey('print-printer'),
              initialValue: _printer,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final printer in _printers)
                  DropdownMenuItem(
                    value: printer,
                    child: Text(
                      printer.isDefault
                          ? context.l.tbPrinterDefault(printer.name)
                          : printer.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                DropdownMenuItem(
                  value: null,
                  child: Text(context.l.tbSystemPrintDialog),
                ),
              ],
              onChanged: (p) => setState(() => _printer = p),
            ),
          label(context.l.tbPages),
          RadioGroup<PrintPages>(
            groupValue: _which,
            onChanged: (v) => setState(() => _which = v ?? PrintPages.all),
            child: Column(
              children: [
                RadioListTile<PrintPages>(
                  value: PrintPages.all,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l.tbAllPages(_pageCount)),
                ),
                RadioListTile<PrintPages>(
                  value: PrintPages.current,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l.tbCurrentPage(_page)),
                ),
                RadioListTile<PrintPages>(
                  value: PrintPages.custom,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l.tbPageRange),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: TextField(
              key: const ValueKey('print-range'),
              controller: _range,
              enabled: _which == PrintPages.custom,
              decoration: InputDecoration(
                hintText: context.l.tbPageRangeHint,
                isDense: true,
                border: const OutlineInputBorder(),
                errorText: invalid
                    ? context.l.tbPageRangeInvalid(_pageCount)
                    : null,
              ),
              onTap: () => setState(() => _which = PrintPages.custom),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 12),
          FolioSelect<PrintParity>(
            initialValue: _parity,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(
                value: PrintParity.all,
                child: Text(context.l.tbOddAndEvenPages),
              ),
              DropdownMenuItem(
                value: PrintParity.odd,
                child: Text(context.l.tbOddPagesOnly),
              ),
              DropdownMenuItem(
                value: PrintParity.even,
                child: Text(context.l.tbEvenPagesOnly),
              ),
            ],
            onChanged: (v) => setState(() => _parity = v ?? PrintParity.all),
          ),
          if (_copies > 1) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _collate,
              onChanged: (v) => setState(() => _collate = v ?? true),
              title: Text(context.l.tbCollate),
              subtitle: Text(
                _collate ? '1, 2, 3 · 1, 2, 3' : '1, 1 · 2, 2 · 3, 3',
              ),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.description_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pages == null
                        ? context.l.tbChoosePageToPrint
                        : _copies > 1
                        ? context.l.tbPrintSummaryCopies(
                            pages.length,
                            _copies,
                            sheets,
                          )
                        : context.l.tbPrintSummary(pages.length, sheets),
                    key: const ValueKey('print-summary'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: pages == null || pages.isEmpty || _busy
                ? null
                : _savePdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(context.l.tbSaveSelectedPagesPdf),
          ),
        ],
      ),
    );
  }

  Widget _copiesField(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: context.l.tbOneCopyFewer,
            onPressed: _copies > 1 ? () => setState(() => _copies--) : null,
            icon: const Icon(Icons.remove, size: 18),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$_copies',
                key: const ValueKey('print-copies'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                context.l.tbCopiesLabel,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          IconButton(
            tooltip: context.l.tbOneCopyMore,
            onPressed: _copies < 99 ? () => setState(() => _copies++) : null,
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final document = _document;
    final pages = _pages;
    final printed = pages == null || pages.contains(_page);
    return ColoredBox(
      color: scheme.surfaceContainerHighest.withValues(alpha: .6),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 12),
              child: _openError != null
                  ? Center(
                      child: Text(context.l.tbPreviewFailed('$_openError')),
                    )
                  : document == null
                  ? const Center(child: CircularProgressIndicator())
                  : Center(
                      child: AspectRatio(
                        aspectRatio: _aspect(document),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: .18),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: PdfPageView(
                                key: ValueKey('print-page-$_page'),
                                document: document,
                                pageNumber: _page,
                                backgroundColor: Colors.white,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            if (!printed)
                              ColoredBox(
                                color: Colors.white.withValues(alpha: .72),
                                child: Center(
                                  child: Chip(
                                    avatar: const Icon(Icons.block, size: 16),
                                    label: Text(context.l.tbNotPrinted),
                                    backgroundColor: scheme.surface,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: context.l.tbPreviousPage,
                  onPressed: _page > 1 ? () => _turn(-1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_page / $_pageCount',
                    key: const ValueKey('print-page'),
                  ),
                ),
                IconButton(
                  tooltip: context.l.tbNextPage,
                  onPressed: _page < _pageCount ? () => _turn(1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _aspect(PdfDocument document) {
    final page = document.pages[_page - 1];
    return page.width / page.height;
  }
}
