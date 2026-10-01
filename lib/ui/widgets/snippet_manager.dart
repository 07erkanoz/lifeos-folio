import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../services/editor/snippets.dart';
import 'notice.dart';

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
        title: const Text('Kalıp silinsin mi?'),
        content: Text(
          '“${one.name}” kalıplarınızdan kaldırılacak. Bu kalıpla yazılmış '
          'belgeler değişmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const ValueKey('snippet-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (sure == true) await widget.store.remove(one.id);
  }

  Future<void> _export() async {
    final where = await FilePicker.saveFile(
      dialogTitle: 'Kalıpları dışa aktar',
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
        '${widget.store.all.length} kalıp dışa aktarıldı.',
        kind: NoticeKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      showNotice(
        context,
        'Kalıplar dışa aktarılamadı',
        detail: '$e',
        kind: NoticeKind.error,
      );
    }
  }

  Future<void> _import() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Kalıpları içe aktar',
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
        added == 0
            ? 'Yeni kalıp yok; hepsi zaten kalıplarınızda.'
            : '$added kalıp eklendi.',
        kind: NoticeKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      showNotice(
        context,
        'Kalıplar içe aktarılamadı',
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
          const Expanded(child: Text('Kalıplarım')),
          IconButton(
            tooltip: 'İçe aktar',
            onPressed: _import,
            icon: const Icon(Icons.file_download_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Dışa aktar',
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
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                hintText: 'Kalıp ara',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: found.isEmpty
                  ? Center(
                      child: Text(
                        widget.store.all.isEmpty
                            ? 'Henüz kalıp yok. "Yeni kalıp" ile ekleyebilir '
                                  'ya da belgede bir paragrafı seçip '
                                  'Ctrl+Space ile kalıba alabilirsiniz.'
                            : 'Bu aramaya uyan kalıp yok.',
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
                                    _Badge('${one.used} kez', muted: true),
                                ],
                              ),
                            ],
                          ),
                          onTap: () => _edit(one),
                          trailing: IconButton(
                            key: ValueKey('snippet-delete-${one.id}'),
                            tooltip: 'Sil',
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
          label: const Text('Yeni kalıp'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
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
      error = 'Kalıbın metni boş olamaz.';
    } else if (keyword.isNotEmpty && !Snippet.validKeyword(keyword)) {
      error =
          'Anahtar kelime 2–20 harf ya da rakamdan oluşmalı, boşluk '
          'olmadan.';
    } else if (keyword.isNotEmpty) {
      final taken = store.keywordTaken(keyword, except: id);
      if (taken != null) {
        error = '“$keyword” zaten “${taken.name}” kalıbının anahtar kelimesi.';
      }
    }
    if (error == null && hotkey != null) {
      final taken = store.hotkeyTaken(hotkey, except: id);
      if (taken != null) {
        error = 'Alt+F$hotkey zaten “${taken.name}” kalıbında.';
      }
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final name = _name.text.trim().isEmpty ? 'Adsız kalıp' : _name.text.trim();
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
      title: Text(widget.snippet == null ? 'Yeni kalıp' : 'Kalıbı düzenle'),
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
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Ad',
                  border: OutlineInputBorder(),
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
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Anahtar kelime',
                        hintText: 'örn. dil1',
                        helperText: 'Belgede yazıp Tab’a basınca kalıp gelir',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<int?>(
                      key: const ValueKey('snippet-edit-hotkey'),
                      initialValue: _hotkey,
                      isDense: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Kısayol',
                        helperText: 'Alt+F4 pencereyi kapatır',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(child: Text('Yok')),
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
                'Metin',
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
                    config: const QuillEditorConfig(
                      placeholder:
                          'Kalıbın metni. Doldurulacak yerleri [MÜVEKKİL] gibi '
                          'köşeli parantez ve büyük harfle yazın.',
                    ),
                  ),
                ),
              ),
              if (blanks.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Doldurulacak yerler: ${blanks.map((b) => '[$b]').join(', ')}',
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
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const ValueKey('snippet-edit-save'),
          onPressed: _save,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
