import 'package:flutter/material.dart';

import '../../services/office/office_transfer.dart';
import '../agenda/agenda_page.dart' show AgendaColors;

String sizeText(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).ceil()} KB'
    : '${(bytes / 1048576).toStringAsFixed(1)} MB';

/// Files a known device offers: what, how large, the sender's note, and
/// the user's yes or no.
class OfficeOfferDialog extends StatelessWidget {
  const OfficeOfferDialog({
    super.key,
    required this.transfer,
    required this.onAccept,
  });

  final OfficeTransfer transfer;
  final Future<void> Function() onAccept;

  static Future<void> show(
    BuildContext context,
    OfficeTransfer transfer,
    Future<void> Function() onAccept,
  ) => showDialog<void>(
    context: context,
    builder: (_) => OfficeOfferDialog(transfer: transfer, onAccept: onAccept),
  );

  @override
  Widget build(BuildContext context) {
    final t = transfer;
    final who = t.peer.name.isEmpty ? t.peer.device : t.peer.name;
    return AlertDialog(
      title: Text('$who dosya gönderiyor'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${t.files.length} dosya · ${sizeText(t.total)} · ${t.peer.device}',
              style: const TextStyle(fontSize: 12.5, color: AgendaColors.muted),
            ),
            const SizedBox(height: 8),
            for (final f in t.files.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      sizeText(f.size),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AgendaColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            if (t.files.length > 8) Text('+${t.files.length - 8} dosya daha'),
            if (t.note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '“${t.note}”',
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Kabul ederseniz dosyalar şifreli olarak gelir, her biri gelince '
              'denetlenir ve “Folio Gelenler” klasörüne konur.',
              style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('offer-decline'),
          onPressed: () {
            t.decline();
            Navigator.of(context).pop();
          },
          child: const Text('Reddet'),
        ),
        FilledButton(
          key: const ValueKey('offer-accept'),
          onPressed: () {
            onAccept();
            Navigator.of(context).pop();
          },
          child: const Text('Kabul et'),
        ),
      ],
    );
  }
}
