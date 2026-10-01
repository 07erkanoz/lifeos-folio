import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/evrak_file.dart';
import '../../services/ocr/preview_ocr.dart';
import 'notice.dart';

/// Recognised text beside the page. Its job is to make the document findable,
/// not to reproduce it: Tesseract reads a boxed sidebar and the body column in
/// whatever order it decides, so lines can interleave even when every word is
/// right. The header says so, because a panel of plain text invites being read
/// as a transcript. Selectable, since the reason to open it is usually to check
/// a word against the page or to quote one.
class OcrTextPanel extends StatelessWidget {
  final String text;
  const OcrTextPanel({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: scheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(
                  Icons.document_scanner_outlined,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Arama için çıkarılan metin',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      Text(
                        'Birebir çeviriyazı değildir: tanıma hataları olabilir '
                        've kutulu bölümler ana metnin arasına karışabilir. '
                        'Kaynak belge değişmedi.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Metni kopyala',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: text));
                    messenger
                      ..clearSnackBars()
                      ..showSnackBar(
                        noticeBar(
                          'Metin panoya kopyalandı.',
                          kind: NoticeKind.success,
                        ),
                      );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: SelectableText(
                text,
                style: const TextStyle(fontSize: 13.5, height: 1.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The toolbar control that reveals recognised text, or offers to read it.
/// Shared by the image, TIFF and PDF viewers so all three behave the same.
class OcrTextButton extends StatelessWidget {
  final PreviewOcr ocr;
  final EvrakFormat format;
  final bool showing;
  final ValueChanged<bool> onToggle;
  const OcrTextButton({
    super.key,
    required this.ocr,
    required this.format,
    required this.showing,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ocr,
    builder: (context, _) {
      if (ocr.running) {
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('Okunuyor…', style: TextStyle(fontSize: 12)),
            ],
          ),
        );
      }
      if (ocr.text != null) {
        return TextButton.icon(
          onPressed: () => onToggle(!showing),
          icon: Icon(
            showing ? Icons.image_outlined : Icons.text_snippet_outlined,
            size: 18,
          ),
          label: Text(showing ? 'Belgeyi göster' : 'Okunan metin'),
        );
      }
      if (ocr.foundNothing) {
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Okunabilir yazı bulunamadı',
            style: TextStyle(fontSize: 12),
          ),
        );
      }
      if (!ocr.canRun) return const SizedBox.shrink();
      // A document opened from the desktop is not in the archive, so its text
      // was never read. Offer it here rather than making the reader index the
      // folder first.
      return TextButton.icon(
        onPressed: () => ocr.run(format),
        icon: const Icon(Icons.document_scanner_outlined, size: 18),
        label: const Text('Metne dönüştür'),
      );
    },
  );
}
