import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/ai/ai_assistant.dart';
import '../../services/ai/ai_groq.dart';
import '../mobile/settings_parts.dart';
import 'ai_dialogs.dart';

/// Ayarlar › Yapay zekâ: the consent given once and its record, the AI
/// programs found on this computer with a way to sign in or install each,
/// the one used, and whether identity numbers are hidden.
class AiSettingsSection extends StatefulWidget {
  const AiSettingsSection({super.key});
  @override
  State<AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends State<AiSettingsSection> {
  AiSettings _settings = const AiSettings();
  List<AiStatus>? _found;
  bool _store = false;

  /// Whether Folio is on Antigravity's own list of tools.
  bool _agyTools = false;

  /// The models each installed program offers.
  final _offered = <AiProvider, List<String>>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final settings = await AiSettings.load();
    final found = await AiAssistant.statuses();
    final store = AiAssistant.hasStore;
    final agyTools = await AiAssistant.antigravityFolio() != null;
    final offered = {
      for (final s in found)
        if (s.installed) s.provider: await AiAssistant.models(s.provider),
    };
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _found = found;
      _store = store;
      _agyTools = agyTools;
      _offered
        ..clear()
        ..addAll(offered);
    });
  }

  Future<void> _save(AiSettings settings) async {
    setState(() => _settings = settings);
    await settings.save();
  }

  static String _when(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
  }

  Widget _program(AiStatus s) {
    final chosen = (_settings.provider ?? _firstUsable) == s.provider;
    final String subtitle;
    final Widget trailing;
    if (s.provider.viaApi) {
      return _groq(s, chosen);
    }
    if (!s.installed) {
      subtitle = 'Kurulu değil';
      trailing = OutlinedButton(
        onPressed: () => _store
            ? unawaited(AiAssistant.openStore(s.provider))
            : unawaited(
                launchUrl(
                  Uri.parse(s.provider.installPage),
                  mode: LaunchMode.externalApplication,
                ),
              ),
        child: Text(_store ? 'Mağaza’da kur' : 'Nasıl kurulur?'),
      );
    } else if (s.signedIn == false) {
      subtitle = 'Kurulu · oturum açılmamış';
      trailing = s.provider.signsInFromFolio
          ? OutlinedButton(
              key: ValueKey('ai-login-${s.provider.name}'),
              onPressed: () async {
                await showAiLogin(context, s.provider);
                await _load();
              },
              child: const Text('Oturum aç'),
            )
          : const SizedBox.shrink();
    } else {
      subtitle = switch (s) {
        AiStatus(account: final a?) => 'Oturum açık · $a',
        AiStatus(signedIn: true) => 'Oturum açık',
        _ =>
          'Kurulu · oturumu ilk soruda denetlenir; açık değilse '
              'Antigravity’yi bir kez kendi penceresinde açıp girin',
      };
      trailing = chosen
          ? const Chip(label: Text('Kullanılıyor'))
          : TextButton(
              onPressed: () => _save(_settings.copyWith(provider: s.provider)),
              child: const Text('Bunu kullan'),
            );
    }
    return SettingsRow(
      key: ValueKey('ai-provider-${s.provider.name}'),
      icon: Icons.smart_toy_outlined,
      title: s.provider.label,
      subtitle: subtitle,
      status: s.usable ? const Color(0xFF157A52) : Colors.grey,
      trailing: trailing,
    );
  }

  /// Groq: no program, the lawyer's own API key, kept in the system's
  /// keyring.
  Widget _groq(AiStatus s, bool chosen) => SettingsRow(
    key: ValueKey('ai-provider-${s.provider.name}'),
    icon: Icons.key_outlined,
    title: s.provider.label,
    subtitle: s.installed
        ? 'Anahtar girildi · Folio Groq’a kendisi sorar, araçları ve '
              'denetimiyle'
        : 'Groq hesabınızdan aldığınız API anahtarıyla. Program kurmak '
              'gerekmez.',
    status: s.usable ? const Color(0xFF157A52) : Colors.grey,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (s.installed && chosen)
          const Chip(label: Text('Kullanılıyor'))
        else if (s.installed)
          TextButton(
            onPressed: () => _save(_settings.copyWith(provider: s.provider)),
            child: const Text('Bunu kullan'),
          ),
        TextButton(
          key: const ValueKey('ai-groq-key'),
          onPressed: () async {
            if (s.installed) {
              await GroqChat.removeKey();
            } else if (!await _askGroqKey()) {
              return;
            }
            await _load();
          },
          child: Text(s.installed ? 'Anahtarı kaldır' : 'Anahtar gir'),
        ),
      ],
    ),
  );

  /// The key asked of the lawyer, checked with Groq, then kept.
  Future<bool> _askGroqKey() async {
    final field = TextEditingController();
    String? said;
    var checking = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Groq API anahtarı'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Anahtarı Groq hesabınızın API Keys sayfasından alın. '
                  'Folio anahtarı bu bilgisayarın anahtar deposunda saklar; '
                  'sorular bu bilgisayardan doğrudan Groq’a gider. Ücretsiz '
                  'katmanın dakikalık sınırı tek bir hukuk sorusuna yetmez; '
                  'ücretli katman gerekir.',
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => unawaited(
                    launchUrl(
                      Uri.parse(GroqChat.keysPage),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Anahtar sayfasını aç'),
                ),
                TextField(
                  key: const ValueKey('ai-groq-key-field'),
                  controller: field,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'API anahtarı',
                    hintText: 'gsk_…',
                    errorText: said,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: checking
                  ? null
                  : () async {
                      final key = field.text.trim();
                      if (key.isEmpty) return;
                      setDialog(() {
                        checking = true;
                        said = null;
                      });
                      var wrong = await GroqChat.checkKey(key);
                      if (wrong == null && !await GroqChat.saveKey(key)) {
                        wrong =
                            'Bu bilgisayarda anahtar deposu yok; anahtar '
                            'güvenle saklanamadı.';
                      }
                      if (!context.mounted) return;
                      if (wrong == null) {
                        Navigator.pop(context, true);
                        return;
                      }
                      setDialog(() {
                        checking = false;
                        said = wrong;
                      });
                    },
              child: Text(checking ? 'Denetleniyor…' : 'Kaydet'),
            ),
          ],
        ),
      ),
    );
    field.dispose();
    return saved == true;
  }

  /// Folio's tools on Antigravity's own list, put there or taken off at the
  /// lawyer's word.
  Widget _antigravityTools() => SettingsRow(
    key: const ValueKey('ai-agy-tools-row'),
    icon: Icons.menu_book_outlined,
    title: 'Antigravity’de Folio’nun araçları',
    subtitle: _agyTools
        ? 'Eklendi. Antigravity kanun maddesini ve kararı Folio’dan okur.'
        : 'Eklenmedi. Antigravity kanun maddesini ve kararı Folio’dan '
              'okuyamaz.',
    status: _agyTools ? const Color(0xFF157A52) : Colors.grey,
    trailing: TextButton(
      key: const ValueKey('ai-agy-tools-toggle'),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          if (_agyTools) {
            await AiAssistant.removeFromAntigravity();
          } else {
            if (!await askAntigravityTools(context)) return;
            await AiAssistant.addToAntigravity();
          }
        } on AiFailure catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(e.message)));
        }
        await _load();
      },
      child: Text(_agyTools ? 'Kaldır' : 'Ekle'),
    ),
  );

  /// The switch for every AI feature. Turned off, nothing of them is shown
  /// and Folio comes off Antigravity's list of tools.
  Widget _main() => SettingsRow(
    key: const ValueKey('ai-enabled'),
    icon: Icons.auto_awesome_outlined,
    title: 'Yapay zekâ özelliklerini kullan',
    subtitle: _settings.enabled
        ? 'Açık. Belge önizlemesinde yapay zekâ düğmesi görünür.'
        : 'Kapalı. Folio’da yapay zekâyla ilgili hiçbir düğme ya da '
              'pencere görünmez.',
    trailing: settingsSwitch(_settings.enabled, (v) async {
      await _save(_settings.copyWith(enabled: v));
      if (!v && _agyTools) {
        try {
          await AiAssistant.removeFromAntigravity();
        } catch (_) {}
        await _load();
      }
    }),
  );

  /// The model [provider] runs for [tier], to choose from what it offers.
  Widget _model(AiProvider provider, AiTier tier) {
    final current = _settings.modelFor(provider, tier);
    final choices = {current, ...?_offered[provider]}.toList();
    return SettingsRow(
      key: ValueKey('ai-model-${provider.name}-${tier.name}'),
      icon: switch (tier) {
        AiTier.strong => Icons.workspace_premium_outlined,
        AiTier.normal => Icons.bolt_outlined,
        AiTier.light => Icons.speed_outlined,
      },
      title: '${provider.label} · ${tier.label}',
      subtitle: tier.detail,
      trailing: DropdownButton<String>(
        value: current,
        isDense: true,
        underline: const SizedBox.shrink(),
        items: [
          for (final m in choices) DropdownMenuItem(value: m, child: Text(m)),
        ],
        onChanged: (m) {
          if (m == null) return;
          final models = Map<String, String>.of(_settings.models);
          final key = '${provider.name}.${tier.name}';
          if (m == provider.defaultModel(tier)) {
            models.remove(key);
          } else {
            models[key] = m;
          }
          unawaited(_save(_settings.copyWith(models: models)));
        },
      ),
    );
  }

  AiProvider? get _firstUsable {
    for (final s in _found ?? const <AiStatus>[]) {
      if (s.usable) return s.provider;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_main(), if (_settings.enabled) ..._features(found)],
    );
  }

  List<Widget> _features(List<AiStatus>? found) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        'Bilgisayarınızda kurulu Claude, Codex ya da Antigravity ile kendi '
        'aboneliğinizle, ya da kendi API anahtarınızla Groq’la soru '
        'sorarsınız: kenar çubuğundaki Yapay zekâ '
        'sayfasından, belge önizlemesinden ve dosyaların Yapay zekâ '
        'sekmesinden. İstekler bu bilgisayardaki programdan doğrudan gider; '
        'Folio araya sunucu koymaz. Telefonunuzdan sorduğunuz soruları da bu '
        'bilgisayar cevaplar.',
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
    if (found == null)
      const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      )
    else
      for (final s in found) ...[
        _program(s),
        if (s.provider == AiProvider.antigravity && s.installed)
          _antigravityTools(),
      ],
    if (found != null)
      for (final s in found)
        if (s.installed)
          for (final tier in AiTier.values) _model(s.provider, tier),
    SettingsRow(
      key: const ValueKey('ai-mask'),
      icon: Icons.shield_outlined,
      title: 'Göndermeden önce TC kimlik numaralarını gizle',
      subtitle: _settings.mask
          ? 'Belgedeki geçerli TC kimlik numaraları yıldızla gönderilir.'
          : 'Belge olduğu gibi gönderilir.',
      trailing: settingsSwitch(
        _settings.mask,
        (v) => _save(_settings.copyWith(mask: v)),
      ),
    ),
    SettingsRow(
      key: const ValueKey('ai-consent-row'),
      icon: Icons.verified_user_outlined,
      title: _settings.consented
          ? 'Kullanım onayı verildi'
          : 'Kullanım onayı verilmedi',
      subtitle: _settings.consented
          ? [
              if (_settings.consentAt case final at?) _when(at),
              ?_settings.consentBy,
              'onay metni sürüm ${_settings.consentVersion}',
            ].join(' · ')
          : 'İlk belgeyi gönderirken bir kez sorulur.',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => showAiConsentText(context),
            child: const Text('Metni göster'),
          ),
          if (_settings.consented)
            TextButton(
              key: const ValueKey('ai-consent-revoke'),
              onPressed: () => _save(_settings.copyWith(revoke: true)),
              child: const Text('Onayı geri al'),
            ),
        ],
      ),
    ),
  ];
}
