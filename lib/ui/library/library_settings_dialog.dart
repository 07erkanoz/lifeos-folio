import 'dart:io';

import '../../services/editor/editor_settings.dart';
import '../../services/legal/legal_settings.dart';

import 'package:file_picker/file_picker.dart';

import '../../services/platform/document_intents.dart';
import '../../services/platform/context_menu_registration.dart';
import '../../services/platform/platform_capabilities.dart';
import '../widgets/default_viewer_dialog.dart';
import '../desktop/quick_search_settings.dart';
import '../widgets/folio_about_dialog.dart';
import '../widgets/notice.dart';

import 'package:flutter/material.dart';

import '../../services/search/library_controller.dart';
import '../theme/theme_controller.dart';
import '../../services/editor/snippets.dart';
import '../widgets/lawyer_profile_dialog.dart';
import '../widgets/learned_phrases_dialog.dart';
import '../widgets/snippet_manager.dart';
import '../widgets/signing_dialog.dart';

class LibrarySettingsDialog extends StatefulWidget {
  final LibraryController library;
  final ThemeController appearance;
  const LibrarySettingsDialog({
    super.key,
    required this.library,
    required this.appearance,
  });
  @override
  State<LibrarySettingsDialog> createState() => _LibrarySettingsDialogState();
}

class _LibrarySettingsDialogState extends State<LibrarySettingsDialog> {
  bool _registeringContext = false;
  Future<void> _registerContext() async {
    setState(() => _registeringContext = true);
    try {
      final message = await ContextMenuRegistration.register();
      if (mounted) showNotice(context, message, kind: NoticeKind.success);
    } catch (e) {
      if (mounted) showNotice(context, '$e', kind: NoticeKind.error);
    } finally {
      if (mounted) setState(() => _registeringContext = false);
    }
  }

