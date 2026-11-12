import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/ai/ai_assistant.dart';
import '../../services/ai/ai_groq.dart';
import '../../services/ai/ai_memory.dart';
import '../../services/portal/observed.dart' show caseKey;
import '../../services/portal/portal_database.dart';
import '../../services/uyap/uyap_case_store.dart';
import 'ai_markdown.dart';
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
    PortalAi.changes.addListener(_changed);
    unawaited(_first());
  }

  /// A record kept here or come from an own device: read again.
  void _changed() {
    if (mounted) unawaited(_load());
  }

  @override
  void dispose() {
    PortalAi.changes.removeListener(_changed);
    _question.dispose();
    super.dispose();
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

  /// A conversation renamed or taken off.
  Widget _chatMenu(Map<String, Object?> c) => PopupMenuButton<String>(
    key: ValueKey('case-ai-chat-menu-${c['id']}'),
    tooltip: 'Sohbet',
    onSelected: (v) => unawaited(v == 'ad' ? _renameChat(c) : _removeChat(c)),
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'ad', child: Text('Adını değiştir')),
      PopupMenuItem(value: 'sil', child: Text('Sohbeti sil')),
    ],
  );

  Future<void> _renameChat(Map<String, Object?> chat) async {
    final name = TextEditingController(text: '${chat['baslik'] ?? ''}');
    final given = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sohbetin adı'),
        content: SizedBox(
          width: 420,
          child: TextField(
            key: const ValueKey('case-ai-chat-name'),
            controller: name,
            autofocus: true,
            maxLength: 120,
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const ValueKey('case-ai-chat-name-save'),
            onPressed: () => Navigator.pop(context, name.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    name.dispose();
    if (given == null || given.isEmpty) return;
    (await widget.database()).putAiRecord(
      '${chat['id']}',
      AiMemory.chat,
      '${chat['dosya'] ?? ''}',
      {...chat, 'baslik': given},
    );
    await _load();
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
    // What the API services were told in it, kept on this computer.
    await GroqChat.forget('${chat['id']}');
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

  /// On a wide one, whether the list is beside the conversation: as the
  /// lawyer last chose, kept while Folio is open; else when the page has
  /// room for both (not on a 1280 or 1366 laptop's screen).
  static bool? _listChoice;

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
            trailing: _chatMenu(c),
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
            final listShown = _listChoice ?? box.maxWidth >= 1000;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (listShown) ...[
                    SizedBox(width: 320, child: list),
                    VerticalDivider(width: 1, color: scheme.outlineVariant),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The list put away for the conversation's room;
                        // above the conversation, not over its first line.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: listShown
                                ? IconButton(
                                    key: const ValueKey('case-ai-list-toggle'),
                                    tooltip: 'Sohbet listesini gizle',
                                    onPressed: () =>
                                        setState(() => _listChoice = false),
                                    icon: const Icon(
                                      Icons.keyboard_double_arrow_left_rounded,
                                      size: 18,
                                    ),
                                  )
                                // Put away, named: the lawyer finds it again.
                                : TextButton.icon(
                                    key: const ValueKey('case-ai-list-toggle'),
                                    onPressed: () =>
                                        setState(() => _listChoice = true),
                                    icon: const Icon(
                                      Icons.keyboard_double_arrow_right_rounded,
                                      size: 18,
                                    ),
                                    label: Text('Sohbetler · ${_chats.length}'),
                                  ),
                          ),
                        ),
                        Expanded(child: talk),
                      ],
                    ),
                  ),
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
      else if (_relays) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FilledButton.icon(
            key: const ValueKey('case-ai-new'),
            onPressed: () => unawaited(_show(null)),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Yeni soru'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            'Sorularınızı bilgisayarınızdaki Folio, kendi yapay zekâ '
            'programıyla cevaplar. Bilgisayar kapalıysa açıldığında '
            'cevaplanır.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
            trailing: _chatMenu(c),
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
    } else if (open == null && !_relays) {
      body = Center(child: _empty('Okumak için soldan bir sohbet seçin.'));
    } else {
      final turns = open == null
          ? const <Map<String, Object?>>[]
          : AiMemory.turnsOf(open);
      final list = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (turns.isEmpty)
            _empty(
              'Sorunuzu aşağıya yazın. Bir dosyayla ilgiliyse dosyayı '
              'numarasıyla, mahkemesiyle ya da bir tarafıyla anmanız yeter.',
            ),
          for (final (i, t) in turns.indexed) ...[
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
            if (t['bekliyor'] == true)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    if (t['alindi'] != null)
                      const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t['alindi'] != null
                            ? '${t['cevaplayan'] ?? 'Bilgisayarınız'} '
                                  'cevaplıyor…'
                            : 'Bilgisayarınız açılınca ve bu cihazla '
                                  'eşitlenince cevaplanacak.',
                        key: const ValueKey('case-ai-waiting'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (t['hata'] != null)
              Text('${t['hata']}', style: TextStyle(color: scheme.error))
            else ...[
              Text(
                '${t['yazan'] ?? ''}',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              AiMarkdown('${t['cevap'] ?? ''}'),
              for (final (j, o) in [
                for (final o in t['teklifler'] as List? ?? const [])
                  if (o is Map) o.cast<String, Object?>(),
              ].indexed)
                _relayOffer(open!, i, j, o, scheme),
            ],
            const SizedBox(height: 16),
          ],
        ],
      );
      body = !_relays
          ? list
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: list),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 8, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('case-ai-relay-question'),
                          controller: _question,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => unawaited(_relayAsk()),
                          decoration: const InputDecoration(
                            hintText: 'Sorun…',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('case-ai-relay-send'),
                        tooltip: 'Gönder',
                        onPressed: () => unawaited(_relayAsk()),
                        icon: const Icon(Icons.send_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
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

  /// Asked here and answered by the lawyer's computer (AiRelay): a device
  /// that runs no AI program, with the features on.
  bool get _relays => !AiAssistant.available && AiSettings.on.value;

  final _question = TextEditingController();

  /// The question written into the conversation open, or a new one, as
  /// waiting: the computer takes it when Senkron brings it.
  Future<void> _relayAsk() async {
    final text = _question.text.trim();
    if (text.isEmpty) return;
    final db = await widget.database();
    final now = DateTime.now();
    final turn = {
      'soru': text,
      'bekliyor': true,
      'soran': 'telefon',
      'zaman': now.toIso8601String(),
    };
    final open = _open;
    if (open == null) {
      final id = AiMemory.id();
      final kase = widget.record ?? _openCase;
      db.putAiRecord(
        id,
        AiMemory.chat,
        widget.caseKey ??
            (kase == null ? '' : caseKey(kase.number, kase.court)),
        AiMemory.chatRecord(
          title: text,
          document: '',
          started: now,
          turns: [turn],
          court: kase?.court,
          number: kase?.number,
        ),
      );
      _openId = id;
    } else {
      db.putAiRecord('${open['id']}', AiMemory.chat, '${open['dosya']}', {
        ...open,
        'turlar': [...AiMemory.turnsOf(open), turn],
        'guncellendi': now.toIso8601String(),
      });
    }
    _question.clear();
    await _load();
  }

  /// What the computer's program offered with the [turn]th answer of
  /// [chat]: kept here, on the lawyer's word, as the case's.
  Widget _relayOffer(
    Map<String, Object?> chat,
    int turn,
    int index,
    Map<String, Object?> offer,
    ColorScheme scheme,
  ) {
    final findings = offer['tur'] == AiMemory.finding;
    final items = [
      for (final f in offer['bulgular'] as List? ?? const [])
        if (f is Map) f.cast<String, Object?>(),
    ];
    final decided = offer['karar'] as String?;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            findings
                ? 'Dosyaya ${items.length} bulgu kaydedilsin mi?'
                : 'Taslak: ${offer['baslik'] ?? ''}',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          if (findings)
            for (final f in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${AiMemory.kinds[f['tur']] ?? f['tur']}: ${f['metin']}',
                  style: const TextStyle(fontSize: 12.5),
                ),
              )
          else
            Text(
              '${offer['metin'] ?? ''}',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          if (decided != null)
            Text(
              decided,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      unawaited(_decideRelayed(chat, turn, index, false)),
                  child: const Text('Kaydetme'),
                ),
                FilledButton(
                  key: ValueKey('case-ai-relay-keep-$turn-$index'),
                  onPressed: () =>
                      unawaited(_decideRelayed(chat, turn, index, true)),
                  child: Text(findings ? 'Kaydet' : 'Taslağı kaydet'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _decideRelayed(
    Map<String, Object?> chat,
    int turn,
    int index,
    bool keep,
  ) async {
    final db = await widget.database();
    final key = '${chat['dosya'] ?? ''}';
    final turns = AiMemory.turnsOf(chat);
    final offers = [
      for (final o in turns[turn]['teklifler'] as List? ?? const [])
        if (o is Map) o.cast<String, Object?>(),
    ];
    final offer = offers[index];
    final now = DateTime.now().toIso8601String();
    var said = 'Kaydedilmedi';
    if (keep && key.isNotEmpty) {
      if (offer['tur'] == AiMemory.finding) {
        final items = offer['bulgular'] as List? ?? const [];
        for (final f in items) {
          if (f is! Map) continue;
          db.putAiRecord(AiMemory.id(), AiMemory.finding, key, {
            ...f.cast<String, Object?>(),
            'sohbet': chat['id'],
            'yazan': turns[turn]['yazan'],
            'zaman': now,
          });
        }
        said = '${items.length} bulgu dosyaya kaydedildi';
      } else {
        db.putAiRecord(AiMemory.id(), AiMemory.draft, key, {
          'baslik': offer['baslik'],
          'metin': offer['metin'],
          'sohbet': chat['id'],
          'yazan': turns[turn]['yazan'],
          'zaman': now,
        });
        said = 'Taslak kaydedildi.';
      }
    } else if (keep) {
      said = 'Sohbet bir dosyaya bağlı değil; kaydedilemedi.';
    }
    offers[index] = {...offer, 'karar': said};
    turns[turn] = {...turns[turn], 'teklifler': offers};
    db.putAiRecord('${chat['id']}', AiMemory.chat, key, {
      ...chat,
      'turlar': turns,
    });
    await _load();
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
