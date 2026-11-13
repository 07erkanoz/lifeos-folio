import '../security/secret_store.dart';
import 'ai_assistant.dart';
import 'ai_groq.dart';

/// The lawyer's API keys kept alike on their own devices: given on one,
/// taken off on one, so on all (Senkron's part, over the channel only
/// their own devices open). Each key is kept with when it was given or
/// taken off, and the later wins. A key from before that time was kept is
/// taken where the other device has none.
abstract final class ApiKeysSync {
  static Future<Map<String, Object?>> export({SecretStore? store}) async {
    final safe = store ?? SecretStore();
    return {
      for (final s in ApiService.values)
        if (await safe.read(s.secret) case final kept?)
          s.name: {
            'anahtar': '${kept['anahtar'] ?? ''}',
            'zaman': '${kept['zaman'] ?? ''}',
          },
    };
  }

  /// Another own device's [export]; true when a key here changed.
  static Future<bool> merge(Object? theirs, {SecretStore? store}) async {
    if (theirs is! Map) return false;
    final safe = store ?? SecretStore();
    var changed = false;
    for (final s in ApiService.values) {
      final their = theirs[s.name];
      if (their is! Map) continue;
      final key = '${their['anahtar'] ?? ''}'.trim();
      final at = '${their['zaman'] ?? ''}';
      final mine = await safe.read(s.secret);
      final mineKey = '${mine?['anahtar'] ?? ''}'.trim();
      final mineAt = '${mine?['zaman'] ?? ''}';
      final newer = at.isNotEmpty && at.compareTo(mineAt) > 0;
      // A key kept before keys had a time: given where there is none.
      final fills = at.isEmpty && mine == null && key.isNotEmpty;
      if (!(newer || fills) || (key == mineKey && at == mineAt)) continue;
      if (!await safe.write(s.secret, {'anahtar': key, 'zaman': at})) {
        continue;
      }
      GroqChat.forgetKey(s);
      changed = true;
    }
    if (changed) await AiAssistant.lookForPhoneKey();
    return changed;
  }
}
