import 'package:flutter/material.dart';

import '../../services/editor/document_history.dart';

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
      tooltip: 'Kaydedilmemiş taslak · ${draftDate(draft.created)}',
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
    title: const Text('Kaydedilmemiş taslak'),
    content: Text(
      '“${draft.name}” için ${draftDate(draft.created)} tarihli, '
      'kaydedilmemiş bir taslak var. Uygulama beklenmedik biçimde kapandığında '
      'kalmış olabilir.\n\nAçarsanız editöre kaydedilmemiş değişiklik olarak '
      'gelir; siz kaydedene kadar dosya değişmez.'
      '${count > 1 ? '\n\nBu belgenin ${count - 1} taslağı daha var; hepsi ana '
                'sayfadaki «Kurtarılabilir taslaklar»da.' : ''}',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, LeftDraftAction.delete),
        child: const Text('Taslağı sil'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, LeftDraftAction.open),
        child: const Text('Taslağı aç'),
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
        title: const Text('Taslak silinsin mi?'),
        content: Text(
          '“${draft.name}” için ${draftDate(draft.created)} tarihli '
          'kaydedilmemiş taslak kalıcı olarak silinecek. Belgenin kendisi '
          'değişmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Taslağı sil'),
          ),
        ],
      ),
    ) ==
    true;

enum ReplaceChoice { saveFirst, replace }

/// Asks before a draft or an old version replaces edits that were never
/// saved. The question the save guard asks on the way out — “Kaydetmeden
/// çık” — made no sense here: nothing is being left.
Future<ReplaceChoice?> confirmReplaceEdits(
  BuildContext context,
  String what,
) => showDialog<ReplaceChoice>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Kaydedilmemiş değişiklikler var'),
    content: Text(
      '$what editöre alınınca şu anki kaydedilmemiş değişiklikler onun yerine '
      'geçer. Önce kaydederseniz bugünkü hali de belge geçmişinde kalır.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, ReplaceChoice.replace),
        child: const Text('Kaydetmeden aç'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, ReplaceChoice.saveFirst),
        child: const Text('Önce kaydet'),
      ),
    ],
  ),
);
