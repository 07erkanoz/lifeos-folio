import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/ai/ai_assistant.dart';
import '../../services/ai/ai_memory.dart';
import '../../services/portal/portal_database.dart';
import '../../services/uyap/uyap_case_store.dart';
import 'ai_panel.dart';

/// A case's "Yapay zekâ" tab: what the lawyer's AI program left of it
/// (AiMemory) — its conversations, to read or go on with; the findings the
/// lawyer kept, those found wrong struck through with why; the drafts it
/// wrote. Shown only while the AI features are on. On a device that runs
/// no AI program (a phone) it is read, not asked.
class CaseAiTab extends StatefulWidget {
  const CaseAiTab({
    super.key,
    required this.caseKey,
    required this.record,
    required this.database,
    this.onOpenPath,
  });

  final String caseKey;
  final UyapCaseRecord? record;
  final Future<PortalDatabase> Function() database;
  final ValueChanged<String>? onOpenPath;

  @override
  State<CaseAiTab> createState() => _CaseAiTabState();
}

class _CaseAiTabState extends State<CaseAiTab> {
  List<Map<String, Object?>> _chats = const [], _findings = const [];
  List<Map<String, Object?>> _drafts = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final db = await widget.database();
    final key = widget.caseKey;
    List<Map<String, Object?>> newest(String kind, String at) =>
        db.aiRecords(kind, caseKey: key)
          ..sort((a, b) => '${b[at]}'.compareTo('${a[at]}'));
    if (!mounted) return;
    setState(() {
      _chats = newest(AiMemory.chat, 'guncellendi');
      _findings = newest(AiMemory.finding, 'zaman');
      _drafts = newest(AiMemory.draft, 'zaman');
      _loaded = true;
    });
  }

  static String _day(Object? at) {
    final t = DateTime.tryParse('${at ?? ''}');
    if (t == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year}';
  }

  /// [chat] gone on with, or a new one when null: beside the case, as on a
  /// document.
  Future<void> _ask([Map<String, Object?>? chat]) async {
    final record = widget.record;
    if (record == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 640,
          child: AiPanel(
            caseRecord: record,
            chat: chat,
            onClose: () => Navigator.pop(context),
            onOpen: (path) {
              Navigator.pop(context);
              widget.onOpenPath?.call(path);
            },
          ),
        ),
      ),
    );
    await _load();
  }

  /// [chat] read, on a device that asks nothing.
  Future<void> _read(Map<String, Object?> chat) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${chat['baslik'] ?? 'Sohbet'}'),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final t in AiMemory.turnsOf(chat)) ...[
              Text(
                '${t['soru'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '${t['yazan'] ?? ''}',
                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              SelectableText(
                '${t['cevap'] ?? ''}',
                style: const TextStyle(height: 1.5),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    ),
  );

  Future<void> _removeChat(Map<String, Object?> chat) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sohbet silinsin mi?'),
        content: const Text(
          'Sohbet bu cihazdan ve eşitlenen diğer cihazlarınızdan silinir. '
          'Bu sohbetten kaydettiğiniz bulgular ve taslaklar kalır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    (await widget.database()).removeAiRecord('${chat['id']}');
    await _load();
  }

  /// [finding] said to be wrong, with why: it stays, struck through, and
  /// the program reads it so.
  Future<void> _markWrong(Map<String, Object?> finding) async {
    final why = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bulgu yanlış'),
        content: SizedBox(
          width: 420,
          child: TextField(
            key: const ValueKey('ai-wrong-reason'),
            controller: why,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Neden yanlış?',
              hintText: 'Bordroda izin kullanımı yok',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const ValueKey('ai-wrong-save'),
            onPressed: () {
              if (why.text.trim().isNotEmpty) {
                Navigator.pop(context, why.text.trim());
              }
            },
            child: const Text('Yanlış işaretle'),
          ),
        ],
      ),
    );
    why.dispose();
    if (reason == null) return;
    final db = await widget.database();
    db.putAiRecord('${finding['id']}', AiMemory.finding, widget.caseKey, {
      ...finding,
      'yanlis': {'neden': reason, 'zaman': DateTime.now().toIso8601String()},
    });
    await _load();
  }

  Future<void> _openDraft(Map<String, Object?> draft) async {
    final path = draft['yol'];
    if (path is String && File(path).existsSync()) {
      widget.onOpenPath?.call(path);
      return;
    }
    // Not on this device: its text as the program wrote it.
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${draft['baslik'] ?? 'Taslak'}'),
        scrollable: true,
        content: SizedBox(
          width: 520,
          child: SelectableText('${draft['metin'] ?? ''}'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Widget _heading(String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final asks = AiAssistant.shown && widget.record != null;
    final byKind = <String, List<Map<String, Object?>>>{};
    for (final f in _findings) {
      byKind.putIfAbsent('${f['tur']}', () => []).add(f);
    }
    final standing = _findings.where((f) => f['yanlis'] == null).length;
    return ListView(
      key: const ValueKey('case-ai-tab'),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: [
        if (asks)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const ValueKey('case-ai-ask'),
                onPressed: () => _ask(),
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Dosyaya sor'),
              ),
            ),
          )
        else if (!AiAssistant.available)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Bu cihazda yapay zekâya soru sorulmaz; bilgisayarınızda '
              'yapılanlar burada okunur.',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
        _heading('Sohbetler'),
        if (_chats.isEmpty)
          _empty('Bu dosyada henüz yapay zekâ sohbeti yok.')
        else
          for (final c in _chats)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                key: ValueKey('case-ai-chat-${c['id']}'),
                dense: true,
                title: Text(
                  '${c['baslik'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    _day(c['guncellendi']),
                    if (AiMemory.turnsOf(c).lastOrNull?['yazan'] case final by?)
                      '$by',
                    '${AiMemory.turnsOf(c).length} soru',
                  ].join(' · '),
                ),
                onTap: () => asks ? _ask(c) : _read(c),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => v == 'oku' ? _read(c) : _removeChat(c),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'oku', child: Text('Oku')),
                    PopupMenuItem(value: 'sil', child: Text('Sohbeti sil')),
                  ],
                ),
              ),
            ),
        _heading('Bulgular · $standing geçerli'),
        if (_findings.isEmpty)
          _empty(
            'Kaydedilmiş bulgu yok. Yapay zekâ bulgu önerdiğinde panelde '
            'onayınıza sunulur.',
          )
        else
          for (final kind in [
            ...AiMemory.kinds.keys.where(byKind.containsKey),
            ...byKind.keys.where((k) => !AiMemory.kinds.containsKey(k)),
          ]) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
              child: Text(
                AiMemory.kinds[kind] ?? kind,
                style: TextStyle(fontSize: 11.5, color: scheme.outline),
              ),
            ),
            for (final f in byKind[kind]!) _finding(f, scheme),
          ],
        _heading('Taslaklar'),
        if (_drafts.isEmpty)
          _empty('Yapay zekânın yazıp kaydettiğiniz taslak yok.')
        else
          for (final d in _drafts)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.description_outlined),
                title: Text('${d['baslik'] ?? ''}'),
                subtitle: Text(
                  '${_day(d['zaman'])} · Yapay zekâ taslağı · '
                  '${d['yazan'] ?? ''}',
                ),
                onTap: () => _openDraft(d),
              ),
            ),
      ],
    );
  }

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _finding(Map<String, Object?> f, ColorScheme scheme) {
    final wrong = f['yanlis'] is Map ? f['yanlis'] as Map : null;
    final sources = [for (final s in f['kaynaklar'] as List? ?? const []) '$s'];
    return Card(
      key: ValueKey('case-ai-finding-${f['id']}'),
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${f['metin'] ?? ''}',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                decoration: wrong == null ? null : TextDecoration.lineThrough,
                color: wrong == null ? null : scheme.outline,
              ),
            ),
            if (sources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  sources.join(' · '),
                  style: TextStyle(fontSize: 11.5, color: scheme.primary),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    wrong != null
                        ? 'Yanlış: ${wrong['neden'] ?? ''}'
                        : [
                            _day(f['zaman']),
                            if (f['yazan'] case final by?) '$by',
                            if (f['denetim'] == 'dogrulandi')
                              'alıntı evrakta var',
                          ].join(' · '),
                    style: TextStyle(
                      fontSize: 11,
                      color: wrong != null ? scheme.error : scheme.outline,
                    ),
                  ),
                ),
                if (wrong == null)
                  TextButton(
                    key: ValueKey('case-ai-wrong-${f['id']}'),
                    onPressed: () => _markWrong(f),
                    child: const Text('Yanlış işaretle'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
