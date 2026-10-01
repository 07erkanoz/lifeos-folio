import 'package:flutter/material.dart';

import '../../services/legal/citation.dart';
import '../../services/legal/decision.dart';
import 'editor_citations.dart';

/// Everything a document points at, gathered in one place.
///
/// The marks in the text answer "what is this?" where the reader already is.
/// This answers the other question — "what does this filing rest on?" —
/// which is the one asked before reading it, or when checking that nothing
/// has been left out. Opened from the foot of the window and closed again;
/// it is a drawer, not a second screen.
class CitationList extends StatelessWidget {
  const CitationList({
    super.key,
    required this.laws,
    required this.decisions,
    required this.onLaw,
    required this.onDecision,
    required this.onClose,
  });

  final List<Citation> laws;
  final List<DecisionCitation> decisions;
  final void Function(Citation citation, Offset at) onLaw;
  final void Function(DecisionCitation citation, Offset at) onDecision;
  final VoidCallback onClose;

  /// How many articles and decisions the list shows: each once, as it
  /// lists them, so the count under the page and the list agree.
  static ({int laws, int decisions}) counts(
    List<Citation> laws,
    List<DecisionCitation> decisions,
  ) {
    final list = CitationList(
      laws: laws,
      decisions: decisions,
      onLaw: (_, _) {},
      onDecision: (_, _) {},
      onClose: () {},
    );
    return (
      laws: list._byLaw.values.fold(0, (sum, one) => sum + one.length),
      decisions: list._decisionsOnce.length,
    );
  }

  /// Each law once, with the articles cited from it, in the order they were
  /// written. A filing that leans on one article six times should say so
  /// once and not fill the list.
  Map<String, List<Citation>> get _byLaw {
    final out = <String, List<Citation>>{};
    for (final one in laws) {
      final key = '${one.law.number} s. ${one.law.name}';
      final held = out.putIfAbsent(key, () => []);
      if (held.any((c) => c.article == one.article)) continue;
      held.add(one);
    }
    return out;
  }

  List<DecisionCitation> get _decisionsOnce {
    final seen = <String>{};
    return [
      for (final one in decisions)
        if (seen.add('${one.esas}|${one.karar}')) one,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byLaw = _byLaw;
    final cases = _decisionsOnce;
    final nothing = byLaw.isEmpty && cases.isEmpty;

    return Material(
      key: const ValueKey('citation-list'),
      color: theme.colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.format_list_bulleted_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Bu belgenin dayanakları',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    nothing
                        ? ''
                        : '${byLaw.values.fold(0, (n, l) => n + l.length)} madde'
                              '${cases.isEmpty ? '' : ' · ${cases.length} karar'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Kapat',
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Flexible(
            child: nothing
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Text(
                      'Bu belgede kanun maddesi ya da mahkeme kararı atfı '
                      'bulunamadı.',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Scrollbar(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                      children: [
                        for (final entry in byLaw.entries)
                          _Row(
                            title: entry.key,
                            chips: [
                              for (final one in entry.value)
                                _Chip(
                                  label: 'm. ${one.article}',
                                  onTap: (at) => onLaw(one, at),
                                ),
                            ],
                          ),
                        if (cases.isNotEmpty)
                          _Row(
                            title: 'Mahkeme kararları',
                            chips: [
                              for (final one in cases)
                                _Chip(
                                  label: 'E.${one.esas} K.${one.karar}',
                                  dotted: true,
                                  onTap: (at) => onDecision(one, at),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.chips});

  final String title;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: chips),
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap, this.dotted = false});

  final String label;

  /// Handed where it was pressed, so the card opens beside it rather than
  /// in the middle of the page.
  final void Function(Offset at) onTap;

  /// Dotted for a decision, as it is in the text: it may or may not be in
  /// the bank, and the mark should not promise more than the app can keep.
  final bool dotted;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        final box = context.findRenderObject() as RenderBox?;
        onTap(box?.localToGlobal(box.size.center(Offset.zero)) ?? Offset.zero);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: citationInk.withValues(alpha: 0.08),
          border: Border.all(
            color: citationInk.withValues(alpha: dotted ? 0.3 : 0.5),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: citationInk,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ),
  );
}
