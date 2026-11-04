import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../services/editor/snippets.dart';
import '../../services/platform/app_language.dart';
import 'editor_image_embed.dart';
import 'notice.dart';
import 'folio_select.dart';

/// The kept passages, to tidy: the name, the keyword Tab expands, the Alt+F
/// key, the passage itself, and whether to keep it at all.
///
/// The palette is for using the library mid-sentence; this is for looking
/// after it, which nobody does mid-sentence.
class SnippetManager extends StatefulWidget {
  const SnippetManager({super.key, required this.store});

  final SnippetStore store;

  static Future<void> show(BuildContext context, SnippetStore store) =>
      showDialog<void>(
        context: context,
        builder: (_) => SnippetManager(store: store),
      );

  @override
  State<SnippetManager> createState() => _SnippetManagerState();
}

class _SnippetManagerState extends State<SnippetManager> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_changed);
  }

  @override
  void dispose() {
    widget.store.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _edit([Snippet? one]) => showDialog<void>(
    context: context,
    builder: (_) => SnippetEditor(store: widget.store, snippet: one),
  );

  Future<void> _delete(Snippet one) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l.snipDeleteTitle),
        content: Text(context.l.snipDeleteBody(one.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l.snipCancel),
          ),
          FilledButton(
            key: const ValueKey('snippet-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l.snipDelete),
          ),
        ],
      ),
    );
    if (sure == true) await widget.store.remove(one.id);
  }

  Future<void> _export() async {
    final where = await FilePicker.saveFile(
      dialogTitle: AppLanguage.t.snipExportDialog,
      fileName: 'kaliplar.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (where == null) return;
    try {
      await File(where).writeAsString(widget.store.export(), flush: true);
      if (!mounted) return;
      showNotice(
        context,
        context.l.snipExported(widget.store.all.length),
        kind: NoticeKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      showNotice(
        context,
        context.l.snipExportFailed,
        detail: '$e',
        kind: NoticeKind.error,
      );
    }
  }

  Future<void> _import() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: AppLanguage.t.snipImportDialog,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    try {
      final added = await widget.store.import(await File(path).readAsString());
      if (!mounted) return;
      showNotice(
        context,
        added == 0 ? context.l.snipImportNone : context.l.snipImported(added),
        kind: NoticeKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      showNotice(
        context,
        context.l.snipImportFailed,
        detail: e is FormatException ? e.message : '$e',
        kind: NoticeKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final found = widget.store.matching(_search.text);
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(context.l.snipManagerTitle)),
          IconButton(
            tooltip: context.l.snipImport,
            onPressed: _import,
            icon: const Icon(Icons.file_download_outlined, size: 20),
          ),
          IconButton(
            tooltip: context.l.snipExport,
            onPressed: widget.store.all.isEmpty ? null : _export,
            icon: const Icon(Icons.file_upload_outlined, size: 20),
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        height: 480,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('snippet-manager-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                hintText: context.l.snipSearchHint,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: found.isEmpty
                  ? Center(
                      child: Text(
                        widget.store.all.isEmpty
                            ? context.l.snipManagerEmpty
                            : context.l.snipNoMatch,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      itemCount: found.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final one = found[i];
                        return ListTile(
                          key: ValueKey('snippet-row-${one.id}'),
                          dense: true,
                          title: Text(
                            one.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                one.preview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  if (one.keyword.isNotEmpty)
                                    _Badge('${one.keyword} + Tab'),
                                  if (one.hotkey != null)
                                    _Badge('Alt+F${one.hotkey}'),
                                  if (one.used > 0)
                                    _Badge(
                                      context.l.snipUsedTimes(one.used),
                                      muted: true,
                                    ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () => _edit(one),
                          trailing: IconButton(
                            key: ValueKey('snippet-delete-${one.id}'),
                            tooltip: context.l.snipDelete,
                            onPressed: () => _delete(one),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('snippet-new'),
          onPressed: () => _edit(),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(context.l.snipNew),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l.snipClose),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: muted
            ? scheme.surfaceContainerHighest
            : scheme.primary.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: muted ? scheme.onSurfaceVariant : scheme.primary,
        ),
      ),
    );
  }
}

/// One passage, new or kept, with its name, keyword, key and text.
class SnippetEditor extends StatefulWidget {
  const SnippetEditor({super.key, required this.store, this.snippet});

  final SnippetStore store;

  /// The passage being edited; null for a new one.
  final Snippet? snippet;

  @override
  State<SnippetEditor> createState() => _SnippetEditorState();
}

class _SnippetEditorState extends State<SnippetEditor> {
  late final _name = TextEditingController(text: widget.snippet?.name ?? '');
  late final _keyword = TextEditingController(
    text: widget.snippet?.keyword ?? '',
  );
  late int? _hotkey = widget.snippet?.hotkey;
  late final _body = QuillController(
    document: widget.snippet == null
        ? Document()
        : Document.fromDelta(widget.snippet!.body),
    selection: const TextSelection.collapsed(offset: 0),
  );
  final _focus = FocusNode(debugLabel: 'snippet-body');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _keyword.dispose();
    _body.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = widget.store;
    final keyword = _keyword.text.trim();
    final hotkey = _hotkey;
    final id = widget.snippet?.id;
    String? error;
    if (_body.document.toPlainText().trim().isEmpty) {
      error = context.l.snipEmptyBody;
    } else if (keyword.isNotEmpty && !Snippet.validKeyword(keyword)) {
      error = context.l.snipBadKeyword;
    } else if (keyword.isNotEmpty) {
      final taken = store.keywordTaken(keyword, except: id);
      if (taken != null) {
        error = context.l.snipKeywordTaken(keyword, taken.name);
      }
    }
    if (error == null && hotkey != null) {
      final taken = store.hotkeyTaken(hotkey, except: id);
      if (taken != null) {
        error = context.l.snipHotkeyTaken('$hotkey', taken.name);
      }
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final name = _name.text.trim().isEmpty
        ? context.l.snipUntitled
        : _name.text.trim();
    final body = _body.document.toDelta();
    final kept = widget.snippet;
    if (kept == null) {
      final added = await store.add(name, body);
      await store.update(
        added.copyWith(keyword: keyword, hotkey: () => hotkey),
      );
    } else {
      await store.update(
        kept.copyWith(
          name: name,
          body: body,
          keyword: keyword,
          hotkey: () => hotkey,
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final blanks = Snippet(
      id: '',
      name: '',
      body: _body.document.toDelta(),
    ).blanks;
    return AlertDialog(
      title: Text(
        widget.snippet == null ? context.l.snipNew : context.l.snipEditTitle,
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('snippet-edit-name'),
                controller: _name,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: context.l.snipName,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('snippet-edit-keyword'),
                      controller: _keyword,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: context.l.snipKeyword,
                        hintText: context.l.snipKeywordHint,
                        helperText: context.l.snipKeywordHelper,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 170,
                    child: FolioSelect<int?>(
                      key: const ValueKey('snippet-edit-hotkey'),
                      initialValue: _hotkey,
                      isDense: true,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: context.l.snipHotkey,
                        helperText: context.l.snipHotkeyHelper,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem<int?>(
                          child: Text(context.l.snipNoHotkey),
                        ),
                        for (final key in Snippet.hotkeys)
                          DropdownMenuItem<int?>(
                            value: key,
                            child: Text('Alt+F$key'),
                          ),
                      ],
                      onChanged: (value) => setState(() => _hotkey = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                context.l.snipText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                key: const ValueKey('snippet-edit-body'),
                height: 200,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: Colors.black),
                  child: QuillEditor.basic(
                    controller: _body,
                    focusNode: _focus,
                    config: QuillEditorConfig(
                      placeholder: context.l.snipBodyPlaceholder,
                      // A snippet an earlier Folio kept with a picture or a
                      // table in it opens, rather than breaking the editor.
                      embedBuilders: [EditorImageEmbed()],
                      unknownEmbedBuilder: _LeftOutEmbed(),
                    ),
                  ),
                ),
              ),
              if (blanks.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  context.l.snipBlanksList(
                    blanks.map((b) => '[$b]').join(', '),
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  key: const ValueKey('snippet-edit-error'),
                  style: TextStyle(color: scheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l.snipCancel),
        ),
        FilledButton(
          key: const ValueKey('snippet-edit-save'),
          onPressed: _save,
          child: Text(context.l.snipSave),
        ),
      ],
    );
  }
}

/// What a snippet does not carry, shown where it was: a table, kept by an
/// earlier Folio, that goes in no document from here.
class _LeftOutEmbed extends EmbedBuilder {
  @override
  String get key => 'kalipta-yok';

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      context.l.snipTableLeftOut,
      style: const TextStyle(
        fontStyle: FontStyle.italic,
        color: Colors.black54,
      ),
    ),
  );
}
