import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../agenda/agenda_page.dart' show AgendaColors;
import 'global_search.dart';
import 'global_search_panel.dart';

/// The desktop home page's search field, with what it found opened under
/// it. A widget of its own (Codex, for a slow laptop): a letter typed or an
/// arrow pressed builds this again, not the whole home page.
class HomeSearchBox extends StatefulWidget {
  const HomeSearchBox({
    super.key,
    required this.focusNode,
    required this.onSearch,
    this.search,
    this.onFound,
    this.onShowCases,
  });

  /// The home page's own, for Ctrl K.
  final FocusNode focusNode;

  /// The archive searched for these words: Enter with nothing found, or
  /// its group's "tümünü göster".
  final ValueChanged<String> onSearch;

  /// What is found as it is typed; null for the archive alone.
  final GlobalSearch? search;
  final ValueChanged<Found>? onFound;
  final ValueChanged<String>? onShowCases;

  @override
  State<HomeSearchBox> createState() => _HomeSearchBoxState();
}

class _HomeSearchBoxState extends State<HomeSearchBox> {
  final _search = TextEditingController();
  FocusNode get _focus => widget.focusNode;

  /// What the search found, shown under it while it has the focus.
  final _found = OverlayPortalController();
  final _link = LayerLink();
  final _box = GlobalKey();
  GlobalSearchResults? _results;
  int _at = 0;
  bool _finding = false;
  Timer? _findSoon;
  Future<GlobalSearchResults?>? _finds;
  int _findGeneration = 0;

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = _searchKey;
    _focus.addListener(_focused);
  }

  @override
  void didUpdateWidget(HomeSearchBox old) {
    super.didUpdateWidget(old);
    // Another search (another lawyer's name): what the old one finds is
    // not shown.
    if (old.search != widget.search) {
      _findSoon?.cancel();
      _findGeneration++;
      _results = null;
      // Empty, the list draws nothing; hidden here, in a build, it may not.
      _finding = false;
    }
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_focused);
      old.focusNode.onKeyEvent = null;
      _focus.onKeyEvent = _searchKey;
      _focus.addListener(_focused);
    }
  }

  @override
  void dispose() {
    _findSoon?.cancel();
    _focus.removeListener(_focused);
    _focus.onKeyEvent = null;
    _search.dispose();
    super.dispose();
  }

  /// Away from the field, what it found closes; back, it opens again.
  void _focused() {
    if (!_focus.hasFocus) {
      _found.hide();
    } else {
      // What is searched is made ready while the first word is typed.
      unawaited(widget.search?.prepare().catchError((Object _) {}));
      if (_results != null) _found.show();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _found,
        overlayChildBuilder: _overlay,
        child: KeyedSubtree(
          key: _box,
          child: TextField(
            key: const ValueKey('home-search'),
            controller: _search,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            onChanged: _typed,
            onSubmitted: (text) => unawaited(_submitted(text)),
            decoration: InputDecoration(
              filled: true,
              fillColor: scheme.surface,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              hintText: 'Evrak adı ya da içinde geçen bir kelime…',
              suffixIcon: Padding(
                padding: const EdgeInsets.all(10),
                child: Container(
                  // Its own width: aligned, it took the whole field's
                  // and left nothing for what is typed.
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    Platform.isMacOS ? '⌘ K' : 'Ctrl K',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AgendaColors.muted,
                    ),
                  ),
                ),
              ),
              suffixIconConstraints: const BoxConstraints(minHeight: 44),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: scheme.primary, width: 1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlay(BuildContext context) {
    final results = _results;
    final box = _box.currentContext?.findRenderObject() as RenderBox?;
    if (results == null || box == null || !box.hasSize) {
      return const SizedBox.shrink();
    }
    final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
    final room = MediaQuery.sizeOf(context).height - bottom - 24;
    return Positioned(
      width: box.size.width,
      child: CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.bottomLeft,
        offset: const Offset(0, 6),
        child: TextFieldTapRegion(
          child: Container(
            key: const ValueKey('home-search-results'),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: room.clamp(160.0, 680.0)),
              child: GlobalSearchPanel(
                results: results,
                selected: _at,
                searching: _finding,
                onPick: _open,
                onShowCases: () =>
                    _leave(() => widget.onShowCases?.call(results.query)),
                onShowFiles: () => _leave(() => widget.onSearch(results.query)),
                onOpenGroup: ({documents = false, agenda = false}) => setState(
                  () => _results = results.open(
                    documents: documents,
                    agenda: agenda,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A letter typed: looked for a moment later, once typing pauses. What
  /// was asked for before it is no longer wanted, even when it comes back
  /// in the pause.
  void _typed(String text) {
    final search = widget.search;
    if (search == null) return;
    _findSoon?.cancel();
    _findGeneration++;
    if (GlobalSearch.words(text).isEmpty) {
      _finds = null;
      _found.hide();
      setState(() {
        _results = null;
        _finding = false;
      });
      return;
    }
    if (!_finding) setState(() => _finding = true);
    _findSoon = Timer(
      const Duration(milliseconds: 200),
      () => unawaited(_find(text)),
    );
  }

  Future<GlobalSearchResults?> _find(String text) {
    final search = widget.search!;
    final generation = ++_findGeneration;
    return _finds = () async {
      GlobalSearchResults? results;
      try {
        results = await search.find(text);
      } catch (_) {
        results = GlobalSearchResults(query: text.trim());
      }
      if (!mounted || generation != _findGeneration) return null;
      setState(() {
        _results = results;
        _at = 0;
        _finding = false;
      });
      if (_focus.hasFocus) _found.show();
      return results;
    }();
  }

  /// Enter: the row the arrows are on, the first unless moved; nothing
  /// found, the archive searched as before.
  Future<void> _submitted(String text) async {
    if (widget.search == null || GlobalSearch.words(text).isEmpty) {
      _leave(() => widget.onSearch(text.trim()));
      return;
    }
    var results = _results;
    if (_findSoon?.isActive ?? false) {
      _findSoon!.cancel();
      results = await _find(text);
    } else if (_finding) {
      results = await _finds;
    }
    // Typed on while it was awaited: what Enter was for is gone.
    if (!mounted || results == null || _search.text.trim() != text.trim()) {
      return;
    }
    final count = results.shownCount;
    if (count == 0) {
      _leave(() => widget.onSearch(text.trim()));
    } else {
      _open(results.shownAt(_at.clamp(0, count - 1)));
    }
  }

  void _open(Found found) => _leave(() => widget.onFound?.call(found));

  /// The search done: emptied and closed, then [go].
  void _leave(VoidCallback go) {
    _findSoon?.cancel();
    _findGeneration++;
    _found.hide();
    _search.clear();
    _focus.unfocus();
    setState(() {
      _results = null;
      _finding = false;
      _at = 0;
    });
    go();
  }

  /// The arrows go through what was found, Escape closes it.
  KeyEventResult _searchKey(FocusNode node, KeyEvent event) {
    final results = _results;
    if (event is KeyUpEvent || results == null || !_found.isShowing) {
      return KeyEventResult.ignored;
    }
    final count = results.shownCount;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _found.hide();
      setState(() {});
      return KeyEventResult.handled;
    }
    if (count == 0) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _at = (_at + 1) % count);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _at = (_at - 1 + count) % count);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
