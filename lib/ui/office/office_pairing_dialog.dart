import 'package:flutter/material.dart';

import '../../services/office/office_pairing.dart';
import '../agenda/agenda_page.dart' show AgendaColors;

/// Knowing a new device (docs/design/buro-paylasim-taslak.png, 3): the
/// code both screens show, and the user's word that they match.
class OfficePairingDialog extends StatelessWidget {
  const OfficePairingDialog({super.key, required this.pairing});

  final OfficePairing pairing;

  static Future<void> show(BuildContext context, OfficePairing pairing) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => OfficePairingDialog(pairing: pairing),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: pairing,
    builder: (context, _) {
      final other = pairing.other;
      final state = pairing.state;
      final scheme = Theme.of(context).colorScheme;
      final who = other == null
          ? 'Yeni cihaz'
          : 'Yeni cihaz: ${other.device} · ${other.platform.label}';
      Widget waiting(String text) => Row(
        children: [
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      );
      final body = switch (state) {
        PairingState.connecting => waiting('Karşı cihaza bağlanılıyor…'),
        PairingState.waiting => waiting('Karşı cihazın yanıtı bekleniyor…'),
        PairingState.code || PairingState.confirmed => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              other == null
                  ? 'Karşı ekranda da aynı kod görünüyorsa onaylayın.'
                  : 'Ağda “${other.name.isEmpty ? 'adı yazılmamış bir kullanıcı' : other.name}” '
                        'adıyla bir Folio göründü. Karşı ekranda da aynı kod '
                        'görünüyorsa onaylayın.',
            ),
            const SizedBox(height: 14),
            Container(
              key: const ValueKey('pairing-code'),
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                pairing.code ?? '',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (state == PairingState.confirmed)
              waiting('Karşı tarafın onayı bekleniyor…')
            else
              const Text(
                'Onaydan sonra bu cihazla her aktarım şifreli olur; kod bir '
                'daha sorulmaz.',
                style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
              ),
          ],
        ),
        PairingState.done => Row(
          children: [
            const Icon(Icons.verified_rounded, color: AgendaColors.ok),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                other == null
                    ? 'Cihaz tanındı.'
                    : '${other.device} tanındı. Bundan sonra bu cihazla '
                          'şifreli olarak evrak alıp verebilirsiniz.',
              ),
            ),
          ],
        ),
        PairingState.rejected => Text(
          pairing.reason ?? 'Tanıma reddedildi; cihaz tanınmadı.',
        ),
        PairingState.failed => Text(
          pairing.reason ?? 'Cihaz tanınamadı.',
          style: TextStyle(color: scheme.error),
        ),
      };
      final open =
          state == PairingState.connecting ||
          state == PairingState.waiting ||
          state == PairingState.code ||
          state == PairingState.confirmed;
      return AlertDialog(
        title: Text(who),
        content: SizedBox(width: 420, child: body),
        actions: [
          if (open)
            TextButton(
              key: const ValueKey('pairing-reject'),
              onPressed: () {
                pairing.reject();
                Navigator.of(context).pop();
              },
              child: Text(state == PairingState.code ? 'Reddet' : 'Vazgeç'),
            ),
          if (state == PairingState.code)
            FilledButton(
              key: const ValueKey('pairing-confirm'),
              onPressed: pairing.confirm,
              child: const Text('Kodlar aynı, tanı'),
            ),
          if (!open)
            FilledButton(
              key: const ValueKey('pairing-close'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Kapat'),
            ),
        ],
      );
    },
  );
}
