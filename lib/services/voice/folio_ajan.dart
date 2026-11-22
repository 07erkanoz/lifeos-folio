import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../ai/ai_assistant.dart';
import '../ai/ai_office.dart';
import '../ai/ai_relay.dart';
import 'ajan_voice.dart';
import 'codex_conversation.dart';
import 'live_conversation.dart';
import 'live_tools.dart';
import 'voice_settings.dart';

/// One line of the briefing.
class BriefItem {
  const BriefItem(
    this.title,
    this.detail, {
    this.when = '',
    this.clock = '',
    this.days,
    this.urgent = false,
  });
  final String title, detail, when;

  /// The hour, when the record has one ("10:30").
  final String clock;

  /// Days from today; none, the record has no date.
  final int? days;
  final bool urgent;
}

/// Jarvis mode's sides: the day's hearings, the deadlines near, what came
/// in (UYAP's notifications and the e-notices not read) and the tasks
/// open. Read through Folio's own office tools, as the AI programs read
/// them: what is secret is not shown.
class AjanBrief {
  const AjanBrief({
    this.hearings = const [],
    this.deadlines = const [],
    this.incoming = const [],
    this.tasks = const [],
  });

  final List<BriefItem> hearings, deadlines, incoming, tasks;

  /// One sentence for the top of the screen.
  String get summary {
    final parts = [
      if (hearings.isNotEmpty) '${hearings.length} duruşma',
      if (deadlines.any((d) => d.urgent))
        '${deadlines.where((d) => d.urgent).length} yakın süre',
      if (incoming.isNotEmpty) '${incoming.length} yeni gelen',
      if (tasks.isNotEmpty) '${tasks.length} açık görev',
    ];
    return parts.isEmpty
        ? 'Bugün için kayıtlı bir şey yok.'
        : '${parts.join(', ')}.';
  }

  static String _case(Map m) => [
    m['esas'],
    m['mahkeme'],
  ].where((v) => '${v ?? ''}'.isNotEmpty).join(' · ');

  static String _clock(String iso) =>
      iso.length > 15 && iso[10] == 'T' ? iso.substring(11, 16) : '';

  static int? _days(String iso, DateTime today) {
    final d = DateTime.tryParse(iso);
    if (d == null) return null;
    return DateTime(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
  }

  static String _day(String iso, DateTime today) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    final days = DateTime(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
    final clock = iso.length > 10 ? ' ${iso.substring(11, 16)}' : '';
    return switch (days) {
      0 => 'Bugün$clock',
      1 => 'Yarın$clock',
      _ => '${d.day}.${d.month.toString().padLeft(2, '0')}$clock',
    };
  }

  /// From the office tools' answers.
  static AjanBrief from(
    Map<String, Object?> agenda,
    Map<String, Object?> notifications,
    Map<String, Object?> notices,
    DateTime today,
  ) {
    List<Map> list(Map<String, Object?> m, String key) =>
        (m[key] as List? ?? const []).whereType<Map>().toList();
    final todayIso = today.toIso8601String().substring(0, 10);
    final soon = today
        .add(const Duration(days: 3))
        .toIso8601String()
        .substring(0, 10);
    return AjanBrief(
      hearings: [
        // The week's (the agenda tool reads seven days): two hearings three
        // and six days off were left out by a three-day cut (21 Kasım 2026).
        for (final h in list(agenda, 'durusmalar'))
          BriefItem(
            _case(h),
            '${h['tur'] ?? 'Duruşma'}',
            when: _day('${h['tarih']}', today),
            clock: _clock('${h['tarih']}'),
            days: _days('${h['tarih']}', today),
            urgent: '${h['tarih']}'.startsWith(todayIso),
          ),
      ],
      deadlines: [
        for (final d in list(agenda, 'sureler'))
          BriefItem(
            '${d['baslik']}',
            _case(d),
            when: _day('${d['son_gun']}', today),
            days: _days('${d['son_gun']}', today),
            urgent: '${d['son_gun']}'.compareTo(soon) <= 0,
          ),
      ],
      incoming: [
        for (final n in list(notifications, 'bildirimler'))
          BriefItem(
            '${n['baslik']}',
            _case(n),
            when: _day('${n['tarih']}', today),
          ),
        for (final n in list(notices, 'tebligatlar'))
          BriefItem(
            'Tebligat: ${n['konu']}',
            _case(n),
            when: _day('${n['tarih']}', today),
          ),
      ],
      tasks: [
        for (final t in list(agenda, 'gorev_ve_notlar'))
          if (t['tur'] == 'görev' && t['bitti'] != true)
            BriefItem(
              '${t['baslik']}',
              _case(t),
              when: t['tarih'] == null ? '' : _day('${t['tarih']}', today),
            ),
      ],
    );
  }

  static Future<AjanBrief> load({FolioOfficeTools? tools}) async {
    final office = tools ?? FolioOfficeTools(Directory.systemTemp);
    final results = await Future.wait([
      office.call('ajanda', const {}),
      office.call('uyap_bildirimleri', const {'gun': 3, 'okunmamis': true}),
      office.call('tebligatlar', const {'gun': 7, 'okunmamis': true}),
    ]);
    return from(results[0], results[1], results[2], DateTime.now());
  }

  /// What Live is asked to read aloud.
  String get spoken {
    String items(List<BriefItem> l) => l
        .take(5)
        .map((i) => '${i.when} ${i.title} ${i.detail}'.trim())
        .join('; ');
    return [
      'Bana günün kısa sesli brifingini ver; yalnız aşağıdakilere dayan, '
          'iki üç cümleyi geçme, önce acil olanlar:',
      if (hearings.isNotEmpty) 'Duruşmalar: ${items(hearings)}.',
      if (deadlines.isNotEmpty) 'Süreler: ${items(deadlines)}.',
      if (incoming.isNotEmpty) 'Yeni gelenler: ${items(incoming)}.',
      if (tasks.isNotEmpty) 'Açık görevler: ${items(tasks)}.',
      if (hearings.isEmpty &&
          deadlines.isEmpty &&
          incoming.isEmpty &&
          tasks.isEmpty)
        'Bugün için kayıtlı bir şey yok.',
    ].join(' ');
  }
}

/// Folio Ajan in the quick search palette and in Jarvis mode: the voice
/// (Live, with Folio's tools), the written question (the lawyer's AI
/// program), and the briefing.
class FolioAjan extends ChangeNotifier {
  FolioAjan();

