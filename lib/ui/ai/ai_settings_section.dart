import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/ai/ai_assistant.dart';
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
    final offered = {
      for (final s in found)
        if (s.installed) s.provider: await AiAssistant.models(s.provider),
    };
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _found = found;
      _store = store;
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

  /// The model [provider] runs for [tier], to choose from what it offers.
  Widget _model(AiProvider provider, AiTier tier) {
    final current = _settings.modelFor(provider, tier);
    final choices = {current, ...?_offered[provider]}.toList();
    return SettingsRow(
      key: ValueKey('ai-model-${provider.name}-${tier.name}'),
      icon: tier == AiTier.strong
          ? Icons.workspace_premium_outlined
          : Icons.bolt_outlined,
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
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            'Belgeleri kendi yapay zekâ aboneliğinizle özetletip '
            'sorabilirsiniz. İstekler bilgisayarınızdaki programdan doğrudan '
            'gider; Folio araya sunucu koymaz.',
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
          for (final s in found) _program(s),
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
      ],
    );
  }
}
