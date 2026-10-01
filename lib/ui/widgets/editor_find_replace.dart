import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../services/editor/document_search.dart';

class EditorFindReplace extends StatefulWidget {
  final QuillController controller;
  final bool replace;
  const EditorFindReplace({
    super.key,
    required this.controller,
    this.replace = false,
  });
  @override
  State<EditorFindReplace> createState() => _EditorFindReplaceState();
}

class _EditorFindReplaceState extends State<EditorFindReplace> {
  final _query = TextEditingController();
  final _replacement = TextEditingController();
  bool _matchCase = false, _wholeWord = false;
  late bool _replace = widget.replace;
  List<TextRange> _matches = [];
  int _current = -1;
  String? _message;
  @override
  void initState() {
    super.initState();
    final selection = widget.controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      _query.text = widget.controller.document.toPlainText().substring(
        selection.start,
        selection.end,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(_search);
    });
  }

  void _search() {
    _matches = DocumentSearch.find(
      widget.controller.document,
      _query.text,
      matchCase: _matchCase,
      wholeWord: _wholeWord,
    );
    _current = _matches.isEmpty ? -1 : 0;
    _message = null;
    _select();
  }

  void _select() {
    if (_current < 0) return;
    final range = _matches[_current];
    widget.controller.updateSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
      ChangeSource.local,
    );
  }

  void _next(int delta) => setState(() {
    if (_matches.isEmpty) return;
    _current = (_current + delta) % _matches.length;
    _select();
  });
  void _apply(bool all) => setState(() {
    final ranges = all ? _matches : [_matches[_current]];
    final count = ranges.length;
    final nextOffset = ranges.first.start + _replacement.text.length;
    DocumentSearch.replace(widget.controller, ranges, _replacement.text);
    _search();
    if (!all && _matches.isNotEmpty) {
      final next = _matches.indexWhere((range) => range.start >= nextOffset);
      _current = next < 0 ? 0 : next;
      _select();
    }
    _message = '$count eşleşme değiştirildi.';
  });
  @override
  void dispose() {
    _query.dispose();
    _replacement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Bul ve değiştir'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Aranan metin',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(_search),
              onSubmitted: (_) => _next(1),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Büyük/küçük harf'),
                  selected: _matchCase,
                  onSelected: (value) => setState(() {
                    _matchCase = value;
                    _search();
                  }),
                ),
                FilterChip(
                  label: const Text('Tam sözcük'),
                  selected: _wholeWord,
                  onSelected: (value) => setState(() {
                    _wholeWord = value;
                    _search();
                  }),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _query.text.isEmpty
                        ? 'Belge içinde arayın'
                        : _matches.isEmpty
                        ? 'Eşleşme bulunamadı'
                        : '${_current + 1} / ${_matches.length} eşleşme',
                  ),
                ),
                IconButton(
                  tooltip: 'Önceki eşleşme',
                  onPressed: _matches.isEmpty ? null : () => _next(-1),
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  tooltip: 'Sonraki eşleşme',
                  onPressed: _matches.isEmpty ? null : () => _next(1),
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Değiştir'),
              value: _replace,
              onChanged: (value) => setState(() => _replace = value),
            ),
            if (_replace) ...[
              TextField(
                controller: _replacement,
                decoration: const InputDecoration(labelText: 'Yeni metin'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _matches.isEmpty ? null : () => _apply(false),
                    child: const Text('Değiştir'),
                  ),
                  FilledButton(
                    onPressed: _matches.isEmpty ? null : () => _apply(true),
                    child: const Text('Tümünü değiştir'),
                  ),
                ],
              ),
            ],
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_message!),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Kapat'),
      ),
    ],
  );
}