  static final instance = FolioAjan();

  VoiceSettings settings = const VoiceSettings();

  /// The palette's and Jarvis's theme; none, Folio's own.
  bool? dark;

  /// The AI program that answers ("Claude", "Codex (ChatGPT)"…); empty,
  /// none is ready.
  String brainLabel = '';

  void toggleDark(bool current) {
    dark = !current;
    notifyListeners();
  }

  /// Gemini Live (a paid API key).
  late final LiveConversation gemini = LiveConversation(
    tools: FolioLiveTools(brain: askFolio),
  )..addListener(notifyListeners);

  /// Codex (the lawyer's ChatGPT subscription); the main voice.
  late final CodexConversation codex = CodexConversation(
    brain: (q) async {
      final claude = this.claude;
      return claude == null
          ? 'Claude bağlı değil; bu işi kendin yap.'
          : askFolio(q, only: claude);
    },
  )..addListener(notifyListeners);

  /// Claude, where it is signed in (Claude Code) or has a key (its API):
  /// a Codex conversation may hand it the heavy work.
  AiProvider? claude;

  /// Codex CLI is here and signed in: then it carries the voice, at no
  /// cost beyond the subscription; Gemini only where it is not.
  bool codexReady = false;

  /// Codex where it is signed in; otherwise Gemini Live, with its key.
  AjanVoice get voice => codexReady ? codex : gemini;

  AjanBrief? brief;
  bool briefLoading = false;
  String? briefError;

  /// The written question and its answer, in the palette.
  String question = '';
  String answer = '';
  String? askError;
  bool asking = false;
  final steps = <String>[];
  Completer<void>? _cancel;

  /// Whether the AI features may be shown at all.
  /// Linux's desktop alone for now: Windows and macOS have neither the
  /// wake word's library nor a tried voice (21 Kasım 2026).
  bool get available => Platform.isLinux && AiAssistant.shown;

  Future<void> loadSettings() async {
    settings = await VoiceSettings.load();
    codexReady = await CodexConversation.ready();
    claude = await usableClaude();
    try {
      brainLabel = (await AiRelay.usable(await AiSettings.load()))?.label ?? '';
    } catch (_) {
      brainLabel = '';
    }
    _apply(settings);
    notifyListeners();
  }

