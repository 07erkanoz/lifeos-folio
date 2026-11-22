import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/evrak_file.dart';
import '../../services/search/library_controller.dart';
import '../../services/search/search_models.dart';
import '../../services/voice/folio_ajan.dart';
import '../../services/voice/live_conversation.dart';
import '../library/search_controls.dart';
import '../library/search_results.dart';
import 'ajan_theme.dart';
import 'folio_mark.dart';

/// The compact palette of the approved mock-up ("Birleşik"): the search on
/// the left, what is chosen on the right (a document's passages, or Folio
/// Ajan's answer), the day when nothing is typed. The library's own search,
/// as it always was; Folio Ajan is asked only on purpose (its row, Tab, or
/// the microphone): typing never sends anything anywhere.
class QuickSearchPalette extends StatefulWidget {
  final LibraryController library;
  final ValueChanged<EvrakFile> onOpen;
  final VoidCallback onDismiss;
  final VoidCallback onMain;

  /// Folio Ajan; none, the palette is the search alone.
  final FolioAjan? ajan;
  final VoidCallback? onJarvis;
  const QuickSearchPalette({
    super.key,
    required this.library,
    required this.onOpen,
    required this.onDismiss,
    required this.onMain,
    this.ajan,
    this.onJarvis,
  });
  @override
  State<QuickSearchPalette> createState() => _QuickSearchPaletteState();
}

class _QuickSearchPaletteState extends State<QuickSearchPalette> {
  late final TextEditingController _text;
  final _focus = FocusNode();
  final _scroll = ScrollController();
  int _selected = 0;
  String? _selectedPath;
  final _passages = <String, Future<DocumentPassages>>{};

  static const _rowHeight = 62.0;

