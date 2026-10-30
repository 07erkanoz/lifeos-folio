import 'dart:async';
import 'dart:io';

import '../portal/observed.dart' show caseKey;
import '../portal/portal_database.dart';
import '../uyap/uyap_case_store.dart';
import 'ai_assistant.dart';
import 'ai_case.dart';
import 'ai_memory.dart';

/// The lawyer's computer answering what they asked on their phone: a
/// question the phone wrote in a conversation as waiting (Senkron brings
/// it) is asked of this computer's AI program, and the answer written
/// back in its place, with the findings and drafts the program offered
/// for the phone to keep or not. A computer that is off answers when it
/// is on again. One question at a time, the oldest first.
class AiRelay {
  AiRelay({
    Future<PortalDatabase> Function()? database,
    Future<String> Function(AiProvider, String, AiCaseSession?, String?)? ask,
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
  ) => AiAssistant.ask(provider, prompt, model: model, caseSession: session);

  /// The question waiting, if any, asked and answered. True when one was.
  Future<bool> poke() async {
    // Only a computer that runs an AI program answers: a phone never
    // takes a question.
    if (_working || !AiAssistant.available) return false;
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
    void write(Map<String, Object?> last, {String? court, String? number}) {
      db.putAiRecord(id, AiMemory.chat, key, {
        ...chat,
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
    final prompt = AiAssistant.prompt(
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
                'fazla uyuyorsa hangisi olduğunu avukata sor.'
          : null,
      history: [
        for (final t in turns.take(turns.length - 1))
          if (t['cevap'] case final String a)
            (question: '${t['soru'] ?? ''}', answer: a),
      ],
    );
    final session = tools ? await AiCaseSession.open(record, chat: id) : null;
    // Asked from the phone: no document is downloaded without the lawyer
    // at the computer, so a download asked for is said no to at once.
    final refuse = session == null
        ? null
        : Timer.periodic(const Duration(seconds: 1), (_) async {
            for (final r in await session.pending()) {
              await session.answer(
                r,
                'reddedildi',
                'Soru telefondan soruldu; evrak indirilemez. Avukat evrakı '
                    'bilgisayardan indirebilir.',
              );
            }
          });
    try {
      final answer = await _ask(
        provider,
        prompt,
        session,
        settings.modelFor(provider, AiTask.question.tier),
      );
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
              for (final o in offers) {'tur': o.kind, ...o.body},
            ],
        },
        court: court,
        number: number,
      );
    } on AiFailure catch (e) {
      write({...claimed, 'bekliyor': false, 'hata': e.message});
    } catch (e) {
      write({...claimed, 'bekliyor': false, 'hata': 'Yanıt alınamadı: $e'});
    } finally {
      refuse?.cancel();
      unawaited(session?.close());
    }
  }

  static String _thisComputer() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'Bilgisayar';
    }
  }
}
