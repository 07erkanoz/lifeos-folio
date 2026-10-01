import 'package:flutter/material.dart';

import '../../services/legal/case_law.dart';
import '../../services/legal/citation.dart';
import '../../services/legal/decision.dart';
import '../../services/legal/legal_terms.dart';
import '../../services/legal/legislation.dart';
import 'citation_preview.dart';
import 'overlay_card.dart';

/// The text of a cited article, shown over the document.
class ArticlePanel {
  const ArticlePanel._();

  static void show(
    BuildContext context, {
    required Citation citation,
    required Future<ArticleLookup> Function() lookup,
    required Offset at,
  }) {
    // Held before the card is built: the overlay's own context has no route
    // to push onto, and full screen is a route.
    final navigator = Navigator.of(context);
    if (CitationPreviewScreen.wanted(context)) {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => CitationPreviewScreen(
            data: articleWaiting(citation),
            load: () async => articlePreview(citation, await lookup()),
          ),
        ),
      );
      return;
    }
    OverlayCard.show(
      context,
      at: at,
      width: 620,
      height: 520,
      shrinkToFit: true,
      builder: (close) => ArticleCard(
        citation: citation,
        lookup: lookup,
        maxHeight: 520,
        onClose: close,
        onFullScreen: (data) {
          close();
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => CitationPreviewScreen(data: data),
            ),
          );
        },
      ),
    );
  }
}

/// The card itself, so it can be built and looked at without an overlay.
class ArticleCard extends StatelessWidget {
  const ArticleCard({
    super.key,
    required this.citation,
    required this.lookup,
    required this.maxHeight,
    required this.onClose,
    this.onFullScreen,
  });

  final Citation citation;
  final Future<ArticleLookup> Function() lookup;
  final double maxHeight;
  final VoidCallback onClose;
  final void Function(PreviewData data)? onFullScreen;

  @override
  Widget build(BuildContext context) => CitationPreviewCard(
    cardKey: const ValueKey('article-panel'),
    icon: Icons.gavel_outlined,
    waiting: articleWaiting(citation),
    load: () async => articlePreview(citation, await lookup()),
    maxHeight: maxHeight,
    onClose: onClose,
    onFullScreen: onFullScreen,
  );
}

/// The text of a cited decision, shown over the document.
class DecisionPanel {
  const DecisionPanel._();

  static void show(
    BuildContext context, {
    required DecisionCitation citation,
    required Future<DecisionLookup> Function() lookup,
    required Offset at,
  }) {
    final navigator = Navigator.of(context);
    if (CitationPreviewScreen.wanted(context)) {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => CitationPreviewScreen(
            data: decisionWaiting(citation),
            load: () async => decisionPreview(citation, await lookup()),
          ),
        ),
      );
      return;
    }
    OverlayCard.show(
      context,
      at: at,
      // Wider and taller than an article: a decision runs to pages, and a
      // lawyer reads it rather than glancing at it.
      width: 780,
      height: 600,
      shrinkToFit: true,
      builder: (close) => DecisionCard(
        citation: citation,
        lookup: lookup,
        maxHeight: 600,
        onClose: close,
        onFullScreen: (data) {
          close();
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => CitationPreviewScreen(data: data),
            ),
          );
        },
      ),
    );
  }
}

class DecisionCard extends StatelessWidget {
  const DecisionCard({
    super.key,
    required this.citation,
    required this.lookup,
    required this.maxHeight,
    required this.onClose,
    this.onFullScreen,
  });

  final DecisionCitation citation;
  final Future<DecisionLookup> Function() lookup;
  final double maxHeight;
  final VoidCallback onClose;
  final void Function(PreviewData data)? onFullScreen;

  @override
  Widget build(BuildContext context) => CitationPreviewCard(
    cardKey: const ValueKey('decision-panel'),
    icon: Icons.balance_outlined,
    waiting: decisionWaiting(citation),
    load: () async => decisionPreview(citation, await lookup()),
    maxHeight: maxHeight,
    onClose: onClose,
    onFullScreen: onFullScreen,
  );
}

/// A decision found by searching, read with nothing else on screen.
Future<void> showFoundDecision(BuildContext context, Decision decision) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CitationPreviewScreen(data: decisionFound(decision)),
      ),
    );

/// What a term of art means, shown over the document.
class TermPanel {
  const TermPanel._();

  static void show(
    BuildContext context, {
    required TermMatch term,
    required Offset at,
  }) => OverlayCard.show(
    context,
    at: at,
    width: 440,
    height: 300,
    builder: (close) => TermCard(term: term, maxHeight: 300, onClose: close),
  );
}

class TermCard extends StatelessWidget {
  const TermCard({
    super.key,
    required this.term,
    required this.maxHeight,
    required this.onClose,
  });

  final TermMatch term;
  final double maxHeight;
  final VoidCallback onClose;

  /// Who said this, named so the reader can weigh it.
  static String _source(TermMatch term) {
    if (term.dictionary != null && term.statutes.isNotEmpty) {
      return 'sozluk.adalet.gov.tr · mevzuat.gov.tr';
    }
    if (term.dictionary == null) return 'mevzuat.gov.tr · resmî metin';
    return term.dictionary!.clipped
        ? 'sozluk.adalet.gov.tr · tanım kaynakta kısaltılmış'
        : 'sozluk.adalet.gov.tr';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OverlayCardFrame(
      cardKey: const ValueKey('term-panel'),
      icon: Icons.menu_book_outlined,
      title: term.term,
      source: _source(term),
      maxHeight: maxHeight,
      onClose: onClose,
      body: OverlayCardBody(
        maxHeight: maxHeight - 82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (term.dictionary != null)
              SelectableText(
                // The source cuts a long entry off at a fixed length. Said
                // rather than hidden: a reader must not take half a
                // sentence for the whole of the meaning.
                term.dictionary!.clipped
                    ? '${term.dictionary!.meaning}…'
                    : term.dictionary!.meaning,
                style: TextStyle(
                  height: 1.6,
                  fontSize: 13,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            if (term.statutes.isNotEmpty) ...[
              if (term.dictionary != null) ...[
                const SizedBox(height: 16),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 14),
              ],
              Text(
                // Never "the" meaning: a statute scopes a word to itself,
                // and eight of them can scope the same word eight ways.
                term.statutes.length == 1
                    ? 'Kanundaki tanımı'
                    : 'Kanunlardaki tanımları',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              for (final statute in term.statutes) ...[
                const SizedBox(height: 10),
                Text(
                  statute.law,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  statute.meaning,
                  style: TextStyle(
                    height: 1.55,
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
