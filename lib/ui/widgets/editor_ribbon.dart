import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

/// The editor's ribbon tabs (docs/design/editor-serit-taslak.png), after
/// Banaozel's: Giriş holds the writing tools, Hukuk the petition, the case,
/// the signature, the agenda and research; Ekle and Görünüm what is put in
/// a document and how it is looked at.
enum RibbonTab {
  home('Giriş'),
  legal('Hukuk'),
  insert('Ekle'),
  view('Görünüm');

  const RibbonTab(this.label);
  final String label;
}

/// The tab chosen, shared by the editor and the heading that shows the tabs,
/// and kept while the app runs: the next document opens on it.
final editorRibbonTab = ValueNotifier<RibbonTab>(RibbonTab.home);

/// The tabs in a heading: the chosen one in the primary colour, underlined.
class EditorRibbonTabs extends StatelessWidget {
  const EditorRibbonTabs({super.key, this.height = 48});
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<RibbonTab>(
      valueListenable: editorRibbonTab,
      builder: (context, chosen, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tab in RibbonTab.values)
            InkWell(
              key: ValueKey('ribbon-tab-${tab.name}'),
              onTap: () => editorRibbonTab.value = tab,
              child: Container(
                height: height,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: tab == chosen
                          ? scheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  tab.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: tab == chosen
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: tab == chosen
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The tabs as one button and a menu, where no heading shows them: a phone,
/// a window of the editor alone without its frame.
class RibbonTabPicker extends StatelessWidget {
  const RibbonTabPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<RibbonTab>(
      valueListenable: editorRibbonTab,
      builder: (context, chosen, _) => MenuAnchor(
        menuChildren: [
          for (final tab in RibbonTab.values)
            MenuItemButton(
              key: ValueKey('ribbon-pick-${tab.name}'),
              onPressed: () => editorRibbonTab.value = tab,
              trailingIcon: tab == chosen
                  ? Icon(Icons.check_rounded, size: 18, color: scheme.primary)
                  : const SizedBox(width: 18),
              child: Text(tab.label),
            ),
        ],
        builder: (context, menu, _) => MediaQuery.sizeOf(context).width < 600
            // A phone keeps the row's room for its tools: an icon alone.
            ? IconButton(
                key: const ValueKey('ribbon-tab-picker'),
                tooltip: 'Şerit: ${chosen.label}',
                onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                style: IconButton.styleFrom(
                  backgroundColor: scheme.primary.withValues(alpha: .08),
                  foregroundColor: scheme.primary,
                  minimumSize: const Size(32, 32),
                  fixedSize: const Size(32, 32),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.view_week_outlined, size: 18),
              )
            : TextButton(
                key: const ValueKey('ribbon-tab-picker'),
                onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: scheme.primary.withValues(alpha: .08),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chosen.label,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Icon(Icons.expand_more_rounded, size: 18),
                  ],
                ),
              ),
      ),
    );
  }
}

// The ribbon's parts, as the Giriş tab draws them: buttons 30 high with a
// 16 px icon and 12 px text, groups of two rows with their name under them.

Widget ribbonButton(
  BuildContext context,
  IconData icon,
  String label,
  VoidCallback? onPressed, {
  bool selected = false,
  String? tooltip,
  Key? key,
  Widget? badge,
}) {
  final scheme = Theme.of(context).colorScheme;
  final button = TextButton.icon(
    key: key,
    onPressed: onPressed,
    icon: Icon(icon, size: 16),
    label: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        ?badge,
      ],
    ),
    style: TextButton.styleFrom(
      minimumSize: const Size(0, 30),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: selected ? scheme.primary : scheme.onSurface,
      iconColor: selected ? scheme.primary : scheme.onSurfaceVariant,
      backgroundColor: selected ? scheme.primary.withValues(alpha: .12) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
  );
  return tooltip == null ? button : Tooltip(message: tooltip, child: button);
}

