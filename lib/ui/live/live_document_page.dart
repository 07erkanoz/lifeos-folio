import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../models/document_model.dart';
import '../../services/live/live_share.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../widgets/flowing_document_view.dart';

/// A document another device shares live, shown as it is written there:
/// read-only, the writer's selection marked.
class LiveDocumentPage extends StatefulWidget {
  const LiveDocumentPage({super.key, required this.session});

  final LiveSession session;

  /// [session] on a page of its own.
  static Future<void> open(BuildContext context, LiveSession session) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LiveDocumentPage(session: session),
        ),
      );

  @override
  State<LiveDocumentPage> createState() => _LiveDocumentPageState();
}

class _LiveDocumentPageState extends State<LiveDocumentPage> {
  QuillController? _controller;
  int _whole = -1;
  StreamSubscription<Delta>? _changes;

  LiveSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _s.addListener(_changed);
    _changed();
  }

  /// The page's own copy of the document, taken from the session's as it
  /// stands, and kept up from its changes from then on: taken and listened
  /// to at once, nothing comes between.
  void _copy() {
    final doc = _s.document;
    unawaited(_changes?.cancel());
    _changes = null;
    final old = _controller;
    _controller = doc == null
        ? null
        : QuillController(
            document: Document.fromDelta(doc.toDelta()),
            selection: const TextSelection.collapsed(offset: 0),
            readOnly: true,
          );
    if (doc != null) {
      _changes = _s.changes.listen((d) {
        final c = _controller;
        if (c == null) return;
        try {
          c.compose(d, c.selection, ChangeSource.remote);
        } catch (_) {
          // Out of step with the session's own: taken again from it.
          _copy();
          if (mounted) setState(() {});
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  /// The document let go here: the page's copy and the pictures it drew.
  void _forget() {
    unawaited(_changes?.cancel());
    _changes = null;
    final old = _controller;
    _controller = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old?.dispose();
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    });
  }

  void _changed() {
    if (!mounted) return;
    if (_s.ended) {
      if (_controller != null) _forget();
      setState(() {});
      return;
    }
    if (_s.ready && _s.whole != _whole) {
      _whole = _s.whole;
      _copy();
    }
    final sel = _s.selection, c = _controller;
    if (sel != null && c != null) {
      final end = c.document.length - 1;
      int clamp(int v) => v < 0 ? 0 : (v > end ? end : v);
      c.updateSelection(
        TextSelection(
          baseOffset: clamp(sel.base),
          extentOffset: clamp(sel.extent),
        ),
        ChangeSource.remote,
      );
    }
    setState(() {});
  }

  @override
  void dispose() {
    _s.removeListener(_changed);
    _forget();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(_s.title, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            key: const ValueKey('live-leave'),
            onPressed: () async {
              await _s.leave();
              if (context.mounted) Navigator.of(context).maybePop();
            },
            child: const Text('İzlemeyi bırak'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: _s.ended ? AgendaColors.taskFill : AgendaColors.hearingFill,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(
                  _s.ended
                      ? Icons.stop_circle_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                  color: _s.ended
                      ? AgendaColors.taskText
                      : AgendaColors.hearingText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _s.ended
                        ? 'Paylaşım bitti; belge bu cihazda kalmadı.'
                        : '${_s.from} paylaşıyor · canlı izliyorsunuz · '
                              'yalnız görebilirsiniz',
                    style: TextStyle(
                      fontSize: 13,
                      color: _s.ended
                          ? AgendaColors.taskText
                          : AgendaColors.hearingText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _s.ended
                ? const SizedBox()
                : c == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, box) => Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: FlowingDocumentView(
                          key: ValueKey('live-$_whole'),
                          model: DocModel(blocks: const []),
                          scale: box.maxWidth > 700
                              ? 1.15
                              : FlowingDocumentView.zoom,
                          live: (controller: c, blocks: () => _s.blocks),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
