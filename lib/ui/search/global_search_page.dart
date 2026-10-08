import 'dart:async';

import 'package:flutter/material.dart';

import '../agenda/agenda_page.dart' show AgendaColors;
import 'global_search.dart';
import 'global_search_panel.dart';

/// Where the phone's search leaves to: a row found, or UYAP Dosyalarım or
/// the archive searched for the words.
sealed class SearchExit {
  const SearchExit();
}

class SearchOpened extends SearchExit {
  const SearchOpened(this.found);
  final Found found;
}

class SearchShowCases extends SearchExit {
  const SearchShowCases(this.query);
  final String query;
}

class SearchShowFiles extends SearchExit {
  const SearchShowFiles(this.query);
  final String query;
}

/// The home page's search on a phone: the field on top, what it found
/// below it on the whole screen.
class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({super.key, required this.search});
  final GlobalSearch search;

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final _field = TextEditingController();
  GlobalSearchResults? _results;
  bool _finding = false;
  Timer? _soon;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    // Made ready while the first word is typed.
    unawaited(widget.search.prepare().catchError((Object _) {}));
  }

  @override
  void dispose() {
    _soon?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _typed(String text) {
    _soon?.cancel();
    if (GlobalSearch.words(text).isEmpty) {
      _generation++;
      setState(() {
        _results = null;
        _finding = false;
      });
      return;
    }
    setState(() => _finding = true);
    _soon = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_find(text)),
    );
  }

  Future<GlobalSearchResults?> _find(String text) async {
    final generation = ++_generation;
    GlobalSearchResults results;
    try {
      results = await widget.search.find(text);
    } catch (_) {
      results = GlobalSearchResults(query: text.trim());
    }
    if (!mounted || generation != _generation) return null;
    setState(() {
      _results = results;
      _finding = false;
    });
    return results;
  }

  Future<void> _submitted(String text) async {
    if (GlobalSearch.words(text).isEmpty) return;
    var results = _results;
    if (_finding) {
      _soon?.cancel();
      results = await _find(text);
    }
    if (!mounted) return;
    final first = results?.shown.firstOrNull;
    if (first != null) {
      Navigator.pop(context, SearchOpened(first));
    } else {
      Navigator.pop(context, SearchShowFiles(text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const ValueKey('phone-search'),
          controller: _field,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _typed,
          onSubmitted: (text) => unawaited(_submitted(text)),
          decoration: const InputDecoration(
            hintText: 'Dosya, taraf, evrak ya da not ara',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
        ),
        actions: [
          if (_field.text.isNotEmpty)
            IconButton(
              tooltip: 'Temizle',
              onPressed: () {
                _field.clear();
                _typed('');
              },
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      body: results == null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _finding
                    ? 'Aranıyor…'
                    : 'UYAP dosyaları, taraflar, evraklar, arşiv ve '
                          'ajanda birlikte aranır.',
                style: const TextStyle(fontSize: 13, color: AgendaColors.muted),
              ),
            )
          : GlobalSearchPanel(
              results: results,
              selected: -1,
              searching: _finding,
              onPick: (f) => Navigator.pop(context, SearchOpened(f)),
              onShowCases: () =>
                  Navigator.pop(context, SearchShowCases(results.query)),
              onShowFiles: () =>
                  Navigator.pop(context, SearchShowFiles(results.query)),
              onOpenGroup: ({documents = false, agenda = false}) => setState(
                () => _results = results.open(
                  documents: documents,
                  agenda: agenda,
                ),
              ),
            ),
    );
  }
}
