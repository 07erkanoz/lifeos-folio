import 'dart:async';
import 'dart:io';

import '../portal/observed.dart' show caseKey;
import '../portal/portal_database.dart';
import '../uyap/uyap_case_store.dart';
import 'ai_assistant.dart';
import 'ai_guide.dart';
import 'ai_case.dart';
import 'ai_memory.dart';
import 'ai_refresh.dart';

/// The lawyer's computer answering what they asked on their phone: a
/// question the phone wrote in a conversation as waiting (Senkron brings
/// it) is asked of this computer's AI program, and the answer written
/// back in its place, with the findings and drafts the program offered
/// for the phone to keep or not. A computer that is off answers when it
/// is on again. One question at a time, the oldest first.
class AiRelay {
  AiRelay({
    Future<PortalDatabase> Function()? database,
    Future<String> Function(
      AiProvider,
      String,
      AiCaseSession?,
      String?,
      AiThread?,
    )?
    ask,
    Future<AiProvider?> Function(AiSettings settings)? provider,
  }) : _database = database ?? PortalDatabase.shared,
       _ask = ask ?? _askProgram,
       _provider = provider ?? _usable;

  static final instance = AiRelay();

  final Future<PortalDatabase> Function() _database;
  final Future<String> Function(
    AiProvider provider,
    String prompt,
    AiCaseSession? session,
    String? model,
    AiThread? thread,
  )
  _ask;
  final Future<AiProvider?> Function(AiSettings settings) _provider;

  /// The program the lawyer chose, or the first one signed in.
  static Future<AiProvider?> _usable(AiSettings settings) async {
    final statuses = await AiAssistant.statuses();
    return settings.provider != null &&
            statuses.any((s) => s.provider == settings.provider && s.usable)
        ? settings.provider!
        : statuses.where((s) => s.usable).map((s) => s.provider).firstOrNull;
  }

  /// A question taken by a computer and not answered in this long is
  /// taken again: the computer was turned off on it.
  static const stale = Duration(minutes: 15);

  Timer? _timer;
  bool _working = false;

  /// Looked at now and then while this computer asks its AI program.
  void start() {
    _timer ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(poke()),
    );
    unawaited(poke());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<String> _askProgram(
    AiProvider provider,
    String prompt,
    AiCaseSession? session,
    String? model,
    AiThread? thread,
  ) => AiAssistant.ask(
    provider,
    prompt,
    model: model,
    tier: AiTier.strong,
    caseSession: session,
    thread: thread,
  );

  /// The question waiting, if any, asked and answered. True when one was.
  Future<bool> poke() async {
    // Only a computer that runs an AI program answers: a phone never
    // takes a question.
    // A phone asks for itself or waits for the computer; it answers none.
    if (_working || !AiAssistant.available || AiAssistant.phone) return false;
    _working = true;
    try {
      final settings = await AiSettings.load();
      if (!settings.enabled || !settings.consented) return false;
      final db = await _database();
      final now = DateTime.now();
      final waiting = [
        for (final c in db.aiRecords(AiMemory.chat))
          if (AiMemory.turnsOf(c).lastOrNull case final t?
              when t['bekliyor'] == true &&
                  (DateTime.tryParse('${t['alindi'] ?? ''}') == null ||
                      now.difference(DateTime.parse('${t['alindi']}')) > stale))
            c,
      ]..sort((a, b) => '${a['guncellendi']}'.compareTo('${b['guncellendi']}'));
      if (waiting.isEmpty) return false;
      await _answer(db, waiting.first, settings);
      return true;
    } catch (_) {
      return false;
    } finally {
      _working = false;
    }
  }

