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
/// no AI program (a phone) it is read, not asked. With no [caseKey], the
/// home page's: every conversation, each with the case it came to be of,
/// and a new one of no case, whose case the program finds.
class CaseAiTab extends StatefulWidget {
  const CaseAiTab({
    super.key,
    required this.caseKey,
    required this.record,
    required this.database,
    this.onOpenPath,
    this.onChanged,
    this.onChat,
    this.openChat,
    this.startCase,
  });

  final String? caseKey;
  final UyapCaseRecord? record;
  final Future<PortalDatabase> Function() database;
  final ValueChanged<String>? onOpenPath;

  /// Something kept or taken off: the tab's count read again.
  final VoidCallback? onChanged;

  /// A case's tab: a conversation is had on the Yapay zekâ page, this
  /// opening it there ([chatId] null for a new one of the case).
  final void Function(String? chatId)? onChat;

  /// The Yapay zekâ page's: the conversation to open, or a new one of
  /// [startCase].
  final String? openChat;
  final UyapCaseRecord? startCase;

  @override
  State<CaseAiTab> createState() => _CaseAiTabState();
}

class _CaseAiTabState extends State<CaseAiTab> {
  List<Map<String, Object?>> _chats = const [], _findings = const [];
  List<Map<String, Object?>> _drafts = const [];
  bool _loaded = false;
  Map<String, ({String court, String number})> _names = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_first());
  }

  Future<void> _first() async {
    await _load();
    if (!mounted) return;
    if (widget.openChat case final id?) {
      await _show(id);
    } else if (widget.startCase case final kase?) {
      setState(() {
        _openId = null;
        _openCase = kase;
        _slot++;
        _talking = true;
      });
    }
  }

  Future<void> _load() async {
    final db = await widget.database();
    final key = widget.caseKey;
    List<Map<String, Object?>> newest(String kind, String at) =>
        db.aiRecords(kind, caseKey: key)
          ..sort((a, b) => '${b[at]}'.compareTo('${a[at]}'));
    // The cases of the home page's conversations, by key, for what they
    // are called.
    final names = <String, ({String court, String number})>{};
    if (key == null) {
      for (final c in db.aiRecords(AiMemory.chat)) {
        final k = '${c['dosya'] ?? ''}';
        if (k.isEmpty || names.containsKey(k)) continue;
        if (db.caseOf(k) case final kase?) {
          names[k] = (court: kase.court, number: kase.number);
        } else if (c['mahkeme'] is String) {
          names[k] = (court: '${c['mahkeme']}', number: '${c['esas']}');
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _names = names;
      _chats = newest(AiMemory.chat, 'guncellendi');
      if (key != null) {
        _findings = newest(AiMemory.finding, 'zaman');
        _drafts = newest(AiMemory.draft, 'zaman');
      }
      _loaded = true;
    });
    widget.onChanged?.call();
  }

  static String _day(Object? at) {
    final t = DateTime.tryParse('${at ?? ''}');
    if (t == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year}';
  }

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
    db.putAiRecord(
      '${finding['id']}',
      AiMemory.finding,
      '${finding['dosya']}',
      {
        ...finding,
        'yanlis': {'neden': reason, 'zaman': DateTime.now().toIso8601String()},
      },
    );
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

  /// What the tab shows: the conversations, the findings or the drafts.
  _Part _part = _Part.chats;

  /// The conversation open: null for a new one. [_slot] names the panel
  /// shown, a new one each time another is opened, never as an answer is
  /// kept (the panel keeps what it put before the lawyer).
  String? _openId;
  int _slot = 0;

  /// On a narrow screen the list and the conversation take the room by
  /// turns: whether the conversation has it.
  bool _talking = false;

  Map<String, Object?>? get _open =>
      _chats.where((c) => c['id'] == _openId).firstOrNull;

  /// The case of the conversation open on the home page, read for it.
  UyapCaseRecord? _openCase;

  Future<void> _show(String? id) async {
    UyapCaseRecord? kase;
    final chat = _chats.where((c) => c['id'] == id).firstOrNull;
    final named = _names['${chat?['dosya'] ?? ''}'];
    if (widget.caseKey == null && named != null) {
      final (:court, :number) = named;
      kase =
          await UyapCaseStore.instance.load(court, number) ??
          UyapCaseRecord(
            court: court,
            number: number,
            fetchedAt: DateTime.now(),
          );
    }
    if (!mounted) return;
    setState(() {
      _openId = id;
      _openCase = kase;
      _slot++;
      _talking = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final scheme = Theme.of(context).colorScheme;
    final standing = _findings.where((f) => f['yanlis'] == null).length;
    Widget chip(_Part part, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey('case-ai-part-${part.name}'),
        label: Text(label),
        selected: _part == part,
        onSelected: (_) => setState(() => _part = part),
      ),
    );
    // The home page's: the conversations alone.
    if (widget.caseKey == null) {
      return KeyedSubtree(
        key: const ValueKey('home-ai'),
        child: _chatsPart(scheme),
      );
    }
    return Column(
      key: const ValueKey('case-ai-tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chip(_Part.chats, 'Sohbetler · ${_chats.length}'),
                chip(_Part.findings, 'Bulgular · $standing'),
                chip(_Part.drafts, 'Taslaklar · ${_drafts.length}'),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: switch (_part) {
            _Part.chats => _chatsPart(scheme),
            _Part.findings => _findingsPart(scheme),
            _Part.drafts => _draftsPart(),
          },
        ),
      ],
    );
  }

  bool get _asks =>
      AiAssistant.shown && (widget.caseKey == null || widget.record != null);

  /// A case's conversations, each opened on the Yapay zekâ page.
  Widget _chatLinks(ColorScheme scheme) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: const ValueKey('case-ai-new'),
          onPressed: () => widget.onChat!(null),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Bu dosyayla yeni sohbet'),
        ),
      ),
      const SizedBox(height: 10),
      if (_chats.isEmpty) _empty('Bu dosyada henüz sohbet yok.'),
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
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => widget.onChat!('${c['id']}'),
          ),
        ),
    ],
  );

  Widget _chatsPart(ColorScheme scheme) => widget.onChat != null && _asks
      ? _chatLinks(scheme)
      : LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 720;
            final list = _chatList(scheme);
            final talk = _conversation(scheme, back: !wide);
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 280, child: list),
                  VerticalDivider(width: 1, color: scheme.outlineVariant),
                  Expanded(child: talk),
                ],
              );
            }
            return _talking ? talk : list;
          },
        );

  Widget _chatList(ColorScheme scheme) => ListView(
    padding: const EdgeInsets.all(10),
    children: [
      if (_asks)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: FilledButton.icon(
            key: const ValueKey('case-ai-new'),
            onPressed: () => unawaited(_show(null)),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Yeni sohbet'),
          ),
        )
      else if (!AiAssistant.available)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            'Bu cihazda yapay zekâya soru sorulmaz; bilgisayarınızda '
            'yapılanlar burada okunur.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      if (_chats.isEmpty) _empty('Bu dosyada henüz sohbet yok.'),
      for (final c in _chats)
        Material(
          color: c['id'] == _openId
              ? scheme.primary.withValues(alpha: .08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: ListTile(
            key: ValueKey('case-ai-chat-${c['id']}'),
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            title: Text(
              '${c['baslik'] ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                if (widget.caseKey == null)
                  switch (_names['${c['dosya'] ?? ''}']) {
                    final n? => '${n.number} · ${n.court}',
                    null => 'Dosyasız',
                  },
                _day(c['guncellendi']),
                if (AiMemory.turnsOf(c).lastOrNull?['yazan'] case final by?)
                  '$by',
                '${AiMemory.turnsOf(c).length} soru',
              ].join(' · '),
              style: const TextStyle(fontSize: 11.5),
            ),
            onTap: () => unawaited(_show('${c['id']}')),
            trailing: PopupMenuButton<String>(
              tooltip: 'Sohbet',
              onSelected: (_) => _removeChat(c),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'sil', child: Text('Sohbeti sil')),
              ],
            ),
          ),
        ),
    ],
  );

  /// The conversation open, asked on where this device asks; read where
  /// it does not.
  Widget _conversation(ColorScheme scheme, {required bool back}) {
    final open = _open;
    final record = widget.record;
    final Widget body;
    if (_asks) {
      body = AiPanel(
        key: ValueKey('case-ai-panel-$_slot'),
        caseRecord: record ?? _openCase,
        chat: open,
        embedded: true,
        showCase: widget.caseKey == null,
        onOpen: widget.onOpenPath,
        onKept: (id) {
          _openId = id;
          unawaited(_load());
        },
      );
    } else if (open == null) {
      body = Center(child: _empty('Okumak için soldan bir sohbet seçin.'));
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final t in AiMemory.turnsOf(open)) ...[
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                margin: const EdgeInsets.only(left: 40, bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${t['soru'] ?? ''}',
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ),
            ),
            Text(
              '${t['yazan'] ?? ''}',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            SelectableText(
              '${t['cevap'] ?? ''}',
              style: const TextStyle(fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 16),
          ],
        ],
      );
    }
    if (!back) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('case-ai-back'),
            onPressed: () => setState(() => _talking = false),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Sohbetler'),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _findingsPart(ColorScheme scheme) {
    final byKind = <String, List<Map<String, Object?>>>{};
    for (final f in _findings) {
      byKind.putIfAbsent('${f['tur']}', () => []).add(f);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
      children: [
        if (_findings.isEmpty)
          _empty(
            'Kaydedilmiş bulgu yok. Yapay zekâ bulgu önerdiğinde sohbette '
            'onayınıza sunulur.',
          ),
        for (final kind in [
          ...AiMemory.kinds.keys.where(byKind.containsKey),
          ...byKind.keys.where((k) => !AiMemory.kinds.containsKey(k)),
        ]) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
            child: Text(
              AiMemory.kinds[kind] ?? kind,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final f in byKind[kind]!) _finding(f, scheme),
        ],
      ],
    );
  }

  Widget _draftsPart() => ListView(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
    children: [
      if (_drafts.isEmpty)
        _empty('Yapay zekânın yazıp kaydettiğiniz taslak yok.'),
      for (final d in _drafts)
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.description_outlined),
            title: Text('${d['baslik'] ?? ''}'),
            subtitle: Text(
              '${_day(d['zaman'])} · Yapay zekâ taslağı · ${d['yazan'] ?? ''}',
            ),
            onTap: () => _openDraft(d),
          ),
        ),
    ],
  );

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
                              'kaynağında denetlendi',
                          ].join(' · '),
                    style: TextStyle(
                      fontSize: 11,
                      color: wrong != null
                          ? scheme.error
                          : scheme.onSurfaceVariant,
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

enum _Part { chats, findings, drafts }
