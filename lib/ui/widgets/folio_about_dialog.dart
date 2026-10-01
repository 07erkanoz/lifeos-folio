import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'notice.dart';

void showFolioAbout(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const FolioAboutDialog(),
);

class FolioAboutDialog extends StatelessWidget {
  const FolioAboutDialog({super.key});

  Future<void> _open(BuildContext context, String domain) async {
    try {
      if (await launchUrl(
        Uri.https(domain),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {}
    if (context.mounted) {
      showNotice(
        context,
        'Adres açılamadı',
        detail: 'https://$domain',
        kind: NoticeKind.error,
      );
    }
  }

  Future<void> _license(BuildContext context) async {
    final text = await rootBundle.loadString('assets/legal/LICENSE.txt');
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ücretsiz kullanım lisansı'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colors.primary.withValues(alpha: .13),
                      colors.secondary.withValues(alpha: .07),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        tooltip: 'Kapat',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(
                        'assets/branding/lifeos_folio.png',
                        width: 88,
                        height: 88,
                        cacheWidth:
                            (88 * MediaQuery.devicePixelRatioOf(context))
                                .ceil(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'LifeOS Folio',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // The version the release was built as, from pubspec.
                    FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, info) => Text(
                        info.hasData
                            ? 'Sürüm ${info.data!.version} (${info.data!.buildNumber})'
                            : ' ',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Belgelerinize sakin bir alan.',
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: .8),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Text(
                        'Ücretsiz kullanım',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    const Text(
                      'Erkan ÖZ tarafından geliştirilmiştir.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Önizleyin, arayın, düzenleyin.\nGünlük belge işleriniz için hızlı ve sade bir çalışma alanı.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final domain in ['lifeos.com.tr', 'erkanoz.com'])
                          OutlinedButton.icon(
                            onPressed: () => _open(context, domain),
                            icon: const Icon(
                              Icons.north_east_rounded,
                              size: 15,
                            ),
                            label: Text(domain),
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const Divider(),
                    const SizedBox(height: 14),
                    Text(
                      'Kişisel ve iş amaçlı kullanım ücretsizdir.\nTelif hakları saklıdır; kullanım lisans koşullarına tabidir.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => _license(context),
                          child: const Text('Kullanım lisansı'),
                        ),
                        TextButton(
                          onPressed: () async {
                            final info = await PackageInfo.fromPlatform();
                            if (!context.mounted) return;
                            showLicensePage(
                              context: context,
                              applicationName: 'LifeOS Folio',
                              applicationVersion: info.version,
                              applicationLegalese: '© 2026 Erkan ÖZ',
                            );
                          },
                          child: const Text('Bileşen lisansları'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