  bool _recursive = true;
  bool _picking = false;
  Future<void> _addFolder() async {
    setState(() => _picking = true);
    try {
      final path = Platform.isAndroid
          ? await DocumentIntents.pickFolder()
          : await FilePicker.getDirectoryPath(
              dialogTitle: 'İndekslenecek klasörü seçin',
            );
      if (path != null && mounted) {
        await widget.library.addPaths([path], recursive: _recursive);
      }
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Klasör eklenemedi',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  bool _pickingOcr = false;
  Future<void> _addOcrFolder() async {
    setState(() => _pickingOcr = true);
    try {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: 'OCR uygulanacak klasörü seçin',
      );
      if (path == null || !mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final affected = await widget.library.addOcrFolder(
        path,
        recursive: _ocrRecursive,
      );
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          noticeBar(
            widget.library.ocrEnabled
                ? '$affected belge OCR sırasına alındı.'
                : 'Bu seçimle $affected belge okunacak.',
          ),
        );
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Klasör seçilemedi',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _pickingOcr = false);
    }
  }

  bool _ocrRecursive = true;

  Future<void> _registerViewer() => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const DefaultViewerDialog(),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.library, widget.appearance]),
    builder: (context, _) {
      final scheme = Theme.of(context).colorScheme;
      final library = widget.library;
      final folders = library.sources.where((s) => s.folder).toList();
      return AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.settings_outlined, size: 23),
            const SizedBox(width: 12),
            const Text('Ayarlar'),
          ],
        ),
        content: SizedBox(
          width: 700,
          height: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Arşiv klasörleri',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Klasörlerinizi buradan ekleyin. Desteklenen dosyalar otomatik indekslenir; içerikleri ana sayfada aranabilir.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Üzerine gelince hızlı önizleme'),
                    subtitle: const Text(
                      'Evrak üzerinde kısa süre bekleyince açılır. Esc ile kapanır.',
                    ),
                    value: widget.appearance.hoverPreview,
                    onChanged: (value) => setState(
                      () => widget.appearance.setHoverPreview(value),
                    ),
                  ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Kanun maddelerini göster'),
                  subtitle: const Text(
                    'TMK m. 166 gibi atıflar tıklanır olur, maddenin resmî '
                    'metni açılır. Kanun ilk istendiğinde mevzuat.gov.tr\'den '
                    'indirilip saklanır; belgeniz dışarı çıkmaz.',
                  ),
                  value: LegalSettings.instance.articles,
                  onChanged: (value) async {
                    await LegalSettings.instance.setArticles(value);
                    if (mounted) setState(() {});
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mahkeme kararlarını göster'),
                  subtitle: const Text(
                    'Yargıtay, BAM ve Danıştay atıfları tıklanır olur, kararın '
                    'tam metni Bedesten\'den getirilir. Karar bankası kararların '
                    'bir bölümünü yayımlar; hepsi bulunmaz. İlk derece dosya '
                    'numaralarına dokunulmaz.',
                  ),
                  value: LegalSettings.instance.decisions,
                  onChanged: (value) async {
                    await LegalSettings.instance.setDecisions(value);
                    if (mounted) setState(() {});
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hukuk sözlüğü'),
                  subtitle: const Text(
                    'Bir terime sağ tıklayınca anlamı gösterilir. Sözlük '
                    'uygulamayla gelir, internet gerekmez.',
                  ),
                  value: LegalSettings.instance.dictionary,
                  onChanged: (value) async {
                    await LegalSettings.instance.setDictionary(value);
                    if (mounted) setState(() {});
                  },
                ),
                SwitchListTile.adaptive(
                  key: const ValueKey('setting-suggestions'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Yazarken öneri'),
                  subtitle: const Text(
                    'Editörde yazarken sık kullandığınız ifadeler imlecin '
                    'altında önerilir. Enter ya da Tab ile seçilir, Esc ile '
                    'kapanır; liste kapalıyken Enter yeni satır açar.',
                  ),
                  value: EditorSettings.instance.suggestions,
                  onChanged: (value) async {
                    await EditorSettings.instance.setSuggestions(value);
                    if (mounted) setState(() {});
                  },
                ),
                SwitchListTile.adaptive(
                  key: const ValueKey('setting-learn-saved'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Kaydettiğim belgelerden öğren'),
                  subtitle: const Text(
                    'Editörde kaydettiğiniz belgelerde geçen ifadeler '
                    'öneriye eklenir. Bir belge kaç kez kaydedilirse '
                    'kaydedilsin bir kez sayılır.',
                  ),
                  value: EditorSettings.instance.learnSaved,
                  onChanged: (value) async {
                    await EditorSettings.instance.setLearnSaved(value);
                    if (mounted) setState(() {});
                  },
                ),
                SwitchListTile.adaptive(
                  key: const ValueKey('setting-learn-archive'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Arşivden öğren'),
                  subtitle: const Text(
                    'Arşivinizde en az üç belgede geçen ifadeler öneriye '
                    'eklenir. Arşiv arka planda, haftada bir okunur. Kişisel '
                    'bilgi içeren ifadeler öğrenilmez; hepsi bu bilgisayarda '
                    'kalır.',
                  ),
                  value: EditorSettings.instance.learnArchive,
                  onChanged: (value) async {
                    await EditorSettings.instance.setLearnArchive(value);
                    if (mounted) setState(() {});
                  },
                ),
                if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Taranmış belgeleri oku (OCR)'),
                    subtitle: Text(
                      widget.library.ocrAvailable
                          ? 'Metin katmanı olmayan PDF ve görsellerin içindeki yazı '
                                'okunup aranabilir hale getirilir. Açtığınızda arşivdeki '
                                'aranamayan belgeler sıraya alınır; sayfa başına birkaç '
                                'saniye sürer ve arka planda çalışır.'
                          : 'Bu sürümde OCR bileşeni bulunamadı.',
                    ),
                    value: widget.library.ocrEnabled,
                    onChanged: widget.library.ocrAvailable
                        ? (value) async {
                            // Captured before the await: the dialog can close
                            // while the indexer is still answering.
                            final messenger = ScaffoldMessenger.of(context);
                            final queued = await widget.library.setOcr(value);
                            if (!mounted) return;
                            setState(() {});
                            if (queued > 0) {
                              messenger
                                ..clearSnackBars()
                                ..showSnackBar(
                                  noticeBar(
                                    '$queued belge yeniden okunmak üzere '
                                    'sıraya alındı.',
                                    detail: 'Sayfa başına birkaç saniye sürer.',
                                  ),
                                );
                            }
                          }
                        : null,
                  ),
                if ((Platform.isLinux ||
                        Platform.isWindows ||
                        Platform.isMacOS) &&
                    library.ocrAvailable)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          library.ocrFolders.isEmpty
                              ? 'Şu an arşivin tamamı kapsanıyor: '
                                    '${library.ocrPending} belge okunmayı bekliyor.'
                              : 'Seçili ${library.ocrFolders.length} klasör: '
                                    '${library.ocrPending} belge okunmayı bekliyor.',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _pickingOcr ? null : _addOcrFolder,
                              icon: const Icon(Icons.folder_open, size: 16),
                              label: const Text('OCR klasörü seç'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  visualDensity: VisualDensity.compact,
                                  value: _ocrRecursive,
                                  onChanged: (v) =>
                                      setState(() => _ocrRecursive = v ?? true),
                                ),
                                const Text(
                                  'Alt klasörler dahil',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                        for (final folder in library.ocrFolders)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Icon(
                                  folder.recursive
                                      ? Icons.account_tree_outlined
                                      : Icons.folder_outlined,
                                  size: 14,
                                  color: scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    folder.recursive
                                        ? '${folder.path}  (alt klasörlerle)'
                                        : '${folder.path}  (yalnız bu klasör)',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Kapsamdan çıkar',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.close, size: 15),
                                  onPressed: () =>
                                      library.removeOcrFolder(folder.id),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _picking ? null : _addFolder,
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                      ),
                      label: const Text('Klasör seç ve ekle'),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _recursive,
                          onChanged: (value) =>
                              setState(() => _recursive = value ?? true),
                        ),
                        const Flexible(
                          child: Text(
                            'Alt klasörleri dahil et',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (library.active) ...[
                  LinearProgressIndicator(
                    value: library.toProcess == 0
                        ? null
                        : library.processed / library.toProcess,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${library.phase} · ${library.processed}/${library.toProcess}',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (library.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      library.error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: scheme.error),
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  height: folders.isEmpty ? 80 : 240,
                  child: folders.isEmpty
                      ? Center(
                          child: Text(
                            'Henüz klasör eklenmedi.',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.separated(
                          itemCount: folders.length,
                          separatorBuilder: (_, i) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final folder = folders[i];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.folder_outlined,
                                        color: scheme.primary,
                                        size: 21,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          folder.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${folder.count} evrak',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Klasörü yeniden tara',
                                        onPressed: () =>
                                            library.refresh(ids: [folder.id]),
                                        icon: const Icon(
                                          Icons.refresh,
                                          size: 18,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Klasörü arşivden çıkar',
                                        onPressed: () =>
                                            library.removeSource(folder.id),
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SelectableText(
                                    folder.path,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      SizedBox(
                                        height: 32,
                                        width: 28,
                                        child: Checkbox(
                                          value: folder.recursive,
                                          onChanged: (value) =>
                                              library.addPaths([
                                                folder.path,
                                              ], recursive: value ?? true),
                                        ),
                                      ),
                                      const SizedBox(width: 7),
                                      const Expanded(
                                        child: Text(
                                          'Alt klasörleri de indeksle',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (folder.error != null)
                                    Text(
                                      folder.error!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.error,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const Divider(height: 24),
                Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const SizedBox(
                      width: 160,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Görünüm',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Tema seçiminiz hatırlanır.',
                            style: TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final option in [
                          (ThemeMode.light, 'Beyaz'),
                          (ThemeMode.dark, 'Siyah'),
                          (ThemeMode.system, 'Sistem'),
                        ])
                          ChoiceChip(
                            label: Text(option.$2),
                            showCheckmark: false,
                            selected: widget.appearance.mode == option.$1,
                            onSelected: (_) =>
                                widget.appearance.setMode(option.$1),
                          ),
                      ],
                    ),
                  ],
                ),
                const QuickSearchSettings(),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _registerViewer,
                  icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                  label: const Text(
                    'Varsayılan uygulama · dosya türlerini seç',
                  ),
                ),
                if (Platform.isLinux || Platform.isWindows)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: _registeringContext ? null : _registerContext,
                      icon: const Icon(Icons.ads_click_rounded, size: 18),
                      label: Text(
                        _registeringContext
                            ? 'Bağlantılar ekleniyor…'
                            : 'Sağ tuşa önizle ve düzenle ekle',
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('lawyer-profile'),
                  onPressed: () => LawyerProfileDialog.show(context),
                  icon: const Icon(Icons.badge_outlined, size: 18),
                  label: const Text('Avukat profili'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('snippet-library'),
                  onPressed: () async {
                    final store = await SnippetStore.shared();
                    if (context.mounted) {
                      await SnippetManager.show(context, store);
                    }
                  },
                  icon: const Icon(Icons.bookmark_border_rounded, size: 18),
                  label: const Text('Kalıplarım'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('learned-phrases-button'),
                  onPressed: () => LearnedPhrasesDialog.show(context),
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Öğrenilen ifadeler'),
                ),
                const SizedBox(height: 8),
                if (desktopSigningAvailable)
                  OutlinedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const SigningDialog(),
                    ),
                    icon: const Icon(Icons.draw_outlined, size: 18),
                    label: const Text('E-imza ayarları'),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => showFolioAbout(context),
                  icon: const Icon(Icons.info_outline_rounded, size: 18),
                  label: const Text('LifeOS Folio hakkında'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Klasörler bu cihazda saklanır ve uygulama veya arka plan modu çalışırken değişiklikler izlenir. Arşivden kaldırmak kaynak dosyaları silmez.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (library.active)
            TextButton(
              onPressed: library.cancel,
              child: const Text('İndekslemeyi durdur'),
            ),
          if (!library.active && folders.isNotEmpty)
            TextButton(
              onPressed: () => library.refresh(),
              child: const Text('Tüm klasörleri güncelle'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      );
    },
  );
}
