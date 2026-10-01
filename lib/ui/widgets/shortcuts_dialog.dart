import 'dart:io';

import 'package:flutter/material.dart';

/// Every key the app answers to, in one place.
///
/// The editor had a list of its own and nothing else did, so the keys that
/// move between documents, open the search or turn a page were there to be
/// found only by guessing.
class ShortcutsDialog extends StatelessWidget {
  const ShortcutsDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const ShortcutsDialog(),
  );

  static const _groups = <(String, List<(String, String)>)>[
    (
      'Gezinme',
      [
        ('Ctrl+K', 'Ara'),
        ('Ctrl+O', 'Dosya aç'),
        ('Ctrl+N', 'Yeni belge'),
        ('Ctrl+Shift+E', 'Önizleme ile düzenleme arasında geç'),
        ('Alt+← / Alt+→', 'Önceki / sonraki belge'),
        ('Esc', 'Geri: tam ekran, düzenleme, önizleme, arama'),
        ('F1 / Ctrl+/', 'Bu pencere'),
      ],
    ),
    (
      'Önizleme — belge, resim, PDF, TIFF',
      [
        ('', 'Tuşlar sayfaya bir kez tıkladıktan sonra çalışır.'),
        ('← / → · PgUp / PgDn · Boşluk', 'Önceki / sonraki sayfa'),
        ('Home / End', 'İlk / son sayfa'),
        ('+ / −', 'Yakınlaştır / uzaklaştır'),
        ('0', 'Sayfayı sığdır'),
        ('R', 'Çeyrek tur döndür'),
        ('Ctrl+F', 'Belgede bul — PDF ve önizlenen UDF/DOCX'),
        ('Ctrl+P', 'Yazdır: önizlemeli, sayfa seçmeli'),
        ('Enter · Shift+Enter', 'Sonraki · önceki eşleşme'),
        ('', 'Sayfa sayacına dokunarak bir sayfa numarasına gidilir.'),
        ('', 'Telefonda sol kenardan kaydırmak geri götürür.'),
      ],
    ),
    (
      'Düzenleme',
      [
        ('Ctrl+S · Ctrl+Shift+S', 'Kaydet · farklı kaydet'),
        ('Ctrl+Z · Ctrl+Y', 'Geri al · yinele'),
        ('Ctrl+B / I / U', 'Kalın / italik / altı çizili'),
        ('Ctrl+F · Ctrl+H', 'Bul · bul ve değiştir'),
        ('Ctrl+P', 'Yazdır'),
        ('Ctrl+L / E / R / J', 'Sola / ortaya / sağa / iki yana yasla'),
        ('Ctrl+Shift+L · Ctrl+Shift+7', 'Madde işaretleri · numaralı liste'),
        ('Ctrl+M · Ctrl+Shift+M', 'Girintiyi artır · azalt'),
        ('Sekme', 'Sonraki sekme durağına git'),
        ('Ctrl+Boşluk', 'Kalıp metin ekle · seçimi kalıba al'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A Mac spells the same key differently, and saying so once at the foot
    // is less noise than writing every line twice.
    final mac = !kIsWebFallback && Platform.isMacOS;
    return AlertDialog(
      title: const Text('Klavye kısayolları'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (heading, rows) in _groups) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 6),
                  child: Text(
                    heading,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ),
                for (final (keys, what) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 168,
                          child: Text(
                            keys,
                            style: const TextStyle(
                              fontSize: 12,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            what,
                            style: TextStyle(
                              fontSize: 12,
                              color: keys.isEmpty
                                  ? scheme.onSurfaceVariant
                                  : scheme.onSurface,
                              fontStyle: keys.isEmpty
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (mac)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    'macOS’ta Ctrl yerine ⌘ kullanılır.',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

/// Reading [Platform] on the web throws, and this dialog is built for every
/// target the app is built for.
const kIsWebFallback = bool.fromEnvironment('dart.library.js_util');
