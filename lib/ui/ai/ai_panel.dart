import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/ai/ai_assistant.dart';
import '../../services/ai/ai_case.dart';
import '../../services/ai/ai_draft.dart';
import '../../services/ai/ai_memory.dart';
import '../../services/ai/folio_mcp.dart';
import '../../services/portal/observed.dart' show caseKey;
import '../../services/portal/portal_database.dart';
import '../../services/uyap/uyap_case_panel_controller.dart';
import '../../services/uyap/uyap_case_store.dart';
import 'ai_dialogs.dart';

/// Beside a document's preview: the document summarised or asked about by
/// the lawyer's own AI program ([AiAssistant]). Nothing is sent before the
/// lawyer presses a button, nor before the consent asked once. A document
/// of a case keeps the conversation with the case (AiMemory), and the
/// findings and drafts the lawyer agrees to; with no document, the
/// questions are of [caseRecord] itself, [chat] one gone on with.
class AiPanel extends StatefulWidget {
  const AiPanel({
    super.key,
    this.path,
    this.caseRecord,
    this.chat,
    this.onClose,
    this.onOpen,
  }) : assert(path != null || caseRecord != null);

  final String? path;
  final UyapCaseRecord? caseRecord;
  final Map<String, Object?>? chat;
  final VoidCallback? onClose;

  /// Opens a draft saved in the case's folder, in the editor.
  final void Function(String path)? onOpen;

  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _Turn {
  _Turn(this.question, this.by);
  final String question;

  /// Who answers: the program and the tier, as the lawyer sees them.
  final String by;
  String? answer;
  String? error;

  /// The answer's citations as Folio found them (FolioMcp.atif_dogrula);
  /// null while they are being checked.
  List<Map<String, Object?>>? checks;

  /// The documents the program asked to download, as the lawyer answered.
  final requests = <_Request>[];

  /// What the program put before the lawyer: findings to keep, drafts.
  final offers = <_Offer>[];
}

/// Findings or a draft the program offered, waiting for the lawyer or
/// decided.
class _Offer {
  _Offer(this.kind, this.body)
    : chosen = {
        for (var i = 0; i < (body['bulgular'] as List? ?? const []).length; i++)
          i,
      };
  final String kind;
  final Map<String, Object?> body;

  /// The findings ticked to keep.
  final Set<int> chosen;
  String? outcome;

  List<Map<String, Object?>> get findings => [
    for (final f in body['bulgular'] as List? ?? const [])
      if (f is Map) f.cast<String, Object?>(),
  ];
}

/// A download the AI program asked for, waiting for the lawyer or
/// answered.
class _Request {
  _Request(this.asked, this.title);
  final AiDownloadRequest asked;
  final String title;

  /// What came of it, said to the lawyer; null while it waits.
  String? outcome;
  bool working = false;
}

class _AiPanelState extends State<AiPanel> {
  List<AiStatus>? _found;
  AiProvider? _provider;
  final _turns = <_Turn>[];
  final _question = TextEditingController();
  final _scroll = ScrollController();
  Completer<void>? _cancel;
  String? _text;
  AiProvider? _sentTo;

  /// The case the document belongs to, whose other documents the program
  /// may read with Folio's tools; null for a document of no case.
  UyapCaseRecord? _case;
  AiCaseSession? _session;

  /// The conversation as kept with the case: its id once the first answer
  /// came, and when it began.
  String? _chatId;
  DateTime _chatStarted = DateTime.now();

  bool get _busy => _cancel != null;

  @override
  void initState() {
    super.initState();
    if (widget.chat case final chat?) {
      _chatId = chat['id'] as String?;
      _chatStarted =
          DateTime.tryParse('${chat['basladi'] ?? ''}') ?? DateTime.now();
      for (final t in AiMemory.turnsOf(chat)) {
        _turns.add(
          _Turn('${t['soru'] ?? ''}', '${t['yazan'] ?? ''}')
            ..answer = '${t['cevap'] ?? ''}',
        );
      }
    }
    unawaited(_load());
  }

  @override
  void didUpdateWidget(AiPanel old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _cancel?.complete();
      _cancel = null;
      _turns.clear();
      _text = null;
      _sentTo = null;
      _case = null;
      _chatId = null;
      _chatStarted = DateTime.now();
      unawaited(_findCase());
    }
  }

