import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/desktop/desktop_companion.dart';
import '../../services/desktop/global_shortcut.dart';

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
              label: Text(companion.shortcutLabel),
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
              'GNOME / Wayland’da kısayolu masaüstünün izin ekranı belirler. Gösterilen tuş birleşimi masaüstünün atadığı kısayoldur.',
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