/// A button that opens a menu, a chevron after its name.
Widget ribbonMenu(
  BuildContext context,
  IconData icon,
  String label,
  List<Widget> items, {
  Key? key,
  bool enabled = true,
  String? tooltip,
}) => MenuAnchor(
  menuChildren: items,
  builder: (context, menu, _) => ribbonButton(
    context,
    icon,
    label,
    enabled && items.isNotEmpty
        ? () => menu.isOpen ? menu.close() : menu.open()
        : null,
    key: key,
    tooltip: tooltip,
    badge: Icon(
      Icons.expand_more_rounded,
      size: 15,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  ),
);

/// A tall button, its icon over its name: the ribbon's main actions.
Widget ribbonBigButton(
  BuildContext context,
  IconData icon,
  String label,
  VoidCallback? onPressed, {
  bool primary = false,
  String? tooltip,
  Key? key,
}) {
  final scheme = Theme.of(context).colorScheme;
  final fill = primary ? scheme.primary : Colors.transparent;
  final ink = primary
      ? scheme.onPrimary
      : onPressed == null
      ? scheme.onSurfaceVariant.withValues(alpha: .5)
      : scheme.onSurface;
  final button = Material(
    color: onPressed == null && primary ? fill.withValues(alpha: .4) : fill,
    borderRadius: BorderRadius.circular(6),
    child: InkWell(
      key: key,
      borderRadius: BorderRadius.circular(6),
      onTap: onPressed,
      child: SizedBox(
        width: 64,
        height: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: primary ? ink : scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(fontSize: 11, height: 1.15, color: ink),
            ),
          ],
        ),
      ),
    ),
  );
  return Tooltip(
    message: tooltip ?? label.replaceAll('\n', ' '),
    child: button,
  );
}

/// A group: its rows, and its name under them.
Widget ribbonGroup(
  BuildContext context,
  String name,
  List<List<Widget>> rows, {
  bool last = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      border: last
          ? null
          : Border(
              right: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .7),
              ),
            ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (rows.length == 1)
          SizedBox(
            height: 66,
            child: Row(mainAxisSize: MainAxisSize.min, children: rows.first),
          )
        else
          for (final row in rows.take(2))
            SizedBox(
              height: 33,
              child: Row(mainAxisSize: MainAxisSize.min, children: row),
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
}

/// The groups in a row, scrolled sideways when the window is narrower than
/// all of them; the "…" menu kept at the right.
Widget ribbonStrip(List<Widget> groups, {Widget? more}) => Row(
  children: [
    Expanded(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: groups),
      ),
    ),
    ?more,
  ],
);

Widget ribbonDivider(BuildContext context) => Container(
  width: 1,
  height: 24,
  margin: const EdgeInsets.symmetric(horizontal: 4),
  color: Theme.of(context).colorScheme.outlineVariant,
);

/// "…": what a short ribbon has no room for.
Widget ribbonMore(String tooltip, List<Widget> items, {Key? key}) => MenuAnchor(
  menuChildren: items,
  builder: (context, menu, _) => IconButton(
    key: key,
    tooltip: tooltip,
    icon: const Icon(Icons.more_horiz, size: 18),
    onPressed: () => menu.isOpen ? menu.close() : menu.open(),
  ),
);

