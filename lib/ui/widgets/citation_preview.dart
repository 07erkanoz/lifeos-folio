import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/document_model.dart';
import '../../services/docx/docx_bridge.dart';
import '../../services/legal/case_law.dart';
import '../../services/legal/citation.dart';
import '../../services/legal/decision.dart';
import '../../services/legal/legislation.dart';
import '../../services/legal/rich_text.dart';
import '../../services/pdf/pdf_service.dart';
import '../../services/platform/rich_clipboard.dart';
import '../../services/udf/udf_writer.dart';
import 'notice.dart';

/// What a preview shows, whether of an article or of a decision.
@immutable
class PreviewData {
  const PreviewData({
    required this.title,
    this.source = '',
    this.rows = const [],
    this.reference = '',
    this.headings = const [],
    this.body = const [],
    this.warning,
    this.message,
    this.loading,
    this.url = '',
    this.retry = false,
  });

  /// "Yargıtay Hukuk Genel Kurulu E.2019/811 K.2022/642 17.05.2022".
  final String title;

  /// Who said this, named so the reader can weigh it.
  final String source;

  /// The reference laid out line by line: court, esas, karar, date, and how
  /// the document wrote it. Selectable, like the rest of the preview.
  final List<(String, String)> rows;

  /// The reference on one line: what is copied, and what heads a copy or a
  /// saved document, since a decision without it cannot be cited.
  final String reference;

  /// An article's own headings, set above its text.
  final List<String> headings;

  final List<RichParagraph> body;

  /// Said above the text: the document named another chamber.
  final String? warning;

  /// Said instead of the text, and why there is none.
  final String? message;

  /// Said while the text is on its way.
  final String? loading;

  /// The official page, so the reader can go and look there if they want.
  final String url;

  /// Whether asking again might help: the source could not be reached.
  final bool retry;

  bool get hasText => body.isNotEmpty;

  /// Headings and text as one run of paragraphs.
  List<RichParagraph> get paragraphs => [
    for (final heading in headings)
      RichParagraph([RichRun(heading, bold: true)]),
    ...body,
  ];

  /// The whole of it as a document, the reference at its head.
  DocModel get document => documentOfParagraphs(reference, paragraphs);

  /// The whole of it as plain text, the reference at its head.
  String get plainText => '$reference\n\n${plainTextOfParagraphs(paragraphs)}';
}

// -- what a preview says ---------------------------------------------------------

/// An article's preview before its text has come.
PreviewData articleWaiting(Citation citation) => PreviewData(
  title: citation.label,
  source: 'Mevzuat',
  rows: _articleRows(citation, null),
  reference: _articleReference(citation, null),
  loading: 'Madde getiriliyor…',
  url: Legislation.pageOf(citation.law),
);

/// An article's preview once the sources have answered.
PreviewData articlePreview(Citation citation, ArticleLookup lookup) {
  final article = lookup.article;
  if (article == null) {
    return PreviewData(
      title: citation.label,
      source: 'Mevzuat',
      rows: _articleRows(citation, null),
      reference: _articleReference(citation, null),
      message: lookup.outcome == ArticleOutcome.unreachable
          ? 'Resmî kaynağa şu an ulaşılamadı; bakılamadı. Bu kanun daha önce '
                'açılmadıysa internet bağlantısı gerekir.'
          : 'Bu maddenin metni resmî kaynaklarda bulunamadı. Kanunun resmî '
                'sayfasından bakabilirsiniz.',
      url: lookup.url.isEmpty ? Legislation.pageOf(citation.law) : lookup.url,
      retry: lookup.outcome == ArticleOutcome.unreachable,
    );
  }
  return PreviewData(
    title: '${article.title}${article.repealed ? ' (MÜLGA)' : ''}',
    source: article.source.label,
    rows: _articleRows(citation, article),
    reference: _articleReference(citation, article),
    headings: article.headings,
    body: article.body,
    // Said above the one line a repealed article still has, which alone
    // reads like the text failed to load.
    warning: article.repealNotice,
    url: [
      article.url,
      lookup.url,
      Legislation.pageOf(citation.law),
    ].firstWhere((url) => url.isNotEmpty),
  );
}

