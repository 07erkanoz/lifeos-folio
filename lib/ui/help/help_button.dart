import 'dart:async';

import 'package:flutter/material.dart';

import 'help_texts.dart';

export 'help_texts.dart' show Help, HelpTopic;

/// A page's small "?": its help, a window over the page on a computer and a
/// sheet from below on a phone.
class HelpButton extends StatelessWidget {
  const HelpButton(this.topic, {super.key, this.size = 20});

  final HelpTopic topic;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
    key: ValueKey('help-${topic.title}'),
    tooltip: 'Bu sayfa nasıl kullanılır?',
    onPressed: () => unawaited(showHelp(context, topic)),
    icon: Icon(Icons.help_outline_rounded, size: size),
  );
}

/// [topic] shown: a dialog where there is room, a sheet on a phone.
Future<void> showHelp(BuildContext context, HelpTopic topic) {
  if (MediaQuery.sizeOf(context).width >= 700) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: _HelpBody(topic, scrolling: null),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .8,
      minChildSize: .4,
      maxChildSize: 1,
      builder: (context, controller) => _HelpBody(topic, scrolling: controller),
    ),
  );
}

class _HelpBody extends StatelessWidget {
  const _HelpBody(this.topic, {required this.scrolling});

  final HelpTopic topic;
  final ScrollController? scrolling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium?.copyWith(height: 1.5);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 8, 0),
          child: Row(
            children: [
              Icon(Icons.help_outline_rounded, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  topic.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (scrolling == null)
                IconButton(
                  tooltip: 'Kapat',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            controller: scrolling,
            shrinkWrap: scrolling == null,
            padding: EdgeInsets.fromLTRB(
              22,
              10,
              22,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Text(topic.intro, style: body),
              for (final part in topic.parts) ...[
                const SizedBox(height: 18),
                Text(
                  part.heading,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (final (i, line) in part.lines.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text(
                            part.numbered ? '${i + 1}.' : '•',
                            style: body?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        Expanded(child: Text(line, style: body)),
                      ],
                    ),
                  ),
              ],
              if (topic.tip != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 20,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text('İpucu: ${topic.tip}', style: body)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
