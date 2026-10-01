import 'package:flutter/material.dart';

import '../../services/editor/editor_settings.dart';
import '../../services/editor/suggestions/phrase_memory.dart';
import '../../services/editor/suggestions/phrases.dart';
import '../../services/search/library_controller.dart';

/// What the suggestions have learned, and the reader's say over it: search,
/// delete, never offer again, forget everything, learn from the archive now.
class LearnedPhrasesDialog extends StatefulWidget {
  const LearnedPhrasesDialog({super.key, required this.memory});

  final PhraseMemory memory;

  static Future<void> show(BuildContext context) async {
    final memory = await PhraseMemory.shared();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => LearnedPhrasesDialog(memory: memory),
    );
  }

  @override
  State<LearnedPhrasesDialog> createState() => _LearnedPhrasesDialogState();
}

class _LearnedPhrasesDialogState extends State<LearnedPhrasesDialog> {
  final _search = TextEditingController();
  var _query = '';

  PhraseMemory get _memory => widget.memory;

  @override
  void initState() {
    super.initState();
    _memory.addListener(_changed);
  }

  @override
  void dispose() {
    _memory.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _learnNow() async {
    final path = await LibraryController.defaultDatabasePath();
    try {
      final kept = await _memory.learnArchive(path);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Arşivden $kept ifade öğrenildi.')),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Arşiv okunamadı. Önce Ayarlar’dan klasör ekleyin.'),
          ),
        );
      }
    }
  }

  Future<void> _clear() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Öğrenilenlerin hepsi silinsin mi?'),
        content: const Text(
          'Folio’nun belgelerinizden öğrendiği bütün ifadeler silinir. '
          '“Bir daha önerme” dediğiniz ifadeler engelli kalır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hepsini sil'),
          ),
        ],
      ),
    );
    if (sure == true) _memory.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final key = foldPhrase(_query.trim());
    final shown = [
      for (final phrase in _memory.phrases)
        if (key.isEmpty || phrase.key.contains(key)) phrase,
    ];
    final learned = _memory.archiveLearned;
    return Dialog(
      key: const ValueKey('learned-phrases'),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Öğrenilen ifadeler',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Folio, kaydettiğiniz belgelerde ve arşivinizde sık geçen '
                'ifadeleri öğrenir ve yazarken önerir. Kimlik, telefon, IBAN, '
                'e-posta, adres ve dosya numarası içeren ifadeler öğrenilmez. '
                'Hepsi yalnızca bu bilgisayarda durur.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('learned-search'),
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'İfade ara',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${shown.length} ifade'
                '${learned == null ? '' : ' · arşiv en son ${_date(learned)} tarihinde okundu'}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Text(
                          _memory.learningArchive
                              ? 'Arşiv okunuyor…'
                              : 'Henüz öğrenilen bir ifade yok.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, i) => _row(shown[i]),
                      ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('learn-archive'),
                    onPressed:
                        _memory.learningArchive ||
                            !EditorSettings.instance.learnArchive
                        ? null
                        : _learnNow,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(
                      _memory.learningArchive
                          ? 'Arşiv okunuyor…'
                          : 'Arşivden yeniden öğren',
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('learned-clear'),
                    onPressed: _memory.phrases.isEmpty ? null : _clear,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Hepsini sil'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Kapat'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(LearnedPhrase phrase) {
    final scheme = Theme.of(context).colorScheme;
    final where = [
      if (phrase.saved > 0) '${phrase.saved} kaydettiğiniz belgede',
      if (phrase.archive > 0) '${phrase.archive} arşiv belgesinde',
      if (phrase.accepted > 0) '${phrase.accepted} kez seçildi',
    ].join(' · ');
    return ListTile(
      key: ValueKey('learned-${phrase.key}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(phrase.text, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        where,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Bir daha önerme',
            icon: const Icon(Icons.block, size: 18),
            onPressed: () => _memory.block(phrase.key, phrase.text),
          ),
          IconButton(
            tooltip: 'Sil',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => _memory.remove(phrase.key),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}