String _lawLine(Citation citation, Article? article) {
  final law = citation.law;
  final name = article?.lawName ?? law.name;
  if (!law.isKnown && name == law.name) return name;
  return '${law.number} sayılı $name${law.repealed ? ' (mülga)' : ''}';
}

String _articleReference(Citation citation, Article? article) =>
    '${_lawLine(citation, article)} ${citation.place}';

List<(String, String)> _articleRows(Citation citation, Article? article) => [
  ('Kanun', _lawLine(citation, article)),
  ('Madde', citation.place),
  if (article != null && article.repealed) ('Durum', 'Mülga'),
  if (article != null) ('Kaynak', article.source.label),
  if (citation.written.isNotEmpty) ('Belgedeki yazım', citation.written),
];

/// A decision's preview before the banks have answered.
PreviewData decisionWaiting(DecisionCitation citation) => PreviewData(
  title: citation.label,
  source: citation.constitutional
      ? 'Anayasa Mahkemesi Kararlar Bilgi Bankası'
      : 'Bedesten · UYAP Emsal',
  rows: _citedRows(citation),
  reference: _citedReference(citation),
  loading: citation.constitutional
      ? 'Anayasa Mahkemesi karar bilgi bankasında aranıyor…'
      : 'Karar bankalarında aranıyor…',
);

/// A decision's preview once the banks have answered.
PreviewData decisionPreview(DecisionCitation citation, DecisionLookup lookup) {
  final decision = lookup.decision;
  if (decision == null) {
    final site = citation.constitutional
        ? DecisionSource.constitutional.site
        : DecisionSource.bedesten.site;
    return PreviewData(
      title: citation.label,
      source: citation.constitutional
          ? DecisionSource.constitutional.label
          : 'Bedesten · UYAP Emsal',
      rows: _citedRows(citation),
      reference: _citedReference(citation),
      message: _notFound(citation, lookup.outcome),
      url: site,
      retry: lookup.outcome == LookupOutcome.unreachable,
    );
  }
  final found = decisionFound(decision, written: _writtenOf(citation));
  if (!lookup.chamberDiffers) return found;
  final declared = fullCourtName(citation.courtLabel);
  return PreviewData(
    title: found.title,
    source: found.source,
    rows: found.rows,
    reference: found.reference,
    body: found.body,
    url: found.url,
    warning:
        'Belgede “$declared” yazıyor; bu numaralarla bulunan karar '
        '${fullCourtName(decision.court)} kararı. Aynı numara başka bir '
        'dairede de olabilir, atfı kontrol edin.',
  );
}

/// A decision as found, by a citation or by a search.
PreviewData decisionFound(Decision decision, {String written = ''}) {
  final court = fullCourtName(decision.court);
  return PreviewData(
    title: decision.title,
    source: [
      if (decision.date.isNotEmpty) 'Karar tarihi ${decision.date}',
      decision.source.label,
      'resmî metin',
    ].join(' · '),
    rows: [
      if (court.isNotEmpty) ('Mahkeme / Daire', court),
      if (decision.isApplication)
        ('Başvuru No', decision.esas)
      else ...[
        ('Esas No', decision.esas),
        ('Karar No', decision.karar),
      ],
      if (decision.date.isNotEmpty) ('Karar Tarihi', decision.date),
      for (final (name, value) in decision.details)
        if (!(decision.isApplication && name == 'Başvuru No')) (name, value),
      ('Kaynak', decision.source.label),
      if (written.isNotEmpty) ('Belgedeki yazım', written),
    ],
    reference: decision.reference,
    body: decision.paragraphs,
    url: decision.url.isEmpty ? decision.source.site : decision.url,
  );
}

List<(String, String)> _citedRows(DecisionCitation citation) {
  final court = fullCourtName(citation.courtLabel);
  return [
    if (court.isNotEmpty) ('Mahkeme / Daire', court),
    if (citation.application)
      ('Başvuru No', citation.esas)
    else ...[
      ('Esas No', citation.esas),
      ('Karar No', citation.karar),
    ],
    if (citation.written.isNotEmpty) ('Belgedeki yazım', _writtenOf(citation)),
  ];
}

