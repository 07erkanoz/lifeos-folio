import 'package:flutter/material.dart';

import '../../services/editor/snippets.dart';

/// Filling the blanks in a passage, once, before it goes in.
///
/// The first design walked the cursor from blank to blank inside the
/// document with Tab. Quill already owns Tab, and fighting it for the key
/// would have been fragile in exactly the place a mistake is expensive.
/// Asking once, here, is simpler and safer: the passage arrives finished,
/// and nothing is left in the filing for the reader to notice later.
class SnippetFill extends StatefulWidget {
  const SnippetFill({super.key, required this.snippet, this.known = const {}});

  final Snippet snippet;

  /// Values already known, from the lawyer's profile: filled in, and still
  /// open to change for this one filing.
  final Map<String, String> known;

  /// The values given, or null if the reader backed out. Leaving the blanks
  /// empty keeps what the profile knew and leaves the rest showing.
  static Future<Map<String, String>?> ask(
    BuildContext context,
    Snippet snippet, {
    Map<String, String> known = const {},
  }) => showDialog<Map<String, String>>(
    context: context,
    builder: (_) => SnippetFill(snippet: snippet, known: known),
  );

  @override
  State<SnippetFill> createState() => _SnippetFillState();
}

class _SnippetFillState extends State<SnippetFill> {
  late final _fields = {
    for (final blank in widget.snippet.blanks)
      blank: TextEditingController(text: widget.known[blank] ?? ''),
  };

  /// The first blank the profile did not fill, where typing starts.
  late final String _first = widget.snippet.blanks.firstWhere(
    (blank) => !widget.known.containsKey(blank),
    orElse: () => widget.snippet.blanks.first,
  );

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _given => {
    for (final entry in _fields.entries)
      if (entry.value.text.trim().isNotEmpty)
        entry.key: entry.value.text.trim(),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blanks = widget.snippet.blanks;
    return AlertDialog(
      title: Text(widget.snippet.name),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Bu kalıpta doldurulacak ${blanks.length} yer var.',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              for (final blank in blanks) ...[
                TextField(
                  key: ValueKey('snippet-blank-$blank'),
                  controller: _fields[blank],
                  autofocus: blank == _first,
                  textInputAction: blank == blanks.last
                      ? TextInputAction.done
                      : TextInputAction.next,
                  onSubmitted: blank == blanks.last
                      ? (_) => Navigator.pop(context, _given)
                      : null,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: blank,
                    helperText: widget.known.containsKey(blank)
                        ? 'Avukat profilinden'
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        // Boş bırakmak meşru: değeri henüz bilmiyor olabilir. O zaman
        // köşeli parantezler metinde kalır ve kaydederken uyarı çıkar.
        TextButton(
          key: const ValueKey('snippet-blanks-skip'),
          onPressed: () => Navigator.pop(context, {
            for (final blank in blanks) blank: ?widget.known[blank],
          }),
          child: const Text('Boş bırak'),
        ),
        FilledButton(
          key: const ValueKey('snippet-blanks-fill'),
          onPressed: () => Navigator.pop(context, _given),
          child: const Text('Yerleştir'),
        ),
      ],
    );
  }
}
