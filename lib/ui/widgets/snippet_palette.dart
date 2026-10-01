import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/editor/snippets.dart';

/// What the reader asked the palette for.
sealed class SnippetChoice {
  const SnippetChoice();
}

/// Put this passage in at the cursor.
class InsertSnippet extends SnippetChoice {
  const InsertSnippet(this.snippet);
  final Snippet snippet;
}

/// Keep what is selected as a new passage, under this name.
class KeepSelection extends SnippetChoice {
  const KeepSelection(this.name);
  final String name;
}

/// Go and look through the archive for passages that already repeat.
class HarvestArchive extends SnippetChoice {
  const HarvestArchive();
}

/// Open the list of passages to tidy it: rename, keyword, key, delete.
class ManageSnippets extends SnippetChoice {
  const ManageSnippets();
}

/// Put this text in at the cursor: a value from the lawyer's profile.
class InsertText extends SnippetChoice {
  const InsertText(this.text);
  final String text;
}

/// Open the lawyer's profile, which has not been filled in yet.
class EditProfile extends SnippetChoice {
  const EditProfile();
}

/// The list of kept passages, over the document, reached with Ctrl+Space.
///
/// A palette rather than a side panel: inserting a passage is something done
/// mid-sentence, and a panel means leaving the keyboard for the mouse and
/// then finding the cursor again. The panel is for tidying the library; this
/// is for using it.
class SnippetPalette extends StatefulWidget {
  const SnippetPalette({
    super.key,
    required this.store,
    this.selection = '',
    this.canHarvest = false,
    this.profile = const [],
    this.profileSet = true,
  });

  /// The lawyer's profile, labelled: offered above the passages, so a name
  /// or an address goes in without typing brackets around anything.
  final List<(String, String)> profile;

  /// Whether the profile has a lawyer in it; when not, the palette offers
  /// to fill it in.
  final bool profileSet;

  final SnippetStore store;

  /// What is selected in the document, if anything. Its presence is what
  /// offers to keep it.
  final String selection;

  /// Whether there is an archive behind this editor to look through.
  final bool canHarvest;

  static Future<SnippetChoice?> show(
    BuildContext context, {
    required SnippetStore store,
    String selection = '',
    bool canHarvest = false,
    List<(String, String)> profile = const [],
    bool profileSet = true,
  }) => showDialog<SnippetChoice>(
    context: context,
    builder: (_) => SnippetPalette(
      store: store,
      selection: selection,
      canHarvest: canHarvest,
      profile: profile,
      profileSet: profileSet,
    ),
  );

  @override
  State<SnippetPalette> createState() => _SnippetPaletteState();
}

class _SnippetPaletteState extends State<SnippetPalette> {
  final _asked = TextEditingController();
  final _named = TextEditingController();
  var _at = 0;
  var _naming = false;

  @override
  void initState() {
    super.initState();
    // A name suggested from the opening words, which is nearly always what
    // the passage would be called anyway.
    final opening = widget.selection.trim().split(RegExp(r'\s+')).take(5);
    _named.text = opening.join(' ');
  }

  @override
  void dispose() {
    _asked.dispose();
    _named.dispose();
    super.dispose();
  }

  List<Snippet> get _found => widget.store.matching(_asked.text);

  /// The profile's values the search matches, by label or by value; none
  /// while nothing is typed, when they are offered as buttons instead.
  List<(String, String)> get _profileFound {
    final want = SnippetStore.fold(_asked.text).trim();
    if (want.isEmpty) return const [];
    final words = want.split(RegExp(r'\s+'));
    return [
      for (final entry in widget.profile)
        if (words.every(
          (word) => SnippetStore.fold('${entry.$1} ${entry.$2}').contains(word),
        ))
          entry,
    ];
  }

  void _move(int by) {
    final count = _profileFound.length + _found.length;
    if (count == 0) return;
    setState(() => _at = (_at + by).clamp(0, count - 1));
  }

  void _take() {
    final profile = _profileFound, found = _found;
    if (_at < profile.length) {
      Navigator.pop(context, InsertText(profile[_at].$2));
      return;
    }
    final at = _at - profile.length;
    if (at >= found.length) return;
    Navigator.pop(context, InsertSnippet(found[at]));
  }

