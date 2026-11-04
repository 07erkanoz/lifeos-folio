import 'package:flutter/material.dart';

import '../../services/editor/document_history.dart';
import '../../services/platform/app_language.dart';

String draftDate(DateTime date) {
  final d = date.toLocal();
  String two(int n) => '$n'.padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// A quiet sign in an editor's toolbar that an earlier session left unsaved
/// work in this same file — after a crash, a power cut, a killed process.
///
/// A button rather than a banner or a notice: it waits to be noticed and
/// asks nothing of a reader who is busy with something else.
class LeftDraftButton extends StatelessWidget {
  final DocumentRevision draft;
  final VoidCallback onPressed;
  const LeftDraftButton({
    super.key,
    required this.draft,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      key: const ValueKey('left-draft'),
      tooltip: context.l.noteDraftTooltip(draftDate(draft.created)),
      onPressed: onPressed,
      icon: Badge(
        smallSize: 8,
        backgroundColor: colors.tertiary,
        child: Icon(Icons.restore_page_outlined, color: colors.tertiary),
      ),
    );
  }
}

enum LeftDraftAction { open, delete }

/// What to do with a draft another session left in the open file.
Future<LeftDraftAction?> askLeftDraft(
  BuildContext context,
  DocumentRevision draft,
  int count,
) => showDialog<LeftDraftAction>(
  context: context,
  builder: (context) => AlertDialog(
    icon: Icon(
      Icons.restore_page_outlined,
      color: Theme.of(context).colorScheme.primary,
    ),
    title: Text(context.l.noteDraftTitle),
    content: Text(
      context.l.noteDraftBody(draft.name, draftDate(draft.created)) +
          (count > 1 ? context.l.noteDraftMore(count - 1) : ''),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, LeftDraftAction.delete),
        child: Text(context.l.noteDraftDelete),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l.noteCancel),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, LeftDraftAction.open),
        child: Text(context.l.noteDraftOpen),
      ),
    ],
  ),
);

/// Asks before a draft is thrown away for good.
Future<bool> confirmDraftDelete(
  BuildContext context,
  DocumentRevision draft,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l.noteDraftDeleteTitle),
        content: Text(
          context.l.noteDraftDeleteBody(draft.name, draftDate(draft.created)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l.noteCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l.noteDraftDelete),
          ),
        ],
      ),
    ) ==
    true;

enum ReplaceChoice { saveFirst, replace }

/// Asks before a draft or an old version replaces edits that were never
/// saved. The question the save guard asks on the way out — “Kaydetmeden
/// çık” — made no sense here: nothing is being left.
Future<ReplaceChoice?> confirmReplaceEdits(BuildContext context, String what) =>
    showDialog<ReplaceChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l.noteUnsavedTitle),
        content: Text(context.l.noteUnsavedBody(what)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l.noteCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ReplaceChoice.replace),
            child: Text(context.l.noteOpenWithoutSaving),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ReplaceChoice.saveFirst),
            child: Text(context.l.noteSaveFirst),
          ),
        ],
      ),
    );
