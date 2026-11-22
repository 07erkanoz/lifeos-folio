import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/desktop/desktop_companion.dart';
import '../../services/desktop/global_shortcut.dart';
import '../../services/voice/codex_conversation.dart';
import '../../services/voice/folio_ajan.dart';
import '../../services/voice/voice_settings.dart';
import '../../services/voice/wake_word.dart';
import 'ajan_skins.dart';

class QuickSearchSettings extends StatelessWidget {
  const QuickSearchSettings({super.key});
  Future<void> _record(BuildContext context, DesktopCompanion companion) async {
    FolioShortcut? candidate;
    final selected = await showDialog<FolioShortcut>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Hızlı arama kısayolu'),
          content: Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent) {
                final value = FolioShortcut.fromEvent(event);
                if (value != null) {
                  setState(() => candidate = value);
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ctrl, Alt veya Super ile birlikte bir harf, sayı, Space ya da F1–F12 tuşuna basın.',
                  ),
                  const SizedBox(height: 20),
                  Text(
                    candidate?.label ?? 'Tuş birleşiminizi bekliyorum…',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: candidate == null
                  ? null
                  : () => Navigator.pop(context, candidate),
              child: const Text('Kullan'),
            ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await companion.configure(companion.enabled, binding: selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final companion = CompanionScope.maybeOf(context);
    if (companion == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 28),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Masaüstünde hızlı arama',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Pencereyi kapatınca tepside bekler. Eklenen ve düzenlenen evrakları sessizce indeksler.',
            style: TextStyle(fontSize: 12, height: 1.5),
          ),
          value: companion.enabled,
          onChanged: companion.busy
              ? null
              : (value) => companion.configure(value),
        ),
        if (companion.busy) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: companion.busy
                  ? null
                  : () => companion.usesDesktopShortcutSettings
                        ? companion.configureDesktopShortcut()
                        : _record(context, companion),
              icon: const Icon(Icons.keyboard_rounded, size: 18),
              label: Text('Hızlı arama: ${companion.shortcutLabel}'),
            ),
            // Folio Ajan's own key: the desktop's shortcut settings list it
            // beside the search's (KDE / Wayland).
            if (companion.usesDesktopShortcutSettings &&
                FolioAjan.instance.available)
              Tooltip(
                message:
                    'Folio Ajan’ı doğrudan tam ekran açar. Tuşları masaüstünün '
                    'kısayol ayarlarından değiştirebilirsiniz.',
                child: OutlinedButton.icon(
                  onPressed: companion.busy
                      ? null
                      : companion.configureDesktopShortcut,
                  icon: const Icon(Icons.keyboard_rounded, size: 18),
                  label: Text(
                    'Folio Ajan: ${companion.ajanShortcutLabel.isEmpty ? companion.ajanShortcut.label : companion.ajanShortcutLabel}',
                  ),
                ),
              ),
            TextButton.icon(
              onPressed: companion.busy
                  ? null
                  : () {
                      // Shut the dialog it may sit in; never the page.
                      final route = ModalRoute.of(context);
                      if (route is PopupRoute) Navigator.pop(context);
                      companion.toggleQuick();
                    },
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Hızlı aramayı aç'),
            ),
          ],
        ),
        if (companion.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SelectableText(
              companion.error!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        if (companion.usesDesktopShortcutSettings)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Wayland’da (KDE, GNOME) kısayolları masaüstünün kısayol ayarları belirler; düğmeye basınca orası açılır. Gösterilen tuş birleşimi masaüstünün atadığı kısayoldur. Elle tanımlamak için komutlar: “lifeos_folio --quick-search” ve “lifeos_folio --folio-ajan”.',
              style: TextStyle(fontSize: 11, height: 1.5),
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'Ana ekranla aynı arşivi ve arama seçeneklerini kullanır. Tepsi menüsündeki “Tamamen çık” arka plan çalışmasını da sonlandırır.',
          style: TextStyle(fontSize: 11, height: 1.5),
        ),
      ],
    );
  }
}

/// Folio Ajan's voice: off until the lawyer turns it on. In Ayarlar ›
/// Yapay zekâ, under its own heading (it was under the quick search's,
/// in Belgeler ve arşiv, and not found there: 21 Kasım 2026).
class AjanVoiceSettings extends StatefulWidget {
  const AjanVoiceSettings({super.key});
  @override
  State<AjanVoiceSettings> createState() => _AjanVoiceSettingsState();
}

