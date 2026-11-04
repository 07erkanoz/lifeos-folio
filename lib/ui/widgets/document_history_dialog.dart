import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/editor/document_history.dart';
import 'draft_prompts.dart';
import 'notice.dart';
import '../../services/platform/app_language.dart';

/// Unsaved work left behind by editors that closed without a decision — a
/// crash, a power cut, a window that went away. Returns the draft to open.
///
/// Drafts of editors that are still open are not listed: they are being
/// written, and opening one sent the reader to a draft the open editor was
/// about to replace.
Future<DocumentRevision?> showRecoverableDrafts(BuildContext context) =>
    showDialog<DocumentRevision>(
      context: context,
      builder: (_) => const _DraftsDialog(),
    );

class _DraftsDialog extends StatefulWidget {
  const _DraftsDialog();
  @override
  State<_DraftsDialog> createState() => _DraftsDialogState();
}

typedef _Draft = ({DocumentRevision entry, bool sourceExists});

class _DraftsDialogState extends State<_DraftsDialog> {
  late Future<List<_Draft>> _entries = _load();

  Future<List<_Draft>> _load() async => [
    for (final entry in await DocumentHistory.instance.recoveries())
      (
        entry: entry,
        sourceExists:
            entry.sourcePath != null && await File(entry.sourcePath!).exists(),
      ),
  ];

  Future<void> _delete(DocumentRevision entry) async {
    if (!await confirmDraftDelete(context, entry)) return;
    try {
      await DocumentHistory.instance.clearRecovery(entry.document);
      if (mounted) setState(() => _entries = _load());
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          context.l.viewDraftDeleteFailed,
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
    }
  }

  Future<void> _deleteAll(List<_Draft> drafts) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l.viewDeleteAllDraftsTitle),
        content: Text(context.l.viewDeleteAllDraftsBody(drafts.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l.viewCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l.viewDeleteAll),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      for (final draft in drafts) {
        await DocumentHistory.instance.clearRecovery(draft.entry.document);
      }
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          context.l.viewDraftsDeleteFailed,
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
    }
    if (mounted) setState(() => _entries = _load());
  }

  String _where(_Draft draft) {
    final source = draft.entry.sourcePath;
    if (source == null) return context.l.viewDraftNeverSaved;
    if (!draft.sourceExists) {
      return context.l.viewDraftSourceGone(source);
    }
    return source;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<List<_Draft>>(
      future: _entries,
      builder: (context, snapshot) {
        final drafts = snapshot.data ?? const <_Draft>[];
        return AlertDialog(
          icon: Icon(Icons.restore_rounded, color: colors.primary),
          title: Text(context.l.viewDraftsTitle),
          content: SizedBox(
            width: 560,
            height: MediaQuery.sizeOf(context).height.clamp(280, 560) - 190,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l.viewDraftsNote,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(child: _body(snapshot, drafts, colors)),
              ],
            ),
          ),
          actions: [
            if (drafts.length > 1)
              TextButton(
                onPressed: () => _deleteAll(drafts),
                child: Text(context.l.viewDeleteAll),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l.viewClose),
            ),
          ],
        );
      },
    );
  }

  Widget _body(
    AsyncSnapshot<List<_Draft>> snapshot,
    List<_Draft> drafts,
    ColorScheme colors,
  ) {
    if (snapshot.hasError) {
      return Center(child: Text(context.l.viewDraftsUnreachable));
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (drafts.isEmpty) {
      return Center(child: Text(context.l.viewDraftsEmpty));
    }
    return ListView.separated(
      itemCount: drafts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final draft = drafts[i];
        final item = draft.entry;
        return Material(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: Icon(
              draft.sourceExists || item.sourcePath == null
                  ? Icons.restore_page_outlined
                  : Icons.report_gmailerrorred_outlined,
              color: colors.primary,
            ),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${draftDate(item.created)}\n${_where(draft)}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: context.l.viewDeleteDraft,
              onPressed: () => _delete(item),
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
            onTap: () => Navigator.pop(context, item),
          ),
        );
      },
    );
  }
}
