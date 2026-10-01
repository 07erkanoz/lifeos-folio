import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../services/fonts/document_fonts.dart';
import '../../services/editor/doc_delta_map.dart';

/// Two-row groups on desktop; the same tools remain available on narrow screens.
class EditorToolbar extends StatelessWidget {
  final QuillController controller;
  final String defaultFont;
  final double defaultFontSize;
  final VoidCallback onFind, onReplace, onPrint, onHelp;
  final VoidCallback? onHistory;

  /// Opens the case-law search beside the page.
  final VoidCallback? onCaseLaw;
  final bool caseLawOpen;

  /// Opens the UYAP case the document is written for, beside the page.
  final VoidCallback? onUyapCase;
  final bool uyapCaseOpen;

  /// The kept passages. Inserting one is inserting, like a table or a
  /// picture, so it sits with them rather than in a corner of its own.
  final VoidCallback? onSnippets;

  /// Reading the page aloud and writing down what is said.
  final VoidCallback? onReadAloud, onDictate;

  final VoidCallback? onInsertImage;
  final void Function(String key)? onToggleRegion;
  final void Function(int rows, int columns)? onInsertTable;
  final bool hasHeader, hasFooter;
  final VoidCallback onHorizontalRuler, onVerticalRuler;
  final bool showHorizontalRuler, showVerticalRuler;
  final Future<void> Function(String) onFontSelected;

  /// The width from which the strip has room for the voice's own group.
  /// Measured in Liberation Sans: the groups take 1331 pixels with it, the
  /// rest is room for a wider system font. Below it the strip keeps the
  /// voice in the editing group rather than scroll.
  static const roomyWidth = 1380.0;

  /// The width from which every tool is named, measured the same way: 1490
  /// pixels of groups, and the same room again for the system's font.
  static const namedWidth = 1550.0;

  const EditorToolbar({
    super.key,
    required this.controller,
    this.defaultFont = 'Times New Roman',
    this.defaultFontSize = 12,
    required this.onFind,
    this.onHistory,
    this.onCaseLaw,
    this.caseLawOpen = false,
    this.onUyapCase,
    this.uyapCaseOpen = false,
    required this.onReplace,
    required this.onPrint,
    this.onSnippets,
    this.onReadAloud,
    this.onDictate,
    this.onInsertImage,
    this.onToggleRegion,
    this.onInsertTable,
    this.hasHeader = false,
    this.hasFooter = false,
    required this.onHelp,
    required this.onHorizontalRuler,
    required this.onVerticalRuler,
    required this.showHorizontalRuler,
    required this.showVerticalRuler,
    required this.onFontSelected,
  });

  void toggle(Attribute attribute) {
    final current = controller.getSelectionStyle().attributes[attribute.key];
    controller.formatSelection(
      Attribute.clone(
        attribute,
        current?.value == attribute.value ? null : attribute.value,
      ),
    );
  }

  void _clear() {
    final attributes = <String, Attribute>{};
    for (final style in controller.getAllSelectionStyles()) {
      for (final attr in style.attributes.values) {
        if (attr.scope == AttributeScope.inline) attributes[attr.key] = attr;
      }
    }
    for (final attr in attributes.values) {
      controller.formatSelection(Attribute.clone(attr, null));
    }
  }

  void _size(double points) => controller.formatSelection(
    Attribute.clone(Attribute.size, '${points * 96 / 72}'),
  );

  /// Applying a heading sets Quill's own header attribute, which draws it, and
  /// clears any size or weight left on the run so the style decides how the
  /// text looks rather than whatever was applied by hand before it.
  void _heading(int? level) {
    controller.formatSelection(Attribute.clone(Attribute.header, level));
    controller.formatSelection(Attribute.clone(Attribute.size, null));
    controller.formatSelection(Attribute.clone(Attribute.bold, null));
  }

