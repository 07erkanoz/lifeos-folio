import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/security/app_lock.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../mobile/settings_parts.dart';

/// Ayarlar › Güvenlik: Folio's sign-in password, its idle lock and its
/// recovery code.
class SecuritySettings extends StatelessWidget {
  const SecuritySettings({super.key, this.lock});
  final AppLock? lock;

  AppLock get _lock => lock ?? AppLock.instance;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _lock,
    builder: (context, _) {
      final on = _lock.enabled;
      final idle = _lock.idleMinutes;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsRow(
            key: const ValueKey('settings-lock'),
            icon: Icons.lock_outline_rounded,
            title: 'Giriş şifresi',
            subtitle: on
                ? idle == 0
                      ? 'Açık · Folio açılışta kilitlenir'
                      : 'Açık · Folio açılışta ve $idle dakika kullanılmayınca kilitlenir'
                : 'Kapalı · Folio şifre sormadan açılır',
            trailing: Switch(
              key: const ValueKey('settings-lock-switch'),
              value: on,
              onChanged: (v) =>
                  unawaited(v ? _turnOn(context) : _turnOff(context)),
            ),
          ),
          if (on) ...[
            SettingsRow(
              icon: Icons.timer_outlined,
              title: 'Otomatik kilit',
              subtitle: 'Bu kadar süre kullanılmayınca kilit ekranı açılır',
              trailing: DropdownButton<int>(
                key: const ValueKey('settings-lock-idle'),
                value: const [5, 15, 30, 60, 0].contains(idle) ? idle : 15,
                underline: const SizedBox.shrink(),
                onChanged: (v) => v == null ? null : _lock.setIdleMinutes(v),
                items: const [
                  DropdownMenuItem(value: 5, child: Text('5 dakika')),
                  DropdownMenuItem(value: 15, child: Text('15 dakika')),
                  DropdownMenuItem(value: 30, child: Text('30 dakika')),
                  DropdownMenuItem(value: 60, child: Text('1 saat')),
                  DropdownMenuItem(value: 0, child: Text('Yalnız açılışta')),
                ],
              ),
            ),
            SettingsRow(
              key: const ValueKey('settings-lock-change'),
              icon: Icons.password_rounded,
              title: 'Şifreyi değiştir',
              onTap: () => unawaited(_change(context)),
            ),
            SettingsRow(
              key: const ValueKey('settings-lock-code'),
              icon: Icons.key_outlined,
              title: 'Yeni kurtarma kodu',
              subtitle: 'Eski kod geçersiz olur',
              onTap: () => unawaited(_newCode(context)),
            ),
            SettingsRow(
              key: const ValueKey('settings-lock-now'),
              icon: Icons.screen_lock_portrait_outlined,
              title: 'Şimdi kilitle',
              onTap: _lock.lockNow,
            ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Text(
              'Şifre Folio’nun açılmasını korur; bilgisayardaki dosyaları '
              'şifrelemez. Bilgisayarınızın disk şifrelemesini (Windows’ta '
              'BitLocker, Mac’te FileVault, Linux’ta LUKS) de açık tutun. '
              'Kurtarma kodunu kaybeder ve şifreyi unutursanız şifre '
              'sıfırlanamaz.',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
          ),
        ],
      );
    },
  );

  Future<void> _turnOn(BuildContext context) async {
    final words = await _ask(
      context,
      'Giriş şifresi belirleyin',
      ['Şifre', 'Şifre (yeniden)'],
      check: (v) =>
          AppLock.weakness(v[0]) ??
          (v[0] != v[1] ? 'İki şifre aynı değil.' : null),
    );
    if (words == null || !context.mounted) return;
    final code = await _lock.setPassword(words[0]);
    if (context.mounted) await _showCode(context, code);
  }

  Future<void> _turnOff(BuildContext context) async {
    final words = await _ask(context, 'Giriş şifresini kapat', ['Şifre']);
    if (words == null) return;
    if (!await _lock.disable(words[0]) && context.mounted) {
      _say(context, 'Şifre yanlış; giriş şifresi açık kaldı.');
    }
  }

  Future<void> _change(BuildContext context) async {
    final words = await _ask(
      context,
      'Şifreyi değiştir',
      ['Şimdiki şifre', 'Yeni şifre', 'Yeni şifre (yeniden)'],
      check: (v) =>
          AppLock.weakness(v[1]) ??
          (v[1] != v[2] ? 'İki yeni şifre aynı değil.' : null),
    );
    if (words == null) return;
    if (!await _lock.checkPassword(words[0])) {
      if (context.mounted) _say(context, 'Şimdiki şifre yanlış.');
      return;
    }
    final code = await _lock.setPassword(words[1]);
    if (context.mounted) await _showCode(context, code);
  }

  Future<void> _newCode(BuildContext context) async {
    final words = await _ask(context, 'Yeni kurtarma kodu', ['Şifre']);
    if (words == null) return;
    if (!await _lock.checkPassword(words[0])) {
      if (context.mounted) _say(context, 'Şifre yanlış.');
      return;
    }
    final code = await _lock.setPassword(words[0]);
    if (context.mounted) await _showCode(context, code);
  }

  void _say(BuildContext context, String text) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));

  /// Asks for passwords; null when given up.
  static Future<List<String>?> _ask(
    BuildContext context,
    String title,
    List<String> labels, {
    String? Function(List<String> values)? check,
  }) {
    final fields = [for (final _ in labels) TextEditingController()];
    String? error;
    return showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) {
          void done() {
            final values = [for (final f in fields) f.text];
            final why = check?.call(values);
            if (why != null) return set(() => error = why);
            Navigator.pop(context, values);
          }

          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, label) in labels.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        key: ValueKey('lock-field-$i'),
                        controller: fields[i],
                        obscureText: true,
                        autofocus: i == 0,
                        decoration: InputDecoration(labelText: label),
                        onSubmitted: (_) => done(),
                      ),
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                key: const ValueKey('lock-field-ok'),
                onPressed: done,
                child: const Text('Tamam'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Shows the recovery code once; it is asked to be written down.
  static Future<void> _showCode(BuildContext context, String code) {
    var written = false;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Kurtarma kodunuz'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Şifrenizi unutursanız Folio’yu bu kodla açar ve yeni şifre '
                  'koyarsınız. Kod bir daha gösterilmez; kâğıda yazın ya da '
                  'parola yöneticinize kaydedin.',
                ),
                const SizedBox(height: 14),
                Container(
                  key: const ValueKey('lock-shown-code'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    code,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(text: code)),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Kopyala'),
                ),
                CheckboxListTile(
                  key: const ValueKey('lock-written'),
                  contentPadding: EdgeInsets.zero,
                  value: written,
                  onChanged: (v) => set(() => written = v ?? false),
                  title: const Text('Kurtarma kodunu güvenli bir yere yazdım'),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              key: const ValueKey('lock-code-done'),
              onPressed: written ? () => Navigator.pop(context) : null,
              child: const Text('Tamam'),
            ),
          ],
        ),
      ),
    );
  }
}
