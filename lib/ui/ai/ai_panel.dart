import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:file_picker/file_picker.dart';

import '../../models/evrak_file.dart';
import '../../services/ai/ai_assistant.dart';
import '../../services/ai/ai_attachment.dart';
import '../../services/ai/ai_case.dart';
import '../../services/ai/ai_draft.dart';
import '../../services/ai/ai_memory.dart';
import '../../services/ai/ai_refresh.dart';
import 'ai_markdown.dart';
import '../../services/ai/folio_mcp.dart';
import '../../services/legal/citation.dart';
import '../../services/legal/decision.dart';
import '../widgets/article_panel.dart';
import '../../services/portal/observed.dart' show caseKey;
import '../../services/portal/portal_database.dart';
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
    this.onKept,
    this.embedded = false,
    this.showCase = false,
  });

  final String? path;
  final UyapCaseRecord? caseRecord;
  final Map<String, Object?>? chat;
  final VoidCallback? onClose;

  /// Opens a draft saved in the case's folder, in the editor.
  final void Function(String path)? onOpen;

  /// The conversation kept with the case, by its id: after each answer.
  final void Function(String chatId)? onKept;

  /// In a case's page, filling the room it is given: no edge of its own,
  /// no closing, the case not named again.
  final bool embedded;

  /// Embedded on the home page: the case the conversation is of named all
  /// the same, with a way to take it off when the program chose wrong.
  final bool showCase;

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

  /// What the answer rests on as Folio read it in its text: articles
  /// ([Citation]) and decisions ([DecisionCitation]), each once.
  List<Object> sources = const [];

  /// The documents the program asked to download, as the lawyer answered.
  final requests = <_Request>[];

  /// What the program put before the lawyer: findings to keep, drafts.
  final offers = <_Offer>[];

  /// The documents the question went with, by name.
  List<String> attached = const [];

  /// What Folio did for it on the way (UYAP asked for fresh).
  final notes = <String>[];

  /// What the program did on the way: Folio's tools it called, by id;
  /// what it thought or remarked; the answer as it is being written.
  final steps = <String, AiStep>{};
  final thought = StringBuffer();
  final live = StringBuffer();
  final started = DateTime.now();

  /// The trace opened or folded by the lawyer; null to follow the work.
  bool? traceOpen;

  /// The steps of an answer kept, as they were told.
  List<String> recorded = const [];

  /// The documents it wrote.
  final documents = <_Doc>[];
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
  _Request(this.id, this.title);
  final String id;
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

  /// The conversation each program goes on with, and the documents added
  /// it was already given (by program and name).
  AiThread? _thread;
  final _given = <String>{};
  DateTime _chatStarted = DateTime.now();

  bool get _busy => _cancel != null;

  /// The documents the lawyer added to the conversation: sent with every
  /// question until taken off. Each made ready once a program.
  final _attached = <String>[];
  final _prepared = <String, AiAttachment>{};

  static const _attachable = [
    'pdf', 'udf', 'docx', 'doc', 'odt', 'rtf', 'txt', 'md', //
    'tif', 'tiff', 'png', 'jpg', 'jpeg', 'webp',
  ];

  Future<void> _attach() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Sohbete belge ekle',
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _attachable,
    );
    if (picked == null || !mounted) return;
    setState(() {
      for (final f in picked.files) {
        if (f.path case final path? when !_attached.contains(path)) {
          _attached.add(path);
        }
      }
    });
  }

  /// Whether a document added goes as pictures: what is in it, identity
  /// numbers too, goes as it is.
  bool get _sendsPictures => _attached.any(
    (path) => const {
      '.tif',
      '.tiff',
      '.png',
      '.jpg',
      '.jpeg',
      '.webp',
    }.contains(p.extension(path).toLowerCase()),
  );

  @override
  void initState() {
    super.initState();
    if (widget.chat case final chat?) {
      _chatId = chat['id'] as String?;
      if (_chatId case final id?) _thread = AiThread.of(id, chat['oturumlar']);
      _chatStarted =
          DateTime.tryParse('${chat['basladi'] ?? ''}') ?? DateTime.now();
      for (final t in AiMemory.turnsOf(chat)) {
        _turns.add(
          _Turn('${t['soru'] ?? ''}', '${t['yazan'] ?? ''}')
            ..answer = '${t['cevap'] ?? ''}'
            ..recorded = [
              for (final a in t['adimlar'] as List? ?? const []) '$a',
            ],
        );
        unawaited(_read(_turns.last));
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
      _thread = null;
      _given.clear();
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
    unawaited(_loadDocuments());
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
    // The seconds counted while it works.
    final tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
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
      // The documents added, made ready for this program.
      final attachments = <AiAttachment>[];
      for (final path in _attached) {
        final key = '${provider.name}|$path';
        attachments.add(
          _prepared[key] ??= await AiAttachment.prepare(
            path,
            provider,
            mask: settings.mask,
          ),
        );
      }
      turn.attached = [for (final a in attachments) a.name];
      // The case's tools only for a program given Folio's tools.
      final record = _case;
      final tools =
          AiAssistant.takesTools(provider) ||
          await AiAssistant.antigravityFolio() != null;
      final withCase = record != null && tools;
      // Asked of no document and no case: the program finds the case.
      final open = path == null && record == null && tools;
      final db = withCase || open ? await PortalDatabase.shared() : null;
      if (db != null) _chatId ??= AiMemory.id();
      // The program goes on with the conversation it had: the document,
      // the earlier answers and the documents it was given are not sent
      // again.
      final thread = _thread ??= AiThread(_chatId ?? AiMemory.id());
      final who = await AiAssistant.who();
      String prompt({required bool full}) => AiAssistant.prompt(
        task: task,
        name: path == null ? null : p.basename(path),
        text: full ? text : null,
        question: question,
        caseName: withCase ? '${record.court} ${record.number}' : null,
        note: withCase
            // The case's memory, for the program to read first.
            ? AiMemory.hint(db!.aiCounts(caseKey(record.number, record.court)))
            : open
            ? 'Soru avukatın bir dosyasıyla ilgiliyse dosya_ara ile dosyayı '
                  'bul; tek dosya açıkça uyuyorsa dosya_sec ile seç, birden '
                  'fazla uyuyorsa hangisi olduğunu avukata sor. Ajanda, '
                  'süre, tebligat ve bildirim soruları için Folio\'nun '
                  'ajanda, tebligatlar ve uyap_bildirimleri araçları var.'
            : null,
        attached: AiAttachment.block([
          for (final a in attachments)
            if (full || !_given.contains('${provider.name}|${a.name}')) a,
        ]),
        who: who,
        history: full ? history : const [],
      );
      if (cancel.isCompleted) return;
      setState(() => _sentTo = provider);
      final session = db != null
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
        Future<String> asking({required bool full}) => AiAssistant.ask(
          provider,
          prompt(full: full),
          model: model,
          tier: task.tier,
          caseSession: session,
          attachments: [
            for (final a in attachments)
              if (full || !_given.contains('${provider.name}|${a.name}')) a,
          ],
          onEvent: (e) => _heard(turn, e),
          cancel: cancel.future,
          thread: thread,
        );
        String answer;
        if (thread.ids.containsKey(provider)) {
          try {
            answer = await asking(full: false);
          } on AiFailure catch (e) {
            if (e.timedOut || cancel.isCompleted) rethrow;
            // Its record gone (another computer, or cleared): from the
            // start, with all that was said.
            thread.ids.remove(provider);
            turn.steps.clear();
            turn.live.clear();
            answer = await asking(full: true);
          }
        } else {
          answer = await asking(full: true);
        }
        for (final a in attachments) {
          _given.add('${provider.name}|${a.name}');
        }
        turn.answer = answer;
        unawaited(_read(turn));
        unawaited(_check(turn, answer));
        if (db != null) {
          // The case it chose at the very end.
          if (session != null) await _bind(session);
          _keep(db);
        }
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
      tick.cancel();
      if (mounted) {
        setState(() {
          if (identical(_cancel, cancel)) _cancel = null;
        });
        _toEnd();
      }
    }
  }

  /// The case the program chose in [session] (dosya_sec), taken as the
  /// conversation's: its documents' requests and its record are of it.
  Future<void> _bind(AiCaseSession session) async {
    final bound = await session.bound();
    if (bound == null) return;
    final now = _case;
    if (now != null && now.court == bound.court && now.number == bound.number) {
      return;
    }
    final record =
        await UyapCaseStore.instance.load(bound.court, bound.number) ??
        UyapCaseRecord(
          court: bound.court,
          number: bound.number,
          fetchedAt: DateTime.now(),
        );
    session.record = record;
    if (mounted) setState(() => _case = record);
  }

  /// The conversation kept, with its case or with none, as it is now.
  void _keep(PortalDatabase db) {
    final id = _chatId;
    if (id == null) return;
    final kase = _case;
    final key = kase == null ? '' : caseKey(kase.number, kase.court);
    final turns = [
      for (final t in _turns)
        if (t.answer case final a?)
          {
            'soru': t.question,
            'cevap': a,
            'yazan': t.by,
            if (t.attached.isNotEmpty) 'ekler': t.attached,
            if (t.steps.isNotEmpty)
              'adimlar': [
                for (final s in t.steps.values)
                  AiStep(s.id, s.tool, args: s.args, done: true).label,
              ],
            'zaman': DateTime.now().toIso8601String(),
          },
    ];
    if (turns.isEmpty) return;
    try {
      // Said after it is kept.
      scheduleMicrotask(() => widget.onKept?.call(id));
      db.putAiRecord(
        id,
        AiMemory.chat,
        key,
        AiMemory.chatRecord(
          // A name the lawyer gave it stays.
          title: '${db.aiRecord(id)?['baslik'] ?? _turns.first.question}',
          document: widget.path == null ? '' : p.basename(widget.path!),
          started: _chatStarted,
          turns: turns,
          court: kase?.court,
          number: kase?.number,
          threads: _thread?.toJson(),
        ),
      );
    } catch (_) {}
  }

  /// Downloads the program asked for in [session], and the findings and
  /// drafts it offered, put before the lawyer.
  Future<void> _look(AiCaseSession session, _Turn turn) async {
    await _bind(session);
    // UYAP asked for fresh, shown as it is done.
    await AiRefresh.serve(
      session,
      told: (said) {
        if (mounted) setState(() => turn.notes.add(said));
      },
    );
    final offered = await session.proposals();
    if (offered.isNotEmpty && mounted) {
      setState(() {
        for (final o in offered) {
          // A document goes to the documents; findings wait for a word.
          if (o.kind == AiMemory.draft) {
            _wrote(turn, o.body);
          } else {
            turn.offers.add(_Offer(o.kind, o.body));
          }
        }
      });
      _toEnd();
    }
    if (!mounted || !identical(_session, session)) return;
    // What it asked to download, fetched from UYAP as it asks, one after
    // another; shown as it goes.
    _downloads = _downloads.then(
      (_) => AiRefresh.serveDownloads(
        session,
        told: (id, title, outcome) {
          if (!mounted) return;
          setState(() {
            final known = turn.requests.where((r) => r.id == id).firstOrNull;
            if (known == null) {
              turn.requests.add(_Request(id, title)..working = true);
            } else {
              known
                ..outcome = outcome
                ..working = outcome == null;
            }
          });
          _toEnd();
        },
      ),
    );
    await _downloads;
  }

  Future<void> _downloads = Future.value();

  /// A document it had downloaded: as it goes, and what came of it.
  Widget _request(_Request r, ColorScheme scheme) => Padding(
    key: ValueKey('ai-request-${r.id}'),
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        if (r.working)
          const SizedBox.square(
            dimension: 13,
            child: CircularProgressIndicator(strokeWidth: 1.8),
          )
        else
          Icon(
            r.outcome == 'İndirildi'
                ? Icons.download_done_rounded
                : Icons.file_download_off_outlined,
            size: 15,
            color: r.outcome == 'İndirildi'
                ? const Color(0xFF157A52)
                : scheme.onSurfaceVariant,
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            r.working
                ? 'Evrak UYAP’tan indiriliyor · ${r.title}'
                : '${r.outcome ?? ''} · ${r.title}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
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

  /// What an empty conversation shows: what may be asked, and a few
  /// questions to start with.
  Widget _empty(ColorScheme scheme) {
    final home = widget.path == null && _case == null;
    final ideas = widget.path != null
        ? const [
            'Bu belgeyi özetle',
            'Bu belgede süre doğuran bir şey var mı?',
            'Bu belgeye karşı ne yapmalıyım?',
          ]
        : home
        ? const [
            'Bu hafta duruşmalarım neler?',
            'Yeni tebligat var mı, süreleri ne?',
            'Son günü yaklaşan süreler',
            'UYAP’ta yeni bildirim var mı?',
          ]
        : const [
            'Dosyanın durumu ne?',
            'Son gelen evrakı özetle',
            'Dosyada eksik ne var, ne yapmalıyım?',
          ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          home
              ? 'Sorunuzu aşağıya yazın. Bir dosyayla ilgiliyse dosyayı esas '
                    'numarasıyla, mahkemesiyle ya da bir tarafın adıyla anmanız '
                    'yeter; yapay zekâ dosyayı kendisi bulur. Ajandanızı, '
                    'tebligatlarınızı ve dosyalarınızı da bilir.'
              : widget.path == null
              ? 'Dosyayla ilgili sorunuzu aşağıya yazın. Yapay zekâ dosyanın '
                    'bilgilerine, evrakına ve hafızasına Folio’nun araçlarıyla '
                    'bakar.'
              : 'Belgeyi özetletebilir ya da aşağıya belgeyle ilgili bir soru '
                    'yazabilirsiniz. Bir şey göndermeden önce size sorulur.',
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final idea in ideas)
              ActionChip(
                key: ValueKey('ai-idea-$idea'),
                label: Text(idea),
                onPressed: _provider == null || _busy
                    ? null
                    : () => unawaited(_ask(AiTask.question, idea)),
              ),
          ],
        ),
      ],
    );
  }

  /// One question and its answer, with what the program did on the way.
  List<Widget> _turnView(_Turn t, ColorScheme scheme) {
    final muted = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);
    final running = t.answer == null && t.error == null;
    return [
      Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 10, left: 60),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            t.question,
            style: TextStyle(color: scheme.onPrimaryContainer),
          ),
        ),
      ),
      if (t.attached.isNotEmpty)
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('Ekler: ${t.attached.join(', ')}', style: muted),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(t.by, style: muted),
      ),
      for (final n in t.notes)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Icon(Icons.sync_rounded, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  n,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      if (t.steps.isNotEmpty ||
          t.thought.isNotEmpty ||
          t.recorded.isNotEmpty ||
          t.requests.isNotEmpty)
        _trace(t, scheme),
      if (t.answer case final a?) ...[
        AiMarkdown(a),
        Row(
          children: [
            TextButton.icon(
              key: ValueKey('ai-copy-${identityHashCode(t)}'),
              onPressed: () {
                unawaited(Clipboard.setData(ClipboardData(text: a)));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(content: Text('Yanıt kopyalandı.')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 15),
              label: const Text('Kopyala'),
            ),
          ],
        ),
        _sourcesOf(t, scheme),
      ] else if (t.error case final e?)
        Text(
          e,
          key: const ValueKey('ai-error'),
          style: TextStyle(color: scheme.error),
        )
      else if (running) ...[
        _status(t, scheme),
        if (t.live.isNotEmpty) AiMarkdown(t.live.toString()),
      ],
      for (final o in t.offers) _offer(t, o, scheme),
      // In the narrow panel beside a document, with the answer; on the
      // page, beside the conversation.
      if (!widget.embedded)
        for (final d in t.documents) _docCard(d, scheme)
      else if (t.documents.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: TextButton.icon(
            onPressed: () => setState(() => _documentsOpen = true),
            icon: const Icon(Icons.description_outlined, size: 16),
            label: Text(
              t.documents.length == 1
                  ? 'Belge hazırlandı: ${t.documents.single.title}'
                  : '${t.documents.length} belge hazırlandı',
            ),
          ),
        ),
    ];
  }

  /// While it works: what it is doing, and for how long.
  Widget _status(_Turn t, ColorScheme scheme) {
    final open = t.steps.values.where((s) => !s.done).lastOrNull;
    final fetching = t.requests.where((r) => r.working).lastOrNull;
    final label = fetching != null
        ? 'Evrak UYAP’tan indiriliyor · ${fetching.title}'
        : open != null
        ? open.label
        : t.live.isNotEmpty
        ? 'Yazıyor'
        : t.steps.isEmpty
        ? 'Düşünüyor'
        : 'Araştırıyor';
    final seconds = DateTime.now().difference(t.started).inSeconds;
    return Padding(
      key: const ValueKey('ai-status'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              seconds >= 3 ? '$label… · $seconds sn' : '$label…',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  /// What the program did on the way, the documents it had downloaded
  /// among it: folded, one line, unless the lawyer opens it; the line
  /// under it says what it is doing now.
  Widget _trace(_Turn t, ColorScheme scheme) {
    final open = t.traceOpen ?? false;
    final downloaded = t.requests.where((r) => r.outcome == 'İndirildi').length;
    final steps = t.steps.isNotEmpty
        ? t.steps.values.toList()
        : [for (final (i, l) in t.recorded.indexed) _Told('$i', l)];
    final small = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('ai-trace-${identityHashCode(t)}'),
            onTap: () => setState(() => t.traceOpen = !open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              child: Row(
                children: [
                  Icon(
                    open
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      [
                        steps.isEmpty
                            ? 'Düşünme'
                            : 'Yapılan incelemeler (${steps.length})',
                        if (downloaded > 0)
                          '$downloaded evrak UYAP’tan indirildi',
                      ].join(' · '),
                      style: small.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in t.requests) _request(r, scheme),
                  for (final s in steps)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          s.done
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 14,
                                  color: scheme.primary,
                                )
                              : const SizedBox.square(
                                  dimension: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.6,
                                  ),
                                ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(s.label, style: small)),
                        ],
                      ),
                    ),
                  if (t.thought.isNotEmpty) ...[
                    if (steps.isNotEmpty) const SizedBox(height: 6),
                    Text(
                      'Düşünme',
                      style: small.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    AiMarkdown(t.thought.toString().trim(), size: 12),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// A program's event, put in its turn: drawn a few times a second at
  /// most, an answer coming a letter at a time.
  void _heard(_Turn turn, AiEvent e) {
    switch (e) {
      case AiStep(:final id, done: true):
        final known = turn.steps[id];
        if (known != null) {
          turn.steps[id] = AiStep(id, known.tool, args: known.args, done: true);
        }
      case AiStep(:final id, :final tool, :final args):
        final known = turn.steps[id];
        turn.steps[id] = AiStep(
          id,
          tool.isEmpty ? (known?.tool ?? '') : tool,
          args: args.isEmpty ? (known?.args ?? const {}) : args,
          done: known?.done ?? false,
        );
      case AiThought(:final text):
        turn.thought.write(text);
      case AiWriting(:final text, :final restart):
        if (restart) {
          // What it said before calling a tool was a remark on the way.
          if (turn.live.isNotEmpty) {
            turn.thought.write('${turn.live}\n\n');
          }
          turn.live.clear();
        }
        turn.live.write(text);
    }
    if (_drawing) return;
    _drawing = true;
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      _drawing = false;
      if (mounted) setState(() {});
      _toEnd();
    });
  }

  bool _drawing = false;

  /// The documents the program wrote in this conversation, the newest
  /// first; kept with the case's drafts when it is of one.
  final _documents = <_Doc>[];

  /// Whether the documents are beside the conversation (on the page).
  bool _documentsOpen = true;

  void _wrote(_Turn turn, Map<String, Object?> body) {
    final doc = _Doc(
      AiMemory.id(),
      '${body['baslik'] ?? 'Belge'}',
      '${body['metin'] ?? ''}',
    );
    turn.documents.add(doc);
    _documents.insert(0, doc);
    _documentsOpen = true;
    final kase = _case;
    if (kase == null) return;
    unawaited(() async {
      try {
        (await PortalDatabase.shared()).putAiRecord(
          doc.id,
          AiMemory.draft,
          caseKey(kase.number, kase.court),
          {
            'baslik': doc.title,
            'metin': doc.text,
            'sohbet': ?_chatId,
            'yazan': turn.by,
            'zaman': DateTime.now().toIso8601String(),
          },
        );
      } catch (_) {}
    }());
  }

  /// The documents written in the conversation gone on with.
  Future<void> _loadDocuments() async {
    final chat = widget.chat?['id'];
    if (chat == null) return;
    try {
      final db = await PortalDatabase.shared();
      final kept = [
        for (final d in db.aiRecords(AiMemory.draft))
          if (d['sohbet'] == chat) d,
      ]..sort((a, b) => '${b['zaman']}'.compareTo('${a['zaman']}'));
      if (!mounted || kept.isEmpty) return;
      setState(() {
        for (final d in kept) {
          _documents.add(
            _Doc('${d['id']}', '${d['baslik'] ?? ''}', '${d['metin'] ?? ''}')
              ..path = d['yol'] as String?,
          );
        }
      });
    } catch (_) {}
  }

  /// [doc] opened in Folio's editor: written as a UDF in the case's folder
  /// (or Folio's "Yapay zekâ" folder) once.
  Future<void> _openDoc(_Doc doc) async {
    try {
      doc.path ??= await writeAiDraft(
        UyapCaseStore.instance,
        _case,
        doc.title,
        doc.text,
      );
      final kase = _case;
      if (kase != null) {
        (await PortalDatabase.shared()).putAiRecord(
          doc.id,
          AiMemory.draft,
          caseKey(kase.number, kase.court),
          {
            'baslik': doc.title,
            'metin': doc.text,
            'yol': doc.path,
            'sohbet': ?_chatId,
            'zaman': DateTime.now().toIso8601String(),
          },
        );
      }
      if (mounted) setState(() {});
      widget.onOpen?.call(doc.path!);
    } catch (e) {
      _say('Belge açılamadı: $e');
    }
  }

  /// [doc] saved where the lawyer chooses, as [format].
  Future<void> _exportDoc(_Doc doc, EvrakFormat format) async {
    final ext = switch (format) {
      EvrakFormat.docx => 'docx',
      EvrakFormat.pdf => 'pdf',
      _ => 'udf',
    };
    final where = await FilePicker.saveFile(
      dialogTitle: 'Belgeyi kaydet',
      fileName: '${aiDraftName(doc.title)}.$ext',
      type: FileType.custom,
      allowedExtensions: [ext],
    );
    if (where == null) return;
    try {
      final path = where.toLowerCase().endsWith('.$ext')
          ? where
          : '$where.$ext';
      await File(path).writeAsBytes(
        await aiDraftBytes(doc.title, doc.text, format),
        flush: true,
      );
      _say('Kaydedildi: ${p.basename(path)}');
    } catch (e) {
      _say('Kaydedilemedi: $e');
    }
  }

  void _say(String text) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));

  Widget _docCard(_Doc doc, ColorScheme scheme) => Container(
    key: ValueKey('ai-doc-${doc.id}'),
    margin: const EdgeInsets.only(top: 6, bottom: 6),
    padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
    decoration: BoxDecoration(
      border: Border.all(color: scheme.outlineVariant),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.description_outlined, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                doc.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          doc.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
        Wrap(
          spacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              key: ValueKey('ai-doc-open-${doc.id}'),
              onPressed: () => unawaited(_openDoc(doc)),
              icon: const Icon(Icons.edit_note_rounded, size: 16),
              label: const Text('Aç'),
            ),
            for (final (format, label) in const [
              (EvrakFormat.udf, 'UDF'),
              (EvrakFormat.docx, 'DOCX'),
              (EvrakFormat.pdf, 'PDF'),
            ])
              TextButton(
                key: ValueKey('ai-doc-$label-${doc.id}'),
                onPressed: () => unawaited(_exportDoc(doc, format)),
                child: Text(label),
              ),
          ],
        ),
      ],
    ),
  );

  /// Beside the conversation on the page: what it wrote and what was
  /// added to it.
  Widget _documentsPanel(ColorScheme scheme) => Container(
    key: const ValueKey('ai-documents'),
    width: 300,
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: scheme.outlineVariant)),
    ),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Belgeler',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Gizle',
              onPressed: () => setState(() => _documentsOpen = false),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
        if (_documents.isNotEmpty) ...[
          Text(
            'Yapay zekânın yazdıkları',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
          for (final d in _documents) _docCard(d, scheme),
        ],
        if (_attached.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Sohbete eklenenler',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
          for (final path in _attached)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.attach_file_rounded, size: 18),
              title: Text(
                p.basename(path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: widget.onOpen == null ? null : () => widget.onOpen!(path),
            ),
        ],
      ],
    ),
  );

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

  /// The citations in [turn]'s answer, read by Folio itself.
  Future<void> _read(_Turn turn) async {
    final answer = turn.answer;
    if (answer == null || answer.isEmpty) return;
    try {
      final (articles, decisions) = await _mcp.citationsIn(answer);
      final seen = <String>{};
      String said(String w) =>
          w.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      final list = <Object>[
        for (final c in articles)
          if (seen.add(said(_written(answer, c.start, c.length)))) c,
        for (final c in decisions)
          if (seen.add(said(_written(answer, c.start, c.length)))) c,
      ];
      if (mounted && list.isNotEmpty) setState(() => turn.sources = list);
    } catch (_) {}
  }

  static String _written(String text, int start, int length) =>
      start >= 0 && start + length <= text.length
      ? text.substring(start, start + length)
      : '';

  /// What the answer rests on, under it: each article and decision it
  /// cites, opened in full from the official source as in the editor;
  /// marked as Folio found it there once it has looked.
  Widget _sourcesOf(_Turn t, ColorScheme scheme) {
    final answer = t.answer ?? '';
    if (t.sources.isEmpty) return const SizedBox.shrink();
    final checked = {
      for (final c in t.checks ?? const <Map<String, Object?>>[])
        '${c['yazilan']}': c,
    };
    return Padding(
      key: ValueKey('ai-sources-${identityHashCode(t)}'),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dayanakları',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in t.sources) _source(s, answer, checked, scheme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _source(
    Object source,
    String answer,
    Map<String, Map<String, Object?>> checked,
    ColorScheme scheme,
  ) {
    final (start, length, decision) = switch (source) {
      final Citation c => (c.start, c.length, false),
      final DecisionCitation c => (c.start, c.length, true),
      _ => (0, 0, false),
    };
    final written = _written(answer, start, length);
    final check = checked[written];
    final state = check?['durum'];
    final wrong = state != null && state != 'bulundu' && state != 'ulasilamadi';
    final color = wrong ? scheme.error : scheme.primary;
    final note = switch (state) {
      'bulundu' => 'Resmî kaynakta var',
      'mulga' => 'Mülga',
      'yayimlanmamis' => 'Yayımlanmamış',
      'ulasilamadi' => 'Denetlenemedi',
      null => null,
      _ => 'Resmî kaynakta bulunamadı',
    };
    return Tooltip(
      message: [
        note ?? 'Tam metni aç',
        if (check?['daire_farkli'] == true) 'dairesi farklı',
      ].join(' · '),
      child: Material(
        color: color.withValues(alpha: 0.07),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: color.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          key: ValueKey('ai-source-$written'),
          borderRadius: BorderRadius.circular(8),
          onTapUp: (d) => _openSource(source, d.globalPosition),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  decision ? Icons.balance_outlined : Icons.gavel_outlined,
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    written.replaceAll(RegExp(r'\s+'), ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                ),
                if (state == 'bulundu') ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.check_circle_outline,
                    size: 13,
                    color: Color(0xFF157A52),
                  ),
                ] else if (wrong) ...[
                  const SizedBox(width: 4),
                  Text(
                    note!.toLowerCase(),
                    style: TextStyle(fontSize: 11, color: scheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [source]'s full text, over the page as the editor shows it.
  void _openSource(Object source, Offset at) {
    switch (source) {
      case final Citation c:
        ArticlePanel.show(
          context,
          citation: c,
          lookup: () => _mcp.article(c),
          at: at,
        );
      case final DecisionCitation c:
        DecisionPanel.show(
          context,
          citation: c,
          lookup: () => _mcp.decision(c),
          at: at,
        );
    }
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
      width: widget.embedded ? null : 380,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: widget.embedded
            ? null
            : Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.embedded ||
              usable.length > 1 ||
              (!_documentsOpen &&
                  (_documents.isNotEmpty || _attached.isNotEmpty)))
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
              child: Row(
                children: [
                  // On the Yapay zekâ page the page says it already.
                  if (widget.embedded)
                    const Spacer()
                  else ...[
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
                  ],
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
                  if (widget.embedded &&
                      !_documentsOpen &&
                      (_documents.isNotEmpty || _attached.isNotEmpty))
                    TextButton.icon(
                      key: const ValueKey('ai-documents-open'),
                      onPressed: () => setState(() => _documentsOpen = true),
                      icon: const Icon(Icons.description_outlined, size: 16),
                      label: Text(
                        'Belgeler (${_documents.length + _attached.length})',
                      ),
                    ),
                  if (widget.onClose != null)
                    IconButton(
                      tooltip: 'Kapat',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: widget.onClose,
                    ),
                ],
              ),
            ),
          if (_case case final c? when !widget.embedded || widget.showCase)
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
                  // Of no document: the case was chosen, and may be
                  // taken off; the conversation goes on of none.
                  if (widget.path == null && widget.showCase)
                    TextButton(
                      key: const ValueKey('ai-case-off'),
                      onPressed: _busy
                          ? null
                          : () => setState(() => _case = null),
                      child: const Text('Kaldır'),
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
            if (widget.path != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    key: const ValueKey('ai-summary'),
                    onPressed: _busy ? null : () => _ask(AiTask.summary),
                    icon: const Icon(Icons.subject_rounded, size: 18),
                    label: const Text('Özetle'),
                  ),
                ),
              ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _turns.isEmpty
                        ? _empty(scheme)
                        : ListView(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                            children: [
                              for (final t in _turns) ..._turnView(t, scheme),
                            ],
                          ),
                  ),
                  if (widget.embedded &&
                      _documentsOpen &&
                      (_documents.isNotEmpty || _attached.isNotEmpty))
                    _documentsPanel(scheme),
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
            if (_attached.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final path in _attached)
                          InputChip(
                            key: ValueKey('ai-attached-$path'),
                            avatar: const Icon(
                              Icons.description_outlined,
                              size: 16,
                            ),
                            label: Text(
                              p.basename(path),
                              overflow: TextOverflow.ellipsis,
                            ),
                            onDeleted: _busy
                                ? null
                                : () => setState(() => _attached.remove(path)),
                          ),
                      ],
                    ),
                    if (_sendsPictures)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Taranmış belge ve resimler görüntü olarak gider; '
                          'içlerindeki kimlik numaraları gizlenemez.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 12),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('ai-attach'),
                    tooltip: 'Belge ekle',
                    onPressed: _busy ? null : () => unawaited(_attach()),
                    icon: const Icon(Icons.attach_file_rounded, size: 20),
                  ),
                  Expanded(
                    // Enter sends, Shift+Enter starts a new line.
                    child: Focus(
                      onKeyEvent: (_, event) {
                        if (event is KeyDownEvent &&
                            (event.logicalKey == LogicalKeyboardKey.enter ||
                                event.logicalKey ==
                                    LogicalKeyboardKey.numpadEnter) &&
                            !HardwareKeyboard.instance.isShiftPressed) {
                          _send();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        key: const ValueKey('ai-question'),
                        controller: _question,
                        enabled: !_busy,
                        minLines: 1,
                        maxLines: 6,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: widget.path != null
                              ? 'Belgeye sorun…'
                              : _case != null
                              ? 'Dosyaya sorun…'
                              : 'Sorun…',
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  if (_busy)
                    IconButton(
                      key: const ValueKey('ai-stop'),
                      tooltip: 'Durdur',
                      onPressed: () => _cancel?.complete(),
                      icon: Icon(
                        Icons.stop_circle_rounded,
                        size: 24,
                        color: scheme.primary,
                      ),
                    )
                  else
                    IconButton(
                      key: const ValueKey('ai-send'),
                      tooltip: 'Sor',
                      onPressed: _send,
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

/// A step of an answer kept: its words as they were told.
class _Told extends AiStep {
  const _Told(String id, this.said) : super(id, '', done: true);
  final String said;
  @override
  String get label => said;
}

/// A document the program wrote in the conversation: its title and text,
/// and where it was written as a UDF once opened.
class _Doc {
  _Doc(this.id, this.title, this.text);
  final String id, title, text;
  String? path;
}