  Future<void> _findCase() async {
    final path = widget.path;
    if (path == null) {
      setState(() => _case = widget.caseRecord);
      return;
    }
    UyapCaseRecord? record;
    try {
      record = await AiCaseSession.ofDocument(path, UyapCaseStore.instance);
    } catch (_) {}
    if (mounted && widget.path == path) setState(() => _case = record);
  }

  @override
  void dispose() {
    _cancel?.complete();
    _question.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    unawaited(_findCase());
    final settings = await AiSettings.load();
    final found = await AiAssistant.statuses();
    if (!mounted) return;
    AiProvider? use = settings.provider;
    if (use == null || !found.any((s) => s.provider == use && s.usable)) {
      use = found.where((s) => s.usable).map((s) => s.provider).firstOrNull;
    }
    setState(() {
      _found = found;
      _provider = use;
    });
  }

  /// "Anthropic’e", "OpenAI’a", "Google’a".
  static String _to(AiProvider provider) => switch (provider) {
    AiProvider.claude => 'Anthropic’e',
    AiProvider.codex => 'OpenAI’a',
    AiProvider.antigravity => 'Google’a',
  };

  Future<void> _ask(AiTask task, [String question = '']) async {
    final provider = _provider;
    if (provider == null || _busy) return;
    if (!await askAiConsent(context)) return;
    final settings = await AiSettings.load();
    final model = settings.modelFor(provider, task.tier);
    final turn = _Turn(
      task == AiTask.summary ? 'Belgeyi özetle' : question.trim(),
      '${provider.label} · ${task.tier.label}',
    );
    final cancel = Completer<void>();
    setState(() {
      _turns.add(turn);
      _cancel = cancel;
    });
    _question.clear();
    _toEnd();
    try {
      final path = widget.path;
      String? text;
      if (path != null) {
        text = _text ??= await AiAssistant.documentText(path);
        if (text.trim().isEmpty) {
          throw const AiFailure(
            'Bu belgede okunabilir metin bulunamadı; gönderilecek bir şey '
            'yok.',
          );
        }
        if (settings.mask) {
          text = AiAssistant.maskIdentityNumbers(text);
        }
      }
      final history = [
        for (final t in _turns)
          if (t != turn && t.answer != null)
            (question: t.question, answer: t.answer!),
      ];
      // The case's tools only for a program given Folio's tools.
      final record = _case;
      final withCase =
          record != null &&
          (AiAssistant.takesTools(provider) ||
              await AiAssistant.antigravityFolio() != null);
      if (record == null && path == null) return;
      final db = withCase ? await PortalDatabase.shared() : null;
      final key = record == null ? null : caseKey(record.number, record.court);
      final prompt = AiAssistant.prompt(
        task: task,
        name: path == null ? null : p.basename(path),
        text: text,
        question: question,
        caseName: withCase ? '${record.court} ${record.number}' : null,
        // The case's memory, for the program to read first.
        note: db == null ? null : AiMemory.hint(db.aiCounts(key!)),
        history: history,
      );
      if (cancel.isCompleted) return;
      setState(() => _sentTo = provider);
      if (withCase) _chatId ??= AiMemory.id();
      final session = withCase
          ? await AiCaseSession.open(record, chat: _chatId)
          : null;
      _session = session;
      final watch = session == null
          ? null
          : Timer.periodic(
              const Duration(milliseconds: 700),
              (_) => unawaited(_look(session, turn)),
            );
      try {
        final answer = await AiAssistant.ask(
          provider,
          prompt,
          model: model,
          caseSession: session,
          cancel: cancel.future,
        );
        turn.answer = answer;
        unawaited(_check(turn, answer));
        if (db != null) _keep(db, key!);
      } finally {
        watch?.cancel();
        // What it put before the lawyer at the very end.
        if (session != null) await _look(session, turn);
        _session = null;
        unawaited(session?.close());
        for (final r in turn.requests) {
          r.outcome ??= 'Yanıtlanmadı';
        }
      }
    } on AiFailure catch (e) {
      turn.error = e.message;
    } catch (e) {
      turn.error = 'Yanıt alınamadı: $e';
    } finally {
      if (mounted) {
        setState(() {
          if (identical(_cancel, cancel)) _cancel = null;
        });
        _toEnd();
      }
    }
  }

