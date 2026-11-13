import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/ai/ai_assistant.dart';
import '../../services/ai/ai_usage.dart';
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
    final used = await AiUsage.of();
    if (!mounted) return;
    setState(() {
      _used = used.total;
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
      return _api(s, chosen);
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

  /// What the lawyer reads before giving a service's key: where to get
  /// one, and what the service does with what is sent.
  static String _note(ApiService a) => switch (a) {
    ApiService.groq =>
      'Anahtarı Groq hesabınızın API Keys sayfasından alın. Ücretsiz '
          'katmanın dakikalık sınırı tek bir hukuk sorusuna yetmez; ücretli '
          'katman gerekir.',
    ApiService.gemini =>
      'Anahtarı Google AI Studio’dan alın (Get API key). Varsayılan model '
          'Gemini 3.8 Flash; Normal düzeyde orta, Güçlü düzeyde yüksek '
          'düşünmeyle çalışır. Faturalandırması açık (ücretli) bir hesapta '
          'Google, gönderdiğiniz metni ve cevapları ürünlerini ya da '
          'modellerini geliştirmek için kullanmaz; yalnız kötüye kullanımı '
          'denetlemek için kısa süre kayıt tutar. Ücretsiz katmanda ise '
          'veriler model geliştirmede kullanılabilir ve insanlar tarafından '
          'okunabilir: müvekkil evrakı için ücretli katmanı kullanın.',
    ApiService.openai =>
      'Anahtarı OpenAI hesabınızın API keys sayfasından alın. API ile '
          'gönderilen veriler, siz izin vermedikçe OpenAI’ın modellerini '
          'eğitmek için kullanılmaz.',
    ApiService.anthropic =>
      'Anahtarı Claude Console’dan (API Keys) alın. Güçlü düzeyde Claude '
          'Opus 5.5, Normal’de Sonnet 5.5, Hafif’te Haiku 5.5 çalışır. API '
          'ile gönderilen veriler, siz izin vermedikçe Anthropic’in '
          'modellerini eğitmek için kullanılmaz.',
  };

  /// A service's API: no program, the lawyer's own key, kept in the
  /// system's keyring.
  Widget _api(AiStatus s, bool chosen) => SettingsRow(
    key: ValueKey('ai-provider-${s.provider.name}'),
    stackOnNarrow: true,
    icon: Icons.key_outlined,
    title: s.provider.label,
    subtitle: s.installed
        ? 'Anahtar girildi · Folio ${ApiService.of(s.provider)!.label}’a '
              'kendisi sorar, araçları ve denetimiyle'
        : '${s.provider.company} hesabınızdan aldığınız API anahtarıyla. '
              'Program kurmak gerekmez.',
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
          key: ValueKey('ai-${s.provider.name}-key'),
          onPressed: () async {
            final api = ApiService.of(s.provider)!;
            if (s.installed) {
              await GroqChat.removeKey(api);
            } else if (!await _askKey(api)) {
              return;
            }
            await _load();
          },
          child: Text(s.installed ? 'Anahtarı kaldır' : 'Anahtar gir'),
        ),
      ],
    ),
  );

  /// The key asked of the lawyer, checked with the service, then kept.
  Future<bool> _askKey(ApiService api) async {
    final field = TextEditingController();
    String? said;
    var checking = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('${api.label} API anahtarı'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_note(api)} Folio anahtarı bu '
                  '${AiAssistant.phone ? 'cihazın' : 'bilgisayarın'} anahtar '
                  'deposunda saklar; sorular bu '
                  '${AiAssistant.phone ? 'cihazdan' : 'bilgisayardan'} doğrudan '
                  '${api.label}’a gider.',
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => unawaited(
                    launchUrl(
                      Uri.parse(api.keysPage),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Anahtar sayfasını aç'),
                ),
                TextField(
                  key: ValueKey('ai-${api.name}-key-field'),
                  controller: field,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'API anahtarı',
                    hintText: switch (api) {
                      ApiService.groq => 'gsk_…',
                      ApiService.gemini => 'AIza…',
                      ApiService.openai => 'sk-…',
                      ApiService.anthropic => 'sk-ant-…',
                    },
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
                      var wrong = await GroqChat.checkKey(key, api);
                      if (wrong == null && !await GroqChat.saveKey(key, api)) {
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
        ? AiAssistant.phone
              ? 'Açık. Yapay zekâ sayfası ve dosyaların Yapay zekâ sekmesi '
                    'görünür.'
              : 'Açık. Belge önizlemesinde yapay zekâ düğmesi görünür.'
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

  /// This month's tokens on every own device, and the month's limit.
  int _used = 0;

  static const _limits = [1000000, 5000000, 20000000, 100000000];

  Widget _usage() => SettingsRow(
    key: const ValueKey('ai-usage'),
    icon: Icons.data_usage_rounded,
    title: 'Bu ayki kullanım: ${AiUsage.shown(_used)} token',
    subtitle: _settings.monthlyTokens == null
        ? 'API anahtarlarınızla bütün cihazlarınızda. Sınır yok.'
        : 'API anahtarlarınızla bütün cihazlarınızda. Sınıra ulaşınca bu ay '
              'soru gönderilmez.',
    stackOnNarrow: true,
    trailing: DropdownButton<int>(
      key: const ValueKey('ai-usage-limit'),
      value: _settings.monthlyTokens ?? 0,
      underline: const SizedBox.shrink(),
      items: [
        const DropdownMenuItem(value: 0, child: Text('Sınır yok')),
        for (final l in {..._limits, ?_settings.monthlyTokens})
          if (l > 0)
            DropdownMenuItem(value: l, child: Text('Ayda ${AiUsage.shown(l)}')),
      ],
      onChanged: (v) => unawaited(
        _save(
          v == null || v == 0
              ? _settings.copyWith(noLimit: true)
              : _settings.copyWith(monthlyTokens: v),
        ),
      ),
    ),
  );

  List<Widget> _features(List<AiStatus>? found) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        aiIntroText(),
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
    if (found != null && found.any((s) => s.provider.viaApi && s.installed))
      _usage(),
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
      stackOnNarrow: true,
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

/// What the AI settings say first: the programs where they run (Linux),
/// the services' APIs everywhere.
String aiIntroText({bool programs = false}) => AiAssistant.phone
    ? [
        'Kendi API anahtarınızla Gemini, ChatGPT ya da Claude’la bu '
            'telefondan doğrudan soru sorarsınız.',
        'Yapay zekâ sayfasından ve dosyaların Yapay zekâ sekmesinden '
            'kullanılır. İstekler telefondan doğrudan sağlayıcıya gider; '
            'Folio araya sunucu koymaz.',
        'Anahtar girmezseniz sorularınızı bilgisayarınızdaki Folio, '
            'açıldığında cevaplar.',
      ].join(' ')
    : [
        if (programs || Platform.isLinux)
          'Bilgisayarınızda kurulu Claude, Codex ya da Antigravity ile kendi '
              'aboneliğinizle, ya da kendi API anahtarınızla Gemini, ChatGPT, '
              'Claude ya da Groq’la soru sorarsınız.'
        else
          'Kendi API anahtarınızla Gemini, ChatGPT, Claude ya da Groq’la soru '
              'sorarsınız; program kurmanız gerekmez.',
        'Kenar çubuğundaki Yapay zekâ sayfasından, belge önizlemesinden, '
            'dosyaların Yapay zekâ sekmesinden ve UETS tebligatlarından süre ile '
            'yapılacak iş çıkarırken kullanılır. İstekler bu bilgisayardan '
            'doğrudan sağlayıcıya gider; Folio araya sunucu koymaz.',
        if (programs || Platform.isLinux)
          'Telefonunuzdan sorduğunuz soruları da bu bilgisayar cevaplar.',
      ].join(' ');
