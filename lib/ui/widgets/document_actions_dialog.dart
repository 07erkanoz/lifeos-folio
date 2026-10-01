import 'package:flutter/material.dart';

import '../../models/evrak_file.dart';
import '../../services/platform/editor_window.dart';
import '../../services/platform/platform_capabilities.dart';

/// Whether [file] opens in an editor window of its own: what LifeOS Editör
/// edits, a document of text.
bool opensInEditorWindow(EvrakFile file) =>
    file.format.canEdit &&
    !file.format.usesPlainTextEditor &&
    file.format != EvrakFormat.spreadsheet;

/// Whether [file] can be printed: it has pages to print.
bool canPrint(EvrakFile file) => ![
  EvrakFormat.spreadsheet,
  EvrakFormat.data,
  EvrakFormat.svg,
  EvrakFormat.unknown,
].contains(file.format);

/// A root navigator dialog avoids popup placement/focus issues over viewers.
class DocumentActionsDialog extends StatelessWidget {
  final EvrakFile file;
  const DocumentActionsDialog({super.key, required this.file});
  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 600;
    final colors = Theme.of(context).colorScheme;
    final actions = <(String, String, IconData)>[
      // Folio keeps versions of what it saves; a PDF is only ever exported.
      if (file.format.canEdit && file.format != EvrakFormat.pdf)
        ('history', 'Belge geçmişi', Icons.history_rounded),
      if (file.conversionTargets.isNotEmpty)
        (
          'convert',
          file.format == EvrakFormat.tif ? 'PDF’ye dönüştür' : 'Dönüştür',
          Icons.transform_rounded,
        ),
      if (file.canOptimize)
        ('optimize', 'Kayıpsız boyut küçült', Icons.compress_rounded),
      if (signingAvailable && file.format == EvrakFormat.udf)
        (
          'sign',
          desktopSigningAvailable ? 'UDF e-imzala' : 'Mobil imzayla imzala',
          Icons.draw_outlined,
        ),
      if (EditorWindow.available && opensInEditorWindow(file))
        ('newWindow', 'Yeni pencerede düzenle', Icons.open_in_new_rounded),
      if (canPrint(file)) ('print', 'Yazdır', Icons.print_outlined),
      ('share', 'Paylaş / Gönder', Icons.ios_share_rounded),
      ('openWith', 'Birlikte aç…', Icons.apps_rounded),
      if (desktopSigningAvailable)
        ('folder', 'Klasörde göster', Icons.folder_open_outlined),
      ('external', 'Varsayılan uygulamayla aç', Icons.open_in_new_rounded),
    ];
    return Dialog(
      alignment: phone ? Alignment.bottomCenter : Alignment.topRight,
      insetPadding: EdgeInsets.fromLTRB(12, phone ? 24 : 58, 12, 12),
      constraints: const BoxConstraints(maxWidth: 360),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 6, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Belge işlemleri',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Menüyü kapat · Esc',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final action in actions)
                      ListTile(
                        leading: Icon(
                          action.$3,
                          size: 21,
                          color: colors.primary,
                        ),
                        title: Text(
                          action.$2,
                          style: const TextStyle(fontSize: 14),
                        ),
                        minTileHeight: 48,
                        onTap: () => Navigator.pop(context, action.$1),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
