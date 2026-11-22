import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ai/ai_groq.dart';
import 'ajan_voice.dart';
import 'live_audio.dart';
import 'live_session.dart';
import 'live_tools.dart';
import 'live_usage.dart';
import 'speech_gate.dart';

enum LiveState {
  /// The microphone is shut.
  off,

  /// Hands free: the microphone is open but its sound stays here until
  /// someone begins to speak.
  waiting,
  connecting,
  listening,
  thinking,

  /// The brain (Claude Code, Codex, Antigravity or an API) is at work.
  working,
  speaking,
}

class LiveLine {
  LiveLine(this.who, this.text);

  /// `avukat`, `ajan` or `bilgi`.
  final String who;
  String text;
}

/// "21 Kasım 2026 Cumartesi, saat 09:05".
String ajanToday(DateTime now) {
  const days = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];
  const months = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];
  final hm =
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}';
  return '${now.day} ${months[now.month - 1]} ${now.year} '
      '${days[now.weekday - 1]}, saat $hm';
}

/// What the voice may do beyond reading, and how: only when asked, and
/// only once the lawyer said yes to what it read back (22 Kasım 2026).
String ajanWrites() =>
    'Avukat isterse ajandaya görev ya da süre (ajanda_ekle), not (not_ekle) '
    've dosya notu (dosya_notu_ekle) ekleyebilir, dilekçe hazırlayıp '
    'dosyanın Dilekçelerim bölümüne UDF olarak kaydedebilirsin '
    '(dosya_sec, sonra dilekce_kaydet). Yazmadan önce ne yazacağını '
    'tarihiyle kısaca oku ve “kaydedeyim mi?” diye sor; avukat açıkça evet '
    'demeden yazma, kendiliğinden hiçbir şey ekleme. Dilekçeyi dosyanın '
    'bilgisine ve evrakına bakarak eksiksiz yaz, sesli olarak tamamını okuma: '
    'konusunu ve istemini bir iki cümleyle söyle. UYAP’tan güncel bilgi '
    '(uyap_guncelle) alabilir, inmemiş evrakı indirebilir (evrak_indir) ve '
    'e-tebligatın metnini okuyabilirsin (tebligat_oku); bunlar biraz '
    'sürer, beklerken “UYAP’tan alıyorum” de. Hiçbir şeyi silme, '
    'değiştirme ya da dışarı gönderme.';

/// Today, and how the voice reads "this week": on a Saturday the calendar
/// week was all past, and Folio Ajan answered "bu hafta duruşmalarım" with
/// two hearings that had gone, not the next week's (21 Kasım 2026).
String ajanDates(DateTime now) =>
    'Bugün ${ajanToday(now)}. Tarih, gün ya da saat sorulursa buna göre '
    'cevap ver. “Bu hafta”, “önümüzdeki günler”, “duruşmalarım neler” gibi '
    'sorularda ajandayı tarih vermeden oku: bugünden itibaren yedi gün gelir; '
    'takvim haftasının geçmiş günlerini sayma. Geçmiş bir tarihi yalnız '
    'açıkça sorulursa (“dün”, “geçen hafta”) söyle ve geçti diye belirt. '
    'Araç çıktısında olmayan bir duruşma ya da tarih söyleme.';

/// Folio Ajan's spoken conversation, after AvukatOS Asistan's (`asistan.dart`),
/// whose lessons it keeps:
///
/// - Each question has a new, small Live session: Live re-bills the whole
///   context every turn and caches nothing. The conversation goes on through
///   its last lines, written; the next session is opened while the answer is
///   still being heard, and what is said meanwhile waits in a buffer.
/// - A session that cannot be renewed three turns in a row ends the
///   conversation, so that the cost does not pile up.
/// - Quiet for [idle] after the answer has been heard closes the session.
///   Hands free, the conversation then waits for speech on the computer
///   ([SpeechGate]); no sound and no silence is billed meanwhile.
/// - Without headphones nothing is sent while Live speaks: its voice would
///   come back through the microphone and cut itself off.
/// - Live calls Folio's tools itself ([FolioLiveTools]: a few declared,
///   the rest found when needed, long answers summarized); heavy work goes
///   to the lawyer's AI program.
class LiveConversation extends ChangeNotifier implements AjanVoice {
  LiveConversation({
    required this.tools,
    Future<String?> Function()? key,
    LiveSession Function(LiveEvents)? session,
    LiveMicrophone? microphone,
    LiveSpeaker? speaker,
    Future<SpeechDetector> Function()? detector,
    Future<void> Function()? prepare,
    this.idle = const Duration(seconds: 20),
    this.headphones = false,
    this.voice = '',
  }) : _key = key ?? (() => GroqChat.key(ApiService.gemini)),
       _newSession = session ?? LiveSession.new,
       microphone = microphone ?? LiveMicrophone(),
       speaker = speaker ?? LiveSpeaker(),
       _detector = detector ?? SileroDetector.open,
       _prepare = prepare ?? LiveSpeaker.prepare;