  /// How else the passage can be reached, and how often it has been:
  /// "dil1 ⇥ · Alt+F2 · 5×".
  static String _marks(Snippet one) => [
    if (one.keyword.isNotEmpty) '${one.keyword} ⇥',
    if (one.hotkey != null) 'Alt+F${one.hotkey}',
    if (one.used > 0) '${one.used}×',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
          },
          child: _naming ? _nameIt(theme) : _pick(theme),
        ),
      ),
    );
  }

  Widget _pick(ThemeData theme) {
    final found = _found, profile = _profileFound;
    final count = profile.length + found.length;
    if (_at >= count) _at = count == 0 ? 0 : count - 1;
    final searching = _asked.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: TextField(
            key: const ValueKey('snippet-search'),
            controller: _asked,
            autofocus: true,
            textInputAction: TextInputAction.go,
            onChanged: (_) => setState(() => _at = 0),
            onSubmitted: (_) => _take(),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.bookmark_border_rounded, size: 20),
              hintText: 'Kalıp ya da profil bilgisi ara',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        if (!searching && widget.profileSet && widget.profile.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profilden',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (label, value) in widget.profile)
                      Tooltip(
                        message: '$label · belgeye ekle',
                        child: ActionChip(
                          key: ValueKey('profile-$label'),
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.badge_outlined, size: 16),
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(
                              value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          onPressed: () =>
                              Navigator.pop(context, InsertText(value)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (!searching && !widget.profileSet)
          ListTile(
            key: const ValueKey('profile-fill'),
            dense: true,
            leading: const Icon(Icons.badge_outlined, size: 20),
            title: const Text('Avukat profilini doldurun'),
            subtitle: const Text(
              'Adınız, baronuz, adresiniz buradan tek tıkla eklensin',
            ),
            onTap: () => Navigator.pop(context, const EditProfile()),
          ),
        if (widget.selection.trim().isNotEmpty)
          ListTile(
            key: const ValueKey('snippet-keep'),
            dense: true,
            leading: const Icon(Icons.add_rounded, size: 20),
            title: const Text('Seçimi kalıba al'),
            subtitle: Text(
              widget.selection.replaceAll(RegExp(r'\s+'), ' ').trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => setState(() => _naming = true),
          ),
        if (widget.canHarvest)
          ListTile(
            key: const ValueKey('snippet-harvest'),
            dense: true,
            leading: const Icon(Icons.travel_explore_rounded, size: 20),
            title: const Text('Arşivden kalıp bul'),
            subtitle: const Text('Belgelerinizde tekrar eden paragraflar'),
            onTap: () => Navigator.pop(context, const HarvestArchive()),
          ),
        ListTile(
          key: const ValueKey('snippet-manage'),
          dense: true,
          leading: const Icon(Icons.tune_rounded, size: 20),
          title: const Text('Kalıplarımı yönet'),
          subtitle: const Text('Ad, anahtar kelime, Alt+F kısayolu, silme'),
          onTap: () => Navigator.pop(context, const ManageSnippets()),
        ),
        const Divider(height: 1),
        Flexible(
          child: count == 0
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
                  child: Text(
                    // Boş bir kitaplık herkesin başlangıç hâli, ve o an
                    // ekranda yapılacak bir şey yoksa özellik çıkmaz sokak
                    // olur. Seçim yokken ilk adımın ne olduğu yazılı durur.
                    widget.store.all.isNotEmpty || searching
                        ? 'Bu aramaya uyan kalıp ya da profil bilgisi yok.'
                        : widget.canHarvest
                        ? 'Henüz kalıp yok.\n\nYukarıdan arşivinizde tekrar '
                              'eden paragraflara bakabilir, ya da bir '
                              'paragrafı belgede seçip yeniden Ctrl+Space’e '
                              'basabilirsiniz.'
                        : widget.selection.trim().isEmpty
                        ? 'Henüz kalıp yok.\n\nSık yazdığınız bir paragrafı '
                              'belgede seçin, sonra Ctrl+Space’e basın — '
                              'burada “Seçimi kalıba al” çıkacak.'
                        : 'Henüz kalıp yok. Yukarıdan seçiminizi kalıba '
                              'alabilirsiniz.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: count,
                  itemBuilder: (context, i) => Material(
                    color: i == _at
                        ? theme.colorScheme.primaryContainer.withValues(
                            alpha: .5,
                          )
                        : Colors.transparent,
                    child: i < profile.length
                        ? ListTile(
                            key: ValueKey('profile-found-$i'),
                            dense: true,
                            leading: const Icon(Icons.badge_outlined, size: 20),
                            title: Text(
                              profile[i].$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text('Profilden · ${profile[i].$1}'),
                            onTap: () => Navigator.pop(
                              context,
                              InsertText(profile[i].$2),
                            ),
                          )
                        : _snippetTile(theme, found[i - profile.length]),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Text(
            '↑ ↓ ile seçin · Enter ile yerleştirin · Esc ile kapatın',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _snippetTile(ThemeData theme, Snippet one) => ListTile(
    dense: true,
    title: Text(
      one.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      one.preview,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, height: 1.35),
    ),
    trailing: _marks(one).isEmpty
        ? null
        : Text(
            _marks(one),
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
    onTap: () => Navigator.pop(context, InsertSnippet(one)),
  );

  Widget _nameIt(ThemeData theme) => Padding(
    padding: const EdgeInsets.all(18),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Kalıba ad verin',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Sonra bu adın ilk harflerini yazarak bulacaksınız.',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('snippet-name'),
          controller: _named,
          autofocus: true,
          onSubmitted: (value) =>
              Navigator.pop(context, KeepSelection(value.trim())),
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Ad',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() => _naming = false),
              child: const Text('Geri'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('snippet-keep-save'),
              onPressed: () =>
                  Navigator.pop(context, KeepSelection(_named.text.trim())),
              child: const Text('Kalıba al'),
            ),
          ],
        ),
      ],
    ),
  );
}
