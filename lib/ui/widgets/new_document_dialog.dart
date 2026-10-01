import 'package:flutter/material.dart';

import '../../models/evrak_file.dart';

/// Only offer formats that the editor can actually write.
class NewDocumentDialog extends StatefulWidget {
  const NewDocumentDialog({super.key});

  @override
  State<NewDocumentDialog> createState() => _NewDocumentDialogState();
}

class _NewDocumentDialogState extends State<NewDocumentDialog> {
  EvrakFormat _format = EvrakFormat.udf;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Yeni belge oluştur'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Belge türünü seçin. Boş bir sayfayla başlayın.'),
            const SizedBox(height: 20),
            for (final option in const [
              (
                EvrakFormat.udf,
                'UDF belgesi',
                'UYAP uyumlu belge',
                Icons.description_outlined,
              ),
              (
                EvrakFormat.docx,
                'Word belgesi',
                'DOCX · Microsoft Word ile uyumlu',
                Icons.article_outlined,
              ),
              (
                EvrakFormat.text,
                'Metin belgesi',
                'TXT · Biçimlendirme içermeyen düz metin',
                Icons.notes_rounded,
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Semantics(
                  selected: _format == option.$1,
                  child: Material(
                    color: _format == option.$1
                        ? colors.primary.withValues(alpha: .08)
                        : colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: _format == option.$1
                            ? colors.primary
                            : colors.outlineVariant,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      leading: Icon(option.$4, color: colors.primary),
                      title: Text(
                        option.$2,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(option.$3),
                      trailing: Icon(
                        _format == option.$1
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: _format == option.$1
                            ? colors.primary
                            : colors.outline,
                        size: 20,
                      ),
                      onTap: () => setState(() => _format = option.$1),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _format),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Oluştur'),
        ),
      ],
    );
  }
}
