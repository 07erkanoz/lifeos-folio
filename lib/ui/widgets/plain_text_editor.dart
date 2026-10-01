import 'dart:async';
import 'dart:convert';

import '../../services/platform/android_document_save.dart';

import '../../services/editor/document_history.dart';
import 'document_versions_window.dart';
import 'draft_prompts.dart';
import 'notice.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/search/text_extractor.dart';
import '../../services/editor/editor_drafts.dart';

/// Source text editor for Markdown, HTML and data files. No rich-text roundtrip
/// that could damage markup, JSON syntax or delimiters. Always saves a copy.
class PlainTextEditor extends StatefulWidget {
  final String path;
  final EditorDraft? draft;
  final DocumentRevision? recovery;
  final ValueChanged<String>? onSaved;
  const PlainTextEditor({
    super.key,
    required this.path,
    this.draft,
    this.recovery,
    this.onSaved,
  });
  @override
  State<PlainTextEditor> createState() => _PlainTextEditorState();
}

class _PlainTextEditorState extends State<PlainTextEditor>
    with WidgetsBindingObserver {
  /// This editor's own recovery slot; see [DocumentHistory.draftKey].
  final String _draftKey = DocumentHistory.draftKey();
  late final DraftRecovery _recovery;
  bool _historyErrorShown = false;
  DocumentRevision? _leftDraft;
  int _leftDrafts = 0;
  bool get _hasChanges =>
      !_loading && _error == null && _text.text != _baseline;
  void _historyError(Object e) {
    if (!mounted || _historyErrorShown) return;
    _historyErrorShown = true;
    showNotice(
      context,
      'Belge geçmişine yazılamadı',
      detail: 'Belgeniz yine de kaydedilebilir; yalnız bu sürüm saklanmadı.',
      kind: NoticeKind.error,
    );
  }

  Future<void> _capture(String path, List<int> bytes, String kind) async {
    try {
      await DocumentHistory.instance.capture(
        document: DocumentHistory.documentKey(path),
        name: p.basename(path),
        sourcePath: path,
        format: p.extension(path).substring(1),
        bytes: bytes,
        kind: kind,
      );
    } catch (e) {
      _historyError(e);
    }
  }

  Future<void> _writeRecovery() async {
    if (!_hasChanges) {
      await DocumentHistory.instance.clearRecovery(_draftKey);
      return;
    }
    await DocumentHistory.instance.capture(
      document: _draftKey,
      name: p.basename(_savedPath ?? widget.path),
      sourcePath: _savedPath ?? widget.path,
      format: "text-draft",
      bytes: utf8.encode(_text.text),
      kind: "recovery",
    );
  }

  Future<void> _discard() async {
    _text.text = _baseline;
    await _recovery.clear();
  }

  Future<bool> _restore(DocumentRevision entry) async {
    try {
      final bytes = await DocumentHistory.instance.read(entry);
      if (!mounted) return false;
      _text.text = IndexTextExtractor.decodeText(Uint8List.fromList(bytes));
      return true;
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Sürüm açılamadı',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
      return false;
    }
  }

  /// Opens a draft another session left, then moves it into this editor's
  /// slot; the old one goes only once the new one is written.
  Future<void> _recover(DocumentRevision draft) async {
    if (!await _restore(draft) || draft.document == _draftKey) return;
    if (!await _recovery.flush()) return;
    try {
      await DocumentHistory.instance.clearRecovery(draft.document);
    } catch (e) {
      _historyError(e);
    }
  }

  Future<void> _findLeftDrafts() async {
    if (widget.recovery != null) return;
    try {
      final drafts = await DocumentHistory.instance.recoveriesFor(widget.path);
      if (!mounted) return;
      setState(() {
        _leftDraft = drafts.firstOrNull;
        _leftDrafts = drafts.length;
      });
    } catch (_) {
      // The file opens either way; the homepage still lists the drafts.
    }
  }

  Future<void> _leftDraftMenu() async {
    final draft = _leftDraft;
    if (draft == null) return;
    final action = await askLeftDraft(context, draft, _leftDrafts);
    if (action == null || !mounted) return;
    if (action == LeftDraftAction.delete) {
      try {
        await DocumentHistory.instance.clearRecovery(draft.document);
      } catch (e) {
        _historyError(e);
      }
    } else {
      if (_hasChanges) {
        final choice = await confirmReplaceEdits(context, 'Taslak');
        if (choice == null || !mounted) return;
        if (choice == ReplaceChoice.saveFirst && !await _save()) return;
      }
      await _recover(draft);
    }
    await _findLeftDrafts();
  }

  Future<void> _history() async {
    final path = _savedPath ?? widget.path;
    final entry = await showDocumentVersions(
      context,
      document: DocumentHistory.documentKey(path),
      title: p.basename(path),
      currentText: _error == null ? () async => _text.text : null,
      restoreLabel: 'Editöre yükle',
      restoreHint:
          'Seçilen sürüm editöre kaydedilmemiş değişiklik olarak gelir; siz '
          'kaydedene kadar hiçbir dosya değişmez.',
    );
    if (entry == null || !mounted) return;
    if (_hasChanges) {
      final choice = await confirmReplaceEdits(context, 'Seçilen sürüm');
      if (choice == null || !mounted) return;
      if (choice == ReplaceChoice.saveFirst && !await _save()) return;
      if (!mounted) return;
    }
    if (await _restore(entry) && mounted) {
      showNotice(
        context,
        '${draftDate(entry.created)} sürümü editöre yüklendi',
        detail: 'Kalıcı olması için kaydedin.',
        kind: NoticeKind.success,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _recovery.flush();
    }
  }

  final _text = TextEditingController();
  String? _error;
  bool _loading = true;
  bool _saving = false;
  String _baseline = '';
  String? _savedPath;
  @override
  void initState() {
    super.initState();
    DocumentHistory.holdDraft(_draftKey);
    _recovery = DraftRecovery(
      write: _writeRecovery,
      remove: () => DocumentHistory.instance.clearRecovery(_draftKey),
      onError: _historyError,
    );
    WidgetsBinding.instance.addObserver(this);
    _text.addListener(_recovery.changed);
    widget.draft?.changed = () =>
        !_loading && _error == null && _text.text != _baseline;
    widget.draft?.save = _save;
    widget.draft?.saving = () => _saving;
    widget.draft?.discard = _discard;
    widget.draft?.savedPath = () => _savedPath;
    widget.draft?.history = _history;
    _load();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.path);
      if (widget.recovery != null && !await file.exists()) return;
      if (await file.length() > 8 * 1024 * 1024) {
        throw const FormatException('Metin editörü en fazla 8 MB dosya açar.');
      }
      final bytes = await file.readAsBytes();
      if (mounted) {
        _text.text = IndexTextExtractor.decodeText(Uint8List.fromList(bytes));
        _baseline = _text.text;
      }
    } catch (e) {
      if (mounted) _error = '$e';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_error == null && widget.recovery != null) {
          await _recover(widget.recovery!);
        } else if (_error == null) {
          unawaited(_findLeftDrafts());
        }
      }
    }
  }

  Future<bool> _save() async {
    if (_saving || _loading || _error != null) return false;
    final savedText = _text.text;
    setState(() => _saving = true);
    try {
      final extension = p.extension(widget.path);
      final bytes = Uint8List.fromList(utf8.encode(savedText));
      final name =
          '${p.basenameWithoutExtension(widget.path)}_duzenlendi$extension';
      final path = Platform.isAndroid
          ? await AndroidDocumentSave.save(fileName: name, bytes: bytes)
          : await FilePicker.saveFile(
              dialogTitle: 'Düzenlenen metni kaydet',
              fileName: name,
              type: FileType.custom,
              allowedExtensions: [extension.substring(1)],
            );
      if (path == null || !mounted) return false;
      if (!Platform.isAndroid) {
        if (p.equals(p.absolute(path), p.absolute(widget.path)) ||
            (await File(path).exists() &&
                await FileSystemEntity.identical(path, widget.path))) {
          throw StateError(
            'Kaynak korunur. Düzenlenen kopya için yeni bir dosya adı seçin.',
          );
        }
        if (await File(path).exists()) {
          await _capture(path, await File(path).readAsBytes(), "original");
        }
        await File(path).writeAsBytes(bytes, flush: true);
      }
      await _capture(path, bytes, "saved");
      _baseline = savedText;
      _savedPath = path;
      if (!_hasChanges) {
        await _recovery.clear();
      } else {
        _recovery.changed();
      }
      if (mounted) {
        widget.onSaved?.call(path);
        showNotice(
          context,
          Platform.isAndroid
              ? 'Belge seçtiğiniz konuma kaydedildi.'
              : 'Kaydedildi: ${p.basename(path)}',
          detail: Platform.isAndroid ? null : p.dirname(path),
          kind: NoticeKind.success,
        );
      }
      return _text.text == _baseline;
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Kaydetme hatası: belge kaydedilemedi',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    final clean = !_loading && _error == null && !_hasChanges;
    (clean ? _recovery.clear() : Future<void>.value()).whenComplete(
      () => DocumentHistory.releaseDraft(_draftKey),
    );
    WidgetsBinding.instance.removeObserver(this);
    _recovery.dispose();
    _text.removeListener(_recovery.changed);
    widget.draft?.detach();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Kaynak metin · UTF-8 kopya',
                style: TextStyle(fontSize: 12),
              ),
            ),
            if (_leftDraft != null)
              LeftDraftButton(draft: _leftDraft!, onPressed: _leftDraftMenu),
            IconButton(
              tooltip: "Belge geçmişi",
              onPressed: _loading ? null : _history,
              icon: const Icon(Icons.history_rounded),
            ),
            FilledButton.icon(
              onPressed: _loading || _saving || _error != null ? null : _save,
              icon: const Icon(Icons.save_outlined, size: 17),
              label: const Text('Farklı kaydet'),
            ),
          ],
        ),
      ),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null)
        Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
      if (!_loading && _error == null)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: TextField(
              controller: _text,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                fontFamily: 'LiberationMono',
                fontSize: 13,
                height: 1.5,
              ),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              autocorrect: false,
              enableSuggestions: false,
            ),
          ),
        ),
    ],
  );
}