/// The numbers as the document wrote them, and the court it named before
/// them: the court is read from further back, so it is joined on.
String _writtenOf(DecisionCitation citation) {
  final court = citation.courtWritten;
  if (court.isEmpty || citation.written.contains(court)) {
    return citation.written;
  }
  return '$court … ${citation.written}';
}

String _citedReference(DecisionCitation citation) {
  if (citation.application) {
    return 'AYM, B. No: ${citation.esas}';
  }
  return decisionReference(
    court: citation.constitutional ? 'Anayasa Mahkemesi' : citation.courtLabel,
    esas: citation.esas,
    karar: citation.karar,
  );
}

String _notFound(DecisionCitation citation, LookupOutcome outcome) {
  if (outcome == LookupOutcome.unreachable) {
    return citation.constitutional
        ? 'Anayasa Mahkemesi karar bilgi bankasına şu an ulaşılamadı; '
              'bakılamadı. İnternet bağlantınızı denetleyip yeniden deneyin.'
        : 'Karar bankalarına şu an ulaşılamadı; bakılamadı. İnternet '
              'bağlantınızı denetleyip yeniden deneyin.';
  }
  if (outcome == LookupOutcome.unpublished) {
    return 'Bu mahkemenin kararları resmî karar bankalarında yayımlanmıyor.';
  }
  if (citation.constitutional) {
    return 'Bu karar Anayasa Mahkemesi karar bilgi bankasında bulunamadı. '
        'Künyeyi Anayasa Mahkemesi’nin sitesinden doğrulayabilirsiniz.';
  }
  final where = citation.court?.kind == 'bam'
      ? 'Bedesten’de ve UYAP Emsal’de'
      : 'Bedesten’de';
  return 'Bu karar $where bulunamadı. Karar bankaları kararların yalnız bir '
      'bölümünü yayımlar; atfı başka bir kaynaktan doğrulayın.';
}

// -- the card and the screen -----------------------------------------------------

/// The text of an official source, laid out to be read: the typeface of a
/// filing, a paragraph at a time, bold where the source set it.
class RichBody extends StatelessWidget {
  const RichBody({super.key, required this.paragraphs, this.size = 14.5});

  final List<RichParagraph> paragraphs;
  final double size;

  static TextAlign _align(DocAlignment alignment) => switch (alignment) {
    DocAlignment.center => TextAlign.center,
    DocAlignment.right => TextAlign.right,
    DocAlignment.justify => TextAlign.justify,
    DocAlignment.left => TextAlign.left,
  };

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: 'LiberationSerif',
      fontSize: size,
      height: 1.55,
      color: Theme.of(context).colorScheme.onSurface,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final paragraph in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text.rich(
              TextSpan(
                children: [
                  for (final run in paragraph.runs)
                    TextSpan(
                      text: run.text,
                      style: base.copyWith(
                        fontWeight: run.bold ? FontWeight.w700 : null,
                        fontStyle: run.italic ? FontStyle.italic : null,
                        decoration: run.underline
                            ? TextDecoration.underline
                            : null,
                      ),
                    ),
                ],
              ),
              style: base,
              textAlign: _align(paragraph.alignment),
            ),
          ),
      ],
    );
  }
}