  /// What Live may call: Folio's tools, and the AI program for heavy work.
  final LiveToolBox tools;
  final Future<String?> Function() _key;
  final LiveSession Function(LiveEvents) _newSession;
  final Future<SpeechDetector> Function() _detector;
  final Future<void> Function() _prepare;
  final LiveMicrophone microphone;
  final LiveSpeaker speaker;
  final Duration idle;
  bool headphones;
  String voice;

  static const _mostSameSession = 3;
  static const _contextLines = 8, _contextChars = 300;

  static const instruction =
      'Sen Folio Ajan’sın: bir avukatın bilgisayarındaki LifeOS Folio’nun sesli '
      'yardımcısısın. Türkçe, kısa ve doğal konuş; avukata “siz” diye hitap et. '
      'Dosya, müvekkil, duruşma, süre, ajanda, tebligat, evrak, karar ya da '
      'mevzuatla ilgili soruları araçlarla cevapla; bilmediğini uydurma, '
      'elindeki araçlar yetmezse önce ${FolioLiveTools.findTool} ile ara. '
      'Dilekçe taslağı ya da uzun inceleme gibi ağır işleri '
      '${FolioLiveTools.brainTool} aracına ver. Araç çalışırken “bakıyorum” '
      'gibi kısa bir söz söyle, sonuç gelince bir-üç cümleyle özetle. Bir '
      'özetin ayrıntısını tahmin etme, ${FolioLiveTools.askText} ile sor.';

  LiveState _state = LiveState.off;
  @override
  LiveState get state => _state;
  @override
  String? error;

  @override
  final lines = <LiveLine>[];

  /// The tools Live called, the latest last (shown while it works).
  @override
  final steps = <String>[];

  @override
  String get label => 'Gemini';

  @override
  ValueListenable<double> get level =>
      speaker.playing ? speaker.level : microphone.level;
  LiveLine? _heardLine, _saidLine;

  /// What this conversation cost, and its last answer.
  LiveCost spent = const LiveCost();
  LiveCost lastTurn = const LiveCost();
  LiveCost _turn = const LiveCost();

  LiveSession? _session;
  SpeechGate? _gate;
  bool _handsFree = false;
  bool _renewing = false;
  int _sameSession = 0;
  int _working = 0;
  bool _replying = false;
  final _waitingSound = <Uint8List>[];
  DateTime _lastActivity = DateTime.now();
  Timer? _clock;

  @override
  bool get active => _state != LiveState.off;

