import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/evrak_file.dart';
import '../../services/search/library_controller.dart';
import '../library/search_controls.dart';
import '../library/search_results.dart';

/// No separate index, extraction, ranking, or query dialect in this surface.
class QuickSearchPalette extends StatefulWidget {
  final LibraryController library;
  final ValueChanged<EvrakFile> onOpen;
  final VoidCallback onDismiss;
  final VoidCallback onMain;
  const QuickSearchPalette({
    super.key,
    required this.library,
    required this.onOpen,
    required this.onDismiss,
    required this.onMain,
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
  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.library.query);
    widget.library.addListener(_changed);
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
      final top = _selected * 100.0;
      final view = _scroll.position.viewportDimension;
      if (top < _scroll.offset) {
        _scroll.jumpTo(top);
      } else if (top + 100 > _scroll.offset + view) {
        _scroll.jumpTo(
          (top + 100 - view).clamp(0, _scroll.position.maxScrollExtent),
        );
      }
    }
  }

  void _open() {
    if (widget.library.searching || widget.library.hits.isEmpty) return;
    widget.library.rememberQuery();
    widget.onOpen(widget.library.hits[_selected].file);
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.library;
    final colors = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.enter): _open,
      },
      child: Material(
        color: colors.surface,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colors.primary.withValues(alpha: .22)),
          ),
          child: Column(
            children: [
              Container(
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colors.primary,
                      const Color(0xFF86B7A9),
                      colors.surface,
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 12, 6),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/branding/lifeos_folio.png',
                        width: 30,
                        height: 30,
                        cacheWidth:
                            (30 * MediaQuery.devicePixelRatioOf(context))
                                .ceil(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        focusNode: _focus,
                        autofocus: true,
                        style: const TextStyle(fontSize: 20, height: 1.4),
                        decoration: const InputDecoration(
                          hintText: 'Bir belge, bir cümle, bir sözcük…',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: (value) {
                          _selected = 0;
                          _selectedPath = null;
                          library.setQuery(value);
                        },
                        onSubmitted: (_) => _open(),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat · Esc',
                      onPressed: widget.onDismiss,
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SearchControls(library: library),
              ),
              SizedBox(
                height: 2,
                child: library.searching
                    ? const LinearProgressIndicator(minHeight: 2)
                    : const SizedBox.shrink(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
                child: Row(
                  children: [
                    Text(
                      library.query.trim().isEmpty
                          ? 'EVRAKLARINIZ'
                          : '${library.matches} SONUÇ',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    if (library.sourceId != null ||
                        library.namesOnly ||
                        library.match.name != 'all')
                      Text(
                        'Arama seçenekleri etkin',
                        style: TextStyle(fontSize: 11, color: colors.primary),
                      ),
                  ],
                ),
              ),
              if (library.query.isEmpty && library.recentQueries.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: SizedBox(
                    height: 32,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final recent in library.recentQueries)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              avatar: const Icon(
                                Icons.history_rounded,
                                size: 14,
                              ),
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 190,
                                ),
                                child: Text(
                                  recent,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              onPressed: () => library.setQuery(recent),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: library.searchError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            library.searchError!,
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                      )
                    : library.hits.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              library.searching
                                  ? Icons.manage_search_rounded
                                  : Icons.search_rounded,
                              size: 38,
                              color: colors.primary.withValues(alpha: .6),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              library.searching
                                  ? 'Aranıyor…'
                                  : library.query.isEmpty
                                  ? 'Arşiviniz burada, elinizin altında.'
                                  : 'Eşleşen evrak bulunamadı',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              library.query.isEmpty
                                  ? 'Folio ayarlarından bir klasör ekleyin.'
                                  : 'Sözcükleri veya arama seçeneklerini değiştirebilirsiniz.',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemExtent: 100,
                        itemCount:
                            library.hits.length +
                            (library.matches > library.hits.length ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == library.hits.length) {
                            return Center(
                              child: TextButton(
                                onPressed: library.searching
                                    ? null
                                    : () => library.searchNow(more: true),
                                child: const Text('Daha fazla göster'),
                              ),
                            );
                          }
                          final hit = library.hits[index];
                          final selected = index == _selected;
                          return TweenAnimationBuilder<double>(
                            key: ValueKey('${library.query}:${hit.file.path}'),
                            tween: Tween(begin: 0, end: 1),
                            duration: reduceMotion
                                ? Duration.zero
                                : Duration(
                                    milliseconds: 150 + math.min(index, 7) * 16,
                                  ),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) => Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, (1 - value) * 10),
                                child: child,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Material(
                                color: selected
                                    ? colors.primary.withValues(alpha: .09)
                                    : colors.surface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: selected
                                        ? colors.primary.withValues(alpha: .2)
                                        : Colors.transparent,
                                  ),
                                ),
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 13,
                                      vertical: 11,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 37,
                                          height: 43,
                                          decoration: BoxDecoration(
                                            color: formatColor(hit.file.format)
                                                .withValues(alpha: .08),
                                            borderRadius: BorderRadius.circular(
                                              9,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.description_outlined,
                                            size: 22,
                                            color: formatColor(hit.file.format),
                                          ),
                                        ),
                                        const SizedBox(width: 13),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              SearchHighlight(
                                                text: hit.file.name,
                                                query: library.query,
                                                maxLines: 1,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              SearchHighlight(
                                                text: hit.excerpt.isEmpty
                                                    ? hit.stateLabel
                                                    : hit.excerpt,
                                                query: library.query,
                                                maxLines: 2,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  height: 1.4,
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Tooltip(
                                          message: hit.file.path,
                                          child: Text(
                                            hit.file.name
                                                .split('.')
                                                .last
                                                .toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: colors.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Icon(
                                          Icons.north_east_rounded,
                                          size: 15,
                                          color: selected
                                              ? colors.primary
                                              : colors.outline,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Container(
                height: 43,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
                ),
                child: Row(
                  children: [
                    Text(
                      '↑ ↓ seç    ↵ önizle    Esc kapat',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(library.elapsedMicros / 1000).toStringAsFixed(1)} ms',
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: widget.onMain,
                      child: const Text(
                        'Folio’yu aç',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