class _AjanVoiceSettingsState extends State<AjanVoiceSettings> {
  final _ajan = FolioAjan.instance;

  @override
  void initState() {
    super.initState();
    _ajan.loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ajan,
      builder: (context, _) {
        final s = _ajan.settings;
        VoiceSettings copy({bool? on, bool? headphones}) =>
            s.copyWith(on: on, headphones: headphones);
        final codex = identical(_ajan.voice, _ajan.codex);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Folio Ajan’la sesli konuşma',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Folio Ajan tam ekranda düğmesiz dinler; hızlı aramada mikrofonla '
                'sorulur. '
                'Söyledikleriniz ve araçların okuduğu Folio kayıtları seçtiğiniz '
                'ses hizmetine gider.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
              value: s.on,
              onChanged: (v) => _ajan.saveSettings(copy(on: v)),
            ),
            if (s.on)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  codex
                      ? 'Ses: Codex (ChatGPT aboneliğiniz). Ayrıca ücret yok, '
                            'kotadan düşer; veri OpenAI’a gider. Ağır işleri '
                            'Folio’nun yapay zekâ programına (ör. Claude Code) '
                            'verir.'
                      : 'Ses: Gemini Live (API anahtarı, kullandıkça ücretli). '
                            'Codex CLI kurup terminalde `codex login` ile ChatGPT '
                            'hesabınızla giriş yaparsanız ses kendiliğinden '
                            'Codex’e geçer.',
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
            if (s.on && !codex)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Kulaklık kullanıyorum'),
                subtitle: const Text(
                  'Açıkken Ajan konuşurken de sözünü kesebilirsiniz. Hoparlörde '
                  'kapalı tutun; yoksa kendi sesini duyar.',
                  style: TextStyle(fontSize: 12, height: 1.5),
                ),
                value: s.headphones,
                onChanged: (v) => _ajan.saveSettings(copy(headphones: v)),
              ),
            if (s.on) ...[
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sesle aç: “Ajan açıl”'),
                subtitle: const Text(
                  'Folio açıkken “Ajan açıl” deyin: pencere öndeyse küçük ses '
                  'penceresi, tepsideyse Folio Ajan açılır. Bu bilgisayarda '
                  'dinlenir, hiçbir ses dışarı gitmez. İlk açılışta Türkçe ses '
                  'modeli (37 MB) bir kez iner.',
                  style: TextStyle(fontSize: 12, height: 1.5),
                ),
                value: s.wake,
                onChanged: (v) => _ajan.saveSettings(s.copyWith(wake: v)),
              ),
              if (s.wake) const _WakeStatus(),
              const SizedBox(height: 8),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: DropdownButtonFormField<String>(
                key: ValueKey(s.skin),
                initialValue: AjanSkin.of(s.skin).name,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Folio Ajan tam ekran görünümü',
                  helperText:
                      'Tam ekranda üstteki “Görünüm” düğmesiyle de değişir.',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final k in AjanSkin.values)
                    DropdownMenuItem(value: k.name, child: Text(k.label)),
                ],
                onChanged: (v) {
                  if (v != null) _ajan.setSkin(v);
                },
              ),
            ),
            if (s.on && codex) ...[
              const Text(
                'Kulaklık gerekmez: yankı engelleme açık, konuşurken sözünü '
                'kesebilirsiniz. Yarım dakika sessizlikte ya da “kapan” '
                'deyince konuşma kapanır.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 12),
              _CodexChoices(ajan: _ajan),
            ],
          ],
        );
      },
    );
  }
}

/// Codex's voice, model and reasoning, as Codex offers them here.
class _CodexChoices extends StatefulWidget {
  const _CodexChoices({required this.ajan});
  final FolioAjan ajan;

  @override
  State<_CodexChoices> createState() => _CodexChoicesState();
}

class _CodexChoicesState extends State<_CodexChoices> {
  CodexCatalog? _catalog;
  String? _error;
  bool _sampling = false;

  static const _efforts = {
    'low': 'Düşük (hızlı)',
    'medium': 'Orta',
    'high': 'Yüksek',
    'xhigh': 'Çok yüksek',
    'max': 'En yüksek',
    'ultra': 'Ultra',
  };

  @override
  void initState() {
    super.initState();
    widget.ajan.codex.catalog().then(
      (c) {
        if (mounted) setState(() => _catalog = c);
      },
      onError: (Object e) {
        if (mounted) setState(() => _error = '$e');
      },
    );
  }