  Future<void> _customSize(BuildContext context, double value) async {
    var input = _label(value);
    final size = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yazı boyutu'),
        content: TextFormField(
          initialValue: input,
          onChanged: (value) => input = value,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Punto',
            helperText: '1–200 arasında, örneğin 10,5',
          ),
          onFieldSubmitted: (value) {
            final n = double.tryParse(value.replaceAll(',', '.'));
            if (n != null && n >= 1 && n <= 200) Navigator.pop(context, n);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              final n = double.tryParse(input.replaceAll(',', '.'));
              if (n != null && n >= 1 && n <= 200) Navigator.pop(context, n);
            },
            child: const Text('Uygula'),
          ),
        ],
      ),
    );
    // The dialog route disposes its field after its exit animation.
    if (size != null) _size(size);
  }

  static String _label(double value) => value == value.roundToDouble()
      ? '${value.round()}'
      : value.toStringAsFixed(1);

  Future<void> _font(BuildContext context, String current) async {
    final selection = controller.selection;
    final family = await showDialog<String>(
      context: context,
      builder: (_) => _FontPicker(current: current),
    );
    if (family == null) return;
    controller.updateSelection(selection, ChangeSource.local);
    controller.formatSelection(Attribute.clone(Attribute.font, family));
    await onFontSelected(family);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final scheme = Theme.of(context).colorScheme;
      final attrs = controller.getSelectionStyle().attributes;
      final font =
          attrs[Attribute.font.key]?.value?.toString() ??
          (controller.selection.isCollapsed ? defaultFont : 'Karışık');
      final heading = attrs[Attribute.header.key]?.value as int?;
      final rawSize = double.tryParse('${attrs[Attribute.size.key]?.value}');
      final points = rawSize == null ? defaultFontSize : rawSize * 72 / 96;
      final sizeLabel = rawSize == null && !controller.selection.isCollapsed
          ? '—'
          : _label(points);
      Widget button(
        IconData icon,
        String tip,
        VoidCallback? action, {
        bool selected = false,
      }) => IconButton(
        tooltip: tip,
        onPressed: action,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          maximumSize: const Size(32, 32),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          backgroundColor: selected
              ? scheme.primary.withValues(alpha: .12)
              : Colors.transparent,
          foregroundColor: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
      );
      Widget attrButton(IconData icon, String tip, Attribute attr) => button(
        icon,
        tip,
        () => toggle(attr),
        selected: attrs[attr.key]?.value == attr.value,
      );
      Widget color(bool background) => QuillToolbarColorButton(
        controller: controller,
        isBackground: background,
        options: const QuillToolbarColorButtonOptions(
          iconSize: 17,
          iconButtonFactor: 1.65,
        ),
      );
      Widget menu<T>(
        String tooltip,
        IconData icon,
        List<PopupMenuEntry<T>> items,
        ValueChanged<T> action,
      ) => PopupMenuButton<T>(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        iconSize: 18,
        constraints: const BoxConstraints(minWidth: 180),
        icon: Icon(icon),
        onSelected: action,
        itemBuilder: (_) => items,
      );
      Widget styleField() => SizedBox(
        width: 132,
        height: 30,
        child: PopupMenuButton<int>(
          tooltip: 'Paragraf stili',
          padding: EdgeInsets.zero,
          position: PopupMenuPosition.under,
          onSelected: (level) => _heading(level == 0 ? null : level),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 0, child: Text('Normal metin')),
            for (final entry in DocDeltaMap.headingNames.entries)
              PopupMenuItem(
                value: entry.key,
                child: Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: DocDeltaMap.headingSizes[entry.key],
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    DocDeltaMap.headingNames[heading] ?? 'Normal metin',
                    key: const ValueKey('editor-style-label'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: scheme.onSurface),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 16),
              ],
            ),
          ),
        ),
      );
      Widget fontField() => SizedBox(
        width: 175,
        height: 30,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          onPressed: () => _font(context, font),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  font,
                  key: const ValueKey('editor-font-label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: scheme.onSurface),
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 16),
            ],
          ),
        ),
      );
      Widget sizeField() => SizedBox(
        width: 65,
        height: 30,
        child: PopupMenuButton<double>(
          tooltip: 'Yazı boyutu (punto)',
          padding: EdgeInsets.zero,
          onSelected: (value) =>
              value == 0 ? _customSize(context, points) : _size(value),
          itemBuilder: (_) => [
            for (final value in [
              8,
              9,
              10,
              10.5,
              11,
              12,
              14,
              16,
              18,
              20,
              24,
              28,
              32,
              36,
              48,
              72,
            ])
              PopupMenuItem(value: value.toDouble(), child: Text('$value')),
            const PopupMenuItem(value: 0, child: Text('Özel punto…')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    sizeLabel,
                    key: const ValueKey('editor-font-size-label'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 16),
              ],
            ),
          ),
        ),
      );
      final characterButtons = [
        attrButton(Icons.format_bold, 'Kalın · Ctrl+B', Attribute.bold),
        attrButton(Icons.format_italic, 'İtalik · Ctrl+I', Attribute.italic),
        attrButton(
          Icons.format_underlined,
          'Altı çizili · Ctrl+U',
          Attribute.underline,
        ),
        attrButton(
          Icons.strikethrough_s,
          'Üstü çizili',
          Attribute.strikeThrough,
        ),
        attrButton(Icons.subscript, 'Alt simge', Attribute.subscript),
        attrButton(Icons.superscript, 'Üst simge', Attribute.superscript),
        color(false),
        color(true),
        button(Icons.format_clear, 'Karakter biçimini temizle', _clear),
      ];
      final alignments = [
        for (final item in [
          (
            Icons.format_align_left,
            'Sola hizala · Ctrl+L',
            Attribute.leftAlignment,
          ),
          (
            Icons.format_align_center,
            'Ortala · Ctrl+E',
            Attribute.centerAlignment,
          ),
          (
            Icons.format_align_right,
            'Sağa hizala · Ctrl+R',
            Attribute.rightAlignment,
          ),
          (
            Icons.format_align_justify,
            'İki yana yasla · Ctrl+J',
            Attribute.justifyAlignment,
          ),
        ])
          button(
            item.$1,
            item.$2,
            () => controller.formatSelection(item.$3),
            selected:
                (attrs[Attribute.align.key]?.value ?? 'left') == item.$3.value,
          ),
      ];
      final lists = [
        attrButton(
          Icons.format_list_bulleted,
          'Madde işaretleri · Ctrl+Shift+L',
          Attribute.ul,
        ),
        attrButton(
          Icons.format_list_numbered,
          'Numaralı liste · Ctrl+Shift+7',
          Attribute.ol,
        ),
        button(
          Icons.format_indent_decrease,
          'Girintiyi azalt · Ctrl+Shift+M',
          () => controller.indentSelection(false),
        ),
        button(
          Icons.format_indent_increase,
          'Girintiyi artır · Ctrl+M',
          () => controller.indentSelection(true),
        ),
        menu<double>(
          'Satır aralığı',
          Icons.format_line_spacing,
          [
            for (final value in [1.0, 1.15, 1.5, 2.0])
              CheckedPopupMenuItem(
                value: value,
                checked: attrs[Attribute.lineHeight.key]?.value == value,
                child: Text('$value satır'),
              ),
          ],
          (value) => controller.formatSelection(
            Attribute.clone(Attribute.lineHeight, value),
          ),
        ),
      ];
      Widget labeled(
        IconData icon,
        String label,
        VoidCallback action, {
        bool selected = false,
      }) => TextButton.icon(
        onPressed: action,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: selected
              ? scheme.primary.withValues(alpha: .12)
              : null,
        ),
      );
      final view = menu<String>(
        'Görünüm ve cetveller',
        Icons.straighten,
        [
          CheckedPopupMenuItem(
            value: 'horizontal',
            checked: showHorizontalRuler,
            child: const Text('Yatay cetvel'),
          ),
          CheckedPopupMenuItem(
            value: 'vertical',
            checked: showVerticalRuler,
            child: const Text('Dikey cetvel'),
          ),
        ],
        (value) =>
            value == 'horizontal' ? onHorizontalRuler() : onVerticalRuler(),
      );
      Widget regionMenu() => PopupMenuButton<String>(
        tooltip: 'Üst bilgi ve alt bilgi',
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        onSelected: (key) => onToggleRegion!(key),
        itemBuilder: (_) => [
          CheckedPopupMenuItem(
            value: 'header',
            checked: hasHeader,
            child: const Text('Üst bilgi'),
          ),
          CheckedPopupMenuItem(
            value: 'footer',
            checked: hasFooter,
            child: const Text('Alt bilgi'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'page-numbers',
            child: Text('Sayfa numarası…'),
          ),
          const PopupMenuItem(value: 'letterheads', child: Text('Antet…')),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.view_agenda_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              const Text('Üst/alt bilgi', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
      Widget group(String name, List<Widget> first, List<Widget> second) =>
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: .7),
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 32,
                  child: Row(mainAxisSize: MainAxisSize.min, children: first),
                ),
                SizedBox(
                  height: 32,
                  child: Row(mainAxisSize: MainAxisSize.min, children: second),
                ),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
      return LayoutBuilder(
        builder: (context, constraints) {
          final expanded = constraints.maxHeight > 60;
          // Where there is room, the voice has a group of its own and
          // printing its label back; where there is not, they are icons in
          // the editing group, so the strip does not have to scroll.
          final roomy = expanded && constraints.maxWidth >= roomyWidth;
          // Wider still, the tools that are only icons are named too.
          final named = expanded && constraints.maxWidth >= namedWidth;
          final overflow = menu<String>(
            'Diğer düzenleme araçları',
            Icons.more_horiz,
            [
              if (onSnippets != null)
                const PopupMenuItem(
                  value: 'snippets',
                  child: Text('Kalıp metin · Ctrl+Boşluk'),
                ),
              if (onHistory != null)
                const PopupMenuItem(
                  value: 'history',
                  child: Text('Belge geçmişi'),
                ),
              const PopupMenuItem(
                value: 'find',
                child: Text('Belgede bul · Ctrl+F'),
              ),
              const PopupMenuItem(
                value: 'replace',
                child: Text('Bul ve değiştir · Ctrl+H'),
              ),
              CheckedPopupMenuItem(
                value: 'horizontal',
                checked: showHorizontalRuler,
                child: const Text('Yatay cetvel'),
              ),
              CheckedPopupMenuItem(
                value: 'vertical',
                checked: showVerticalRuler,
                child: const Text('Dikey cetvel'),
              ),
              const PopupMenuItem(
                value: 'format',
                child: Text('Tüm biçimlendirme araçları…'),
              ),
              const PopupMenuItem(
                value: 'print',
                child: Text('Yazdır · Ctrl+P'),
              ),
              if (onUyapCase != null)
                const PopupMenuItem(value: 'uyap', child: Text('UYAP dosyası')),
              if (onReadAloud != null)
                const PopupMenuItem(value: 'read', child: Text('Sesli oku')),
              if (onDictate != null)
                const PopupMenuItem(value: 'dictate', child: Text('Sesli yaz')),
              const PopupMenuItem(
                value: 'help',
                child: Text('Klavye kısayolları'),
              ),
            ],
            (value) {
              switch (value) {
                case 'snippets':
                  onSnippets?.call();
                case 'history':
                  onHistory?.call();
                case 'find':
                  onFind();
                case 'replace':
                  onReplace();
                case 'horizontal':
                  onHorizontalRuler();
                case 'vertical':
                  onVerticalRuler();
                case 'print':
                  onPrint();
                case 'uyap':
                  onUyapCase?.call();
                case 'read':
                  onReadAloud?.call();
                case 'dictate':
                  onDictate?.call();
                case 'help':
                  onHelp();
                case 'format':
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Yazı ve paragraf'),
                      content: SingleChildScrollView(
                        child: SizedBox(
                          width: 460,
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 8,
                            children: [
                              ...characterButtons,
                              ...alignments,
                              ...lists,
                              styleField(),
                              if (onInsertTable != null)
                                TableSizeButton(onPick: onInsertTable!),
                            ],
                          ),
                        ),
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
            },
          );
          return Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: expanded
                        ? [
                            group(
                              'Geçmiş',
                              [
                                button(
                                  Icons.undo,
                                  'Geri al · Ctrl+Z',
                                  controller.hasUndo ? controller.undo : null,
                                ),
                              ],
                              [
                                button(
                                  Icons.redo,
                                  'Yinele · Ctrl+Y',
                                  controller.hasRedo ? controller.redo : null,
                                ),
                              ],
                            ),
                            group('Stil', [styleField()], const []),
                            group('Yazı tipi', [
                              fontField(),
                              const SizedBox(width: 4),
                              sizeField(),
                              button(
                                Icons.text_increase,
                                'Yazıyı büyüt',
                                () => _size((points + 1).clamp(1, 200)),
                              ),
                              button(
                                Icons.text_decrease,
                                'Yazıyı küçült',
                                () => _size((points - 1).clamp(1, 200)),
                              ),
                            ], characterButtons),
                            group('Paragraf', alignments, lists),
                            group(
                              'Düzenleme',
                              [
                                labeled(Icons.search, 'Bul', onFind),
                                labeled(
                                  Icons.find_replace,
                                  'Değiştir',
                                  onReplace,
                                ),
                              ],
                              [
                                // Ölçüldü: grubun genişliğini ilk satır
                                // belirliyor ve ikinci satıra dört simge
                                // sığıyor. "Ekle" grubuna koymak şeridi
                                // genişletip "Belge geçmişi"ni erişilmez
                                // yapmıştı. Dar şeritte Yazdır, Dosya
                                // menüsünde ve Ctrl+P'de de durduğu için
                                // etiketsiz.
                                if (roomy)
                                  labeled(
                                    Icons.print_outlined,
                                    'Yazdır',
                                    onPrint,
                                  )
                                else
                                  button(
                                    Icons.print_outlined,
                                    'Yazdır · Ctrl+P',
                                    onPrint,
                                  ),
                                if (onSnippets != null && named)
                                  Tooltip(
                                    message: 'Kalıp metin · Ctrl+Boşluk',
                                    child: labeled(
                                      Icons.bookmark_add_outlined,
                                      'Kalıp metin',
                                      onSnippets!,
                                    ),
                                  )
                                else if (onSnippets != null)
                                  button(
                                    Icons.bookmark_add_outlined,
                                    'Kalıp metin · Ctrl+Boşluk',
                                    onSnippets,
                                  ),
                                if (!roomy && onReadAloud != null)
                                  button(
                                    Icons.record_voice_over_outlined,
                                    'Sesli oku · seçimi ya da imleçten sonrasını',
                                    onReadAloud,
                                  ),
                                if (!roomy && onDictate != null)
                                  button(
                                    Icons.mic_none_rounded,
                                    'Sesli yaz · söylediğiniz imlecin yerine yazılır',
                                    onDictate,
                                  ),
                              ],
                            ),
                            if (roomy &&
                                (onReadAloud != null || onDictate != null))
                              group(
                                'Ses',
                                [
                                  if (onReadAloud != null)
                                    Tooltip(
                                      message: 'Seçimi ya da imleçten sonrasını okur',
                                      child: labeled(
                                        Icons.record_voice_over_outlined,
                                        'Sesli oku',
                                        onReadAloud!,
                                      ),
                                    ),
                                ],
                                [
                                  if (onDictate != null)
                                    Tooltip(
                                      message:
                                          'Söylediğinizi imlecin yerine yazar',
                                      child: labeled(
                                        Icons.mic_none_rounded,
                                        'Sesli yaz',
                                        onDictate!,
                                      ),
                                    ),
                                ],
                              ),
                            if (onInsertImage != null ||
                                onToggleRegion != null ||
                                onInsertTable != null)
                              group(
                                'Ekle',
                                [
                                  if (onInsertTable != null)
                                    TableSizeButton(onPick: onInsertTable!),
                                  if (onInsertImage != null)
                                    labeled(
                                      Icons.image_outlined,
                                      'Görsel',
                                      onInsertImage!,
                                    ),
                                ],
                                [if (onToggleRegion != null) regionMenu()],
                              ),
                            group(
                              'Görünüm',
                              named
                                  ? [
                                      view,
                                      if (onHistory != null)
                                        labeled(
                                          Icons.history_rounded,
                                          'Belge geçmişi',
                                          onHistory!,
                                        ),
                                      if (onUyapCase != null)
                                        labeled(
                                          Icons.gavel_rounded,
                                          'UYAP dosyası',
                                          onUyapCase!,
                                          selected: uyapCaseOpen,
                                        ),
                                    ]
                                  : [
                                      view,
                                      if (onHistory != null)
                                        button(
                                          Icons.history_rounded,
                                          'Belge geçmişi',
                                          onHistory,
                                        ),
                                      if (onCaseLaw != null)
                                        button(
                                          Icons.balance_outlined,
                                          'İçtihat ara',
                                          onCaseLaw,
                                          selected: caseLawOpen,
                                        ),
                                      if (onUyapCase != null)
                                        button(
                                          Icons.gavel_rounded,
                                          'UYAP dosyası',
                                          onUyapCase,
                                          selected: uyapCaseOpen,
                                        ),
                                    ],
                              named
                                  ? [
                                      if (onCaseLaw != null)
                                        labeled(
                                          Icons.balance_outlined,
                                          'İçtihat ara',
                                          onCaseLaw!,
                                          selected: caseLawOpen,
                                        ),
                                      Tooltip(
                                        message: 'Klavye kısayolları',
                                        child: labeled(
                                          Icons.keyboard_outlined,
                                          'Kısayollar',
                                          onHelp,
                                        ),
                                      ),
                                    ]
                                  : [
                                      button(
                                        Icons.keyboard_outlined,
                                        'Klavye kısayolları',
                                        onHelp,
                                      ),
                                    ],
                            ),
                          ]
                        : [
                            button(
                              Icons.undo,
                              'Geri al · Ctrl+Z',
                              controller.hasUndo ? controller.undo : null,
                            ),
                            button(
                              Icons.redo,
                              'Yinele · Ctrl+Y',
                              controller.hasRedo ? controller.redo : null,
                            ),
                            fontField(),
                            const SizedBox(width: 4),
                            sizeField(),
                            ...characterButtons.take(3),
                            button(
                              Icons.find_replace,
                              'Bul ve değiştir · Ctrl+H',
                              onReplace,
                            ),
                            view,
                            if (onCaseLaw != null)
                              button(
                                Icons.balance_outlined,
                                'İçtihat ara',
                                onCaseLaw,
                                selected: caseLawOpen,
                              ),
                            if (onUyapCase != null)
                              button(
                                Icons.gavel_rounded,
                                'UYAP dosyası',
                                onUyapCase,
                                selected: uyapCaseOpen,
                              ),
                          ],
                  ),
                ),
              ),
              overflow,
            ],
          );
        },
      );
    },
  );
}

