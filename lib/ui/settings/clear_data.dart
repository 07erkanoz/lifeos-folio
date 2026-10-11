import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/platform/data_reset.dart';
import '../agenda/agenda_page.dart' show AgendaColors;

/// Ayarlar › Tüm verileri temizle: what goes and what stays said first,
/// agreed to with a tick, then everything of Folio's cleared and Folio
/// closed, to start again as on its first day.
Future<void> clearAllData(BuildContext context) async {
  final agreed = await showDialog<bool>(
    context: context,
    builder: (_) => const _ClearDialog(),
  );
  if (agreed != true || !context.mounted) return;
  await DataReset.clear();
  // Closed at once: what could not be cleared while open is cleared at the
  // next start, before anything is read.
  if (Platform.isIOS) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Veriler temizlendi'),
          content: const Text(
            'Folio’yu kapatıp yeniden açın; ilk kurulum ekranıyla başlar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
    }
    return;
  }
  await closeFolio();
}

/// How Folio closes after the clearing; replaced under test.
@visibleForTesting
Future<void> Function() closeFolio = () async {
  if (Platform.isAndroid) await SystemNavigator.pop();
  exit(0);
};

class _ClearDialog extends StatefulWidget {
  const _ClearDialog();

  @override
  State<_ClearDialog> createState() => _ClearDialogState();
}

class _ClearDialogState extends State<_ClearDialog> {
  bool _sure = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tüm veriler temizlensin mi?'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bu cihazdan kalıcı olarak silinir:'),
            const SizedBox(height: 8),
            for (final line in const [
              'Profiliniz, antetleriniz ve kalıp metinleriniz',
              'Müvekkiller, ücret sözleşmeleri ve kasa kayıtları',
              'Dava dosyaları, duruşmalar, bildirimler ve tebligatlar',
              'Ajanda, görevler ve büro mesajları',
              'UYAP, UETS ve e-Devlet oturumları, büro ağı anahtarları',
              'Belge dizini, son açılanlar ve bütün ayarlar',
            ])
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text('•  $line'),
              ),
            const SizedBox(height: 8),
            const Text(
              'Kendi klasörlerinizdeki belgeleriniz ve UYAP klasörüne '
              'kaydedilmiş evraklar silinmez. Diğer cihazlarınızdaki Folio '
              'verileri de olduğu gibi kalır.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Folio ardından kapanır ve yeniden açıldığında ilk kurulum '
              'ekranıyla başlar. Bu işlem geri alınamaz.',
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              key: const ValueKey('clear-all-sure'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _sure,
              onChanged: (v) => setState(() => _sure = v ?? false),
              title: const Text(
                'Anladım; bu cihazdaki bütün Folio verileri silinsin.',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        key: const ValueKey('clear-all-yes'),
        style: FilledButton.styleFrom(backgroundColor: AgendaColors.deadline),
        onPressed: _sure ? () => Navigator.pop(context, true) : null,
        child: const Text('Sil ve kapat'),
      ),
    ],
  );
}
