import 'package:evrak_convert/services/ai/ai_assistant.dart';
import 'package:evrak_convert/services/ai/ai_groq.dart';
import 'package:evrak_convert/services/ai/ai_keys_sync.dart';
import 'package:evrak_convert/services/ai/ai_usage.dart';
import 'package:evrak_convert/services/security/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _Kept extends SecretStore {
  final kept = <String, Map<String, Object?>>{};
  @override
  Future<Map<String, Object?>?> read(String name) async => kept[name];
  @override
  Future<bool> write(String name, Map<String, Object?> value) async {
    kept[name] = {...value};
    return true;
  }
}

// The lawyer's API keys alike on their own devices (Senkron), the later
// given or taken off winning; and what the keys spent a month, with a
// limit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gemini = ApiService.gemini.secret;

  test('a key given on the computer comes to the phone; taken off on '
      'the phone, it goes from the computer', () async {
    final computer = _Kept(), phone = _Kept();
    computer.kept[gemini] = {
      'anahtar': 'AIza-bilgisayar',
      'zaman': '2026-11-13T10:00:00Z',
    };
    expect(
      await ApiKeysSync.merge(
        await ApiKeysSync.export(store: computer),
        store: phone,
      ),
      isTrue,
    );
    expect(phone.kept[gemini]?['anahtar'], 'AIza-bilgisayar');
    // Nothing new: nothing written.
    expect(
      await ApiKeysSync.merge(
        await ApiKeysSync.export(store: computer),
        store: phone,
      ),
      isFalse,
    );
    // Taken off on the phone, later: taken off on the computer too, not
    // brought back from it.
    phone.kept[gemini] = {'anahtar': '', 'zaman': '2026-11-13T11:00:00Z'};
    await ApiKeysSync.merge(
      await ApiKeysSync.export(store: computer),
      store: phone,
    );
    expect(phone.kept[gemini]?['anahtar'], '');
    await ApiKeysSync.merge(
      await ApiKeysSync.export(store: phone),
      store: computer,
    );
    expect(computer.kept[gemini]?['anahtar'], '');
  });

  test(
    'a key kept before keys had a time goes only where there is none',
    () async {
      final old = _Kept(), empty = _Kept(), own = _Kept();
      old.kept[gemini] = {'anahtar': 'AIza-eski'};
      own.kept[gemini] = {'anahtar': 'AIza-kendi'};
      await ApiKeysSync.merge(
        await ApiKeysSync.export(store: old),
        store: empty,
      );
      expect(empty.kept[gemini]?['anahtar'], 'AIza-eski');
      await ApiKeysSync.merge(await ApiKeysSync.export(store: old), store: own);
      expect(own.kept[gemini]?['anahtar'], 'AIza-kendi');
    },
  );

  test('the month limit kept with the settings; tokens said as a lawyer '
      'reads them', () {
    final limited = const AiSettings().copyWith(monthlyTokens: 5000000);
    expect(AiSettings.fromJson(limited.toJson()).monthlyTokens, 5000000);
    expect(
      AiSettings.fromJson(limited.copyWith(noLimit: true).toJson())
          .monthlyTokens,
      isNull,
    );
    expect(AiUsage.shown(1234567), '1,2 milyon');
    expect(AiUsage.shown(20000000), '20 milyon');
    expect(AiUsage.shown(850400), '850 bin');
    expect(AiUsage.month(DateTime(2026, 3, 9)), '2026-03');
  });
}
