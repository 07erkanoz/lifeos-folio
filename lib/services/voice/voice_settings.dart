import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../ai/ai_assistant.dart';
import '../ai/ai_relay.dart';

/// Folio Ajan's voice, as this computer's lawyer set it: off until they
/// turn it on. Kept on this computer only (a microphone and a loudspeaker
/// are the computer's, not the lawyer's other devices').
class VoiceSettings {
  const VoiceSettings({
    this.on = false,
    this.headphones = false,
    this.voice = '',
    this.codexVoice = '',
    this.codexModel = '',
    this.codexEffort = 'low',
    this.handOn = true,
    this.wake = false,
  });

  /// "Ajan açıl" opens Folio Ajan: listened for on this computer (Vosk),
  /// nothing leaves it.
  final bool wake;

  /// Codex's agent may hand heavy work to Folio's AI program (Claude Code,
  /// as the AI settings say); off, Codex does everything itself.
  final bool handOn;

  /// Codex's voice, model and reasoning; Codex's own when empty.
  final String codexVoice, codexModel, codexEffort;

  final bool on;

  /// Live may be spoken over: nothing comes back through the microphone.
  final bool headphones;

  /// One of Gemini's ready voices; Live's own when empty.
  final String voice;

  static VoiceSettings fromJson(Object? json) => json is Map
      ? VoiceSettings(
          on: json['acik'] == true,
          headphones: json['kulaklik'] == true,
          voice: '${json['ses'] ?? ''}',
          codexVoice: '${json['codex_ses'] ?? ''}',
          codexModel: '${json['codex_model'] ?? ''}',
          codexEffort: '${json['codex_dusunme'] ?? 'low'}',
          handOn: json['agir_isler_programa'] != false,
          wake: json['sesle_ac'] == true,
        )
      : const VoiceSettings();

  Map<String, Object?> toJson() => {
    'acik': on,
    'kulaklik': headphones,
    'ses': voice,
    'codex_ses': codexVoice,
    'codex_model': codexModel,
    'codex_dusunme': codexEffort,
    'agir_isler_programa': handOn,
    'sesle_ac': wake,
  };

  VoiceSettings copyWith({
    bool? on,
    bool? headphones,
    String? voice,
    String? codexVoice,
    String? codexModel,
    String? codexEffort,
    bool? handOn,
    bool? wake,
  }) => VoiceSettings(
    on: on ?? this.on,
    headphones: headphones ?? this.headphones,
    voice: voice ?? this.voice,
    codexVoice: codexVoice ?? this.codexVoice,
    codexModel: codexModel ?? this.codexModel,
    codexEffort: codexEffort ?? this.codexEffort,
    handOn: handOn ?? this.handOn,
    wake: wake ?? this.wake,
  );

  static Future<File> Function() file = () async => File(
    p.join((await getApplicationSupportDirectory()).path, 'ajan_ses.json'),
  );

  static Future<VoiceSettings> load() async {
    try {
      return fromJson(jsonDecode(await (await file()).readAsString()));
    } catch (_) {
      return const VoiceSettings();
    }
  }

  Future<void> save() async {
    final f = await file();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(toJson()), flush: true);
  }
}

/// What Live hands on, asked of the lawyer's AI program with Folio's tools,
/// under the same switches as every other AI feature: off, or with no
/// consent, nothing is asked.
Future<String> askFolio(
  String question, {
  void Function(AiEvent event)? onEvent,
  AiProvider? only,
}) async {
  final settings = await AiSettings.load();
  if (!settings.enabled || !settings.consented) {
    return 'Folio’da yapay zekâ kapalı. Ayarlar › Yapay zekâ’dan açılabilir.';
  }
  final provider = only ?? await AiRelay.usable(settings);
  if (provider == null) return 'Kullanılabilir bir yapay zekâ programı yok.';
  return AiAssistant.ask(
    provider,
    'Bu soru sesli soruldu; cevap sesli özetlenecek. Türkçe, kısa ve '
    'net cevap ver, gereksiz biçimlendirme kullanma.\n\n$question',
    tier: AiTier.normal,
    onEvent: onEvent,
  );
}

/// Claude on this computer, for Folio Ajan's heavy work: Claude Code if it
/// is signed in, else Claude's API with a key; none, neither is.
Future<AiProvider?> usableClaude() async {
  try {
    final usable = {
      for (final s in await AiAssistant.statuses())
        if (s.usable) s.provider,
    };
    return usable.contains(AiProvider.claude)
        ? AiProvider.claude
        : usable.contains(AiProvider.anthropic)
        ? AiProvider.anthropic
        : null;
  } catch (_) {
    return null;
  }
}
