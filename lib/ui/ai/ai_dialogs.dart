import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/ai/ai_assistant.dart';
import '../../services/ai/ai_login.dart';
import '../../services/editor/lawyer_profile.dart';

/// The consent asked once, before the first document is sent to an AI
/// program, and kept ([AiSettings]); never asked again unless its text
/// changes. True when given.
Future<bool> askAiConsent(BuildContext context) async {
  final settings = await AiSettings.load();
  if (settings.consented) return true;
  if (!context.mounted) return false;
  final given = await showDialog<bool>(
    context: context,
    builder: (_) => const _ConsentDialog(),
  );
  if (given != true) return false;
  String? who;
  try {
    who = (await LawyerProfile.load()).lawyer?.titled;
  } catch (_) {}
  await (await AiSettings.load())
      .copyWith(
        consentVersion: AiSettings.currentConsent,
        consentAt: DateTime.now(),
        consentBy: who,
      )
      .save();
  return true;
}

/// The consent's text, to read again from the settings.
Future<void> showAiConsentText(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _ConsentDialog(readOnly: true),
);

class _ConsentDialog extends StatefulWidget {
  const _ConsentDialog({this.readOnly = false});
  final bool readOnly;
  @override
  State<_ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<_ConsentDialog> {
  bool _read = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const ValueKey('ai-consent'),
      // A short window still shows the buttons.
      scrollable: true,
      title: const Text('Yapay zekâ kullanım onayı'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final point in aiConsentPoints)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Icon(Icons.circle, size: 6, color: scheme.outline),
                    ),
                    Expanded(
                      child: Text(
                        point,
                        style: const TextStyle(fontSize: 13.5, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
            if (!widget.readOnly) ...[
              const SizedBox(height: 6),
              CheckboxListTile(
                key: const ValueKey('ai-consent-read'),
                value: _read,
                onChanged: (v) => setState(() => _read = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Okudum; yukarıdakileri ve Kullanım Koşulları’nın 5. '
                  'maddesini (Yapay zekâ özellikleri) kabul ediyorum.',
                  style: TextStyle(fontSize: 13.5),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: widget.readOnly
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kapat'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                key: const ValueKey('ai-consent-accept'),
                onPressed: _read ? () => Navigator.pop(context, true) : null,
                child: const Text('Kabul ediyorum'),
              ),
            ],
    );
  }
}

/// [provider]'s sign-in, run in Folio's window: the browser is opened at
/// the program's page, a code shown when it gives one. True when the
/// lawyer is signed in.
Future<bool> showAiLogin(BuildContext context, AiProvider provider) async {
  final login = AiLogin(provider);
  unawaited(
    login.start(
      (address) => launchUrl(address, mode: LaunchMode.externalApplication),
    ),
  );
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _LoginDialog(login: login),
  );
  login.dispose();
  return ok == true;
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog({required this.login});
  final AiLogin login;
  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.login.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (widget.login.done == true) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.login.removeListener(_changed);
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final login = widget.login;
    final scheme = Theme.of(context).colorScheme;
    final failed = login.done == false;
    return AlertDialog(
      key: const ValueKey('ai-login'),
      title: Text('${login.provider.label}’da oturum açın'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (failed)
              Text(
                login.error ?? 'Oturum açılamadı.',
                style: TextStyle(color: scheme.error),
              )
            else if (login.address == null)
              const Row(
                children: [
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Giriş sayfası hazırlanıyor…'),
                ],
              )
            else ...[
              Text(
                login.code == null
                    ? 'Tarayıcınızda açılan sayfada '
                          '${login.provider.company} hesabınızla girin ve '
                          'izin verin.'
                    : 'Tarayıcınızda açılan sayfada '
                          '${login.provider.company} hesabınızla girin ve bu '
                          'kodu yazın:',
                style: const TextStyle(height: 1.45),
              ),
              if (login.code case final code?) ...[
                const SizedBox(height: 12),
                Center(
                  child: SelectableText(
                    code,
                    key: const ValueKey('ai-login-code'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 24,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (login.wantsCode) ...[
                const SizedBox(height: 12),
                const Text('Tarayıcının gösterdiği kodu buraya yapıştırın:'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _code,
                        decoration: const InputDecoration(isDense: true),
                        onSubmitted: login.answer,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => login.answer(_code.text),
                      child: const Text('Gönder'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Onayınız bekleniyor…',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (login.address != null && !failed)
          TextButton(
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: login.address!)));
              unawaited(
                launchUrl(
                  Uri.parse(login.address!),
                  mode: LaunchMode.externalApplication,
                ),
              );
            },
            child: const Text('Sayfayı yeniden aç'),
          ),
        TextButton(
          onPressed: () {
            login.cancel();
            Navigator.pop(context, false);
          },
          child: Text(failed ? 'Kapat' : 'Vazgeç'),
        ),
      ],
    );
  }
}

/// Asks before Folio puts its tools on Antigravity's own list, which holds
/// for all of Antigravity's sessions and not only Folio's questions. True
/// when the lawyer agrees.
Future<bool> askAntigravityTools(BuildContext context) async {
  final given = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('ai-agy-tools'),
      scrollable: true,
      title: const Text('Folio’nun araçları Antigravity’ye eklensin mi?'),
      content: const SizedBox(
        width: 480,
        child: Text(
          'Antigravity araçlarını kendi ayar dosyasında tutar ve her soruda '
          'ayrıca araç almaz. Bu yüzden Folio, kanun maddesi ve karar okuma '
          'araçlarını Antigravity’nin ayarlarına ekler. Eklenmezse '
          'Antigravity madde ve karar metnini Folio’dan okuyamaz.\n\n'
          'Bu kayıt Antigravity’nin bütün oturumlarında görünür. Kanun ve '
          'karar araçları yalnız okur. Dosya ve evrak araçları yalnız '
          'Folio’dan sorduğunuz sorularda ve o soruya bağlı dosya için '
          'açılır.\n\n'
          'Kaydı istediğiniz zaman Ayarlar’dan kaldırabilirsiniz. Folio’da '
          'yapay zekâ özelliklerini kapattığınızda kayıt da kaldırılır.',
          style: TextStyle(fontSize: 13.5, height: 1.45),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const ValueKey('ai-agy-tools-accept'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Ekle'),
        ),
      ],
    ),
  );
  return given == true;
}