/// The reference laid out line by line, above the text.
class ReferenceBlock extends StatelessWidget {
  const ReferenceBlock({super.key, required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameStyle = TextStyle(
      fontSize: 12,
      height: 1.45,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueStyle = TextStyle(
      fontSize: 13,
      height: 1.35,
      fontWeight: FontWeight.w500,
      color: theme.colorScheme.onSurface,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      // On a phone the name goes above its value: a column of names beside
      // the values leaves the values two words a line.
      child: LayoutBuilder(
        builder: (context, space) {
          final narrow = space.maxWidth < 380;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (name, value) in rows)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: narrow ? 3.5 : 2.5),
                  child: narrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: nameStyle),
                            Text(value, style: valueStyle),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 124,
                              child: Text(name, style: nameStyle),
                            ),
                            Expanded(child: Text(value, style: valueStyle)),
                          ],
                        ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Everything under the heading of a preview: the reference, a warning,
/// then the text or why there is none. Selectable as one.
class PreviewContent extends StatelessWidget {
  const PreviewContent({super.key, required this.data, this.size = 14.5});

  final PreviewData data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (data.rows.isNotEmpty) ReferenceBlock(rows: data.rows),
          if (data.warning != null) ...[
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('preview-warning'),
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      data.warning!,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (data.loading != null && !data.hasText)
            Column(
              children: [
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 14),
                Text(
                  data.loading!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
              ],
            )
          else if (!data.hasText && data.message != null)
            Text(
              data.message!,
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            RichBody(paragraphs: data.paragraphs, size: size),
        ],
      ),
    );
  }
}

/// What a reader can do with what a preview shows.
class PreviewActions {
  const PreviewActions._();

  static void _say(
    ScaffoldMessengerState? messenger,
    String text, {
    String? detail,
    NoticeKind kind = NoticeKind.success,
  }) {
    messenger
      ?..clearSnackBars()
      ..showSnackBar(noticeBar(text, detail: detail, kind: kind));
  }

  static Future<void> copyReference(
    BuildContext context,
    PreviewData data,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: data.reference));
    _say(messenger, 'Künye panoya kopyalandı.', detail: data.reference);
  }

  /// With its formatting — bold stays bold when pasted into this editor, into
  /// Word or into a mail — and with the reference at its head.
  static Future<void> copyAll(BuildContext context, PreviewData data) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await RichClipboard.write(data.document, data.plainText);
    } on Object {
      await Clipboard.setData(ClipboardData(text: data.plainText));
    }
    _say(messenger, 'Tümü biçimiyle panoya kopyalandı.');
  }

  static Future<void> save(
    BuildContext context,
    PreviewData data,
    String extension,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final where = await FilePicker.saveFile(
      dialogTitle: 'Kaydet',
      fileName: '${fileNameOf(data.reference)}.$extension',
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    if (where == null) return;
    try {
      final model = data.document;
      final List<int> bytes = switch (extension) {
        'pdf' => await PdfService.modelToPdfBytes(model, title: data.reference),
        'docx' => await DocxBridge.writeBytes(model),
        _ => UdfWriter.writeBytes(model),
      };
      await File(where).writeAsBytes(bytes);
      _say(messenger, 'Kaydedildi.', detail: where);
    } on Object catch (error) {
      _say(
        messenger,
        'Kaydedilemedi',
        detail: '$error',
        kind: NoticeKind.error,
      );
    }
  }

  static Future<void> openSource(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      _say(
        messenger,
        'Resmî kaynak açılamadı',
        detail: url,
        kind: NoticeKind.error,
      );
    }
  }

  /// The row of buttons under a preview.
  static List<Widget> of(
    BuildContext context,
    PreviewData data, {
    VoidCallback? onRetry,
    VoidCallback? onFullScreen,
  }) {
    Widget button(IconData icon, String label, VoidCallback onPressed) =>
        TextButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 12.5)),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        );

    return [
      if (data.reference.isNotEmpty)
        button(
          Icons.bookmark_border_rounded,
          'Künyeyi kopyala',
          () => copyReference(context, data),
        ),
      if (data.hasText) ...[
        button(
          Icons.copy_all_rounded,
          'Tümünü kopyala',
          () => copyAll(context, data),
        ),
        button(
          Icons.picture_as_pdf_outlined,
          'PDF',
          () => save(context, data, 'pdf'),
        ),
        button(
          Icons.description_outlined,
          'UDF',
          () => save(context, data, 'udf'),
        ),
        button(
          Icons.article_outlined,
          'Word',
          () => save(context, data, 'docx'),
        ),
      ],
      if (data.url.isNotEmpty)
        button(
          Icons.open_in_new_rounded,
          'Resmî kaynakta aç',
          () => openSource(context, data.url),
        ),
      if (data.retry && onRetry != null)
        button(Icons.refresh_rounded, 'Yeniden dene', onRetry),
      if (data.hasText && onFullScreen != null)
        button(Icons.fullscreen_rounded, 'Tam ekran', onFullScreen),
    ];
  }
}