  /// Called before a conversation takes the microphone: the wake word's
  /// listening lets go of it.
  static Future<void> Function()? beforeVoice;

  /// While a conversation is being started (the wake word waits).
  bool voiceStarting = false;

  /// Starts the conversation, the microphone freed first.
  Future<void> startVoice({bool handsFree = false}) async {
    voiceStarting = true;
    try {
      await beforeVoice?.call();
      await voice.start(handsFree: handsFree);
    } finally {
      voiceStarting = false;
      notifyListeners();
    }
  }

  /// The voice's settings alone, without asking which programs are
  /// signed in: at start, for the bar's button.
  Future<void> loadVoiceSettings() async {
    try {
      settings = await VoiceSettings.load();
      _apply(settings);
      notifyListeners();
    } catch (_) {}
  }

  /// Codex's reasoning, one press each, kept: low, medium, high, very
  /// high. Takes effect from the next conversation.
  static const efforts = ['low', 'medium', 'high', 'xhigh'];
  static const effortNames = {
    'low': 'Düşük',
    'medium': 'Orta',
    'high': 'Yüksek',
    'xhigh': 'Çok yüksek',
  };

  String get effortLabel =>
      effortNames[settings.codexEffort] ?? settings.codexEffort;

  Future<void> nextEffort() {
    final i = efforts.indexOf(settings.codexEffort);
    return saveSettings(
      settings.copyWith(codexEffort: efforts[(i + 1) % efforts.length]),
    );
  }

  /// Who does the heavy work in a Codex conversation: Folio's AI program
  /// (Claude Code…) or Codex itself; one press each, kept.
  String get heavyLabel =>
      settings.handOn && brainLabel.isNotEmpty ? brainLabel : 'Codex';

  Future<void> toggleHandOn() =>
      saveSettings(settings.copyWith(handOn: !settings.handOn));

  void _apply(VoiceSettings s) {
    gemini
      ..headphones = s.headphones
      ..voice = s.voice;
    codex
      ..voice = s.codexVoice
      ..model = s.codexModel
      ..effort = s.codexEffort
      ..handOn = s.handOn && claude != null;
  }

  Future<void> saveSettings(VoiceSettings s) async {
    settings = s;
    _apply(s);
    await s.save();
    if (!s.on && voice.active) await voice.stop();
    notifyListeners();
  }

  Future<void> loadBrief() async {
    briefLoading = true;
    briefError = null;
    notifyListeners();
    try {
      brief = await AjanBrief.load();
    } catch (e) {
      briefError = 'Brifing okunamadı: $e';
    } finally {
      briefLoading = false;
      notifyListeners();
    }
  }

  /// Jarvis mode opened: the briefing, and hands-free listening when the
  /// lawyer turned the voice on.
  Future<void> enterJarvis() async {
    await loadSettings();
    unawaited(loadBrief());
    if (settings.on && available && !voice.active) {
      await startVoice(handsFree: true);
    }
  }

  Future<void> leaveJarvis() async {
    if (voice.active) await voice.stop();
  }

  /// The briefing read aloud by Live.
  Future<void> speakBrief() async {
    final b = brief;
    if (b == null || !settings.on) return;
    await voice.send(b.spoken);
  }

  /// Push to talk from the palette: on, then off.
  Future<void> toggleTalk() async {
    if (voice.active) {
      await voice.stop();
    } else {
      await loadSettings();
      await startVoice();
    }
  }

  /// A written question, answered by the lawyer's AI program with Folio's
  /// tools.
  Future<void> ask(String text) async {
    text = text.trim();
    if (text.isEmpty || asking) return;
    question = text;
    answer = '';
    askError = null;
    steps.clear();
    asking = true;
    _cancel = Completer<void>();
    notifyListeners();
    try {
      final got = await askFolio(
        text,
        onEvent: (e) {
          if (e is AiStep && !e.done) {
            steps.add(e.label);
            notifyListeners();
          }
        },
      );
      if (!(_cancel?.isCompleted ?? true)) answer = got;
    } catch (e) {
      askError = '$e';
    } finally {
      asking = false;
      notifyListeners();
    }
  }

  void clearAnswer() {
    _cancel?.complete();
    _cancel = null;
    question = answer = '';
    askError = null;
    asking = false;
    steps.clear();
    notifyListeners();
  }
}