/// The case the document is written for, on the right of the ribbon.
class RibbonCaseChip extends StatelessWidget {
  const RibbonCaseChip({
    super.key,
    required this.court,
    required this.number,
    required this.onPressed,
    this.short = false,
  });
  final String court, number;
  final VoidCallback onPressed;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final court = this.court.replaceFirst(
      RegExp(r'\s+Mahkemesi$', caseSensitive: false),
      '',
    );
    return Tooltip(
      message: '${this.court} · $number\nUYAP dosya panelini aç',
      child: InkWell(
        key: const ValueKey('ribbon-case-chip'),
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.gavel_rounded,
                size: 15,
                color: Color(0xFF139C8B),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  short ? number : '$court · $number',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// The petition's tools, written into the document at the cursor.

/// Turkish capitals: i is İ.
String trUpper(String s) => s.replaceAll('i', 'İ').toUpperCase();

/// "07.10.2026".
String todayDotted([DateTime? now]) {
  final n = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(n.day)}.${two(n.month)}.${n.year}';
}

/// A line of a template: its text, where it stands, whether it is bold.
typedef PetitionLine = (String text, Attribute<String?> align, bool bold);

class PetitionTools {
  PetitionTools(this.controller);
  final QuillController controller;

  static const sections = [
    'AÇIKLAMALAR',
    'DELİLLER',
    'HUKUKİ SEBEPLER',
    'HUKUKİ DELİLLER',
    'SONUÇ VE TALEP',
  ];
  static const parties = [
    'DAVACI',
    'DAVALI',
    'DAVACILAR',
    'DAVALILAR',
    'VEKİLİ',
    'DOSYA NO',
    'KONU',
  ];
  static const styles = {
    'court': 'Mahkeme başlığı (ortalı, kalın)',
    'section': 'Bölüm başlığı (sola, kalın)',
    'body': 'Gövde (iki yana yaslı)',
    'signature': 'İmza bloğu (sağa)',
    'normal': 'Normal',
  };

  int get _cursor {
    final length = controller.document.length - 1;
    final at = controller.selection.baseOffset;
    return at < 0 || at > length ? length : at;
  }

  /// [text] as a paragraph of its own at the cursor: a line begun is closed
  /// first.
  void paragraph(
    String text, {
    bool bold = false,
    Attribute<String?> align = Attribute.leftAlignment,
  }) {
    final plain = controller.document.toPlainText();
    final index = _cursor;
    final before = plain.substring(0, index.clamp(0, plain.length));
    final lead = before.isEmpty || before.endsWith('\n') ? '' : '\n';
    _write(index, [
      if (lead.isNotEmpty) (lead, null),
      if (text.isNotEmpty) (text, bold ? {'bold': true} : null),
      // A line's alignment sits on its end.
      ('\n', align.value == null ? null : {align.key: align.value}),
    ], index + lead.length + text.length + 1);
  }

  /// [parts] written at [index] as they are, past the editor's typing rules
  /// (which carry the last line's bold onto the next one's end), the cursor
  /// then at [cursor].
  void _write(
    int index,
    List<(String, Map<String, dynamic>?)> parts,
    int cursor,
  ) {
    final delta = Delta()..retain(index);
    for (final (text, attributes) in parts) {
      delta.insert(text, attributes);
    }
    controller.compose(
      delta,
      TextSelection.collapsed(offset: cursor),
      ChangeSource.local,
    );
  }

  /// "DAVALI          : ", the label padded to one column with spaces, as
  /// UYAP keeps them; the cursor after the colon.
  void party(String label) {
    final upper = trUpper(label);
    final body = '$upper${' ' * (16 - upper.length).clamp(1, 40)}: ';
    final plain = controller.document.toPlainText();
    final index = _cursor;
    final before = plain.substring(0, index.clamp(0, plain.length));
    final lead = before.isEmpty || before.endsWith('\n') ? '' : '\n';
    _write(index, [
      if (lead.isNotEmpty) (lead, null),
      (body, {'bold': true}),
      ('\n', null),
    ], index + lead.length + body.length);
  }

  void date() => paragraph(todayDotted(), align: Attribute.rightAlignment);

  void section(String name) => paragraph(trUpper(name), bold: true);

  void signature({String role = 'Vekili', String lawyer = 'Av. [Ad Soyad]'}) {
    paragraph(todayDotted(), align: Attribute.rightAlignment);
    paragraph('Saygılarımla,', align: Attribute.rightAlignment);
    paragraph(role, align: Attribute.rightAlignment);
    paragraph(lawyer, bold: true, align: Attribute.rightAlignment);
  }

  /// A style on the lines chosen.
  void style(String key) {
    switch (key) {
      case 'court':
        controller.formatSelection(Attribute.centerAlignment);
        controller.formatSelection(Attribute.bold);
      case 'section':
        controller.formatSelection(Attribute.leftAlignment);
        controller.formatSelection(Attribute.bold);
      case 'body':
        controller.formatSelection(Attribute.justifyAlignment);
        controller.formatSelection(Attribute.clone(Attribute.bold, null));
      case 'signature':
        controller.formatSelection(Attribute.rightAlignment);
      default:
        controller.formatSelection(Attribute.leftAlignment);
        controller.formatSelection(Attribute.clone(Attribute.bold, null));
    }
  }

  /// The document emptied and [lines] written in its place.
  void replaceWith(List<PetitionLine> lines) {
    final length = controller.document.length - 1;
    if (length > 0) {
      controller.replaceText(
        0,
        length,
        '',
        const TextSelection.collapsed(offset: 0),
      );
    }
    controller.updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    for (final (text, align, bold) in lines) {
      paragraph(text, bold: bold, align: align);
    }
  }

  bool get empty => controller.document.toPlainText().trim().isEmpty;
}

/// A petition's skeleton, filled from the case where the document has one.
class PetitionTemplate {
  const PetitionTemplate(this.name, this.build);
  final String name;
  final List<PetitionLine> Function(PetitionCase? from) build;
}

/// What a template takes from the case the document belongs to.
class PetitionCase {
  const PetitionCase({required this.court, required this.number, this.lawyer});
  final String court, number;
  final String? lawyer;
}

PetitionLine _line(
  String text, {
  Attribute<String?> align = Attribute.leftAlignment,
  bool bold = false,
}) => (text, align, bold);

PetitionLine _party(String label, String value) {
  final upper = trUpper(label);
  return _line('$upper${' ' * (16 - upper.length).clamp(1, 40)}: $value');
}

PetitionLine _court(String text) =>
    _line(text, align: Attribute.centerAlignment, bold: true);

PetitionLine _head(String text) => _line(text, bold: true);

PetitionLine _justified(String text) =>
    _line(text, align: Attribute.justifyAlignment);

/// "ANTALYA 3. ASLİYE HUKUK MAHKEMESİ’NE".
String _courtLine(PetitionCase? from, String fallback) =>
    from == null ? fallback : '${trUpper(from.court)}’NE';

List<PetitionLine> _signature(PetitionCase? from, String role) => [
  _line(''),
  _line(todayDotted(), align: Attribute.rightAlignment),
  _line(role, align: Attribute.rightAlignment),
  _line(
    from?.lawyer ?? 'Av. [Ad Soyad]',
    align: Attribute.rightAlignment,
    bold: true,
  ),
];

final petitionTemplates = <PetitionTemplate>[
  PetitionTemplate(
    'Dava dilekçesi',
    (c) => [
      _court(_courtLine(c, '[…] NÖBETÇİ [ASLİYE HUKUK] MAHKEMESİNE')),
      _line(''),
      _party('DAVACI', '[Ad Soyad] (T.C. …)'),
      _party('VEKİLİ', '${c?.lawyer ?? 'Av. [Ad Soyad]'} ([…] Barosu)'),
      _party('DAVALI', '[Ad Soyad] (T.C. …)'),
      _party('KONU', '[…] talebimizden ibarettir.'),
      _line(''),
      _head('AÇIKLAMALAR'),
      _justified('1- […]'),
      _line(''),
      _head('HUKUKİ SEBEPLER'),
      _line('[İlgili kanun ve maddeler]'),
      _head('HUKUKİ DELİLLER'),
      _line('[Deliller]'),
      _head('SONUÇ VE TALEP'),
      _justified(
        'Yukarıda açıklanan nedenlerle davamızın KABULÜ ile […]; yargılama '
        'giderleri ve vekalet ücretinin karşı tarafa yükletilmesine karar '
        'verilmesini saygıyla talep ederiz.',
      ),
      ..._signature(c, 'Davacı Vekili'),
    ],
  ),
  PetitionTemplate(
    'Cevap dilekçesi',
    (c) => [
      _court(_courtLine(c, '[…] [ASLİYE HUKUK] MAHKEMESİNE')),
      _line(''),
      _party('DOSYA NO', c?.number ?? '20…/…'),
      _line('CEVAP VEREN'),
      _party('DAVALI', '[Ad Soyad] (T.C. …)'),
      _party('VEKİLİ', '${c?.lawyer ?? 'Av. [Ad Soyad]'} ([…] Barosu)'),
      _party('DAVACI', '[Ad Soyad]'),
      _party('KONU', 'Davaya karşı cevaplarımızın sunulmasıdır.'),
      _line(''),
      _head('AÇIKLAMALAR'),
      _justified('1- […]'),
      _line(''),
      _head('HUKUKİ SEBEPLER'),
      _line('[İlgili kanun ve maddeler]'),
      _head('HUKUKİ DELİLLER'),
      _line('[Deliller]'),
      _head('SONUÇ VE TALEP'),
      _justified(
        'Yukarıda açıklanan nedenlerle haksız ve mesnetsiz davanın REDDİNE, '
        'yargılama giderleri ve vekalet ücretinin davacıya yükletilmesine '
        'karar verilmesini saygıyla talep ederiz.',
      ),
      ..._signature(c, 'Davalı Vekili'),
    ],
  ),
  PetitionTemplate(
    'İstinaf dilekçesi',
    (c) => [
      _court('[…] BÖLGE ADLİYE MAHKEMESİ İLGİLİ HUKUK DAİRESİNE'),
      _line('Gönderilmek Üzere', align: Attribute.centerAlignment),
      _court(_courtLine(c, '[…] [ASLİYE HUKUK] MAHKEMESİNE')),
      _line(''),
      _party('DOSYA NO', c?.number ?? '20…/… Esas – 20…/… Karar'),
      _party('İSTİNAF EDEN', '[Davacı/Davalı] – [Ad Soyad]'),
      _party('VEKİLİ', '${c?.lawyer ?? 'Av. [Ad Soyad]'} ([…] Barosu)'),
      _party('KARŞI TARAF', '[Ad Soyad]'),
      _party('KONU', '[…] kararının KALDIRILMASI istemidir.'),
      _party('TEBLİĞ TARİHİ', '…/…/20…'),
      _line(''),
      _head('AÇIKLAMALAR VE İSTİNAF SEBEPLERİ'),
      _justified('1- […]'),
      _line(''),
      _head('HUKUKİ SEBEPLER'),
      _line('HMK m.341 vd. ve ilgili mevzuat.'),
      _head('SONUÇ VE TALEP'),
      _justified(
        'Yukarıda açıklanan ve re’sen gözetilecek nedenlerle; istinaf '
        'başvurumuzun KABULÜ ile […] kararının KALDIRILMASINA karar '
        'verilmesini saygıyla talep ederiz.',
      ),
      ..._signature(c, 'İstinaf Eden Vekili'),
    ],
  ),
  PetitionTemplate(
    'İcra (ödeme emrine) itiraz',
    (c) => [
      _court('[…] İCRA HUKUK MAHKEMESİNE'),
      _line(''),
      _party('İCRA DOSYA NO', c?.number ?? '[…] İcra Müd. 20…/… E.'),
      _party('İTİRAZ EDEN', '[Ad Soyad] (T.C. …)'),
      _party('VEKİLİ', '${c?.lawyer ?? 'Av. [Ad Soyad]'} ([…] Barosu)'),
      _party('ALACAKLI', '[Ad Soyad]'),
      _party('KONU', 'Ödeme/icra emrine itirazımızın sunulmasıdır.'),
      _party('TEBLİĞ TARİHİ', '…/…/20…'),
      _line(''),
      _head('AÇIKLAMALAR'),
      _justified('1- Borca / imzaya / faize İTİRAZ ediyoruz. […]'),
      _line(''),
      _head('HUKUKİ SEBEPLER'),
      _line('İİK m.62 vd. ve ilgili mevzuat.'),
      _head('SONUÇ VE TALEP'),
      _justified(
        'Yukarıda açıklanan nedenlerle takibe İTİRAZIMIZIN KABULÜ ile '
        'takibin DURDURULMASINA/İPTALİNE karar verilmesini saygıyla talep '
        'ederiz.',
      ),
      ..._signature(c, 'İtiraz Eden (Borçlu) Vekili'),
    ],
  ),
  PetitionTemplate(
    'Bilirkişi raporuna itiraz',
    (c) => [
      _court(_courtLine(c, '[…] [ASLİYE HUKUK] MAHKEMESİNE')),
      _line(''),
      _party('DOSYA NO', c?.number ?? '20…/…'),
      _party('İTİRAZ EDEN', '[Davacı/Davalı] – [Ad Soyad]'),
      _party('VEKİLİ', '${c?.lawyer ?? 'Av. [Ad Soyad]'} ([…] Barosu)'),
      _party('KONU', 'Bilirkişi raporuna itirazlarımızın sunulmasıdır.'),
      _line(''),
      _head('AÇIKLAMALAR'),
      _justified('1- Dosyaya sunulan … tarihli bilirkişi raporu […]'),
      _line(''),
      _head('SONUÇ VE TALEP'),
      _justified(
        'Yukarıda açıklanan nedenlerle rapora itirazlarımızın kabulü ile '
        'dosyanın yeni bir bilirkişi heyetine tevdiine karar verilmesini '
        'saygıyla talep ederiz.',
      ),
      ..._signature(c, 'Vekili'),
    ],
  ),
];
