import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/office/office_network.dart';
import '../agenda/agenda_page.dart' show AgendaColors;

/// "Gönder" beside a document: the office's people and this person's own
/// devices, one tap each. Not there at all while there is no one to send to.
class SendToOfficeButton extends StatelessWidget {
  const SendToOfficeButton({
    super.key,
    required this.paths,
    this.text = '',
    this.network,
  });

  final List<String> Function() paths;

  /// Said with the files, as the case they are of.
  final String text;
  final OfficeNetwork? network;

  @override
  Widget build(BuildContext context) {
    final net = network ?? OfficeNetwork.instance;
    return ListenableBuilder(
      listenable: net,
      builder: (context, _) => net.sendTargets.isEmpty
          ? const SizedBox.shrink()
          : IconButton(
              key: const ValueKey('send-to-office'),
              tooltip: 'Gönder',
              onPressed: () => unawaited(
                showSendToOffice(context, paths(), text: text, network: net),
              ),
              icon: const Icon(Icons.send_outlined, size: 20),
            ),
    );
  }
}

Future<void> showSendToOffice(
  BuildContext context,
  List<String> paths, {
  String text = '',
  OfficeNetwork? network,
}) async {
  final net = network ?? OfficeNetwork.instance;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final narrow = MediaQuery.sizeOf(context).width < 600;
  // A short word of what it is, for the one it goes to.
  final note = TextEditingController();
  Widget list(BuildContext context) =>
      _Targets(net: net, note: note, onPick: (t) => Navigator.pop(context, t));
  final SendTarget? to = narrow
      ? await showModalBottomSheet<SendTarget>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (context) => Padding(
            // Above the keyboard while the note is written.
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SafeArea(child: list(context)),
          ),
        )
      : await showDialog<SendTarget>(
          context: context,
          builder: (context) => AlertDialog(
            contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
            content: SizedBox(width: 380, child: list(context)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Vazgeç'),
              ),
            ],
          ),
        );
  final words = note.text.trim();
  note.dispose();
  if (to == null) return;
  final error = await net.sendTo(
    to,
    paths,
    text: [words, text].where((s) => s.isNotEmpty).join('\n'),
  );
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        error ??
            (to.online
                ? 'Gönderildi · Alıcı: ${to.name}'
                : 'Sıraya alındı · Alıcı: ${to.name}. Ağa gelince gider.'),
      ),
    ),
  );
}

class _Targets extends StatelessWidget {
  const _Targets({required this.net, required this.note, required this.onPick});
  final OfficeNetwork net;
  final TextEditingController note;
  final ValueChanged<SendTarget> onPick;

  @override
  Widget build(BuildContext context) {
    final targets = net.sendTargets;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: TextField(
            key: const ValueKey('send-note'),
            controller: note,
            maxLength: 200,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Not (isteğe bağlı)',
              hintText: 'ör. 2024/318 bilirkişi raporu, yarın bakılacak',
              counterText: '',
              isDense: true,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'Kime gönderilsin?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final t in targets)
                ListTile(
                  key: ValueKey('send-to-${t.deviceId}'),
                  leading: Icon(
                    t.member
                        ? Icons.person_outline_rounded
                        : Icons.devices_rounded,
                  ),
                  title: Text(t.name),
                  subtitle: Text(
                    [
                      if (t.detail.isNotEmpty) t.detail,
                      if (!t.online)
                        t.member ? 'ağda değil, gelince gider' : 'ağda değil',
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AgendaColors.muted,
                    ),
                  ),
                  // An own device away cannot take it now.
                  enabled: t.member || t.online,
                  onTap: () => onPick(t),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
