import '../ai/ai_groq.dart';
import '../ai/ai_usage.dart';

/// What one Live turn cost, from its `usageMetadata` (Google's prices for
/// gemini-3.8-live, dollars a million tokens). Live re-bills the whole
/// context every turn, so a turn's input is all that came before it too.
class LiveCost {
  const LiveCost({
    this.textIn = 0,
    this.audioIn = 0,
    this.textOut = 0,
    this.audioOut = 0,
  });

  static const textInPrice = 0.75,
      audioInPrice = 3.0,
      textOutPrice = 4.5,
      audioOutPrice = 12.0;

  final int textIn, audioIn, textOut, audioOut;

  int get input => textIn + audioIn;
  int get output => textOut + audioOut;

  double get dollars =>
      (textIn * textInPrice +
          audioIn * audioInPrice +
          textOut * textOutPrice +
          audioOut * audioOutPrice) /
      1e6;

  static int _of(Object? details, String modality) {
    var n = 0;
    for (final d in (details as List? ?? const []).whereType<Map>()) {
      if ('${d['modality']}'.toUpperCase() == modality) {
        n += (d['tokenCount'] as num?)?.toInt() ?? 0;
      }
    }
    return n;
  }

  static LiveCost of(Map usage) {
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    final input = n(usage['promptTokenCount']);
    // Thinking is billed as text output.
    final output =
        n(usage['responseTokenCount']) + n(usage['thoughtsTokenCount']);
    final audioIn = _of(usage['promptTokensDetails'], 'AUDIO');
    final audioOut = usage['responseTokensDetails'] == null
        ? n(usage['responseTokenCount'])
        : _of(usage['responseTokensDetails'], 'AUDIO');
    return LiveCost(
      textIn: input - audioIn,
      audioIn: audioIn,
      textOut: output - audioOut,
      audioOut: audioOut,
    );
  }

  LiveCost operator +(LiveCost o) => LiveCost(
    textIn: textIn + o.textIn,
    audioIn: audioIn + o.audioIn,
    textOut: textOut + o.textOut,
    audioOut: audioOut + o.audioOut,
  );

  /// Counted against the lawyer's monthly limit with the Gemini key's other
  /// answers.
  Future<void> record() =>
      AiUsage.add(ApiService.gemini, input: input, output: output);
}
