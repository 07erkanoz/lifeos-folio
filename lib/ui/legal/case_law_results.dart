import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/legal/case_law_search.dart';
import '../widgets/editor_citations.dart' show citationInk;
import '../widgets/notice.dart';

/// A page of decisions, as a reader scans them.
///
/// The same list serves the search screen and the small panel in the
/// editor, because what a reader needs from a result is the same in both
/// places: whose decision it is, what it says about the words they asked
/// for, and whether it stands alone.
class CaseLawResultList extends StatelessWidget {
  const CaseLawResultList({
    super.key,
    required this.results,
    required this.onOpen,
    this.busy = false,
    this.settling = false,
    this.asked = false,
    this.compact = false,
    this.onPage,
  });

  final CaseLawResults results;
  final bool busy;

  /// Whether the page is still being read and reordered. The decisions are
  /// already on screen; this only says the order is not final yet.
  final bool settling;

  /// Whether a search has been run at all, so an empty list can say the
  /// right thing: nothing found, rather than nothing asked.
  final bool asked;
  final bool compact;
  final void Function(CaseLawHit hit) onOpen;

  /// Null where there is no room to page, as in the editor panel.
  final void Function(int page)? onPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Text(
          asked
              ? 'Bu aramaya uyan karar bulunamadı. Kelimeleri azaltmayı ya da '
                    '“herhangi biri geçsin” seçeneğini deneyin.'
              : 'Aranacak kelimeleri yazın ya da esas/karar numarası girin.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final gathered = results.hits.fold<int>(0, (n, hit) => n + hit.alike);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _summary(results, gathered),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (settling) ...[
                const SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                ),
                const SizedBox(width: 7),
                Text(
                  'sıralanıyor',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        Flexible(
          child: Scrollbar(
            child: ListView.separated(
              shrinkWrap: compact,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              itemCount: results.hits.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) => _Row(
                hit: results.hits[i],
                compact: compact,
                onOpen: () => onOpen(results.hits[i]),
              ),
            ),
          ),
        ),
        if (onPage != null && results.total > results.hits.length)
          _Paging(results: results, onPage: onPage!),
      ],
    );
  }

  /// What the page is, said plainly.
  ///
  /// The count the bank gives is of decisions, not of holdings, and when a
  /// chamber has decided twenty like cases alike the two numbers are very
  /// far apart. Both are shown rather than only the flattering one.
  static String _summary(CaseLawResults results, int gathered) {
    final shown = results.hits.length;
    final of = '${results.total} karar bulundu';
    if (gathered == 0) return '$of · bu sayfada $shown tanesi';
    return '$of · bu sayfada $shown ayrı gerekçe '
        '($gathered karar aynı gerekçeyle birleştirildi)';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.hit, required this.compact, required this.onOpen});

  final CaseLawHit hit;
  final bool compact;
  final VoidCallback onOpen;

  /// The reference as a filing writes it, without opening the decision.
  Future<void> _copyReference(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final reference = hit.citationReference;
    await Clipboard.setData(ClipboardData(text: reference));
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        noticeBar(
          'Künye panoya kopyalandı.',
          detail: reference,
          kind: NoticeKind.success,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: citationInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Künyeyi kopyala',
                    visualDensity: VisualDensity.compact,
                    iconSize: 17,
                    icon: const Icon(Icons.bookmark_border_rounded),
                    onPressed: () => _copyReference(context),
                  ),
                  if (hit.alike > 0) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message:
                          'Bu sayfada ${hit.alike} karar daha aynı gerekçeyi '
                          'taşıyor; tek satırda toplandı.',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: theme.colorScheme.outlineVariant,
                        ),
                        child: Text(
                          '+${hit.alike} aynı gerekçe',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (hit.snippet.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  hit.snippet,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Paging extends StatelessWidget {
  const _Paging({required this.results, required this.onPage});

  final CaseLawResults results;
  final void Function(int page) onPage;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton.icon(
          onPressed: results.page > 1 ? () => onPage(results.page - 1) : null,
          icon: const Icon(Icons.chevron_left_rounded, size: 18),
          label: const Text('Önceki'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '${results.page}. sayfa',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        TextButton.icon(
          onPressed: () => onPage(results.page + 1),
          icon: const Icon(Icons.chevron_right_rounded, size: 18),
          label: const Text('Sonraki'),
        ),
      ],
    ),
  );
}