  /// The conversation kept with the case [key], as it is now.
  void _keep(PortalDatabase db, String key) {
    final id = _chatId;
    if (id == null) return;
    final turns = [
      for (final t in _turns)
        if (t.answer case final a?)
          {
            'soru': t.question,
            'cevap': a,
            'yazan': t.by,
            'zaman': DateTime.now().toIso8601String(),
          },
    ];
    if (turns.isEmpty) return;
    try {
      db.putAiRecord(
        id,
        AiMemory.chat,
        key,
        AiMemory.chatRecord(
          title: _turns.first.question,
          document: widget.path == null ? '' : p.basename(widget.path!),
          started: _chatStarted,
          turns: turns,
        ),
      );
    } catch (_) {}
  }

  /// Downloads the program asked for in [session], and the findings and
  /// drafts it offered, put before the lawyer.
  Future<void> _look(AiCaseSession session, _Turn turn) async {
    final offered = await session.proposals();
    if (offered.isNotEmpty && mounted) {
      setState(() {
        for (final o in offered) {
          turn.offers.add(_Offer(o.kind, o.body));
        }
      });
      _toEnd();
    }
    final asked = await session.pending();
    if (!mounted || !identical(_session, session)) return;
    final known = {for (final r in turn.requests) r.asked.id};
    final fresh = [
      for (final a in asked)
        if (!known.contains(a.id))
          _Request(
            a,
            [
                  for (final d in session.record.documents) ...[
                    d,
                    ...d.attachments,
                  ],
                ].where((d) => d.key == a.key).firstOrNull?.title ??
                'Evrak',
          ),
    ];
    if (fresh.isEmpty) return;
    setState(() => turn.requests.addAll(fresh));
    _toEnd();
  }

  /// The lawyer's answer to [request]: downloaded from UYAP when agreed.
  Future<void> _answer(_Request request, bool agreed) async {
    final session = _session;
    if (session == null || request.outcome != null || request.working) return;
    if (!agreed) {
      await session.answer(
        request.asked,
        'reddedildi',
        'Avukat bu evrakın indirilmesini istemedi.',
      );
      setState(() => request.outcome = 'İndirilmedi');
      return;
    }
    setState(() => request.working = true);
    final store = UyapCaseStore.instance;
    final panel = UyapCasePanelController(store: store);
    try {
      if (!panel.connected) {
        await session.answer(
          request.asked,
          'uyap_bagli_degil',
          'Folio UYAP\'a bağlı değil; evrak indirilemedi.',
        );
        if (mounted) {
          setState(() => request.outcome = 'UYAP’a bağlı değil; indirilemedi');
        }
        return;
      }
      await panel.show(session.record);
      await panel.download([request.asked.key]);
      final now = await store.load(session.record.court, session.record.number);
      final done = now != null && store.fileOf(now, request.asked.key) != null;
      await session.answer(
        request.asked,
        done ? 'indirildi' : 'indirilemedi',
        done ? null : 'UYAP evrakı vermedi.',
      );
      if (mounted) {
        setState(() => request.outcome = done ? 'İndirildi' : 'İndirilemedi');
      }
    } catch (e) {
      await session.answer(request.asked, 'indirilemedi', '$e');
      if (mounted) setState(() => request.outcome = 'İndirilemedi');
    } finally {
      panel.dispose();
      if (mounted) setState(() => request.working = false);
    }
  }

