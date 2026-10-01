import 'package:flutter/material.dart';

import '../../ui/widgets/notice.dart';

/// Editors own their snapshots; navigation and native close share one decision.
class EditorDraft {
  final String name;
  EditorDraft(this.name);
  bool Function()? changed;
  bool Function()? saving;
  Future<bool> Function()? save;
  Future<void> Function()? discard;
  String? Function()? savedPath;

  /// Whether the document has unsaved edits, kept up to date by the editor a
  /// moment after each change, for a title bar to show.
  final edited = ValueNotifier<bool>(false);

  /// Opens the document's history from the editor, which is the one that
  /// knows the document as it is now, unsaved edits included.
  Future<void> Function()? history;
  bool get hasChanges => changed?.call() ?? false;
  void detach() {
    changed = null;
    saving = null;
    save = null;
    discard = null;
    savedPath = null;
    history = null;
  }
}

enum DraftDecision { save, discard, cancel }

class EditorDrafts {
  final _drafts = <String, EditorDraft>{};
  bool _confirming = false;
  EditorDraft draft(String id, String name) =>
      _drafts.putIfAbsent(id, () => EditorDraft(name));

  Future<bool> confirm(BuildContext context, {EditorDraft? only}) async {
    if (_confirming) return false;
    _confirming = true;
    final discard = <EditorDraft>[];
    try {
      for (final draft in only == null ? _drafts.values.toList() : [only]) {
        if (draft.saving?.call() == true) {
          if (context.mounted) {
            // Also while the document is still being read: a draft opened
            // at that moment would land in an editor nobody is looking at.
            showNotice(
              context,
              'Belge kaydediliyor ya da yükleniyor',
              detail: 'Bitince tekrar deneyin.',
            );
          }
          return false;
        }
        if (!draft.hasChanges) continue;
        if (!context.mounted) return false;
        final decision = await showDialog<DraftDecision>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Değişiklikler kaydedilsin mi?'),
            content: Text(
              '“${draft.name}” belgesinde kaydedilmemiş değişiklikler var. Kaydetmeden çıkarsanız bu değişiklikler silinir.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, DraftDecision.cancel),
                child: const Text('Vazgeç'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, DraftDecision.discard),
                child: const Text('Kaydetmeden çık'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, DraftDecision.save),
                child: const Text('Kaydet'),
              ),
            ],
          ),
        );
        if (decision == null || decision == DraftDecision.cancel) return false;
        if (decision == DraftDecision.discard) {
          discard.add(draft);
        } else if (await draft.save?.call() != true || draft.hasChanges) {
          // A canceled picker, failed write or edits made during the write must
          // never turn an attempted save into permission to leave.
          return false;
        }
      }
      for (final draft in discard) {
        await draft.discard?.call();
      }
      return true;
    } finally {
      _confirming = false;
    }
  }
}
