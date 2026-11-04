import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../models/evrak_file.dart';
import '../../services/live/live_remote.dart';
import '../../services/platform/app_language.dart';
import '../agenda/agenda_page.dart' show AgendaColors;

/// "Canlı belge", from the home page without going into the editor
/// (approved mockup, 26 Ekim 2026): a code to join with on top, filled in
/// from the clipboard when an invitation is on it, and below the recent
/// documents, one of them shared with a tap. A sheet on a phone, a dialog
/// on a computer.
class LiveHub extends StatefulWidget {
  const LiveHub({
    super.key,
    required this.recent,
    required this.onJoin,
    required this.onShare,
    required this.onPick,
    this.join = true,
  });

  final List<EvrakFile> recent;
  final ValueChanged<String> onJoin;
  final ValueChanged<EvrakFile> onShare;
  final VoidCallback onPick;

  /// Whether joining is offered too, not only sharing.
  final bool join;

  /// Whether [format] can be shared live: it opens in Folio's own editor.
  static bool shareable(EvrakFormat format) =>
      format.canEdit &&
      format != EvrakFormat.pdf &&
      format != EvrakFormat.spreadsheet &&
      !format.usesPlainTextEditor;

  /// Shown; what was chosen is done by the callbacks once it is closed.
  static Future<void> show(
    BuildContext context, {
    required List<EvrakFile> recent,
    required ValueChanged<String> onJoin,
    required ValueChanged<EvrakFile> onShare,
    required VoidCallback onPick,
    bool join = true,
  }) async {
    VoidCallback? chosen;
    Widget hub(BuildContext context) => LiveHub(
      recent: recent,
      join: join,
      onJoin: (code) {
        chosen = () => onJoin(code);
        Navigator.of(context).pop();
      },
      onShare: (file) {
        chosen = () => onShare(file);
        Navigator.of(context).pop();
      },
      onPick: () {
        chosen = onPick;
        Navigator.of(context).pop();
      },
    );
    if (MediaQuery.sizeOf(context).width < 700) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheet).bottom,
          ),
          child: hub(sheet),
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (dialog) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: hub(dialog),
            ),
          ),
        ),
      );
    }
    chosen?.call();
  }

  @override
  State<LiveHub> createState() => _LiveHubState();
}

class _LiveHubState extends State<LiveHub> {
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
    if (widget.join) unawaited(_fromClipboard());
  }

  /// An invitation copied from WhatsApp or mail: its code in place.
  Future<void> _fromClipboard() async {
    try {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      final code = text == null ? null : RemoteCode.find(text);
      if (code != null && mounted && _code.text.isEmpty) {
        _code.text = RemoteCode.shown(code);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _join() {
    final code = RemoteCode.read(_code.text);
    if (code != null) widget.onJoin(code);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final documents = [
      for (final f in widget.recent)
        if (LiveHub.shareable(f.format)) f,
    ].take(5).toList();
    final ready = RemoteCode.read(_code.text) != null;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .8,
          color: AgendaColors.muted,
        ),
      ),
    );
    return SingleChildScrollView(
      key: const ValueKey('live-hub'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l.liveDocument,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          if (widget.join) ...[
            Text(
              context.l.liveHubCodePrompt,
              style: TextStyle(color: AgendaColors.muted),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('live-hub-code'),
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                hintText: 'K7Q-4MP-2XD',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _join(),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('live-hub-join'),
              onPressed: ready ? _join : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(context.l.liveJoin),
              ),
            ),
            const SizedBox(height: 18),
            heading(context.l.liveHubOrShare),
          ] else ...[
            Text(
              context.l.liveHubPickPrompt,
              style: TextStyle(color: AgendaColors.muted),
            ),
            const SizedBox(height: 12),
          ],
          for (final f in documents)
            ListTile(
              key: ValueKey('live-hub-share-${f.path}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  f.format.defaultExtension.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ),
              title: Text(
                p.basenameWithoutExtension(f.path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(Icons.cast_rounded, color: scheme.primary),
              onTap: () => widget.onShare(f),
            ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            key: const ValueKey('live-hub-pick'),
            onPressed: widget.onPick,
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: Text(context.l.liveHubPickOther),
          ),
        ],
      ),
    );
  }
}
