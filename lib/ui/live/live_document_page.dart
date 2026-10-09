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
  /// Left when the page is: what was shown is no more watched, and
  /// nothing of it stays.
  static Future<void> open(BuildContext context, LiveSession session) async {
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LiveDocumentPage(session: session),
        ),
      );
    } finally {
      await session.leave();
    }
  }

  @override
  State<LiveDocumentPage> createState() => _LiveDocumentPageState();
}

class _LiveDocumentPageState extends State<LiveDocumentPage> {
  QuillController? _controller;
  int _whole = -1;
  StreamSubscription<Delta>? _changes;

  /// What is written here while holding the pen, to the session.
  StreamSubscription<DocChange>? _written;

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
    unawaited(_written?.cancel());
    _changes = null;
    _written = null;
    final old = _controller;
    old?.removeListener(_moved);
    _controller = doc == null
        ? null
        : QuillController(
            document: Document.fromDelta(doc.toDelta()),
            selection: const TextSelection.collapsed(offset: 0),
            readOnly: !_s.holding,
          );
    final c = _controller;
    if (c != null) {
      // Written here: to the sharer, by the session. Only what the person
      // here typed, not what came from there.
      _written = c.document.changes.listen((e) {
        if (e.source == ChangeSource.local) _s.write(e.change);
      });
      c.addListener(_moved);
    }
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

  /// Where the caret is, for the others while the pen is here.
  void _moved() {
    final c = _controller;
    if (c == null || !_s.holding) return;
    _s.selectionMoved(c.selection.baseOffset, c.selection.extentOffset);
  }

  /// The document let go here: the page's copy and the pictures it drew.
  void _forget() {
    unawaited(_changes?.cancel());
    unawaited(_written?.cancel());
    _changes = null;
    _written = null;
    final old = _controller;
    old?.removeListener(_moved);
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
    if (c != null && c.readOnly == _s.holding) c.readOnly = !_s.holding;
    if (sel != null && c != null && !_s.holding) {
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

  /// What is going on, and what this side may do about it.
  Widget _bar() {
    final s = _s;
    final (Color fill, Color ink, IconData icon, String text) = s.ended
        ? (
            AgendaColors.taskFill,
            AgendaColors.taskText,
            Icons.stop_circle_outlined,
            'Paylaşım bitti; belge bu cihazda kalmadı.',
          )
        : s.holding
        ? (
            AgendaColors.eHearingFill,
            AgendaColors.eHearingText,
            Icons.edit_outlined,
            'Kalem sizde · yazdıklarınız paylaşanın belgesine işlenir',
          )
        : (
            AgendaColors.hearingFill,
            AgendaColors.hearingText,
            Icons.visibility_outlined,
            [
              '${s.from} paylaşıyor',
              if (s.penWith != null)
                '${s.penWith} yazıyor'
              else if (s.right == LiveRight.edit)
                'sırayla düzenleyebilirsiniz'
              else
                'yalnız görebilirsiniz',
            ].join(' · '),
          );
    return Container(
      color: fill,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: ink)),
          ),
          if (!s.ended && s.holding)
            TextButton(
              key: const ValueKey('live-release'),
              onPressed: s.releasePen,
              child: const Text('Kalemi bırak'),
            )
          else if (!s.ended && s.right == LiveRight.edit)
            FilledButton(
              key: const ValueKey('live-ask'),
              onPressed: s.askedPen ? null : s.askPen,
              child: Text(s.askedPen ? 'İstendi' : 'Düzenlemek iste'),
            ),
        ],
      ),
    );
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
          _bar(),
          Expanded(
            child: _s.ended
                ? const SizedBox()
                : c == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    // The page at the top, as tall as the window: written
                    // on from its first line, scrolled within.
                    builder: (context, box) => Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: box.maxWidth > 820 ? 820 : box.maxWidth,
                        height: box.maxHeight,
                        child: FlowingDocumentView(
                          key: ValueKey('live-$_whole'),
                          model: DocModel(blocks: const []),
                          scale: box.maxWidth > 700
                              ? 1.15
                              : FlowingDocumentView.zoom,
                          live: (controller: c, blocks: () => _s.blocks),
                          editable: _s.holding,
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
