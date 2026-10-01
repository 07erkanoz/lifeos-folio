import 'dart:io';

import 'package:evrak_convert/ui/theme/app_theme.dart';
import 'package:evrak_convert/ui/widgets/ribbon.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:window_manager/window_manager.dart';

/// The editor's tabbed ribbon on its own, to look at before it replaces the
/// toolbar. flutter build windows --debug -t tool/ribbon_preview.dart;
/// FOLIO_RIBBON_TAB=0..3 picks the tab it opens on.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final tab = int.tryParse(Platform.environment['FOLIO_RIBBON_TAB'] ?? '') ?? 0;
  runApp(_Preview(tab: tab));
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1440, 520),
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'Şerit önizleme',
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
      // For screenshots taken by a script, which other windows would hide.
      if (Platform.environment['FOLIO_RIBBON_TOP'] == '1') {
        await windowManager.setAlwaysOnTop(true);
      }
    },
  );
}

class _Preview extends StatelessWidget {
  final int tab;
  const _Preview({required this.tab});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFE9E9E9),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TitleBar(),
          Ribbon(
            initialTab: tab,
            leading: RibbonFileTab(onTap: () {}),
            tabs: _tabs(context),
            trailing: const [
              RibbonActionButton(
                icon: FluentIcons.signature_20_regular,
                label: 'İmzala',
              ),
              RibbonActionButton(
                icon: FluentIcons.save_20_regular,
                label: 'Kaydet',
                filled: true,
              ),
            ],
          ),
          const Expanded(child: _Page()),
        ],
      ),
    ),
  );

  List<RibbonTab> _tabs(BuildContext context) {
    final serif = TextStyle(fontFamily: 'Times New Roman', fontSize: 13);
    return [
      RibbonTab('Giriş', [
        RibbonGroup('Yazı tipi', [
          RibbonStack([
            RibbonRow([
              const RibbonField('Times New Roman', width: 140),
              const RibbonField('12', width: 46),
              const RibbonIconButton(
                icon: FluentIcons.font_increase_20_regular,
                tooltip: 'Yazıyı büyüt',
              ),
              const RibbonIconButton(
                icon: FluentIcons.font_decrease_20_regular,
                tooltip: 'Yazıyı küçült',
              ),
            ]),
            const RibbonRow([
              RibbonIconButton(
                icon: FluentIcons.text_bold_20_regular,
                tooltip: 'Kalın · Ctrl+B',
                selected: true,
              ),
              RibbonIconButton(
                icon: FluentIcons.text_italic_20_regular,
                tooltip: 'İtalik · Ctrl+I',
              ),
              RibbonIconButton(
                icon: FluentIcons.text_underline_20_regular,
                tooltip: 'Altı çizili · Ctrl+U',
              ),
              RibbonIconButton(
                icon: FluentIcons.text_strikethrough_20_regular,
                tooltip: 'Üstü çizili',
              ),
              RibbonIconButton(
                icon: FluentIcons.text_subscript_20_regular,
                tooltip: 'Alt simge',
              ),
              RibbonIconButton(
                icon: FluentIcons.text_superscript_20_regular,
                tooltip: 'Üst simge',
              ),
              RibbonIconButton(
                icon: FluentIcons.highlight_20_regular,
                tooltip: 'Vurgu rengi',
                dropdown: true,
                bar: Color(0xFFFFE600),
              ),
              RibbonIconButton(
                icon: FluentIcons.text_color_20_regular,
                tooltip: 'Yazı rengi',
                dropdown: true,
                bar: Color(0xFFD13438),
              ),
              RibbonIconButton(
                icon: FluentIcons.text_clear_formatting_20_regular,
                tooltip: 'Biçimlendirmeyi temizle',
              ),
            ]),
          ]),
        ], onMore: () {}),
        RibbonGroup('Paragraf', [
          const RibbonStack([
            RibbonRow([
              RibbonIconButton(
                icon: FluentIcons.text_bullet_list_ltr_20_regular,
                tooltip: 'Madde işaretleri',
                dropdown: true,
              ),
              RibbonIconButton(
                icon: FluentIcons.text_number_list_ltr_20_regular,
                tooltip: 'Numaralandırma',
                dropdown: true,
              ),
              RibbonIconButton(
                icon: FluentIcons.text_indent_decrease_ltr_20_regular,
                tooltip: 'Girintiyi azalt',
              ),
              RibbonIconButton(
                icon: FluentIcons.text_indent_increase_ltr_20_regular,
                tooltip: 'Girintiyi artır',
              ),
            ]),
            RibbonRow([
              RibbonIconButton(
                icon: FluentIcons.text_align_left_20_regular,
                tooltip: 'Sola hizala',
              ),
              RibbonIconButton(
                icon: FluentIcons.text_align_center_20_regular,
                tooltip: 'Ortala',
              ),
              RibbonIconButton(
                icon: FluentIcons.text_align_right_20_regular,
                tooltip: 'Sağa hizala',
              ),
              RibbonIconButton(
                icon: FluentIcons.text_align_justify_20_regular,
                tooltip: 'İki yana yasla',
                selected: true,
              ),
              RibbonIconButton(
                icon: FluentIcons.text_line_spacing_20_regular,
                tooltip: 'Satır aralığı',
                dropdown: true,
              ),
            ]),
          ]),
        ], onMore: () {}),
        RibbonGroup('Stiller', [
          RibbonStyleGallery(
            styles: [
              ('Normal', serif),
              (
                'Başlık 1',
                serif.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              (
                'Başlık 2',
                serif.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              (
                'Başlık 3',
                serif.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ]),
        const RibbonGroup('Düzenleme', [
          RibbonStack([
            RibbonSmallButton(
              icon: FluentIcons.search_20_regular,
              label: 'Bul',
            ),
            RibbonSmallButton(
              icon: FluentIcons.arrow_swap_20_regular,
              label: 'Değiştir',
            ),
            RibbonSmallButton(
              icon: FluentIcons.select_all_on_20_regular,
              label: 'Tümünü seç',
            ),
          ]),
        ]),
      ]),
      const RibbonTab('Ekle', [
        RibbonGroup('Tablolar', [
          RibbonLargeButton(
            icon: FluentIcons.table_24_regular,
            fill: FluentIcons.table_24_filled,
            tint: RibbonTint.green,
            label: 'Tablo',
            dropdown: true,
          ),
        ]),
        RibbonGroup('Çizimler', [
          RibbonLargeButton(
            icon: FluentIcons.image_24_regular,
            fill: FluentIcons.image_24_filled,
            tint: RibbonTint.teal,
            label: 'Görsel',
          ),
        ]),
        RibbonGroup('Üst ve alt bilgi', [
          RibbonLargeButton(
            icon: FluentIcons.document_header_24_regular,
            fill: FluentIcons.document_header_24_filled,
            tint: RibbonTint.blue,
            label: 'Üst bilgi',
            dropdown: true,
          ),
          RibbonLargeButton(
            icon: FluentIcons.document_footer_24_regular,
            fill: FluentIcons.document_footer_24_filled,
            tint: RibbonTint.blue,
            label: 'Alt bilgi',
            dropdown: true,
          ),
          RibbonLargeButton(
            icon: FluentIcons.number_symbol_square_24_regular,
            fill: FluentIcons.number_symbol_square_24_filled,
            tint: RibbonTint.blue,
            label: 'Sayfa numarası',
            dropdown: true,
          ),
        ]),
        RibbonGroup('Metin', [
          RibbonLargeButton(
            icon: FluentIcons.bookmark_24_regular,
            fill: FluentIcons.bookmark_24_filled,
            tint: RibbonTint.gold,
            label: 'Kalıp metin',
            dropdown: true,
          ),
        ]),
      ]),
      RibbonTab('Araçlar', [
        const RibbonGroup('UYAP', [
          RibbonLargeButton(
            icon: FluentIcons.gavel_24_regular,
            fill: FluentIcons.gavel_24_filled,
            tint: RibbonTint.navy,
            label: 'UYAP dosyası',
            selected: true,
          ),
          RibbonStack([
            RibbonSmallButton(
              icon: FluentIcons.send_20_regular,
              fill: FluentIcons.send_20_filled,
              tint: RibbonTint.blue,
              label: 'UYAP’a gönder',
            ),
            RibbonSmallButton(
              icon: FluentIcons.arrow_sync_circle_20_regular,
              fill: FluentIcons.arrow_sync_circle_20_filled,
              tint: RibbonTint.teal,
              label: 'Devam eden işlemler',
            ),
            RibbonSmallButton(
              icon: FluentIcons.save_20_regular,
              fill: FluentIcons.save_20_filled,
              tint: RibbonTint.navy,
              label: 'UYAP UDF olarak kaydet',
            ),
          ]),
        ]),
        const RibbonGroup('İmza', [
          RibbonLargeButton(
            icon: FluentIcons.signature_24_regular,
            fill: FluentIcons.signature_24_filled,
            tint: RibbonTint.purple,
            label: 'E-imza',
          ),
          RibbonStack([
            RibbonSmallButton(
              icon: FluentIcons.phone_20_regular,
              fill: FluentIcons.phone_20_filled,
              tint: RibbonTint.purple,
              label: 'Mobil imza',
            ),
            RibbonSmallButton(
              icon: FluentIcons.shield_checkmark_20_regular,
              fill: FluentIcons.shield_checkmark_20_filled,
              tint: RibbonTint.green,
              label: 'İmza bilgisi',
            ),
          ]),
        ]),
        const RibbonGroup('Dönüştür', [
          RibbonStack([
            RibbonSmallButton(
              icon: FluentIcons.document_pdf_20_regular,
              fill: FluentIcons.document_pdf_20_filled,
              tint: RibbonTint.red,
              label: 'PDF’e dönüştür',
            ),
            RibbonSmallButton(
              icon: FluentIcons.document_20_regular,
              fill: FluentIcons.document_20_filled,
              tint: RibbonTint.blue,
              label: 'Word olarak kaydet',
            ),
            RibbonSmallButton(
              icon: FluentIcons.document_copy_20_regular,
              fill: FluentIcons.document_copy_20_filled,
              tint: RibbonTint.teal,
              label: 'Başka biçimde',
              dropdown: true,
            ),
          ]),
        ]),
        const RibbonGroup('Ses', [
          RibbonLargeButton(
            icon: FluentIcons.speaker_2_24_regular,
            fill: FluentIcons.speaker_2_24_filled,
            tint: RibbonTint.orange,
            label: 'Sesli oku',
          ),
          RibbonStack([
            RibbonSmallButton(
              icon: FluentIcons.mic_20_regular,
              fill: FluentIcons.mic_20_filled,
              tint: RibbonTint.orange,
              label: 'Sesli yaz',
            ),
            RibbonSmallButton(
              icon: FluentIcons.top_speed_20_regular,
              fill: FluentIcons.top_speed_20_filled,
              tint: RibbonTint.orange,
              label: 'Okuma hızı',
              dropdown: true,
            ),
          ]),
        ]),
        RibbonGroup('Hukuk', [
          const RibbonLargeButton(
            icon: FluentIcons.scales_24_regular,
            fill: FluentIcons.scales_24_filled,
            tint: RibbonTint.gold,
            label: 'İçtihat ara',
          ),
          RibbonStack([
            RibbonCheck('Kanun maddeleri', value: true, onChanged: (_) {}),
            RibbonCheck('Yargıtay kararları', value: true, onChanged: (_) {}),
            RibbonCheck('Hukuk sözlüğü', value: true, onChanged: (_) {}),
          ]),
        ]),
        RibbonGroup('Öneriler', [
          RibbonStack([
            RibbonCheck('Yazarken öner', value: true, onChanged: (_) {}),
            RibbonCheck('Kaydettiklerimden', value: true, onChanged: (_) {}),
            RibbonCheck('Arşivden öğren', value: false, onChanged: (_) {}),
          ]),
        ]),
      ]),
      RibbonTab('Görünüm', [
        RibbonGroup('Göster', [
          RibbonStack([
            RibbonCheck('Yatay cetvel', value: true, onChanged: (_) {}),
            RibbonCheck('Dikey cetvel', value: true, onChanged: (_) {}),
          ]),
        ]),
        const RibbonGroup('Yakınlaştır', [
          RibbonLargeButton(
            icon: FluentIcons.zoom_in_24_regular,
            fill: FluentIcons.zoom_in_24_filled,
            tint: RibbonTint.blue,
            label: 'Yakınlaştır',
            dropdown: true,
          ),
          RibbonLargeButton(
            icon: FluentIcons.document_one_page_24_regular,
            fill: FluentIcons.document_one_page_24_filled,
            tint: RibbonTint.blue,
            label: '%100',
          ),
        ]),
        const RibbonGroup('Yan panel', [
          RibbonStack([
            RibbonSmallButton(
              icon: FluentIcons.gavel_20_regular,
              fill: FluentIcons.gavel_20_filled,
              tint: RibbonTint.navy,
              label: 'UYAP dosyası',
            ),
            RibbonSmallButton(
              icon: FluentIcons.scales_20_regular,
              fill: FluentIcons.scales_20_filled,
              tint: RibbonTint.gold,
              label: 'İçtihat',
            ),
            RibbonSmallButton(
              icon: FluentIcons.history_20_regular,
              fill: FluentIcons.history_20_filled,
              tint: RibbonTint.teal,
              label: 'Belge geçmişi',
            ),
          ]),
        ]),
        const RibbonGroup('Yardım', [
          RibbonLargeButton(
            icon: FluentIcons.keyboard_24_regular,
            fill: FluentIcons.keyboard_24_filled,
            tint: RibbonTint.navy,
            label: 'Kısayollar',
          ),
        ]),
      ]),
    ];
  }
}

/// Folio's own title bar, as DesktopFrame draws it, for the ribbon to sit
/// under.
class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    final colors = RibbonColors.of(context);
    Widget icon(IconData icon) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Icon(icon, size: 16, color: colors.text),
    );
    return Container(
      height: 40,
      color: colors.band,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Image.asset(
              'assets/branding/lifeos_editor.png',
              width: 20,
              height: 20,
            ),
          ),
          const SizedBox(width: 8),
          icon(FluentIcons.save_20_regular),
          icon(FluentIcons.arrow_undo_20_regular),
          icon(FluentIcons.arrow_redo_20_regular),
          icon(FluentIcons.print_20_regular),
          const Spacer(),
          Text(
            'Dilekçe.udf',
            style: ribbonText(
              context,
              size: 12,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            '  ·  Kaydedildi',
            style: ribbonText(context, size: 12, color: colors.secondary),
          ),
          const Spacer(),
          Container(
            width: 260,
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: colors.strip,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(
                  FluentIcons.search_16_regular,
                  size: 14,
                  color: colors.secondary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Belgede ara (Ctrl+F)',
                  style: ribbonText(context, color: colors.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          icon(FluentIcons.subtract_20_regular),
          const SizedBox(width: 8),
          icon(FluentIcons.maximize_20_regular),
          const SizedBox(width: 8),
          icon(FluentIcons.dismiss_20_regular),
        ],
      ),
    );
  }
}

/// The start of a page, for scale.
class _Page extends StatelessWidget {
  const _Page();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Container(
      width: 794,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(90, 60, 90, 0),
      color: Colors.white,
      child: const Text(
        'ANKARA 3. AİLE MAHKEMESİ HÂKİMLİĞİ’NE\n\n'
        'DAVACI      : …\n'
        'DAVALI       : …\n'
        'KONU         : Boşanma ve ferileri hakkındadır.',
        style: TextStyle(
          fontFamily: 'Times New Roman',
          fontSize: 15,
          height: 1.5,
        ),
      ),
    ),
  );
}