  void _set(LiveState s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  /// Opens the microphone. [handsFree]: Live is reached only when someone
  /// speaks (Jarvis mode); otherwise at once (a press to speak).
  @override
  Future<void> start({bool handsFree = false}) async {
    if (active) return;
    error = null;
    _handsFree = handsFree;
    try {
      await _prepare();
      if (handsFree) {
        _gate ??= SpeechGate(await _detector());
        _gate!.reset();
        _set(LiveState.waiting);
      } else {
        await _openSession();
      }
      await microphone.open(_fromMicrophone);
      _clock = Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
    } catch (e) {
      error = '$e';
      await stop();
    }
  }

  /// Written words, as if said: the session is opened for them if there is
  /// none (Jarvis's text field, the briefing).
  @override
  Future<void> send(String text) async {
    text = text.trim();
    if (text.isEmpty) return;
    if (!active) {
      await start();
      if (!active) return;
    }
    if (_session == null) {
      try {
        await _openSession();
      } catch (e) {
        error = '$e';
        _set(_handsFree ? LiveState.waiting : LiveState.off);
        return;
      }
    }
    lines.add(LiveLine('avukat', text));
    _lastActivity = DateTime.now();
    _session?.sendText(text);
    _set(LiveState.thinking);
  }

  @override
  Future<void> stop() async {
    _clock?.cancel();
    _clock = null;
    final s = _session;
    _session = null;
    await microphone.close();
    await speaker.clear();
    await s?.close();
    _endTurn();
    _replying = false;
    _working = 0;
    _waitingSound.clear();
    _set(LiveState.off);
  }

  @override
  void dispose() {
    unawaited(stop());
    _gate?.dispose();
    super.dispose();
  }

  Future<LiveSession> _connect() async {
    final key = await _key();
    if (key == null || key.isEmpty) {
      throw const LiveFailure(
        'Gemini anahtarı yok. Ayarlar › Yapay zekâ’dan ücretli bir Gemini anahtarı girin.',
      );
    }
    final events = LiveEvents();
    final s = _newSession(events);
    events
      ..audio = _fromLive
      ..heard = _heard
      ..said = _said
      ..interrupted = _interrupted
      ..turnComplete = (() => _turnComplete(s))
      ..tools = ((calls) => _tools(s, calls))
      ..usage = ((u) => _turn = LiveCost.of(u))
      ..goingAway = (() => unawaited(_renew()))
      ..closed = ((why) => _closed(s, why));
    await s.connect(
      key: key,
      instruction:
          '$instruction ${ajanDates(DateTime.now())} ${ajanWrites()}'
          '${context(lines)}${tools.remembered}',
      tools: await tools.declarations(),
      voice: voice,
    );
    return s;
  }

  Future<void> _openSession() async {
    _set(LiveState.connecting);
    _renewing = true;
    try {
      _session = await _connect();
      _sameSession = 0;
      _lastActivity = DateTime.now();
      for (final p in _waitingSound) {
        _session!.sendAudio(p);
      }
      _set(LiveState.listening);
    } finally {
      _waitingSound.clear();
      _renewing = false;
    }
  }

  /// The conversation so far, for a new session: its last lines, each
  /// shortened.
  static String context(List<LiveLine> lines) {
    final told = [
      for (final l in lines.where(
        (l) => l.who != 'bilgi' && l.text.trim().isNotEmpty,
      ))
        '${l.who == 'avukat' ? 'Avukat' : 'Sen'}: ${_short(l.text.trim())}',
    ];
    if (told.isEmpty) return '';
    final last = told.length > _contextLines
        ? told.sublist(told.length - _contextLines)
        : told;
    return '\n\nKonuşmanın son satırları (kaldığın yerden sürdür):\n${last.join('\n')}';
  }

  static String _short(String s) =>
      s.length <= _contextChars ? s : '${s.substring(0, _contextChars)}…';

  void _fromMicrophone(Uint8List pcm) {
    final s = _session;
    if (s == null) {
      if (_renewing) {
        _buffer(pcm);
        return;
      }
      if (_state != LiveState.waiting) return;
      final began = _gate?.take(pcm);
      if (began == null) return;
      _waitingSound.addAll(began);
      unawaited(
        _openSession().catchError((Object e) {
          error = '$e';
          _set(_handsFree ? LiveState.waiting : LiveState.off);
        }),
      );
      return;
    }
    // Live's own voice must not come back to it.
    if (!headphones && (_replying || speaker.playing)) return;
    if (_renewing) {
      _buffer(pcm);
      return;
    }
    s.sendAudio(pcm);
  }

  // About four seconds while a session is being opened.
  void _buffer(Uint8List pcm) {
    if (_waitingSound.length < 160) _waitingSound.add(pcm);
  }

  void _fromLive(Uint8List pcm) {
    _replying = true;
    speaker.write(pcm);
    _lastActivity = DateTime.now();
  }

  void _heard(String text) {
    _lastActivity = DateTime.now();
    final l = _heardLine ??= _line('avukat');
    l.text += text;
    if (!_replying) _set(LiveState.thinking);
    notifyListeners();
  }

  void _said(String text) {
    final l = _saidLine ??= _line('ajan');
    l.text += text;
    notifyListeners();
  }

  LiveLine _line(String who) {
    final l = LiveLine(who, '');
    lines.add(l);
    return l;
  }

  void _interrupted() {
    _replying = false;
    unawaited(speaker.clear());
  }

  void _endTurn() {
    _replying = false;
    speaker.finish();
    _heardLine?.text = _heardLine!.text.trim();
    _saidLine?.text = _saidLine!.text.trim();
    _heardLine = _saidLine = null;
  }

  void _turnComplete(LiveSession s) {
    if (isStopCommand(_heardLine?.text ?? '')) {
      _endTurn();
      unawaited(stop());
      return;
    }
    lastTurn = _turn;
    spent = spent + _turn;
    unawaited(_turn.record());
    _turn = const LiveCost();
    _endTurn();
    notifyListeners();
    if (!identical(s, _session)) return;
    if (++_sameSession >= _mostSameSession) {
      lines.add(
        LiveLine(
          'bilgi',
          'Oturum yenilenemedi; maliyet artmasın diye konuşma kapandı.',
        ),
      );
      unawaited(stop());
      return;
    }
    if (_working == 0) unawaited(_renew());
  }

  /// The next question's session, opened while this answer is heard.
  Future<void> _renew() async {
    final old = _session;
    if (_renewing || old == null) return;
    _renewing = true;
    try {
      final opening = _connect();
      final fresh = await opening.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          // Opened late, it is shut: an unused session must not spend.
          unawaited(opening.then((s) => s.close(), onError: (_) {}));
          throw TimeoutException('oturum yenilenemedi');
        },
      );
      if (!identical(_session, old) || !active) {
        await fresh.close();
        return;
      }
      _session = fresh;
      _sameSession = 0;
      for (final p in _waitingSound) {
        fresh.sendAudio(p);
      }
      await old.close();
    } catch (_) {
      // Not renewed: the old session goes on, and what was said meanwhile
      // is not lost.
      if (identical(_session, old) && old.open) {
        for (final p in _waitingSound) {
          old.sendAudio(p);
        }
      }
    } finally {
      _waitingSound.clear();
      _renewing = false;
    }
  }

  void _closed(LiveSession s, String why) {
    if (!identical(s, _session)) return;
    _session = null;
    _endTurn();
    _working = 0;
    if (_handsFree) {
      _gate?.reset();
      _set(LiveState.waiting);
    } else {
      error = why;
      unawaited(stop());
    }
  }

  void _tools(LiveSession s, List<LiveToolCall> calls) {
    final question = lines
        .lastWhere(
          (l) => l.who == 'avukat',
          orElse: () => LiveLine('avukat', ''),
        )
        .text;
    for (final c in calls) {
      _working++;
      steps.add(c.name);
      _set(LiveState.working);
      tools
          .call(c.name, c.args, question: question)
          .then((r) => r, onError: (Object e) => {'hata': '$e'})
          .then((response) {
            _lastActivity = DateTime.now();
            if (identical(_session, s) && s.open) {
              s.answerTools([
                {'id': c.id, 'name': c.name, 'response': response},
              ]);
            }
          })
          .whenComplete(() {
            _working--;
            notifyListeners();
          });
    }
  }

  /// Four times a second: the state shown, and quiet that ends the session.
  @visibleForTesting
  void tick() {
    if (_session == null) return;
    final now = DateTime.now();
    final s = _working > 0
        ? LiveState.working
        : speaker.playing
        ? LiveState.speaking
        : _state == LiveState.thinking &&
              now.difference(_lastActivity).inSeconds < 8
        ? LiveState.thinking
        : LiveState.listening;
    _set(s);
    // Quiet is counted only once the answer has been heard: Live sends the
    // sound long before it has played out.
    if (s != LiveState.listening || _renewing) {
      _lastActivity = now;
      return;
    }
    if (now.difference(_lastActivity) < idle) return;
    final old = _session!;
    _session = null;
    unawaited(old.close());
    _endTurn();
    if (_handsFree) {
      _gate?.reset();
      _set(LiveState.waiting);
    } else {
      unawaited(stop());
    }
  }
}