class _FontPicker extends StatefulWidget {
  final String current;
  const _FontPicker({required this.current});
  @override
  State<_FontPicker> createState() => _FontPickerState();
}

class _FontPickerState extends State<_FontPicker> {
  String _query = '';
  List<String> _families = DocumentFonts.families;
  @override
  void initState() {
    super.initState();
    DocumentFonts.prepare().then((_) {
      if (mounted) setState(() => _families = DocumentFonts.families);
    });
  }

  @override
  Widget build(BuildContext context) {
    final matches = _families
        .where((font) => font.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return AlertDialog(
      title: const Text('Yazı tipi'),
      content: SizedBox(
        width: 420,
        height: (MediaQuery.sizeOf(context).height * .48).clamp(100, 440),
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Yazı tipi ara…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: matches.isEmpty
                  ? const Center(child: Text('Yazı tipi bulunamadı'))
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (_, index) => ListTile(
                        dense: true,
                        title: Text(matches[index]),
                        selected: matches[index] == widget.current,
                        trailing: matches[index] == widget.current
                            ? const Icon(Icons.check, size: 18)
                            : null,
                        onTap: () => Navigator.pop(context, matches[index]),
                      ),
                    ),
            ),
            Text(
              '${_families.length} yazı tipi · Sistem ve belge yazı tipleri',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

/// Word's grid for choosing how big a new table should be: run the cursor
/// across the squares and the size follows it.
class TableSizeButton extends StatefulWidget {
  final void Function(int rows, int columns) onPick;
  const TableSizeButton({super.key, required this.onPick});

  @override
  State<TableSizeButton> createState() => _TableSizeButtonState();
}

class _TableSizeButtonState extends State<TableSizeButton> {
  static const _rows = 6, _columns = 6, _cell = 17.0;
  int _hoverRow = 0, _hoverColumn = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<void>(
      tooltip: 'Tablo ekle',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      itemBuilder: (_) => [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: StatefulBuilder(
            builder: (context, setGrid) => Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var r = 1; r <= _rows; r++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var c = 1; c <= _columns; c++)
                          MouseRegion(
                            onEnter: (_) => setGrid(() {
                              _hoverRow = r;
                              _hoverColumn = c;
                            }),
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                widget.onPick(r, c);
                              },
                              child: Container(
                                key: ValueKey('table-size-$r-$c'),
                                width: _cell,
                                height: _cell,
                                margin: const EdgeInsets.all(1),
                                decoration: BoxDecoration(
                                  color: r <= _hoverRow && c <= _hoverColumn
                                      ? scheme.primary.withValues(alpha: .35)
                                      : scheme.surfaceContainerHighest,
                                  border: Border.all(
                                    color: scheme.outlineVariant,
                                    width: .6,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Text(
                    _hoverRow == 0
                        ? 'Boyut seçin'
                        : '$_hoverRow × $_hoverColumn tablo',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.grid_on_outlined,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            const Text('Tablo', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