  Widget _request(_Request r, ColorScheme scheme) => Container(
    key: ValueKey('ai-request-${r.asked.id}'),
    margin: const EdgeInsets.only(top: 6, bottom: 4),
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
    decoration: BoxDecoration(
      border: Border.all(color: scheme.outlineVariant),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.download_outlined, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'Evrak indirme isteği',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(r.title, style: const TextStyle(fontSize: 13)),
        if (r.asked.reason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Neden: ${r.asked.reason}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        if (r.outcome case final o?)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text(
              o,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: o == 'İndirildi'
                    ? const Color(0xFF157A52)
                    : scheme.onSurfaceVariant,
              ),
            ),
          )
        else if (r.working)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: ValueKey('ai-request-no-${r.asked.id}'),
                onPressed: () => _answer(r, false),
                child: const Text('İndirme'),
              ),
              FilledButton(
                key: ValueKey('ai-request-yes-${r.asked.id}'),
                onPressed: () => _answer(r, true),
                child: const Text('İndir'),
              ),
            ],
          ),
      ],
    ),
  );

  /// [offer] kept as the lawyer chose: the findings ticked as the case's,
  /// or the draft saved in its folder and opened.
  Future<void> _decide(_Turn turn, _Offer offer, bool keep) async {
    final record = _case;
    if (offer.outcome != null || record == null) return;
    if (!keep) {
      setState(
        () => offer.outcome = offer.kind == AiMemory.finding
            ? 'Kaydedilmedi'
            : 'Taslak kaydedilmedi',
      );
      return;
    }
    final key = caseKey(record.number, record.court);
    try {
      final db = await PortalDatabase.shared();
      final now = DateTime.now().toIso8601String();
      if (offer.kind == AiMemory.finding) {
        final chosen = [
          for (final (i, f) in offer.findings.indexed)
            if (offer.chosen.contains(i)) f,
        ];
        for (final f in chosen) {
          db.putAiRecord(AiMemory.id(), AiMemory.finding, key, {
            ...f,
            'sohbet': ?_chatId,
            'yazan': turn.by,
            'zaman': now,
          });
        }
        setState(
          () => offer.outcome = chosen.isEmpty
              ? 'Kaydedilmedi'
              : '${chosen.length} bulgu dosyaya kaydedildi',
        );
      } else {
        final title = '${offer.body['baslik'] ?? 'Taslak'}';
        final text = '${offer.body['metin'] ?? ''}';
        final path = await writeAiDraft(
          UyapCaseStore.instance,
          record,
          title,
          text,
        );
        db.putAiRecord(AiMemory.id(), AiMemory.draft, key, {
          'baslik': title,
          'metin': text,
          'yol': path,
          'sohbet': ?_chatId,
          'yazan': turn.by,
          'zaman': now,
        });
        setState(() => offer.outcome = 'Kaydedildi: ${p.basename(path)}');
        widget.onOpen?.call(path);
      }
    } catch (e) {
      if (mounted) setState(() => offer.outcome = 'Kaydedilemedi: $e');
    }
  }

  Widget _offer(_Turn turn, _Offer o, ColorScheme scheme) {
    final findings = o.kind == AiMemory.finding;
    final items = o.findings;
    return Container(
      key: ValueKey('ai-offer-${o.kind}-${identityHashCode(o)}'),
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                findings
                    ? Icons.bookmark_border_rounded
                    : Icons.description_outlined,
                size: 16,
                color: scheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  findings
                      ? 'Dosyaya ${items.length} bulgu kaydedilsin mi?'
                      : 'Taslak: ${o.body['baslik'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (findings)
            for (final (i, f) in items.indexed)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: o.chosen.contains(i),
                onChanged: o.outcome != null
                    ? null
                    : (v) => setState(
                        () => v == true ? o.chosen.add(i) : o.chosen.remove(i),
                      ),
                title: Text(
                  '${AiMemory.kinds[f['tur']] ?? f['tur']}: ${f['metin']}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                subtitle: Text(
                  [
                    ...?(f['kaynaklar'] as List?)?.map((k) => '$k'),
                    if (f['denetim'] == 'dogrulandi') 'kaynağında denetlendi',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${o.body['metin'] ?? ''}',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          if (o.outcome case final done?)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                done,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const ValueKey('ai-offer-no'),
                  onPressed: () => _decide(turn, o, false),
                  child: const Text('Kaydetme'),
                ),
                FilledButton(
                  key: const ValueKey('ai-offer-yes'),
                  onPressed: () => _decide(turn, o, true),
                  child: Text(findings ? 'Kaydet' : 'Dosyaya kaydet ve aç'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Folio's own look at the answer's citations, shown under it: none is
  /// changed, each found, missing or repealed is said so.
  Future<void> _check(_Turn turn, String answer) async {
    try {
      final got = await _mcp.call('atif_dogrula', {'metin': answer});
      final list = [
        for (final one in got['atiflar'] as List? ?? const [])
          if (one is Map) one.cast<String, Object?>(),
      ];
      if (mounted) setState(() => turn.checks = list);
    } catch (_) {
      if (mounted) setState(() => turn.checks = const []);
    }
  }

  final _mcp = FolioMcp();

  Widget _checks(List<Map<String, Object?>> checks, ColorScheme scheme) {
    if (checks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Folio’nun denetimi',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          for (final c in checks)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (c['durum']) {
                      'bulundu' => Icons.check_circle_outline,
                      'mulga' => Icons.history_toggle_off,
                      'ulasilamadi' => Icons.cloud_off_outlined,
                      _ => Icons.error_outline,
                    },
                    size: 15,
                    color: switch (c['durum']) {
                      'bulundu' => const Color(0xFF157A52),
                      'ulasilamadi' => scheme.onSurfaceVariant,
                      _ => scheme.error,
                    },
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${c['yazilan']}: ${switch (c['durum']) {
                        'bulundu' => 'resmî kaynakta var',
                        'mulga' => 'mülga',
                        'yayimlanmamis' => 'yayımlanmamış',
                        'ulasilamadi' => 'denetlenemedi',
                        _ => 'resmî kaynakta bulunamadı',
                      }}${c['daire_farkli'] == true ? ' (dairesi farklı)' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  });

  void _send() {
    final q = _question.text.trim();
    if (q.isEmpty) return;
    unawaited(_ask(AiTask.question, q));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final found = _found;
    final usable = [
      for (final s in found ?? const <AiStatus>[])
        if (s.usable) s.provider,
    ];
    return Container(
      key: const ValueKey('ai-panel'),
      width: 380,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Yapay zekâ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (usable.length > 1)
                  DropdownButton<AiProvider>(
                    key: const ValueKey('ai-provider'),
                    value: _provider,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final u in usable)
                        DropdownMenuItem(value: u, child: Text(u.label)),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _provider = v),
                  ),
                IconButton(
                  tooltip: 'Kapat',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          if (_case case final c?)
            Padding(
              key: const ValueKey('ai-case'),
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${c.court} · ${c.number}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          if (found == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_provider == null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'Bu bilgisayarda oturumu açık bir yapay zekâ programı '
                  'bulunamadı. Ayarlar › Yapay zekâ’dan Claude, Codex ya da '
                  'Antigravity’yi kurabilir ve oturum açabilirsiniz.',
                  key: const ValueKey('ai-none'),
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (widget.path != null)
                    FilledButton.icon(
                      key: const ValueKey('ai-summary'),
                      onPressed: _busy ? null : () => _ask(AiTask.summary),
                      icon: const Icon(Icons.subject_rounded, size: 18),
                      label: const Text('Özetle'),
                    ),
                  if (_busy)
                    OutlinedButton.icon(
                      key: const ValueKey('ai-stop'),
                      onPressed: () => _cancel?.complete(),
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: const Text('Durdur'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _turns.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        widget.path == null
                            ? 'Dosyayla ilgili sorunuzu aşağıya yazın. Yapay '
                                  'zekâ dosyanın bilgilerine, evrakına ve '
                                  'hafızasına Folio’nun araçlarıyla bakar.'
                            : 'Belgeyi özetletebilir ya da aşağıya belgeyle '
                                  'ilgili bir soru yazabilirsiniz. Bir şey '
                                  'göndermeden önce size sorulur.',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    )
                  : ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                      children: [
                        for (final t in _turns) ...[
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              margin: const EdgeInsets.only(top: 8, left: 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                t.question,
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 2),
                            child: Text(
                              t.by,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          for (final r in t.requests) _request(r, scheme),
                          if (t.answer case final a?) ...[
                            SelectableText(
                              a,
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.5,
                              ),
                            ),
                            if (t.checks case final c?) _checks(c, scheme),
                          ] else if (t.error case final e?)
                            Text(
                              e,
                              key: const ValueKey('ai-error'),
                              style: TextStyle(color: scheme.error),
                            )
                          else
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: LinearProgressIndicator(),
                            ),
                          for (final o in t.offers) _offer(t, o, scheme),
                        ],
                      ],
                    ),
            ),
            if (_sentTo case final to?)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: Text(
                  '${widget.path == null
                      ? 'Sorunuz ve yapay zekânın okuduğu dosya bilgileri'
                      : _case == null
                      ? 'Bu belgenin metni'
                      : 'Bu belgenin ve yapay zekânın okuduğu dosya evrakının metni'} '
                  '${_to(to)} gönderildi. Yanıtlar yanlış olabilir; karar '
                  'sizindir.',
                  key: const ValueKey('ai-sent-note'),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('ai-question'),
                      controller: _question,
                      enabled: !_busy,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: widget.path == null
                            ? 'Dosyaya sorun…'
                            : 'Belgeye sorun…',
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('ai-send'),
                    tooltip: 'Sor',
                    onPressed: _busy ? null : _send,
                    icon: const Icon(Icons.send_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
