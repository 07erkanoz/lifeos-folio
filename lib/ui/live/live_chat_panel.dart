import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/live/live_share.dart';
import '../agenda/agenda_page.dart' show AgendaColors;

/// The talk beside a document shared live (approved mockup, 26 Ekim 2026):
/// the lines said, newest last, and a line to write, which may quote what
/// is selected in the document. Beside the page on a computer, in a sheet
/// on a phone; the same on the sharer's side and the others'.
class LiveChatPanel extends StatefulWidget {
  const LiveChatPanel({
    super.key,
    required this.chat,
    required this.onSay,
    required this.onClose,
    this.quote,
  });

  final ValueListenable<List<LiveMessage>> chat;
  final void Function(String text, {String? quote}) onSay;
  final VoidCallback onClose;

  /// What is selected in the document now, to quote; null for nothing.
  final String? Function()? quote;

  @override
  State<LiveChatPanel> createState() => _LiveChatPanelState();
}

class _LiveChatPanelState extends State<LiveChatPanel> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  String? _quote;

  @override
  void initState() {
    super.initState();
    widget.chat.addListener(_came);
    _focus.onKeyEvent = (node, event) {
      // Enter sends; Shift+Enter starts a new line.
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter &&
          !HardwareKeyboard.instance.isShiftPressed) {
        _send();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void didUpdateWidget(LiveChatPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.chat, widget.chat)) {
      old.chat.removeListener(_came);
      widget.chat.addListener(_came);
    }
  }

  @override
  void dispose() {
    widget.chat.removeListener(_came);
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// A line came: the newest shown.
  void _came() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    widget.onSay(text, quote: _quote);
    _text.clear();
    setState(() => _quote = null);
    _focus.requestFocus();
  }

  void _takeQuote() {
    final q = widget.quote?.call()?.trim();
    setState(() => _quote = q == null || q.isEmpty ? null : q);
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  Widget _line(LiveMessage m) {
    final scheme = Theme.of(context).colorScheme;
    if (m.note) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${m.text} · ${_time(m.at)}',
            style: TextStyle(fontSize: 11, color: AgendaColors.muted),
          ),
        ),
      );
    }
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(11, 7, 11, 8),
          decoration: BoxDecoration(
            color: m.mine
                ? scheme.primary.withValues(alpha: .10)
                : scheme.surfaceContainerHighest.withValues(alpha: .7),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(m.mine ? 12 : 4),
              topRight: Radius.circular(m.mine ? 4 : 12),
              bottomLeft: const Radius.circular(12),
              bottomRight: const Radius.circular(12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${m.from} · ${_time(m.at)}',
                style: TextStyle(fontSize: 10.5, color: AgendaColors.muted),
              ),
              if (m.quote case final q?)
                Container(
                  margin: const EdgeInsets.only(top: 3, bottom: 3),
                  padding: const EdgeInsets.only(left: 7),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: scheme.tertiary, width: 3),
                    ),
                  ),
                  child: Text(
                    '“$q”',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AgendaColors.muted,
                    ),
                  ),
                ),
              SelectableText(m.text, style: const TextStyle(fontSize: 13.5)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('live-chat-panel'),
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
            child: Row(
              children: [
                Icon(Icons.chat_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Yazışma',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Paneli kapat',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: ValueListenableBuilder<List<LiveMessage>>(
              valueListenable: widget.chat,
              builder: (context, talk, _) => talk.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Belge üzerinde birbirinize buradan yazın. '
                          'Yazışma paylaşım bitince silinir.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AgendaColors.muted),
                        ),
                      ),
                    )
                  : ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.all(10),
                      children: [for (final m in talk) _line(m)],
                    ),
            ),
          ),
          if (_quote case final q?)
            Container(
              key: const ValueKey('live-chat-quote'),
              margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              padding: const EdgeInsets.fromLTRB(10, 4, 2, 4),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: scheme.tertiary, width: 3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '“$q”',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: AgendaColors.muted,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Alıntıyı kaldır',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _quote = null),
                    icon: const Icon(Icons.close_rounded, size: 16),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 8, 8),
            child: Row(
              children: [
                if (widget.quote != null)
                  IconButton(
                    key: const ValueKey('live-chat-take-quote'),
                    tooltip: 'Belgede seçili olanı alıntıla',
                    onPressed: _takeQuote,
                    icon: const Icon(Icons.format_quote_rounded),
                  ),
                Expanded(
                  child: TextField(
                    key: const ValueKey('live-chat-input'),
                    controller: _text,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Mesaj yazın…',
                      counterText: '',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  key: const ValueKey('live-chat-send'),
                  tooltip: 'Gönder',
                  onPressed: _send,
                  icon: const Icon(Icons.send_rounded, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
