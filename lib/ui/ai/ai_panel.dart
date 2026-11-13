import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:file_picker/file_picker.dart';

import '../../models/evrak_file.dart';
import '../../services/ai/ai_assistant.dart';
import '../../services/ai/ai_attachment.dart';
import '../../services/ai/ai_audit.dart';
import '../../services/ai/ai_case.dart';
import '../../services/ai/ai_draft.dart';
import '../../services/ai/ai_guide.dart';
import '../../services/ai/ai_memory.dart';
import '../../services/ai/ai_refresh.dart';
import 'ai_markdown.dart';
import '../../services/ai/folio_mcp.dart';
import '../../services/legal/citation.dart';
import '../../services/legal/decision.dart';
import '../widgets/article_panel.dart';
import '../../services/portal/observed.dart' show caseKey;
import '../../services/portal/portal_database.dart';
import '../../services/uyap/uyap_case_data.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../widgets/uyap_case_picker.dart';
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
    this.document,
    this.documentName,
    this.selection,
    this.onInsert,
    this.database = PortalDatabase.shared,
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

  /// Beside the editor: the document as it is written now, asked for with
  /// every question ([path] names a file, which may be older or none yet),
  /// and the name it is known by.
  final String Function()? document;
  final String? documentName;

  /// What is selected in the document, sent with the question when the
  /// lawyer leaves it ticked.
  final String? Function()? selection;

  /// Writes a text the program gave into the document, where the caret is.
  final void Function(String text)? onInsert;

  /// Folio's records, counted for what today holds.
  final Future<PortalDatabase> Function() database;

  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _Turn {
  _Turn(
    this.question,
    this.by, {
    this.task = AiTask.question,
    this.tier = AiTier.strong,
  });
  final String question;
  final AiTask task;
  final AiTier tier;

  /// How long the answer took, once it came.
  int? seconds;

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

  /// Whether what was selected in the document went with the question.
  bool usedSelection = false;

  /// Folio checking the answer before it is shown (AnswerAudit).
  bool auditing = false;

  /// The answer shown while Folio checks it and it is written again.
  String? held;

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

  /// Whether the conversation follows what is written at its end: so
  /// while the lawyer is at the end; not once they scroll up to read.
  bool _follow = true;

  /// Whether the box to ask in shows: at the conversation's end; while the
  /// lawyer scrolls up to read it goes, and a button brings them back.
  bool _composerShown = true;

  /// The box as one thin line: a conversation going on, nothing typed,
  /// not being written in.
  bool get _compact =>
      _turns.isNotEmpty &&
      !_focus.hasFocus &&
      _question.text.isEmpty &&
      _attached.isEmpty &&
      _must.isEmpty;

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
      final shown =
          n.metrics.maxScrollExtent - n.metrics.pixels < 120 ||
          n.metrics.maxScrollExtent <= 0;
      if (shown != _composerShown) setState(() => _composerShown = shown);
    }
    if (n is UserScrollNotification || n is ScrollUpdateNotification) {
      if (n is ScrollUpdateNotification && n.dragDetails == null) {
        return false;
      }
      _follow = n.metrics.maxScrollExtent - n.metrics.pixels < 160;
    } else if (n is ScrollEndNotification) {
      _follow = n.metrics.maxScrollExtent - n.metrics.pixels < 160;
    }
    return false;
  }

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

  /// Of a document: one previewed ([AiPanel.path]) or one being written
  /// ([AiPanel.document]).
  bool get _ofDocument => widget.path != null || widget.document != null;

  /// The tier questions are asked at, as the lawyer chose under the box.
  AiTier _tier = AiTier.strong;

  /// Questions written while an answer was still coming: asked in turn.
  final _queue = <String>[];

  /// The allowance used, as the program last said.
  AiQuota? _quota;

  /// Whether what is selected in the document goes with the question.
  bool _withSelection = true;

  /// The case's documents the lawyer wants read before the next answer,
  /// by key.
  final _must = <String>{};

  /// What today holds, on the page of no case: said over the box.
  ({int today, int week, int deadlines, int notices})? _today;

  final _focus = FocusNode();

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
    // The send button and the box's size follow what is typed and where
    // the cursor is.
    _focus.addListener(_redraw);
    _question.addListener(_redraw);
    if (widget.chat case final chat?) {
      _chatId = chat['id'] as String?;
      if (_chatId case final id?) _thread = AiThread.of(id, chat['oturumlar']);
      _chatStarted =
          DateTime.tryParse('${chat['basladi'] ?? ''}') ?? DateTime.now();
      for (final t in AiMemory.turnsOf(chat)) {
        _turns.add(
          _Turn(
              '${t['soru'] ?? ''}',
              '${t['yazan'] ?? ''}',
              tier: '${t['yazan'] ?? ''}'.endsWith(AiTier.normal.label)
                  ? AiTier.normal
                  : AiTier.strong,
            )
            ..answer = '${t['cevap'] ?? ''}'
            ..seconds = (t['sure'] as num?)?.toInt()
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
    // A document being written keeps its conversation when it is saved
    // under a name.
    if (old.path != widget.path && widget.document == null) {
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

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cancel?.complete();
    _question.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    unawaited(_findCase());
    unawaited(_loadDocuments());
    if (!_ofDocument && widget.caseRecord == null) unawaited(_loadToday());
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
    AiProvider.groq => 'Groq’a',
    AiProvider.gemini => 'Google’a',
    AiProvider.openai => 'OpenAI’a',
    AiProvider.anthropic => 'Anthropic’e',
  };

  Future<void> _ask(AiTask task, [String question = '', AiTier? at]) async {
    final provider = _provider;
    if (provider == null || _busy) return;
    if (!await askAiConsent(context)) return;
    final settings = await AiSettings.load();
    final tier = at ?? (task == AiTask.summary ? task.tier : _tier);
    final model = settings.modelFor(provider, tier);
    final turn = _Turn(
      task == AiTask.summary ? 'Belgeyi özetle' : question.trim(),
      '${provider.label} · ${tier.label}',
      task: task,
      tier: tier,
    );
    final cancel = Completer<void>();
    setState(() {
      _turns.add(turn);
      _cancel = cancel;
    });
    _question.clear();
    _toEnd(now: true);
    // The seconds counted while it works.
    final tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    try {
      final path = widget.path;
      final live = widget.document;
      String? text;
      if (live != null || path != null) {
        text = live != null
            ? live()
            : _text ??= await AiAssistant.documentText(path!);
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
      final open = !_ofDocument && record == null && tools;
      final db = withCase || open ? await PortalDatabase.shared() : null;
      if (db != null) _chatId ??= AiMemory.id();
      // The program goes on with the conversation it had: the document,
      // the earlier answers and the documents it was given are not sent
      // again.
      final thread = _thread ??= AiThread(_chatId ?? AiMemory.id());
      final who = await AiAssistant.who();
      // What is selected in the document, and the documents to be read.
      var picked = _withSelection ? widget.selection?.call()?.trim() : null;
      if (picked != null && picked.length > 8000) {
        picked = '${picked.substring(0, 8000)}…';
      }
      if (picked != null && settings.mask) {
        picked = AiAssistant.maskIdentityNumbers(picked);
      }
      final must = record == null
          ? const <UyapCaseDocument>[]
          : [
              for (final d in _allDocuments(record))
                if (_must.contains(d.key)) d,
            ];
      final notes = [
        if (withCase)
          // The case's memory, for the program to read first.
          AiMemory.hint(db!.aiCounts(caseKey(record.number, record.court)))
        else if (open)
          'Soru avukatın bir dosyasıyla ilgiliyse dosya_ara ile dosyayı '
              'bul; tek dosya açıkça uyuyorsa dosya_sec ile seç, birden '
              'fazla uyuyorsa hangisi olduğunu avukata sor. Ajanda, '
              'süre, tebligat ve bildirim soruları için Folio\'nun '
              'ajanda, tebligatlar ve uyap_bildirimleri araçları var.',
        if (live != null)
          'Avukat bu belgeyi şu anda Folio editöründe yazıyor. Belgeye '
              'girecek metni (yeni paragraf, düzeltilmiş hâl, talep sonucu) '
              '```belge ile başlayan bir kod bloğunun içinde, düz metin '
              'olarak ver; açıklamanı bloğun dışında yaz. Avukat bloğu tek '
              'tıkla belgeye ekler. Belgenin tamamını yeniden yazma; yalnız '
              'isteneni ver.',
        if (picked != null && picked.isNotEmpty)
          'Avukatın belgede seçtiği metin (soru öncelikle bununla ilgili):\n'
              '<secili_metin>\n$picked\n</secili_metin>',
        if (withCase && must.isNotEmpty)
          'Avukat şu evrakın mutlaka okunmasını istiyor; cevaptan önce '
              'her birini evrak_oku ile oku:\n'
              '${[for (final d in must) '- ${d.title} (anahtar: ${d.key})'].join('\n')}',
      ].nonNulls.toList();
      turn.usedSelection = picked != null && picked.isNotEmpty;
      // The guide's topic the question names, added by Folio: the model
      // finds the governing articles there rather than guessing them.
      final guide = tools && task == AiTask.question
          ? (await LegalGuide.load()).blockFor(question)
          : null;
      String prompt({required bool full}) => AiAssistant.prompt(
        task: task,
        name: path != null
            ? p.basename(path)
            : live != null
            ? (widget.documentName ?? 'belge')
            : null,
        // A document being written is sent as it is now, every time.
        text: full || live != null ? text : null,
        question: question,
        caseName: withCase ? '${record.court} ${record.number}' : null,
        note: notes.isEmpty ? null : notes.join('\n\n'),
        guide: guide,
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
          tier: tier,
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
        if (await AiAssistant.goesOn(provider, thread)) {
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
        // Folio's own check before the lawyer sees it (AnswerAudit): what
        // it finds is said to the program, which writes the answer again.
        if (tools && !cancel.isCompleted) {
          var rounds = 0, read = 0;
          final audit = AnswerAudit(_mcp);
          for (var round = 0; round < 2; round++) {
            // The answer stays on the screen while Folio checks it and the
            // program writes it again; the new one takes its place when
            // done, not word by word over a cleared one.
            if (mounted) {
              setState(() {
                turn.auditing = true;
                turn.held = answer;
              });
            }
            final feedback = await audit.feedback(
              answer,
              turn.steps.values,
              said: (_) => read++,
              question: task == AiTask.question ? question : null,
            );
            if (feedback == null || cancel.isCompleted) break;
            // A second round only for a fault in the answer itself.
            if (round > 0 && !audit.serious) break;
            if (!await AiAssistant.goesOn(provider, thread)) break;
            turn.live.clear();
            final again = await AiAssistant.ask(
              provider,
              feedback,
              model: model,
              tier: tier,
              caseSession: session,
              onEvent: (e) => _heard(turn, e),
              cancel: cancel.future,
              thread: thread,
            );
            if (again.trim().isNotEmpty) answer = again;
            rounds++;
          }
          turn.auditing = false;
          turn.held = null;
          if (rounds > 0 || read > 0) {
            turn.notes.add(AnswerAudit.summary(rounds, read));
          }
        }
        for (final a in attachments) {
          _given.add('${provider.name}|${a.name}');
        }
        turn.answer = answer;
        turn.seconds = DateTime.now().difference(turn.started).inSeconds;
        if (withCase) _must.clear();
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
        // What was written meanwhile, asked next.
        if (!cancel.isCompleted && !_busy && _queue.isNotEmpty) {
          final next = _queue.removeAt(0);
          unawaited(_ask(AiTask.question, next));
        }
      }
    }
  }

  /// Stops the answer coming; what waited to be asked goes back to the
  /// box rather than being asked of a conversation the lawyer broke off.
  void _stop() {
    _cancel?.complete();
    if (_queue.isEmpty) return;
    setState(() {
      _question.text = [
        ..._queue,
        if (_question.text.trim().isNotEmpty) _question.text.trim(),
      ].join('\n');
      _queue.clear();
    });
  }

  static List<UyapCaseDocument> _allDocuments(UyapCaseRecord record) => [
    for (final d in record.documents) ...[d, ...d.attachments],
  ];

  /// What today and the week hold, counted from Folio's own records.
  Future<void> _loadToday() async {
    try {
      final db = await widget.database();
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final week = day.add(const Duration(days: 7));
      String iso(DateTime d) => d.toIso8601String().substring(0, 10);
      final found = (
        today: db
            .hearings(from: day, to: day.add(const Duration(days: 1)))
            .length,
        week: db.hearings(from: day, to: week).length,
        deadlines: [
          for (final d in db.deadlines())
            if (d.record.dueDay case final due?
                when due.compareTo(iso(day)) >= 0 &&
                    due.compareTo(iso(week)) <= 0)
              d,
        ].length,
        notices: db.notices().where((n) => !n.seen).length,
      );
      if (mounted) setState(() => _today = found);
    } catch (_) {}
  }

  /// A case chosen for a conversation of none.
  Future<void> _pickCase() async {
    final chosen = await UyapCasePicker.show(context, offerKept: true);
    if (chosen == null || !mounted) return;
    final link = chosen.$1;
    final record =
        await UyapCaseStore.instance.load(link.court, link.number) ??
        UyapCaseRecord(
          court: link.court,
          number: link.number,
          fetchedAt: DateTime.now(),
        );
    if (mounted) setState(() => _case = record);
  }

  /// The case's documents, for the lawyer to tick those that must be read.
  Future<void> _pickMust() async {
    final record = _case;
    if (record == null) return;
    final all = _allDocuments(record);
    final chosen = {..._must};
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Mutlaka okunacak evrak'),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          content: SizedBox(
            width: 460,
            height: 420,
            child: all.isEmpty
                ? const Center(child: Text('Bu dosyada evrak yok.'))
                : ListView(
                    children: [
                      for (final d in all)
                        CheckboxListTile(
                          key: ValueKey('ai-must-${d.key}'),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: chosen.contains(d.key),
                          onChanged: (v) => set(
                            () => v == true
                                ? chosen.add(d.key)
                                : chosen.remove(d.key),
                          ),
                          title: Text(
                            d.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              if (d.date case final at?)
                                '${at.day.toString().padLeft(2, '0')}.'
                                    '${at.month.toString().padLeft(2, '0')}.'
                                    '${at.year}',
                              if (d.sender.isNotEmpty) d.sender,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              key: const ValueKey('ai-must-ok'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Tamam'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(
      () => _must
        ..clear()
        ..addAll(chosen),
    );
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
                  _labelOf(AiStep(s.id, s.tool, args: s.args, done: true)),
              ]
            else if (t.recorded.isNotEmpty)
              'adimlar': t.recorded,
            'sure': ?t.seconds,
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
          document: widget.path == null
              ? (widget.documentName ?? '')
              : p.basename(widget.path!),
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
            // Checked by Folio already: kept at once, as the case's.
            final offer = _Offer(o.kind, o.body);
            turn.offers.add(offer);
            unawaited(_decide(turn, offer, true));
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
    if (offer.outcome != null) return;
    if (record == null) {
      setState(
        () => offer.outcome = 'Sohbet bir dosyaya bağlı değil; kaydedilmedi',
      );
      return;
    }
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
              : '${chosen.length} bulgu dosyanın hafızasına kaydedildi',
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
    // Findings are kept as they come: one line says so.
    if (findings) {
      final repealed = items.where((f) => f['mulga'] is List).length;
      return Padding(
        key: ValueKey('ai-offer-${o.kind}-${identityHashCode(o)}'),
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Row(
          children: [
            Icon(
              Icons.bookmark_added_outlined,
              size: 15,
              color: scheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                [
                  o.outcome ?? 'Bulgular kaydediliyor',
                  if (repealed > 0) '$repealed tanesi mülga maddeye dayanıyor',
                ].join(' · '),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }
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
                    if (f['mulga'] case final List m when m.isNotEmpty)
                      'mülga: ${m.join(', ')}',
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

  /// What an empty conversation shows: what may be done, as cards (one
  /// press asks, or writes the start of a question for the lawyer to end),
  /// and on the page of no case what today holds.
  Widget _empty(ColorScheme scheme) {
    final home = !_ofDocument && _case == null;
    final List<_Idea> ideas = widget.document != null
        ? _editorIdeas
        : widget.path != null
        ? const [
            _Idea(
              Icons.subject_rounded,
              'Belgeyi özetle',
              'Türü, özeti, önemli noktaları ve yapılacaklar',
              'Bu belgeyi özetle',
            ),
            _Idea(
              Icons.hourglass_bottom_rounded,
              'Süre doğuruyor mu?',
              'Belgede yazan süreler ve başlangıçları',
              'Bu belgede süre doğuran bir şey var mı?',
            ),
            _Idea(
              Icons.reply_rounded,
              'Buna karşı ne yapmalıyım?',
              'Yapılabilecek başvurular ve dayanakları',
              'Bu belgeye karşı ne yapmalıyım?',
            ),
            _Idea(
              Icons.fact_check_outlined,
              'Atıfları denetle',
              'Dayanılan madde ve kararlar yerinde mi?',
              'Bu belgede dayanılan kanun maddeleri ve kararlar doğru mu? '
                  'Yanlış ya da yürürlükte olmayanı göster.',
            ),
          ]
        : home
        ? const [
            _Idea(
              Icons.event_outlined,
              'Bu haftaki duruşmalar',
              'Tarihleri ve dosyalarıyla sıralar',
              'Bu hafta duruşmalarım neler?',
            ),
            _Idea(
              Icons.mark_email_unread_outlined,
              'Yeni tebligatlar',
              'Gelenler ve başlattıkları süreler',
              'Yeni tebligat var mı, süreleri ne?',
            ),
            _Idea(
              Icons.hourglass_bottom_rounded,
              'Yaklaşan süreler',
              'Son günü yaklaşan işler',
              'Son günü yaklaşan süreler',
            ),
            _Idea(
              Icons.notifications_none_rounded,
              'UYAP bildirimleri',
              'Dosyalardaki yeni hareketler',
              'UYAP’ta yeni bildirim var mı?',
            ),
            _Idea(
              Icons.folder_open_outlined,
              'Bir dosyayı sor',
              'Esas numarasını ya da tarafın adını yazın',
              'Şu dosyanın durumu ne: ',
              fill: true,
            ),
            _Idea(
              Icons.edit_note_rounded,
              'Dilekçe yazdır',
              'Dosyayı ve dilekçenin türünü yazın',
              'Şu dosya için dilekçe yaz: ',
              fill: true,
            ),
            _Idea(
              Icons.balance_outlined,
              'Emsal karar ara',
              'Konuyu yazın, kararları künyesiyle bulur',
              'Şu konuda Yargıtay kararı bul: ',
              fill: true,
            ),
          ]
        : const [
            _Idea(
              Icons.dashboard_outlined,
              'Dosyanın durumu',
              'Safahat, son işlemler ve bekleyen işler',
              'Dosyanın durumu ne?',
            ),
            _Idea(
              Icons.mark_email_unread_outlined,
              'Son gelen evrak',
              'En yeni evrakın özeti ve doğurduğu iş',
              'Son gelen evrakı özetle',
            ),
            _Idea(
              Icons.checklist_rounded,
              'Eksikler ve yapılacaklar',
              'Dosyada eksik kalan ve sıradaki adımlar',
              'Dosyada eksik ne var, ne yapmalıyım?',
            ),
            _Idea(
              Icons.groups_2_outlined,
              'Karşı tarafın iddiaları',
              'Dayandığı deliller ve zayıf noktaları',
              'Karşı tarafın iddiaları ve dayandığı deliller neler? Zayıf '
                  'noktalarını göster.',
            ),
            _Idea(
              Icons.event_outlined,
              'Duruşmaya hazırlık',
              'Bir sonraki duruşma için yapılacaklar',
              'Bir sonraki duruşma için ne hazırlamalıyım?',
            ),
            _Idea(
              Icons.balance_outlined,
              'Emsal karar bul',
              'Uyuşmazlığa uygun Yargıtay kararları',
              'Bu dosyadaki uyuşmazlığa uygun Yargıtay kararları bul.',
            ),
            _Idea(
              Icons.edit_note_rounded,
              'Dilekçe yazdır',
              'Dilekçenin türünü yazın',
              'Bu dosya için şu dilekçeyi yaz: ',
              fill: true,
            ),
          ];
    final today = _today;
    final rows = <(IconData, String, String)>[
      if (today != null && home) ...[
        if (today.today > 0)
          (
            Icons.gavel_rounded,
            'Bugün ${today.today} duruşmanız var',
            'Bugünkü duruşmalarım neler, her biri için ne hazırlamalıyım?',
          )
        else if (today.week > 0)
          (
            Icons.event_outlined,
            'Bu hafta ${today.week} duruşmanız var',
            'Bu hafta duruşmalarım neler?',
          ),
        if (today.deadlines > 0)
          (
            Icons.hourglass_bottom_rounded,
            '7 gün içinde son günü gelen ${today.deadlines} süre var',
            'Önümüzdeki 7 günde son günü gelen süreler hangileri?',
          ),
        if (today.notices > 0)
          (
            Icons.mark_email_unread_outlined,
            'Okunmamış ${today.notices} tebligat var',
            'Okunmamış tebligatlarım neler, hangi süreleri başlatıyor?',
          ),
      ],
    ];
    final can = _provider != null && !_busy;
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth >= 860
            ? 3
            : box.maxWidth >= 520
            ? 2
            : 1;
        final wide = columns > 1;
        final room = (box.maxWidth - 32).clamp(0.0, 900.0);
        final width = wide
            ? ((room - (columns - 1) * 10) / columns).floorToDouble()
            : box.maxWidth - 28;
        return ListView(
          padding: EdgeInsets.fromLTRB(
            wide ? 16 : 14,
            wide ? 22 : 14,
            wide ? 16 : 14,
            12,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.document != null
                          ? 'Yazdığınız belgeyle ilgili ne yapalım?'
                          : widget.path != null
                          ? 'Bu belgeyle ilgili ne yapalım?'
                          : home
                          ? 'Bugün ne yapalım?'
                          : 'Bu dosyada ne yapalım?',
                      key: const ValueKey('ai-empty-title'),
                      style: TextStyle(
                        fontSize: wide ? 20 : 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.document != null
                          ? 'Bir metni seçip sorarsanız cevap o metinle ilgili '
                                'olur. Belgeye girecek metin ayrı bir kutuda '
                                'gelir ve tek tıkla imlecin olduğu yere eklenir.'
                          : widget.path != null
                          ? 'Belgenin metni, siz bir şey sorduğunuzda '
                                'gönderilir.'
                          : home
                          ? 'Dosyayı esas numarasıyla, mahkemesiyle ya da bir '
                                'tarafın adıyla anmanız yeter; yapay zekâ '
                                'dosyayı kendisi bulur. Ajandanızı ve '
                                'tebligatlarınızı da bilir.'
                          : 'Yapay zekâ dosyanın bilgilerine, evrakına ve '
                                'hafızasına Folio’nun araçlarıyla bakar.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    if (rows.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        key: const ValueKey('ai-today'),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            for (final (icon, said, ask) in rows)
                              InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: can
                                    ? () =>
                                          unawaited(_ask(AiTask.question, ask))
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        icon,
                                        size: 17,
                                        color: scheme.primary,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          said,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        'Sor',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.primary,
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        size: 18,
                                        color: scheme.primary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: wide ? 10 : 6,
                      children: [
                        for (final idea in ideas)
                          SizedBox(
                            width: width,
                            child: _ideaCard(idea, scheme, can, wide),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static const _editorIdeas = [
    _Idea(
      Icons.fact_check_outlined,
      'Bu doğru mu?',
      'Dayanakları ve anlatımı denetler',
      'Seçili metindeki (seçim yoksa belgedeki) hukuki dayanaklar ve '
          'anlatım doğru mu? Yanlış ya da eksik olanı göster.',
    ),
    _Idea(
      Icons.balance_outlined,
      'Karar bul',
      'İddiayı destekleyen Yargıtay kararı',
      'Seçili metindeki (seçim yoksa belgedeki) iddiayı destekleyen '
          'Yargıtay kararı bul; künyesini ve ilgili kısmını ver.',
    ),
    _Idea(
      Icons.gavel_outlined,
      'Kanun maddesi',
      'Dayanılması gereken maddeler',
      'Burada dayanılması gereken kanun maddelerini bul ve metinlerini '
          'göster.',
    ),
    _Idea(
      Icons.checklist_rounded,
      'Eksik ne var?',
      'Eksik talep, olgu, delil ya da dayanak',
      'Bu belgede eksik kalan talep, olgu, delil ya da dayanak var mı?',
    ),
    _Idea(
      Icons.auto_fix_high_outlined,
      'Daha iyi yaz',
      'Seçili metni açık ve resmî dille yeniden yazar',
      'Seçili metni anlamını değiştirmeden daha açık ve resmî bir dille '
          'yeniden yaz.',
    ),
    _Idea(
      Icons.short_text_rounded,
      'Devamını yaz',
      'Belgenin sıradaki paragrafını önerir',
      'Belgenin geldiği yerden devam eden bir sonraki paragrafı yaz.',
    ),
  ];

  /// [idea] asked at once, or written into the box for the lawyer to end.
  void _take(_Idea idea) {
    if (idea.fill) {
      _question.value = TextEditingValue(
        text: idea.ask,
        selection: TextSelection.collapsed(offset: idea.ask.length),
      );
      _focus.requestFocus();
      return;
    }
    unawaited(
      _ask(
        idea.ask == 'Bu belgeyi özetle' ? AiTask.summary : AiTask.question,
        idea.ask,
      ),
    );
  }

  Widget _ideaCard(_Idea idea, ColorScheme scheme, bool can, bool wide) =>
      Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          key: ValueKey('ai-idea-${idea.ask}'),
          borderRadius: BorderRadius.circular(12),
          onTap: can || idea.fill ? () => _take(idea) : null,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, wide ? 12 : 8, 10, wide ? 12 : 8),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(idea.icon, size: 17, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        idea.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        idea.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (idea.fill)
                  Icon(
                    Icons.edit_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      );

  /// The step as the lawyer reads it; a document read named by its title.
  String _labelOf(AiStep s) {
    if (s.tool == 'evrak_oku') {
      final key = '${s.args['anahtar'] ?? ''}';
      final title = _case == null
          ? null
          : _allDocuments(_case!).where((d) => d.key == key).firstOrNull?.title;
      if (title != null) {
        return '${s.done ? 'Evrak okundu' : 'Evrak okunuyor'} · $title';
      }
    }
    return s.label;
  }

  /// What [steps] looked at, counted by kind: "3 mevzuat · 2 karar".
  static String _counted(Iterable<AiStep> steps) {
    final counts = <String, int>{};
    for (final s in steps) {
      final kind = s is _Told
          ? switch (s.said) {
              final l when l.startsWith('Kanun') => 'mevzuat',
              final l when l.startsWith('Karar') => 'karar',
              final l when l.startsWith('Evrak okun') => 'evrak',
              _ => '',
            }
          : s.kind;
      if (kind.isEmpty || kind == 'dosya' || kind == 'ajanda') continue;
      counts[kind] = (counts[kind] ?? 0) + 1;
    }
    return [
      for (final k in const ['evrak', 'mevzuat', 'karar'])
        if (counts[k] case final n?) '$n $k',
    ].join(' · ');
  }

  /// Whether what [s] read can be opened by pressing it.
  bool _opens(AiStep s) {
    final label = _labelOf(s);
    if (!label.contains(' · ')) return false;
    if (s is _Told) {
      return label.startsWith('Kanun maddesi oku') ||
          label.startsWith('Kararın metni oku');
    }
    return s.tool == 'mevzuat_madde' ||
        s.tool == 'karar_getir' ||
        (s.tool == 'evrak_oku' && widget.onOpen != null);
  }

  /// What [s] read, opened: the article or decision over the page as the
  /// editor shows it, a document of the case in Folio.
  Future<void> _openStep(AiStep s, Offset at) async {
    if (s.tool == 'evrak_oku') {
      final record = _case;
      final file = record == null
          ? null
          : UyapCaseStore.instance.fileOf(record, '${s.args['anahtar']}');
      if (file == null) {
        _say('Bu evrak bu bilgisayarda bulunamadı.');
      } else {
        widget.onOpen?.call(file.path);
      }
      return;
    }
    final label = _labelOf(s);
    final what = label.substring(label.indexOf(' · ') + 3);
    try {
      final (articles, decisions) = await _mcp.citationsIn(what);
      if (!mounted) return;
      if (articles.firstOrNull ?? decisions.firstOrNull case final found?) {
        _openSource(found, at);
        return;
      }
    } catch (_) {}
    _say('Bu adımın okuduğu metin buradan açılamadı.');
  }

  /// One question and its answer, with what the program did on the way.
  List<Widget> _turnView(_Turn t, ColorScheme scheme) {
    final muted = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);
    final running = t.answer == null && t.error == null;
    return [
      Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 18, left: 80, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: SelectableText(
            t.question,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: _textSize,
              height: 1.5,
            ),
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
      if (t.usedSelection)
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('Seçili metinle soruldu', style: muted),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(
          [
            t.by,
            // What the answer took, said once it came.
            if (t.answer != null) ...[
              if (t.steps.length + t.recorded.length case final n when n > 0)
                '$n adım',
              if (t.requests.where((r) => r.outcome == 'İndirildi').length
                  case final n when n > 0)
                '$n evrak indirildi',
              if (t.seconds case final s? when s > 0)
                s >= 60 ? '${s ~/ 60} dk ${s % 60} sn' : '$s sn',
            ],
          ].join(' · '),
          key: ValueKey('ai-by-${identityHashCode(t)}'),
          style: muted,
        ),
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
        AiMarkdown(
          a,
          size: _textSize,
          links: {
            for (final source in t.sources)
              if (_writtenOf(a, source) case final w when w.isNotEmpty)
                w: (at) => _openSource(source, at),
          },
          block: (language, text) => _belge(language, text, scheme),
        ),
        TextButtonTheme(
          data: _quiet,
          child: Wrap(
            spacing: 2,
            children: [
              TextButton.icon(
                key: ValueKey('ai-copy-${identityHashCode(t)}'),
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: a)));
                  _say('Yanıt kopyalandı.');
                },
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const Text('Kopyala'),
              ),
              // An answer with a text for the document has its button
              // on that text; the whole answer is not offered beside it.
              if (widget.onInsert case final insert?
                  when !a.contains('```belge'))
                TextButton.icon(
                  key: ValueKey('ai-insert-${identityHashCode(t)}'),
                  onPressed: () => insert(AiAssistant.plain(a).trim()),
                  icon: const Icon(Icons.playlist_add_rounded, size: 16),
                  label: const Text('Belgeye ekle'),
                )
              else if (widget.onInsert == null &&
                  widget.onOpen != null &&
                  a.length > 400)
                TextButton.icon(
                  key: ValueKey('ai-make-${identityHashCode(t)}'),
                  onPressed: () {
                    final title = t.question.length > 60
                        ? '${t.question.substring(0, 60)}…'
                        : t.question;
                    setState(
                      () => _wrote(t, {
                        'baslik': title,
                        'metin': AiAssistant.plain(a).trim(),
                      }),
                    );
                    unawaited(_openDoc(t.documents.last));
                  },
                  icon: const Icon(Icons.note_add_outlined, size: 16),
                  label: const Text('Belge olarak aç'),
                ),
              if (t == _turns.last) ...[
                TextButton.icon(
                  key: ValueKey('ai-again-${identityHashCode(t)}'),
                  onPressed: _busy
                      ? null
                      : () => unawaited(_ask(t.task, t.question, t.tier)),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Yeniden sor'),
                ),
                if (t.tier == AiTier.normal)
                  TextButton.icon(
                    key: ValueKey('ai-stronger-${identityHashCode(t)}'),
                    onPressed: _busy
                        ? null
                        : () => unawaited(
                            _ask(t.task, t.question, AiTier.strong),
                          ),
                    icon: const Icon(Icons.bolt_rounded, size: 16),
                    label: const Text('Güçlü modelle tekrarla'),
                  ),
              ],
            ],
          ),
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
        if (t.held case final held?)
          AiMarkdown(
            held,
            size: _textSize,
            block: (language, text) => _belge(language, text, scheme),
          )
        else if (t.live.isNotEmpty)
          AiMarkdown(
            t.live.toString(),
            size: _textSize,
            block: (language, text) => _belge(language, text, scheme),
          ),
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
            onPressed: () => setState(() => _documentsChoice = true),
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
    final label = t.auditing
        ? 'Folio cevabı denetliyor'
        : fetching != null
        ? 'Evrak UYAP’tan indiriliyor · ${fetching.title}'
        : open != null
        ? _labelOf(open)
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
    // Open while it works, folded once the answer came.
    final open = t.traceOpen ?? (t.answer == null && t.error == null);
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
                        if (_counted(steps) case final c when c.isNotEmpty) c,
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
                          Expanded(
                            child: _opens(s)
                                ? Align(
                                    alignment: Alignment.centerLeft,
                                    child: InkWell(
                                      key: ValueKey('ai-step-${s.id}'),
                                      onTapUp: (d) => unawaited(
                                        _openStep(s, d.globalPosition),
                                      ),
                                      onTap: () {},
                                      child: Text(
                                        _labelOf(s),
                                        style: small.copyWith(
                                          color: scheme.primary,
                                          decoration: TextDecoration.underline,
                                          decorationColor: scheme.primary
                                              .withValues(alpha: .4),
                                        ),
                                      ),
                                    ),
                                  )
                                : Text(_labelOf(s), style: small),
                          ),
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
      case AiQuota():
        _quota = e;
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

  /// The answers' type: larger on a wide page, where a line is long.
  double _textSize = 13.5;

  /// How wide the conversation's lines run in [room]: the whole page, a
  /// narrow margin either side.
  static double readWidth(double room) => room < 1000 ? room : room - 48;

  /// The documents the program wrote in this conversation, the newest
  /// first; kept with the case's drafts when it is of one.
  final _documents = <_Doc>[];

  /// Whether the documents are beside the conversation (on the page): as
  /// the lawyer chose, or when there is room for them.
  bool? _documentsChoice;
  bool _roomy = true;
  bool get _documentsOpen => _documentsChoice ?? _roomy;

  void _wrote(_Turn turn, Map<String, Object?> body) {
    final doc = _Doc(
      AiMemory.id(),
      '${body['baslik'] ?? 'Belge'}',
      '${body['metin'] ?? ''}',
    );
    turn.documents.add(doc);
    _documents.insert(0, doc);
    if (_documentsChoice == false) _documentsChoice = null;
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
              onPressed: () => setState(() => _documentsChoice = false),
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

  static String _writtenOf(String answer, Object source) => switch (source) {
    final Citation c => _written(answer, c.start, c.length),
    final DecisionCitation c => _written(answer, c.start, c.length),
    _ => '',
  };

  /// A text the program wrote for the document (a ```belge block): in a
  /// card of its own, written into the document with one press.
  Widget? _belge(String language, String text, ColorScheme scheme) {
    if (language != 'belge') return null;
    return Container(
      key: ValueKey('ai-belge-${text.hashCode}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .04),
        border: Border.all(color: scheme.primary.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 15,
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Belge için metin',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
            child: TextButtonTheme(
              data: _quiet,
              child: Row(
                children: [
                  if (widget.onInsert case final insert?)
                    TextButton.icon(
                      key: ValueKey('ai-belge-insert-${text.hashCode}'),
                      onPressed: () => insert(text),
                      icon: const Icon(Icons.playlist_add_rounded, size: 16),
                      label: const Text('Belgeye ekle'),
                    ),
                  TextButton.icon(
                    onPressed: () {
                      unawaited(Clipboard.setData(ClipboardData(text: text)));
                      _say('Metin kopyalandı.');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('Kopyala'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What may be done with an answer: said small, under it.
  static final _quiet = TextButtonThemeData(
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
    ),
  );

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
    final color = wrong ? scheme.error : scheme.onSurfaceVariant;
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
        color: wrong
            ? scheme.error.withValues(alpha: 0.08)
            : scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: InkWell(
          key: ValueKey('ai-source-$written'),
          borderRadius: BorderRadius.circular(6),
          onTapUp: (d) => _openSource(source, d.globalPosition),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  decision ? Icons.balance_outlined : Icons.menu_book_outlined,
                  size: 13,
                  color: color,
                ),
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    written.replaceAll(RegExp(r'\s+'), ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
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

  /// To the end of the conversation, if the lawyer is following it;
  /// [now] for a question just asked, which they always follow.
  void _toEnd({bool now = false}) {
    if (now) _follow = true;
    if (!_follow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_follow && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _send() {
    final q = _question.text.trim();
    if (q.isEmpty) return;
    if (_busy) {
      // Asked when the answer coming is done.
      setState(() => _queue.add(q));
      _question.clear();
      return;
    }
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
    return LayoutBuilder(
      builder: (context, box) {
        // A small screen gives the conversation the room; the documents
        // wait behind their button.
        _roomy = box.maxWidth >= 760;
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
                  widget.onClose != null ||
                  usable.length > 1 ||
                  (!_documentsOpen &&
                      (_documents.isNotEmpty || _attached.isNotEmpty)))
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
                  child: Row(
                    children: [
                      // On the Yapay zekâ page the page says it already.
                      if (widget.embedded && widget.document == null)
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
                              : (v) {
                                  setState(() => _provider = v);
                                  // The lawyer's choice for every AI
                                  // feature: the notices read by the same.
                                  if (v != null) {
                                    unawaited(() async {
                                      final s = await AiSettings.load();
                                      if (s.provider != v) {
                                        await s.copyWith(provider: v).save();
                                      }
                                    }());
                                  }
                                },
                        ),
                      if (widget.embedded &&
                          !_documentsOpen &&
                          (_documents.isNotEmpty || _attached.isNotEmpty))
                        TextButton.icon(
                          key: const ValueKey('ai-documents-open'),
                          onPressed: () =>
                              setState(() => _documentsChoice = true),
                          icon: const Icon(
                            Icons.description_outlined,
                            size: 16,
                          ),
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
                      if (!_ofDocument && widget.showCase)
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
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_provider == null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      Platform.isLinux
                          ? 'Bu bilgisayarda oturumu açık bir yapay zekâ '
                                'programı ya da girilmiş bir API anahtarı '
                                'bulunamadı. Ayarlar › Yapay zekâ’dan Claude, '
                                'Codex ya da Antigravity’yi kurup oturum '
                                'açabilir ya da Gemini, ChatGPT, Claude veya '
                                'Groq anahtarınızı girebilirsiniz.'
                          : 'Girilmiş bir API anahtarı yok. Ayarlar › Yapay '
                                'zekâ’dan Gemini, ChatGPT, Claude ya da Groq '
                                'anahtarınızı girin; her birinin yanında '
                                'anahtarın nereden alınacağı yazar.',
                      key: const ValueKey('ai-none'),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ),
                )
              else ...[
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _turns.isEmpty
                            ? _empty(scheme)
                            : NotificationListener<ScrollNotification>(
                                onNotification: _onScroll,
                                child: LayoutBuilder(
                                  // The lines kept to a width read with
                                  // ease on a wide page.
                                  builder: (context, room) {
                                    _textSize = room.maxWidth >= 1900
                                        ? 16
                                        : room.maxWidth >= 1250
                                        ? 15
                                        : 13.5;
                                    final side =
                                        ((room.maxWidth -
                                                    readWidth(room.maxWidth)) /
                                                2)
                                            .clamp(14.0, double.infinity);
                                    return ListView(
                                      controller: _scroll,
                                      padding: EdgeInsets.fromLTRB(
                                        side,
                                        8,
                                        side,
                                        8,
                                      ),
                                      children: [
                                        for (final t in _turns)
                                          ..._turnView(t, scheme),
                                      ],
                                    );
                                  },
                                ),
                              ),
                      ),
                      if (widget.embedded &&
                          _documentsOpen &&
                          (_documents.isNotEmpty || _attached.isNotEmpty))
                        _documentsPanel(scheme),
                    ],
                  ),
                ),
                if (_sentTo case final to? when _composerShown && !_compact)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                    child: Text(
                      '${!_ofDocument
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
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _composerShown || _turns.isEmpty
                      ? KeyedSubtree(
                          key: const ValueKey('ai-composer'),
                          child: _composer(scheme),
                        )
                      : Padding(
                          key: const ValueKey('ai-to-end'),
                          padding: const EdgeInsets.only(bottom: 12, top: 4),
                          child: Center(
                            child: IconButton.filledTonal(
                              tooltip: 'En alta in',
                              onPressed: () {
                                setState(() => _composerShown = true);
                                if (_scroll.hasClients) {
                                  unawaited(
                                    _scroll.animateTo(
                                      _scroll.position.maxScrollExtent,
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      curve: Curves.easeOut,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.arrow_downward_rounded),
                            ),
                          ),
                        ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Under the conversation: what goes with the question (documents added,
  /// what is selected, the documents to be read), the questions waiting,
  /// the box itself, and under it what is added, the tier and sending.
  Widget _composer(ColorScheme scheme) {
    final small = TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant);
    final record = _case;
    final canPickCase =
        !_ofDocument && record == null && widget.caseRecord == null;
    final canMust = record != null && record.documents.isNotEmpty;
    final quota = _quota;
    // As wide as the conversation above it: its margin, no more.
    final side = MediaQuery.sizeOf(context).width >= 1000 ? 24.0 : 12.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 0, side, 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Beside the editor: the questions asked most, one press.
              if (widget.document != null && _turns.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final idea in _editorIdeas)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              key: ValueKey('ai-quick-${idea.title}'),
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                idea.title,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: _provider == null || _busy
                                  ? null
                                  : () => _take(idea),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              for (final (i, q) in _queue.indexed)
                Padding(
                  key: ValueKey('ai-queued-$i'),
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Sırada: $q',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small,
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _queue.removeAt(i)),
                        child: Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: .7),
                  ),
                  borderRadius: BorderRadius.circular(_compact ? 26 : 20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .06),
                      blurRadius: 14,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                padding: _compact
                    ? const EdgeInsets.fromLTRB(10, 4, 6, 4)
                    : const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_attached.isNotEmpty || _must.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final path in _attached)
                              InputChip(
                                key: ValueKey('ai-attached-$path'),
                                visualDensity: VisualDensity.compact,
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
                                    : () => setState(
                                        () => _attached.remove(path),
                                      ),
                              ),
                            if (_must.isNotEmpty)
                              InputChip(
                                key: const ValueKey('ai-must'),
                                visualDensity: VisualDensity.compact,
                                avatar: Icon(
                                  Icons.star_rounded,
                                  size: 16,
                                  color: scheme.primary,
                                ),
                                label: Text(
                                  '${_must.length} evrak mutlaka okunacak',
                                ),
                                onPressed: () => unawaited(_pickMust()),
                                onDeleted: () => setState(_must.clear),
                              ),
                          ],
                        ),
                      ),
                    if (_sendsPictures)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                        child: Text(
                          'Taranmış belge ve resimler görüntü olarak gider; '
                          'içlerindeki kimlik numaraları gizlenemez.',
                          style: small,
                        ),
                      ),
                    if (widget.selection != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
                          child: Tooltip(
                            message:
                                'Belgede seçtiğiniz metin soruyla birlikte '
                                'gider; cevap o metinle ilgili olur.',
                            child: InkWell(
                              key: const ValueKey('ai-selection'),
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setState(
                                () => _withSelection = !_withSelection,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _withSelection
                                          ? Icons.check_box_rounded
                                          : Icons
                                                .check_box_outline_blank_rounded,
                                      size: 16,
                                      color: _withSelection
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        'Belgede seçili metni soruya ekle',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: small,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Enter sends, Shift+Enter starts a new line.
                    Row(
                      crossAxisAlignment: _compact
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Focus(
                            onKeyEvent: (_, event) {
                              if (event is KeyDownEvent &&
                                  (event.logicalKey ==
                                          LogicalKeyboardKey.enter ||
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
                              focusNode: _focus,
                              minLines: !_compact && widget.embedded && _roomy
                                  ? 2
                                  : 1,
                              maxLines: _compact ? 1 : 10,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              style: TextStyle(
                                fontSize: _textSize,
                                height: 1.45,
                              ),
                              decoration: InputDecoration(
                                hintText: _busy
                                    ? 'Sıradaki sorunuzu yazabilirsiniz…'
                                    : _ofDocument
                                    ? 'Belgeye sorun…'
                                    : _case != null
                                    ? 'Dosyaya sorun…'
                                    : 'Sorun…',
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: _compact
                                    ? const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8,
                                      )
                                    : const EdgeInsets.fromLTRB(8, 10, 8, 8),
                              ),
                            ),
                          ),
                        ),
                        if (_compact) _sendButton(scheme),
                      ],
                    ),
                    if (!_compact)
                      Row(
                        children: [
                          if (canPickCase || canMust)
                            PopupMenuButton<String>(
                              key: const ValueKey('ai-plus'),
                              tooltip: 'Ekle',
                              icon: const Icon(Icons.add_rounded, size: 21),
                              onSelected: (v) => unawaited(switch (v) {
                                'belge' => _attach(),
                                'dosya' => _pickCase(),
                                _ => _pickMust(),
                              }),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  key: ValueKey('ai-attach'),
                                  value: 'belge',
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.attach_file_rounded),
                                    title: Text('Belge ekle'),
                                  ),
                                ),
                                if (canPickCase)
                                  const PopupMenuItem(
                                    key: ValueKey('ai-pick-case'),
                                    value: 'dosya',
                                    child: ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(Icons.folder_outlined),
                                      title: Text('Dosya bağla'),
                                    ),
                                  ),
                                if (canMust)
                                  const PopupMenuItem(
                                    key: ValueKey('ai-pick-must'),
                                    value: 'oku',
                                    child: ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(Icons.star_outline_rounded),
                                      title: Text('Mutlaka okunacak evrak'),
                                    ),
                                  ),
                              ],
                            )
                          else
                            IconButton(
                              key: const ValueKey('ai-attach'),
                              tooltip: 'Belge ekle',
                              onPressed: _busy
                                  ? null
                                  : () => unawaited(_attach()),
                              icon: const Icon(
                                Icons.attach_file_rounded,
                                size: 20,
                              ),
                            ),
                          _tierChoice(scheme),
                          const Spacer(),
                          if (quota?.label case final said?)
                            Tooltip(
                              message:
                                  'Yapay zekâ hesabınızın kullanımı: '
                                  '${[for (final w in quota!.used.entries) '${switch (w.key) {
                                      'five_hour' => '5 saatlik',
                                      'seven_day' => 'haftalık',
                                      _ => w.key,
                                    }} %${(w.value * 100).round()}'].join(', ')}',
                              child: Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Text(
                                  said,
                                  key: const ValueKey('ai-quota'),
                                  style: small.copyWith(
                                    color: quota.most >= .9
                                        ? scheme.error
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          _sendButton(scheme),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Send, round, full when there is something to send; stop while it
  /// works.
  Widget _sendButton(ColorScheme scheme) {
    final has = _question.text.trim().isNotEmpty || _attached.isNotEmpty;
    ButtonStyle style(Color fill, Color ink) => IconButton.styleFrom(
      backgroundColor: fill,
      foregroundColor: ink,
      fixedSize: const Size(36, 36),
      minimumSize: const Size(36, 36),
      padding: EdgeInsets.zero,
      shape: const CircleBorder(),
    );
    return Padding(
      padding: EdgeInsets.only(left: 4, bottom: _compact ? 0 : 2),
      child: _busy
          ? IconButton(
              key: const ValueKey('ai-stop'),
              tooltip: 'Durdur',
              onPressed: _stop,
              style: style(scheme.onSurface, scheme.surface),
              icon: Icon(Icons.stop_rounded, size: 18, color: scheme.surface),
            )
          : IconButton(
              key: const ValueKey('ai-send'),
              tooltip: 'Sor',
              onPressed: _send,
              style: style(
                has ? scheme.primary : scheme.surfaceContainerHighest,
                has ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              icon: Icon(
                Icons.arrow_upward_rounded,
                size: 20,
                color: has ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
    );
  }

  /// The tier the next question is asked at: two words, as the lawyer
  /// knows them.
  Widget _tierChoice(ColorScheme scheme) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: .6),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tier in const [AiTier.strong, AiTier.normal])
          Tooltip(
            message: tier.detail,
            child: InkWell(
              key: ValueKey('ai-tier-${tier.name}'),
              borderRadius: BorderRadius.circular(7),
              onTap: () => setState(() => _tier = tier),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _tier == tier ? scheme.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: _tier == tier
                      ? Border.all(color: scheme.outlineVariant)
                      : null,
                ),
                child: Text(
                  tier.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: _tier == tier
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: _tier == tier
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// What an empty conversation offers: asked as it is, or ([fill]) written
/// into the box for the lawyer to end.
class _Idea {
  const _Idea(
    this.icon,
    this.title,
    this.detail,
    this.ask, {
    this.fill = false,
  });
  final IconData icon;
  final String title, detail, ask;
  final bool fill;
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