  Future<void> _answer(
    PortalDatabase db,
    Map<String, Object?> chat,
    AiSettings settings,
  ) async {
    final id = '${chat['id']}';
    var key = '${chat['dosya'] ?? ''}';
    final turns = AiMemory.turnsOf(chat);
    final question = turns.last;
    // Taken by this computer: the others leave it.
    void write(
      Map<String, Object?> last, {
      String? court,
      String? number,
      AiThread? thread,
    }) {
      db.putAiRecord(id, AiMemory.chat, key, {
        ...chat,
        if (thread != null && thread.ids.isNotEmpty)
          'oturumlar': thread.toJson(),
        'turlar': [...turns.take(turns.length - 1), last],
        'guncellendi': DateTime.now().toIso8601String(),
        'mahkeme': ?court ?? chat['mahkeme'],
        'esas': ?number ?? chat['esas'],
      });
    }

    final claimed = {
      ...question,
      'alindi': DateTime.now().toIso8601String(),
      'cevaplayan': _thisComputer(),
    };
    write(claimed);
    final provider = await _provider(settings);
    if (provider == null) {
      write({
        ...claimed,
        'bekliyor': false,
        'hata': 'Bilgisayarınızda oturumu açık bir yapay zekâ programı yok.',
      });
      return;
    }
    UyapCaseRecord? record;
    if (key.isNotEmpty) {
      final kase = db.caseOf(key);
      final court = kase?.court ?? chat['mahkeme'] as String?;
      final number = kase?.number ?? chat['esas'] as String?;
      if (court != null && number != null) {
        record =
            await UyapCaseStore.instance.load(court, number) ??
            UyapCaseRecord(
              court: court,
              number: number,
              fetchedAt: DateTime.now(),
            );
      }
    }
    final tools =
        AiAssistant.takesTools(provider) ||
        await AiAssistant.antigravityFolio() != null;
    // The program goes on with the conversation it had: the earlier
    // answers are then not sent again.
    final thread = AiThread.of(id, chat['oturumlar']);
    final who = await AiAssistant.who();
    final guide = (await LegalGuide.load()).blockFor(
      '${question['soru'] ?? ''}',
    );
    String prompt({required bool full}) => AiAssistant.prompt(
      task: AiTask.question,
      question: '${question['soru'] ?? ''}',
      caseName: record != null && tools
          ? '${record.court} ${record.number}'
          : null,
      note: record != null && tools
          ? AiMemory.hint(db.aiCounts(key))
          : tools
          ? 'Soru avukatın bir dosyasıyla ilgiliyse dosya_ara ile dosyayı '
                'bul; tek dosya açıkça uyuyorsa dosya_sec ile seç, birden '
                'fazla uyuyorsa hangisi olduğunu avukata sor. Ajanda, '
                'süre, tebligat ve bildirim soruları için Folio\'nun '
                'ajanda, tebligatlar ve uyap_bildirimleri araçları var.'
          : null,
      who: who,
      guide: tools ? guide : null,
      history: [
        if (full)
          for (final t in turns.take(turns.length - 1))
            if (t['cevap'] case final String a)
              (question: '${t['soru'] ?? ''}', answer: a),
      ],
    );
    final session = tools ? await AiCaseSession.open(record, chat: id) : null;
    var busy = false;
    final serving = session == null
        ? null
        : Timer.periodic(const Duration(seconds: 1), (_) async {
            if (busy) return;
            busy = true;
            try {
              // UYAP asked for fresh, and documents to download: done here,
              // this computer holding the session.
              await AiRefresh.serve(session);
              await AiRefresh.serveDownloads(session);
            } finally {
              busy = false;
            }
          });
    try {
      final model = settings.modelFor(provider, AiTask.question.tier);
      String answer;
      if (await AiAssistant.goesOn(provider, thread)) {
        try {
          answer = await _ask(
            provider,
            prompt(full: false),
            session,
            model,
            thread,
          );
        } on AiFailure catch (e) {
          if (e.timedOut) rethrow;
          // Its record gone (another computer, or cleared): from the start.
          thread.ids.remove(provider);
          answer = await _ask(
            provider,
            prompt(full: true),
            session,
            model,
            thread,
          );
        }
      } else {
        answer = await _ask(
          provider,
          prompt(full: true),
          session,
          model,
          thread,
        );
      }
      String? court, number;
      if (session != null) {
        if (await session.bound() case final b?) {
          court = b.court;
          number = b.number;
          key = caseKey(b.number, b.court);
        }
      }
      final offers = session == null
          ? const <({String kind, Map<String, Object?> body})>[]
          : await session.proposals();
      write(
        {
          ...claimed,
          'bekliyor': false,
          'cevap': answer,
          'yazan': '${provider.label} · ${AiTask.question.tier.label}',
          'zaman': DateTime.now().toIso8601String(),
          if (offers.isNotEmpty)
            'teklifler': [
              for (final o in offers)
                // Findings are kept at once, as on the computer.
                if (o.kind == AiMemory.finding && key.isNotEmpty)
                  {
                    'tur': o.kind,
                    ...o.body,
                    'karar': _keepFindings(db, key, id, o.body, provider),
                  }
                else
                  {'tur': o.kind, ...o.body},
            ],
        },
        court: court,
        number: number,
        thread: thread,
      );
    } on AiFailure catch (e) {
      write({...claimed, 'bekliyor': false, 'hata': e.message});
    } catch (e) {
      write({...claimed, 'bekliyor': false, 'hata': 'Yanıt alınamadı: $e'});
    } finally {
      serving?.cancel();
      unawaited(session?.close());
    }
  }

  /// [body]'s findings kept as [key]'s; what is said of it.
  static String _keepFindings(
    PortalDatabase db,
    String key,
    String chat,
    Map<String, Object?> body,
    AiProvider provider,
  ) {
    final items = body['bulgular'] as List? ?? const [];
    final now = DateTime.now().toIso8601String();
    var kept = 0;
    for (final f in items) {
      if (f is! Map) continue;
      db.putAiRecord(AiMemory.id(), AiMemory.finding, key, {
        ...f.cast<String, Object?>(),
        'sohbet': chat,
        'yazan': '${provider.label} · ${AiTask.question.tier.label}',
        'zaman': now,
      });
      kept++;
    }
    return '$kept bulgu dosyanın hafızasına kaydedildi';
  }

  static String _thisComputer() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'Bilgisayar';
    }
  }
}