  Widget _pick(
    String label,
    String value,
    Map<String, String> items,
    ValueChanged<String> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DropdownButtonFormField<String>(
      initialValue: items.containsKey(value) ? value : '',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final MapEntry(:key, :value) in items.entries)
          DropdownMenuItem(value: key, child: Text(value)),
      ],
      onChanged: (v) => onChanged(v ?? ''),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ajan = widget.ajan;
    final s = ajan.settings;
    final c = _catalog;
    if (_error != null) {
      return Text(
        'Codex’in modelleri okunamadı: $_error',
        style: const TextStyle(fontSize: 12, color: Colors.redAccent),
      );
    }
    if (c == null) {
      return const Text(
        'Codex’in sesleri ve modelleri okunuyor…',
        style: TextStyle(fontSize: 12),
      );
    }
    final model =
        c.models.where((m) => m.id == s.codexModel).firstOrNull ??
        c.models.where((m) => m.isDefault).firstOrNull;
    final efforts = model?.efforts ?? const ['low', 'medium', 'high'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _pick('Ses', s.codexVoice, {
                '': 'Codex’in varsayılanı',
                for (final v in c.voices)
                  v: v[0].toUpperCase() + v.substring(1),
              }, (v) => ajan.saveSettings(s.copyWith(codexVoice: v))),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: OutlinedButton.icon(
                onPressed: _sampling || ajan.voice.active
                    ? null
                    : () async {
                        setState(() => _sampling = true);
                        try {
                          await ajan.codex.sample(s.codexVoice);
                        } finally {
                          if (mounted) setState(() => _sampling = false);
                        }
                      },
                icon: _sampling
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.volume_up_outlined, size: 18),
                label: Text(_sampling ? 'Bağlanıyor…' : 'Dinle'),
              ),
            ),
          ],
        ),
        _pick(
          'Model (araçları kullanan ajan)',
          s.codexModel,
          {'': 'Codex’in varsayılanı', for (final m in c.models) m.id: m.name},
          (v) {
            final m = c.models.where((m) => m.id == v).firstOrNull;
            final e = m == null || m.efforts.contains(s.codexEffort)
                ? s.codexEffort
                : (m.efforts.firstOrNull ?? 'low');
            ajan.saveSettings(s.copyWith(codexModel: v, codexEffort: e));
          },
        ),
        if (ajan.claude != null)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('Ağır işleri ${ajan.claude!.label}’a ver'),
            subtitle: const Text(
              'Kısa sorular (ajanda, tebligat, madde) Codex’te kalır; taslak, '
              'uzun inceleme ve emsal araştırması Claude’a gider, cevabı ses '
              'okur. Daha uzun sürer. Kapalıyken her şeyi Codex yapar.',
              style: TextStyle(fontSize: 12, height: 1.5),
            ),
            value: s.handOn,
            onChanged: (v) => ajan.saveSettings(s.copyWith(handOn: v)),
          ),
        _pick(
          'Düşünme',
          efforts.contains(s.codexEffort) ? s.codexEffort : efforts.first,
          {for (final e in efforts) e: _efforts[e] ?? e},
          (v) => ajan.saveSettings(s.copyWith(codexEffort: v)),
        ),
        const Text(
          'Ses adları kadın ya da erkek olduğunu söylemiyor: seçip Dinle’ye '
          'basın (ilk bağlantı yarım dakika sürebilir). Düşünme arttıkça '
          'cevap gecikir ve kota daha çok harcanır; sesli konuşma için '
          'Düşük önerilir.',
          style: TextStyle(fontSize: 12, height: 1.5),
        ),
      ],
    );
  }
}

/// What the wake word is doing, and what it heard last.
class _WakeStatus extends StatelessWidget {
  const _WakeStatus();
  @override
  Widget build(BuildContext context) {
    final wake = WakeWord.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([wake.state, wake.message, wake.lastHeard]),
      builder: (context, _) {
        final state = switch (wake.state.value) {
          WakeState.off => 'Kapalı',
          WakeState.preparing => 'Hazırlanıyor',
          WakeState.listening => 'Dinliyor: “Ajan açıl”',
          WakeState.paused => 'Konuşma sürüyor, bekliyor',
          WakeState.unsupported => 'Desteklenmiyor',
          WakeState.failed => 'Hata',
        };
        final lines = [
          state,
          if (wake.message.value.isNotEmpty) wake.message.value,
          if (wake.lastHeard.value.isNotEmpty)
            'Son duyulan: ${wake.lastHeard.value}',
        ];
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            lines.join('\n'),
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: wake.state.value == WakeState.failed
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}