/// A preview shown over the document, filling itself in as its source
/// answers: the reference first, at once, and the text when it comes.
class CitationPreviewCard extends StatefulWidget {
  const CitationPreviewCard({
    super.key,
    required this.icon,
    required this.waiting,
    required this.load,
    required this.maxHeight,
    required this.onClose,
    this.onFullScreen,
    this.cardKey,
  });

  final IconData icon;
  final PreviewData waiting;
  final Future<PreviewData> Function() load;
  final double maxHeight;
  final VoidCallback onClose;
  final void Function(PreviewData data)? onFullScreen;
  final Key? cardKey;

  @override
  State<CitationPreviewCard> createState() => _CitationPreviewCardState();
}

class _CitationPreviewCardState extends State<CitationPreviewCard> {
  late PreviewData _data = widget.waiting;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_ask());
  }

  Future<void> _ask() async {
    final run = ++_asked;
    if (run > 1) setState(() => _data = widget.waiting);
    final PreviewData answer;
    try {
      answer = await widget.load();
    } on Object {
      return;
    }
    if (mounted && run == _asked) setState(() => _data = answer);
  }

  static const _header = 58.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _data;
    final full = widget.onFullScreen;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 140),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 5 * (1 - value)),
          child: child,
        ),
      ),
      child: Material(
        key: widget.cardKey,
        elevation: 12,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        // The text takes the room the heading and the buttons leave; the
        // buttons may wrap onto a second row on a narrower card.
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: _header,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
                  child: Row(
                    children: [
                      Icon(
                        widget.icon,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            if (data.source.isNotEmpty)
                              Text(
                                data.source,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Kapat (Esc)',
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              Flexible(
                child: ColoredBox(
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                      child: PreviewContent(data: data),
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: PreviewActions.of(
                      context,
                      data,
                      onRetry: _ask,
                      onFullScreen: full == null ? null : () => full(data),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A preview read on its own, with nothing else on screen.
///
/// Given [load], it fills itself in the way the card does: on a phone a
/// press on a citation opens this rather than a card over the document,
/// which would have no room.
class CitationPreviewScreen extends StatefulWidget {
  const CitationPreviewScreen({super.key, required this.data, this.load});

  final PreviewData data;
  final Future<PreviewData> Function()? load;

  /// Whether a preview should take the whole screen rather than a card:
  /// the width the rest of the app treats as a phone's.
  static bool wanted(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 700;

  @override
  State<CitationPreviewScreen> createState() => _CitationPreviewScreenState();
}

class _CitationPreviewScreenState extends State<CitationPreviewScreen> {
  late PreviewData _data = widget.data;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    if (widget.load != null) unawaited(_ask());
  }

  Future<void> _ask() async {
    final load = widget.load;
    if (load == null) return;
    final run = ++_asked;
    if (run > 1) setState(() => _data = widget.data);
    final PreviewData answer;
    try {
      answer = await load();
    } on Object {
      return;
    }
    if (mounted && run == _asked) setState(() => _data = answer);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _data;
    final phone = CitationPreviewScreen.wanted(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data.title, style: const TextStyle(fontSize: 15)),
            if (data.source.isNotEmpty)
              Text(
                data.source,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                // A measure a page wide: a line of eighty characters is read
                // more easily than one that runs the width of a monitor.
                constraints: const BoxConstraints(maxWidth: 860),
                child: Scrollbar(
                  child: SingleChildScrollView(
                    padding: phone
                        ? const EdgeInsets.fromLTRB(16, 14, 16, 28)
                        : const EdgeInsets.fromLTRB(28, 22, 28, 40),
                    child: PreviewContent(data: data, size: phone ? 15 : 15.5),
                  ),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 2,
                runSpacing: 2,
                children: PreviewActions.of(
                  context,
                  data,
                  onRetry: widget.load == null ? null : _ask,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