  FolioAjan? get _ajan =>
      widget.ajan != null && widget.ajan!.available ? widget.ajan : null;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.library.query);
    widget.library.addListener(_changed);
    widget.ajan?.addListener(_changed);
    widget.ajan?.loadSettings();
    if (widget.ajan != null && widget.ajan!.brief == null) {
      widget.ajan!.loadBrief();
    }
    widget.library.searchNow();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
        _text.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _text.text.length,
        );
      }
    });
  }

  void _changed() {
    if (!mounted) return;
    if (_text.text != widget.library.query) _text.text = widget.library.query;
    final index = widget.library.hits.indexWhere(
      (hit) => hit.file.path == _selectedPath,
    );
    if (index >= 0) _selected = index;
    _selected = _selected.clamp(0, math.max(0, widget.library.hits.length - 1));
    setState(() {});
  }

  @override
  void dispose() {
    widget.library.removeListener(_changed);
    widget.ajan?.removeListener(_changed);
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _move(int delta) {
    final hits = widget.library.hits;
    if (hits.isEmpty) return;
    setState(() {
      _selected = (_selected + delta).clamp(0, hits.length - 1);
      _selectedPath = hits[_selected].file.path;
    });
    if (_scroll.hasClients) {
      final top = _selected * _rowHeight;
      final view = _scroll.position.viewportDimension;
      if (top < _scroll.offset) {
        _scroll.jumpTo(top);
      } else if (top + _rowHeight > _scroll.offset + view) {
        _scroll.jumpTo(
          (top + _rowHeight - view).clamp(0, _scroll.position.maxScrollExtent),
        );
      }
    }
  }

  void _open() {
    if (widget.library.searching || widget.library.hits.isEmpty) return;
    widget.library.rememberQuery();
    widget.onOpen(widget.library.hits[_selected].file);
  }

  void _askAgent([String? text]) {
    final ajan = _ajan;
    final q = (text ?? _text.text).trim();
    if (ajan == null || q.isEmpty) return;
    if (ajan.voice.active) {
      ajan.voice.send(q);
    } else {
      ajan.ask(q);
    }
  }

  bool get _agentShown {
    final a = _ajan;
    return a != null &&
        (a.question.isNotEmpty || a.voice.active || a.voice.lines.isNotEmpty);
  }

  void _forgetAgent() {
    final a = _ajan;
    if (a == null) return;
    if (a.voice.active) a.voice.stop();
    a.clearAnswer();
    a.voice.lines.clear();
  }

  void _clear() {
    _forgetAgent();
    widget.library.setQuery('');
    _text.clear();
    _focus.requestFocus();
    setState(() {});
  }

  void _escape() {
    if (_agentShown) {
      _forgetAgent();
      setState(() {});
      return;
    }
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final ajan = _ajan;
    // The palette is the approved dark card, unless the lawyer chose light.
    final c = AjanColors.of(context, ajan?.dark ?? true);
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.enter): _open,
        if (ajan != null)
          const SingleActivator(LogicalKeyboardKey.tab): _askAgent,
        if (widget.onJarvis != null && ajan != null)
          const SingleActivator(LogicalKeyboardKey.keyJ, control: true):
              widget.onJarvis!,
      },
      child: Theme(
        // The search highlight reads the theme: light text on the dark card.
        data: theme.copyWith(
          // Every Material inside resets the text to the theme's: the card's.
          textTheme: theme.textTheme.apply(
            bodyColor: c.text,
            displayColor: c.text,
            fontFamily: 'Inter',
          ),
          colorScheme: theme.colorScheme.copyWith(
            primary: AjanColors.blue,
            onSurface: c.dark ? const Color(0xFFF2F5FA) : c.text,
          ),
        ),
        child: Material(
          color: c.surface,
          child: DefaultTextStyle(
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontFamily: 'Inter',
              height: 1.35,
            ),
            child: Column(
              children: [
                _header(c, ajan),
                SizedBox(
                  height: 2,
                  child: widget.library.searching || (ajan?.asking ?? false)
                      ? const LinearProgressIndicator(
                          minHeight: 2,
                          color: AjanColors.blue,
                          backgroundColor: Colors.transparent,
                        )
                      : null,
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final split = box.maxWidth >= 600;
                      final empty =
                          widget.library.query.trim().isEmpty && ajan != null;
                      if (!split) {
                        return _agentShown
                            ? _agentPane(c, ajan!)
                            : empty
                            ? _today(c, ajan)
                            : _left(c, ajan);
                      }
                      final divider = Container(width: 1, color: c.border);
                      if (empty) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _today(c, ajan)),
                            divider,
                            Expanded(
                              child: _agentShown
                                  ? _agentPane(c, ajan)
                                  : _suggest(c, ajan),
                            ),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: math.min(360, box.maxWidth * .5),
                            child: _left(c, ajan),
                          ),
                          divider,
                          Expanded(child: _right(c, ajan)),
                        ],
                      );
                    },
                  ),
                ),
                _footer(c, ajan),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(AjanColors c, FolioAjan? ajan) {
    final talking = ajan?.voice.active ?? false;
    final voiceOn = ajan?.settings.on ?? false;
    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(20, 0, 14, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 22, color: c.faint),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: _focus,
              autofocus: true,
              cursorColor: AjanColors.blue,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                letterSpacing: -.2,
                color: c.dark ? const Color(0xFFF2F5FA) : c.text,
              ),
              decoration: InputDecoration(
                hintText: ajan == null
                    ? 'Evrak ara…'
                    : 'Evrak ara ya da Folio Ajan’a sor…',
                hintStyle: TextStyle(
                  color: c.dark ? const Color(0xFF7D879A) : c.muted,
                  fontWeight: FontWeight.w400,
                ),
                filled: false,
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (value) {
                _selected = 0;
                _selectedPath = null;
                widget.library.setQuery(value);
              },
              onSubmitted: (_) => _open(),
            ),
          ),
          if (_text.text.isNotEmpty || _agentShown) ...[
            const SizedBox(width: 14),
            Tooltip(
              message: 'Temizle',
              child: InkWell(
                onTap: _clear,
                borderRadius: BorderRadius.circular(6),
                child: Kbd('Esc', colors: c),
              ),
            ),
          ],
          const SizedBox(width: 14),
          if (ajan != null)
            Tooltip(
              message: !voiceOn
                  ? 'Ses kapalı: Ayarlar › Hızlı arama'
                  : talking
                  ? 'Konuşmayı bitir'
                  : 'Sesle sor',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: voiceOn
                      ? const [
                          BoxShadow(
                            color: Color.fromRGBO(37, 99, 235, .35),
                            blurRadius: 20,
                            offset: Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Material(
                  color: voiceOn ? AjanColors.blue : c.panel,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: voiceOn ? ajan.toggleTalk : null,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        talking
                            ? Icons.graphic_eq_rounded
                            : Icons.mic_none_rounded,
                        size: 19,
                        color: voiceOn ? Colors.white : c.muted,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Kapat · Esc',
              onPressed: widget.onDismiss,
              icon: Icon(Icons.close_rounded, size: 19, color: c.muted),
            ),
        ],
      ),
    );
  }

  TextStyle _section(AjanColors c) => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1,
    color: c.faint,
  );

  Widget _left(AjanColors c, FolioAjan? ajan) {
    final library = widget.library;
    final query = library.query.trim();
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ajan != null && query.isNotEmpty) _agentRow(c),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
            child: Row(
              children: [
                Text(
                  query.isEmpty ? 'EVRAKLARINIZ' : 'EVRAK · ${library.matches}',
                  style: _section(c),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(fit: BoxFit.scaleDown, child: _filters(c)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _list(c)),
        ],
      ),
    );
  }

  /// "Tümü · PDF · UDF · Word", as the mock-up has them.
  Widget _filters(AjanColors c) {
    final library = widget.library;
    const groups = <(String, List<String>)>[
      ('Tümü', []),
      ('PDF', ['pdf']),
      ('UDF', ['udf']),
      ('Word', ['docx', 'doc', 'rtf']),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, g) in groups.indexed) ...[
          if (i > 0) const SizedBox(width: 4),
          Builder(
            builder: (context) {
              final on =
                  !library.ocrOnly &&
                  library.extensions.join(',') == g.$2.join(',');
              return Material(
                color: on ? c.text : Colors.transparent,
                shape: StadiumBorder(
                  side: on ? BorderSide.none : BorderSide(color: c.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => library.filter(types: g.$2, onlyOcr: false),
                  child: Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    alignment: Alignment.center,
                    child: Text(
                      g.$1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                        color: on
                            ? (c.dark ? const Color(0xFF0D1119) : Colors.white)
                            : (c.dark ? const Color(0xFFA9B2C2) : c.muted),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
        const SizedBox(width: 2),
        IconTheme(
          data: IconThemeData(color: c.faint, size: 16),
          child: SizedBox(
            width: 28,
            height: 24,
            child: FittedBox(child: SearchOptionsButton(library: library)),
          ),
        ),
      ],
    );
  }

  Widget _agentRow(AjanColors c) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: c.accentLine),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.fromRGBO(37, 99, 235, .14),
          Color.fromRGBO(37, 99, 235, .06),
        ],
      ),
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _askAgent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const FolioMark(size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Folio Ajan’a sor',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'dosyalar, evrak, ajanda ve içtihatta arar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Kbd('Tab', colors: c),
            ],
          ),
        ),
      ),
    ),
  );

  static const _months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', //
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];
  static const _weekdays = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  /// A small coloured tag: "Bugün", "2 gün", "3".
  Widget _tag(String text, Color fill, Color ink) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      maxLines: 1,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ink),
    ),
  );

  /// Nothing typed: the day, as the mock-up's left half.
  Widget _today(AjanColors c, FolioAjan ajan) {
    final brief = ajan.brief;
    final now = DateTime.now();
    const blueFill = Color.fromRGBO(76, 125, 255, .14);
    final blueInk = c.dark ? const Color(0xFF9DB7FF) : c.accentText;
    final rows = <(Widget, String, String, bool, String)>[
      if (brief != null) ...[
        for (final d in brief.deadlines.where((d) => d.urgent).take(3))
          (
            (d.days ?? 1) <= 0
                ? _tag(
                    d.days != null && d.days! < 0 ? 'Geçti' : 'Bugün',
                    const Color.fromRGBO(255, 107, 107, .14),
                    c.redText,
                  )
                : _tag('${d.days} gün', c.amberFill, c.amberText),
            d.title,
            [
              d.detail,
              if (d.when.isNotEmpty) 'son gün ${d.when}',
            ].where((s) => s.isNotEmpty).join(' · '),
            (d.days ?? 1) <= 0,
            'Şu süreyi anlat: ${d.title} ${d.detail}',
          ),
        for (final h in brief.hearings.take(3))
          (
            SizedBox(
              width: 46,
              child: Text(
                h.days == 0 && h.clock.isNotEmpty ? h.clock : h.when,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: ajanMono,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: (h.days ?? 0) < 0 ? c.faint : c.chip,
                ),
              ),
            ),
            (h.days ?? 0) < 0 ? '${h.detail} · geçti' : h.detail,
            h.title,
            false,
            'Şu duruşma hakkında bilgi ver: ${h.title} ${h.when}',
          ),
        if (brief.incoming.isNotEmpty)
          (
            SizedBox(
              width: 46,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _tag('${brief.incoming.length}', blueFill, blueInk),
              ),
            ),
            'Yeni gelen',
            'UYAP bildirimi ve e-tebligat',
            false,
            'Okunmamış tebligatlarımı ve UYAP bildirimlerimi özetle.',
          ),
      ],
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('BUGÜN', style: _section(c)),
              const Spacer(),
              Text(
                '${now.day} ${_months[now.month - 1]} '
                '${_weekdays[now.weekday - 1]}',
                style: TextStyle(fontSize: 12, color: c.faint),
              ),
            ],
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              brief == null
                  ? (ajan.briefLoading ? 'Okunuyor…' : 'Brifing okunamadı')
                  : brief.summary,
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: r.$4 ? c.redFill : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _askAgent(r.$5),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      r.$1,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: r.$4
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                            if (r.$3.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                r.$3,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: c.muted),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Nothing typed, the right half: what to ask, the last searches.
  Widget _suggest(AjanColors c, FolioAjan ajan) {
    final library = widget.library;
    const asks = [
      (
        'Bugün neler var?',
        'Bugün neler var? Duruşma, süre ve gelenleri söyle.',
      ),
      ('Bu haftanın süreleri', 'Bu haftanın sürelerini sırayla söyle.'),
      ('Yeni tebligatları özetle', 'Okunmamış tebligatlarımı özetle.'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
          child: Text('FOLIO AJAN’A SOR', style: _section(c)),
        ),
        for (final a in asks)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: c.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: c.dark ? const Color(0xFF1F2838) : c.border,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _askAgent(a.$2),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const FolioMark(size: 16),
                      const SizedBox(width: 10),
                      Text(
                        a.$1,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (library.recentQueries.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
            child: Text('SON ARAMALAR', style: _section(c)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final recent in library.recentQueries.take(8))
                  Material(
                    color: Colors.transparent,
                    shape: StadiumBorder(side: BorderSide(color: c.line)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => library.setQuery(recent),
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 11),

                        child: Align(
                          widthFactor: 1,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 170),
                            child: Text(
                              recent,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: c.chip,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _list(AjanColors c) {
    final library = widget.library;
    if (library.searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            library.searchError!,
            style: const TextStyle(color: AjanColors.red),
          ),
        ),
      );
    }
    if (library.hits.isEmpty) {
      return Center(
        child: Text(
          library.searching
              ? 'Aranıyor…'
              : library.query.trim().isEmpty
              ? 'Folio ayarlarından bir klasör ekleyin.'
              : 'Eşleşen evrak bulunamadı',
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      itemExtent: _rowHeight,
      itemCount:
          library.hits.length + (library.matches > library.hits.length ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == library.hits.length) {
          return Center(
            child: TextButton(
              onPressed: library.searching
                  ? null
                  : () => library.searchNow(more: true),
              child: Text(
                'Daha fazla göster',
                style: TextStyle(fontSize: 12, color: c.accentText),
              ),
            ),
          );
        }
        return _hitRow(c, library.hits[index], index);
      },
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _when(int modified, {bool clock = false}) {
    if (modified <= 0) return '';
    final d = DateTime.fromMicrosecondsSinceEpoch(modified);
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;
    final at = clock ? ' ${_two(d.hour)}:${_two(d.minute)}' : '';
    if (days == 0) return 'bugün$at';
    if (days == 1) return 'dün$at';
    if (d.year == now.year) return '${_two(d.day)}.${_two(d.month)}';
    return '${_two(d.day)}.${_two(d.month)}.${d.year % 100}';
  }

  static String _folder(EvrakFile f) {
    final parts = f.path.replaceAll('\\', '/').split('/');
    return parts.length > 1 ? parts[parts.length - 2] : '';
  }

  /// The mock-up's file tags: PDF red, UDF blue, Word green.
  (String, Color, Color) _kind(EvrakFile f, AjanColors c) {
    final ext = f.name.contains('.')
        ? f.name.split('.').last.toLowerCase()
        : '';
    return switch (ext) {
      'pdf' => ('PDF', const Color.fromRGBO(255, 107, 107, .14), c.redText),
      'udf' => (
        'UDF',
        const Color.fromRGBO(76, 125, 255, .14),
        c.dark ? const Color(0xFF9DB7FF) : c.accentText,
      ),
      'doc' || 'docx' || 'odt' || 'rtf' => (
        'DOC',
        const Color.fromRGBO(61, 214, 140, .13),
        c.dark ? const Color(0xFF7EE2B0) : AjanColors.green,
      ),
      _ => (
        ext.length > 4 ? ext.substring(0, 4).toUpperCase() : ext.toUpperCase(),
        formatColor(f.format).withValues(alpha: .15),
        formatColor(f.format),
      ),
    };
  }

  Widget _badge(EvrakFile f, AjanColors c, {bool big = false}) {
    final (label, fill, ink) = _kind(f, c);
    return Container(
      width: big ? 40 : 34,
      height: big ? 48 : 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(big ? 9 : 7),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: big ? 11 : 10,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
    );
  }

  Widget _hitRow(AjanColors c, SearchHit hit, int index) {
    final selected = index == _selected && !_agentShown;
    final query = widget.library.query;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? c.select : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            _selected = index;
            _open();
          },
          onHover: (hover) {
            if (hover) {
              setState(() {
                _selected = index;
                _selectedPath = hit.file.path;
              });
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                _badge(hit.file, c),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SearchHighlight(
                        text: hit.file.name,
                        query: query,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: c.text,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _folder(hit.file),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: hit.file.path,
                  child: Text(
                    _when(hit.modified),
                    style: TextStyle(fontSize: 11, color: c.faint),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _right(AjanColors c, FolioAjan? ajan) {
    if (_agentShown) return _agentPane(c, ajan!);
    final library = widget.library;
    if (library.hits.isEmpty) {
      return ajan == null ? const SizedBox.shrink() : _suggest(c, ajan);
    }
    final hit = library.hits[_selected.clamp(0, library.hits.length - 1)];
    return _preview(c, ajan, hit);
  }

  Widget _preview(AjanColors c, FolioAjan? ajan, SearchHit hit) {
    final library = widget.library;
    final passages = _passages.putIfAbsent(
      '${hit.id}:${library.query}',
      () => library.passages(hit.id),
    );
    final passageStyle = TextStyle(
      fontSize: 12.5,
      height: 1.55,
      color: c.dark ? const Color(0xFFC9D0DC) : c.muted,
    );
    Widget card(Widget child) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.dark ? const Color(0xFF1F2838) : c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _badge(hit.file, c, big: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hit.file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        _folder(hit.file),
                        _when(hit.modified, clock: true),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('EŞLEŞEN YERLER', style: _section(c)),
          const SizedBox(height: 14),
          Expanded(
            child: FutureBuilder<DocumentPassages>(
              future: passages,
              builder: (context, got) {
                final list = got.data?.passages ?? const <String>[];
                // Until the passages come, the excerpt: nothing spins.
                if (list.isEmpty) {
                  return Align(
                    alignment: Alignment.topCenter,
                    child: card(
                      SearchHighlight(
                        text: hit.excerpt.isEmpty
                            ? hit.stateLabel
                            : hit.excerpt,
                        query: library.query,
                        maxLines: 8,
                        style: passageStyle,
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final p in list.take(4))
                      card(
                        SearchHighlight(
                          text: '… $p …',
                          query: library.query,
                          maxLines: 5,
                          style: passageStyle,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _button(c, 'Aç', onTap: _open, solid: true),
              if (ajan != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: _button(
                    c,
                    'Bu belgeyi ajana sor',
                    mark: true,
                    onTap: () => _askAgent(
                      '“${hit.file.name}” belgesini kısaca özetle: '
                      '${hit.file.path}',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// The mock-up's buttons: "Aç" light and solid, the rest outlined.
  Widget _button(
    AjanColors c,
    String label, {
    required VoidCallback? onTap,
    bool solid = false,
    bool blue = false,
    bool mark = false,
  }) => Material(
    color: blue
        ? AjanColors.blue
        : solid
        ? c.text
        : Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: solid || blue ? BorderSide.none : BorderSide(color: c.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: EdgeInsets.symmetric(horizontal: solid ? 16 : 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mark) ...[const FolioMark(size: 16), const SizedBox(width: 8)],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: solid || blue ? FontWeight.w600 : FontWeight.w500,
                  color: blue
                      ? Colors.white
                      : solid
                      ? (c.dark ? const Color(0xFF0D1119) : Colors.white)
                      : c.text,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// A tool Folio Ajan used, as the mock-up's chips: "✓ ajanda".
  Widget _toolChip(AjanColors c, String text) => Container(
    height: 26,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: c.dark ? const Color(0x0DFFFFFF) : c.panel,
      border: Border.all(color: c.dark ? const Color(0x0FFFFFFF) : c.border),
      borderRadius: BorderRadius.circular(999),
    ),

    child: Align(
      widthFactor: 1,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: text.substring(0, 1),
              style: TextStyle(
                color: text.startsWith('✓') ? const Color(0xFF3DD68C) : c.faint,
              ),
            ),
            TextSpan(text: text.substring(1)),
          ],
        ),
        maxLines: 1,
        style: TextStyle(
          fontFamily: ajanMono,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: c.muted,
        ),
      ),
    ),
  );

  /// Folio Ajan's answer: written, or the spoken conversation.
  Widget _agentPane(AjanColors c, FolioAjan ajan) {
    final voice = ajan.voice;
    final spoken = voice.active || voice.lines.isNotEmpty;
    final steps = spoken ? voice.steps : ajan.steps;
    final working = ajan.asking || voice.state == LiveState.working;
    final error = spoken ? voice.error : ajan.askError;
    final shown = steps.length > 3 ? steps.sublist(steps.length - 3) : steps;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FolioMark(
                size: 24,
                live: voice.state == LiveState.speaking || working,
              ),
              const SizedBox(width: 10),
              const Text(
                'Folio Ajan',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  spoken
                      ? '${voice.label} · ${liveStateLabel(voice.state)}'
                      : ajan.brainLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.faint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (shown.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, s) in shown.indexed)
                  _toolChip(
                    c,
                    toolTrace(s, done: !working || i < shown.length - 1),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (spoken)
                    for (final l in voice.lines)
                      if (l.text.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            l.who == 'avukat' ? '“${l.text}”' : l.text,
                            style: TextStyle(
                              fontSize: l.who == 'ajan' ? 14 : 13,
                              height: 1.5,
                              color: l.who == 'ajan' ? c.text : c.muted,
                            ),
                          ),
                        )
                      else
                        const SizedBox.shrink()
                  else ...[
                    Text(
                      '“${ajan.question}”',
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                    const SizedBox(height: 8),
                    if (error == null)
                      SelectableText(
                        ajan.answer.isEmpty && ajan.asking
                            ? 'Bakıyorum…'
                            : ajan.answer,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: c.text,
                        ),
                      ),
                  ],
                  if (error != null)
                    Text(error, style: const TextStyle(color: AjanColors.red)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (ajan.settings.on && ajan.answer.isNotEmpty && !spoken) ...[
                _button(
                  c,
                  'Sesli oku',
                  onTap: () => ajan.voice.send(
                    'Şu cevabı olduğu gibi, kısaca sesli oku: ${ajan.answer}',
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (widget.onJarvis != null)
                Flexible(
                  child: _button(
                    c,
                    'Folio Ajan’da sürdür',
                    blue: true,
                    onTap: widget.onJarvis,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer(AjanColors c, FolioAjan? ajan) {
    final ink = c.dark ? const Color(0xFFC9D0DC) : c.text;
    Widget hint(String key, String text) => Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(5),
            ),
            child: key == '↵'
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Icon(
                      Icons.keyboard_return_rounded,
                      size: 12,
                      color: ink,
                    ),
                  )
                : Text(
                    key,
                    style: TextStyle(
                      fontFamily: ajanMono,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: ink,
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12, color: c.muted)),
        ],
      ),
    );
    final empty = widget.library.query.trim().isEmpty;
    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(18, 0, 12, 0),
      decoration: BoxDecoration(
        color: c.dark ? const Color.fromRGBO(9, 12, 18, .6) : c.panel,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: empty
                ? Text(
                    'Yazdığınız an evrak aranır; hiçbir şey gönderilmez.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.muted),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        hint('↵', 'aç'),
                        hint('↑↓', 'gez'),
                        if (ajan != null) hint('Tab', 'ajana sor'),
                      ],
                    ),
                  ),
          ),
          TextButton(
            onPressed: widget.onMain,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Folio’yu aç',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: c.dark ? const Color(0xFFA9B2C2) : c.muted,
              ),
            ),
          ),
          if (ajan != null && widget.onJarvis != null) ...[
            const SizedBox(width: 8),
            Material(
              color: AjanColors.blue,
              borderRadius: BorderRadius.circular(9),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onJarvis,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.open_in_full_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Folio Ajan',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(255, 255, 255, .18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Ctrl J',
                          style: TextStyle(
                            fontFamily: ajanMono,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The palette as the mock-up has it: a 720 × 540 card in the middle of
/// the screen. A click beside it closes it.
class FloatingPalette extends StatelessWidget {
  const FloatingPalette({
    super.key,
    required this.child,
    required this.onOutside,
  });

  final Widget child;
  final VoidCallback onOutside;

  static const size = Size(720, 540);

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOutside,
        ),
      ),
      Center(
        child: ConstrainedBox(
          constraints: BoxConstraints.loose(size),
          child: SizedBox.fromSize(
            size: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x8C000000),
                    blurRadius: 60,
                    offset: Offset(0, 24),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF263044)),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
