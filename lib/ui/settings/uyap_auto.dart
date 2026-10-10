import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/portal/portal_sync.dart';
import '../mobile/settings_parts.dart';

/// Ayarlar › Bağlantılar: whether Folio reads UYAP of itself, turned on
/// only after the lawyer has read what it means, with a page on how Folio
/// reaches UYAP at all.
class UyapAutoRow extends StatelessWidget {
  const UyapAutoRow({super.key, required this.sync});

  final PortalSync sync;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sync,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRow(
          key: const ValueKey('settings-uyap-auto'),
          icon: Icons.sync_rounded,
          title: 'UYAP verilerini kendiliğinden al',
          subtitle: sync.autoFetch
              ? 'Açık. Bildirimler saatte bir, duruşmalar günde bir, dosya '
                    'listeniz haftada bir alınır.'
              : 'Kapalı. Folio UYAP’a yalnız siz bir şey yaptığınızda, bir '
                    'tarayıcı gibi sorar.',
          trailing: settingsSwitch(sync.autoFetch, (on) async {
            if (on && !await askUyapAuto(context)) return;
            await sync.setAutoFetch(on);
          }, key: const ValueKey('settings-uyap-auto-switch')),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('settings-uyap-help'),
            onPressed: () => unawaited(UyapHelpPage.open(context)),
            child: const Text('UYAP bağlantısı nasıl çalışır?'),
          ),
        ),
      ],
    ),
  );
}

/// What turning it on means, said before it is: true when the lawyer
/// accepted it.
Future<bool> askUyapAuto(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => const _UyapAutoDialog(),
    ) ??
    false;

class _UyapAutoDialog extends StatefulWidget {
  const _UyapAutoDialog();

  @override
  State<_UyapAutoDialog> createState() => _UyapAutoDialogState();
}

class _UyapAutoDialogState extends State<_UyapAutoDialog> {
  bool _read = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('UYAP verileri kendiliğinden alınsın mı?'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Açarsanız Folio, siz uygulamaya dokunmasanız da UYAP’a kendi '
              'oturumunuzla şunları sorar:',
            ),
            const SizedBox(height: 8),
            for (final line in const [
              'Bildirimlerinizi saatte bir; gece sormaz.',
              'Duruşmalarınızı günde bir.',
              'Dosya listenizi haftada bir, pazartesi günleri.',
            ])
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text('•  $line'),
              ),
            const SizedBox(height: 8),
            const Text(
              'Bu istekler sizin adınıza ve yalnız sizin görme yetkiniz olan '
              'dosyalar için yapılır. Folio istekleri aralıklı ve tek sıradan '
              'gönderir; UYAP yanıt vermezse bekler. Kapalı bıraktığınızda '
              'Folio UYAP’a yalnız siz giriş yaptığınızda, Yenile’ye '
              'bastığınızda ya da bir dosyayı açtığınızda sorar.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Alınan bilgiler yalnız bu cihazda ve Senkron’u açtığınız kendi '
              'cihazlarınızda tutulur; hiçbir sunucuya gönderilmez. Bu ayarı '
              'istediğiniz zaman kapatabilirsiniz.',
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              key: const ValueKey('uyap-auto-read'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _read,
              onChanged: (v) => setState(() => _read = v ?? false),
              title: const Text(
                'Okudum; UYAP verilerimin kendiliğinden '
                'alınmasını istiyorum.',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        key: const ValueKey('uyap-auto-yes'),
        onPressed: _read ? () => Navigator.pop(context, true) : null,
        child: const Text('Aç'),
      ),
    ],
  );
}

/// How Folio reaches UYAP, in a few plain words.
class UyapHelpPage extends StatelessWidget {
  const UyapHelpPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const UyapHelpPage()));

  static const _parts = [
    (
      'Folio bir tarayıcı gibi çalışır',
      'UYAP’a sizin e-Devlet girişiniz, e-imzanız ya da mobil imzanızla '
          'girilir. Folio yalnız sizin görme yetkiniz olan dosyaları gösterir; '
          'şifrenizi ve PIN kodunuzu hiçbir yerde saklamaz. Evrak gönderme ve '
          'imzalama gibi işler yalnız sizin dokunuşunuzla yapılır.',
    ),
    (
      'UYAP’a ne zaman sorulur',
      'Siz giriş yaptığınızda, Yenile ya da Senkronize et’e bastığınızda, bir '
          'dosyayı ya da bildirimler sayfasını açtığınızda. “UYAP verilerini '
          'kendiliğinden al” ayarını açarsanız bunlara ek olarak bildirimler '
          'saatte bir, duruşmalar günde bir ve dosya listeniz haftada bir '
          'alınır; gece hiçbir şey sorulmaz.',
    ),
    (
      'UYAP’ı yormamak için',
      'İstekler tek sıradan, birer ikişer saniye arayla gider. UYAP yanıt '
          'vermediğinde Folio bekler ve bekleme süresini uzatır. Kendi '
          'cihazlarınızdan biri bir bilgiyi aldıysa öbürü onu UYAP’a yeniden '
          'sormaz; telefonunuz, aynı ağdaki bilgisayarınız sorarken kendisi '
          'sormaz.',
    ),
    (
      'Verileriniz nerede durur',
      'Dosyalarınız, evrakınız, müvekkil bilgileriniz ve oturumlarınız yalnız '
          'sizin cihazlarınızda tutulur. Folio’nun bir sunucusu yoktur ve '
          'hiçbir veriyi dışarıya göndermez; veriler KVKK’ya uygun olarak '
          'yalnız sizin cihazınızda işlenir. Folio yapay zekâ hizmeti '
          'kullanmaz. Büro ağında yalnız sizin paylaştığınız şeyler, büronuzun '
          'kendi ağı üzerinden ve şifreli olarak gider.',
    ),
    (
      'Bir hata görürseniz',
      'Folio hatanın nedenini yazar: bağlantınız mı yok, UYAP’ın sunucusu mu '
          'hata veriyor, yoksa UYAP isteği mi reddetti. UYAP’ın kendi '
          'uygulamasında da aynı hata görünüyorsa sorun UYAP’tadır; bir süre '
          'sonra yeniden deneyin.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: settingsPage(context),
      appBar: settingsBar(context, 'UYAP bağlantısı'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          18,
          16,
          18,
          28 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          for (final (title, body) in _parts) ...[
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}
