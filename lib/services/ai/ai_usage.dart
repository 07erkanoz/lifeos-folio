import '../office/office_identity.dart';
import '../portal/portal_database.dart';
import 'ai_assistant.dart';
import 'ai_groq.dart';

/// What the lawyer's API keys spent: the tokens each service counted in
/// its answers, by month, on every own device. Each device keeps its own
/// line a month and service (an AI record, kept alike by Senkron's AI
/// part), so the devices never write over one another; the month's sum is
/// all of them. A limit the lawyer sets stops the services' questions when
/// the month has used it.
abstract final class AiUsage {
  static const kind = 'kullanim';

  static String month([DateTime? at]) {
    final d = at ?? DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}';
  }

  static String? _device;

  static Future<String> _deviceId() async =>
      _device ??= (await OfficeIdentity.load()).deviceId;

  /// [input] and [output] tokens [service] counted for one answer.
  static Future<void> add(
    ApiService service, {
    int input = 0,
    int output = 0,
  }) async {
    if (input <= 0 && output <= 0) return;
    try {
      final db = await PortalDatabase.shared();
      final ay = month();
      final id = '$kind:${await _deviceId()}:$ay:${service.name}';
      final old = db.aiRecord(id) ?? const {};
      int n(Object? v) => v is num ? v.toInt() : 0;
      db.putAiRecord(id, kind, '', {
        'servis': service.name,
        'ay': ay,
        'girdi': n(old['girdi']) + input,
        'cikti': n(old['cikti']) + output,
        'istek': n(old['istek']) + 1,
      });
    } catch (_) {
      // Not counted, never a reason for the answer to fail.
    }
  }

  /// The tokens of [month] (this one when null) on every own device, by
  /// service, and their sum.
  static Future<({int total, Map<String, int> byService})> of([
    String? month,
  ]) async {
    final ay = month ?? AiUsage.month();
    final by = <String, int>{};
    try {
      final db = await PortalDatabase.shared();
      for (final r in db.aiRecords(kind)) {
        if (r['ay'] != ay) continue;
        int n(Object? v) => v is num ? v.toInt() : 0;
        final s = '${r['servis'] ?? ''}';
        by[s] = (by[s] ?? 0) + n(r['girdi']) + n(r['cikti']);
      }
    } catch (_) {}
    return (total: by.values.fold(0, (a, b) => a + b), byService: by);
  }

  /// Stops a question to a service when the month's limit is used.
  static Future<void> checkLimit() async {
    final limit = (await AiSettings.load()).monthlyTokens;
    if (limit == null || limit <= 0) return;
    final used = (await of()).total;
    if (used >= limit) {
      throw AiFailure(
        'Bu ayki yapay zekâ kullanım sınırınız doldu (${shown(used)} / '
        '${shown(limit)} token). Ayarlar › Yapay zekâ’dan sınırı '
        'değiştirebilirsiniz.',
      );
    }
  }

  /// "1,2 milyon", "850 bin", "120".
  static String shown(int tokens) {
    if (tokens >= 1000000) {
      final m = tokens / 1000000;
      return '${m.toStringAsFixed(m >= 10 ? 0 : 1).replaceAll('.', ',')} milyon';
    }
    if (tokens >= 1000) return '${(tokens / 1000).round()} bin';
    return '$tokens';
  }
}
