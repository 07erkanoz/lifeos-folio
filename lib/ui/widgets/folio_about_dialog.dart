import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../agenda/agenda_page.dart' show AgendaColors;
import '../mobile/settings_parts.dart';
import 'notice.dart';

void showFolioAbout(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const FolioAboutDialog(),
);

/// The terms Folio is used under, read in the app.
const folioTerms = (
  title: 'Kullanım Koşulları',
  asset: 'assets/legal/LICENSE.txt',
);

/// How Folio handles personal data, read in the app; the site carries the
/// same notice.
const folioPrivacy = (
  title: 'Gizlilik ve KVKK Aydınlatma Metni',
  asset: 'assets/legal/PRIVACY.txt',
);

/// Opens one of Folio's legal texts on a page of its own.
Future<void> openFolioLegal(
  BuildContext context,
  ({String title, String asset}) text,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => FolioLegalPage(title: text.title, asset: text.asset),
  ),
);

class FolioAboutDialog extends StatelessWidget {
  const FolioAboutDialog({super.key});

  /// Where else Folio runs, said for the device it is read on: a phone
  /// names the computers only (App Store 2.3.10).
  static String get _otherDevices => Platform.isIOS || Platform.isAndroid
      ? 'Windows, macOS ve Linux'
      : 'Telefon ve bilgisayar sürümleri';

  Future<void> _open(
    BuildContext context,
    String path, [
    String? fragment,
  ]) async {
    try {
      if (await launchUrl(
        Uri(
          scheme: 'https',
          host: 'lifeos.com.tr',
          path: path,
          fragment: fragment,
        ),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {}
    if (context.mounted) {
      showNotice(
        context,
        'Adres açılamadı',
        detail: 'https://lifeos.com.tr$path',
        kind: NoticeKind.error,
      );
    }
  }

  Future<void> _components(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    showLicensePage(
      context: context,
      applicationName: 'LifeOS Folio',
      applicationVersion: info.version,
      applicationLegalese: '© 2026 LifeOS',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = colors.onSurfaceVariant;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      backgroundColor: settingsPage(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  tooltip: 'Kapat',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/branding/lifeos_folio.png',
                    width: 72,
                    height: 72,
                    cacheWidth: (72 * MediaQuery.devicePixelRatioOf(context))
                        .ceil(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'LifeOS Folio',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 2),
              // The version the release was built as, from pubspec.
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, info) => Text(
                  info.hasData
                      ? 'Sürüm ${info.data!.version} (${info.data!.buildNumber})'
                      : ' ',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Avukatlar için dilekçe, dava ve büro uygulaması',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Folio ile UDF dilekçenizi yazar, e-imza ya da mobil imzayla '
                'imzalar ve dava dosyanıza gönderirsiniz. Müvekkillerinizi, '
                'duruşma ve süre takviminizi, büronuzun kasasını ve ekibinizi '
                'aynı uygulamadan yönetirsiniz.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.55, color: muted),
              ),
              const SizedBox(height: 8),
              Text(
                'Verileriniz yalnız sizin cihazlarınızda tutulur. Folio’nun '
                'bir sunucusu yoktur ve yapay zekâ hizmeti kullanmaz.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.55, color: muted),
              ),
              const SettingsSection('SÖZLEŞMELER'),
              SettingsGroup(
                children: [
                  SettingsRow(
                    key: const ValueKey('about-terms'),
                    icon: Icons.description_outlined,
                    title: folioTerms.title,
                    subtitle: 'Kullanım izni ve sorumluluklar',
                    onTap: () => unawaited(openFolioLegal(context, folioTerms)),
                  ),
                  SettingsRow(
                    key: const ValueKey('about-privacy'),
                    icon: Icons.shield_outlined,
                    fill: AgendaColors.eHearingFill,
                    tint: AgendaColors.eHearing,
                    title: folioPrivacy.title,
                    subtitle: 'Kişisel verileriniz nasıl korunur',
                    onTap: () =>
                        unawaited(openFolioLegal(context, folioPrivacy)),
                  ),
                  SettingsRow(
                    key: const ValueKey('about-components'),
                    icon: Icons.layers_outlined,
                    fill: AgendaColors.line,
                    tint: AgendaColors.muted,
                    title: 'Açık kaynak lisansları',
                    subtitle: 'Folio’da kullanılan bileşenler',
                    onTap: () => unawaited(_components(context)),
                  ),
                ],
              ),
              const SettingsSection('DESTEK'),
              SettingsGroup(
                children: [
                  SettingsRow(
                    key: const ValueKey('about-download'),
                    icon: Icons.devices_outlined,
                    fill: AgendaColors.taskFill,
                    tint: AgendaColors.task,
                    title: 'Diğer cihazlarınıza indirin',
                    subtitle: _otherDevices,
                    onTap: () => unawaited(_open(context, '/', 'indir')),
                  ),
                  SettingsRow(
                    key: const ValueKey('about-contact'),
                    icon: Icons.mail_outline_rounded,
                    title: 'Destek ve iletişim',
                    subtitle: 'İletişim formuyla bize yazın',
                    onTap: () => unawaited(_open(context, '/iletisim')),
                  ),
                  SettingsRow(
                    key: const ValueKey('about-site'),
                    icon: Icons.language_rounded,
                    fill: AgendaColors.line,
                    tint: AgendaColors.muted,
                    title: 'lifeos.com.tr',
                    subtitle: 'Folio’nun web sitesi',
                    onTap: () => unawaited(_open(context, '/')),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                '© 2026 LifeOS. Tüm hakları saklıdır.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of Folio's legal texts, its numbered headings set apart.
class FolioLegalPage extends StatelessWidget {
  const FolioLegalPage({super.key, required this.title, required this.asset});

  final String title;
  final String asset;

  static final _heading = RegExp(r'^\d+\. ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: settingsPage(context),
      appBar: settingsBar(context, title),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(asset),
        builder: (context, text) {
          if (!text.hasData) return const SizedBox.shrink();
          // The first line repeats the bar's title.
          final lines = text.data!.trim().split('\n').skip(1);
          return SelectionArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                28 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                for (final line in lines)
                  if (line.trim().isEmpty)
                    const SizedBox(height: 10)
                  else if (_heading.hasMatch(line))
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 4),
                      child: Text(
                        line,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    Text(
                      line,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}
