import 'package:flutter/material.dart';

import '../../services/legal/decision_anatomy.dart';

/// What a decision is made of, above its text: the courts it came up
/// through, what it is about, what it decided, its parts, what it cites,
/// and the sentences of its reasoning that stand out.
///
/// Every line is the decision's own words, and every line takes the reader
/// to where it stands in the text. Nothing is called a holding or a
/// principle: the app has not decided what the court meant, it has pointed
/// at where the court said something worth reading.
class DecisionAnatomyView extends StatelessWidget {
  const DecisionAnatomyView({
    super.key,
    required this.anatomy,
    required this.onGo,
  });

  final DecisionAnatomy anatomy;

  /// Takes the reader to where [Quote] stands in the decision.
  final void Function(Quote quote) onGo;

  static const _steps = [
    CourtRole.firstInstance,
    CourtRole.appeal,
    CourtRole.chamber,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = anatomy.outcome;
    final chain = [
      for (final role in _steps)
        for (final step in anatomy.chain)
          if (step.role == role) step,
    ];
    final parts = [
      for (final s in anatomy.sections)
        if (s.level == 1) s,
    ];
    final laws = <String, Quote>{
      for (final c in anatomy.laws.reversed) c.label: Quote(c.written, c.start),
    };
    final cited = <String, Quote>{
      for (final d in anatomy.decisions.reversed)
        d.label: Quote(d.written, d.start),
    };

    return Container(
      key: const ValueKey('decision-anatomy'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: const Text(
            'Karar anatomisi',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'Kararın kendi sözleri; her satır metinde yerine götürür.',
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          children: [
            if (outcome != null && outcome.kinds.isNotEmpty) ...[
              const _Caption('Sonuç (hüküm fıkrasından)'),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final kind in outcome.kinds)
                    _Tag(kind.label, strong: kind == outcome.primary),
                ],
              ),
              const SizedBox(height: 4),
              for (final verb in outcome.verbs.take(4))
                _QuoteLine(verb.clause, onGo: onGo),
            ],
            if (chain.isNotEmpty) ...[
              const _Caption('Mahkeme zinciri'),
              for (final step in chain)
                _QuoteLine(
                  step.court,
                  label: step.role.label,
                  trailing: step.numbers?.text,
                  onGo: onGo,
                ),
            ],
            if (anatomy.subjectHeading != null || anatomy.subject != null) ...[
              const _Caption('Dava konusu'),
              if (anatomy.subjectHeading case final heading?)
                _QuoteLine(heading, onGo: onGo),
              if (anatomy.subject case final subject?)
                _QuoteLine(subject, onGo: onGo),
            ],
            if (anatomy.highlights.isNotEmpty) ...[
              const _Caption('Karardan öne çıkan bölüm (alıntı)'),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Gerekçe bölümünden, aranan kelimelere ve gerekçe '
                  'ifadelerine göre seçildi. Birçok kararda aynen geçen kalıp '
                  'cümleler gösterilmez. Kararın yorumu değil, kendisinden '
                  'alıntıdır.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (var i = 0; i < anatomy.highlights.length; i++)
                _QuoteLine(
                  anatomy.highlights[i].quote,
                  key: ValueKey('anatomy-highlight-$i'),
                  quoted: true,
                  trailing: anatomy.highlights[i].matched.isEmpty
                      ? null
                      : 'Aranan: ${anatomy.highlights[i].matched.join(', ')}',
                  onGo: onGo,
                ),
            ],
            if (parts.length > 1) ...[
              const _Caption('Bölümler'),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final part in parts)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      labelStyle: const TextStyle(fontSize: 11.5),
                      label: Text(part.title),
                      onPressed: () => onGo(part.heading),
                    ),
                ],
              ),
            ],
            if (laws.isNotEmpty || cited.isNotEmpty) ...[
              const _Caption('Atıf yapılan mevzuat ve kararlar'),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final entry in [...laws.entries, ...cited.entries])
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      labelStyle: const TextStyle(fontSize: 11.5),
                      label: Text(entry.key),
                      onPressed: () => onGo(entry.value),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: strong ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          color: strong ? scheme.onSecondaryContainer : scheme.onSurface,
        ),
      ),
    );
  }
}

/// One quotation, pressed to be taken to it.
class _QuoteLine extends StatelessWidget {
  const _QuoteLine(
    this.quote, {
    super.key,
    required this.onGo,
    this.label,
    this.trailing,
    this.quoted = false,
  });

  final Quote quote;
  final void Function(Quote quote) onGo;
  final String? label;
  final String? trailing;

  /// Set in quotation marks and italic: a sentence of the reasoning.
  final bool quoted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = TextStyle(
      fontSize: 12.5,
      height: 1.45,
      fontStyle: quoted ? FontStyle.italic : null,
      color: theme.colorScheme.onSurface,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => onGo(quote),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (label != null)
                      TextSpan(
                        text: '$label: ',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    TextSpan(text: quoted ? '“${quote.text}”' : quote.text),
                    if (trailing != null)
                      TextSpan(
                        text: '  $trailing',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.normal,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                style: body,
                // A court of first instance may give its reasons in one
                // sentence of two thousand characters; the whole of it is a
                // press away, in the text.
                maxLines: quoted ? 8 : null,
                overflow: quoted ? TextOverflow.ellipsis : null,
              ),
            ),
            Tooltip(
              message: 'Metinde göster',
              child: Icon(
                Icons.subdirectory_arrow_left_rounded,
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
