import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/portal/portal_channel.dart';
import '../../services/portal/portal_sync.dart';
import '../mobile/settings_parts.dart';

/// Ayarlar › Bağlantılar: whether Folio reads UYAP of itself, turned on
/// only after the lawyer has read what it means, with a page on how Folio
/// reaches UYAP at all.
class UyapAutoRow extends StatelessWidget {
  const UyapAutoRow({super.key, required this.sync});

  final PortalSync sync;

  /// The channels connected here that another own computer reads of
  /// itself, by its name: one line each name.
  List<String> _leftTo() {
    if (!sync.autoFetch) return const [];
    final by = <String, List<String>>{};
    for (final (channel, connected, name) in [
      (PortalChannel.uyapMobile, sync.mobile.connected, 'UYAP Mobil'),
      (PortalChannel.uyapWeb, sync.web.connected, 'UYAP Web'),
    ]) {
      if (!connected) continue;
      final reader = sync.autoReaderOf(channel);
      if (reader != null) (by[reader] ??= []).add(name);
    }
    return [
      for (final MapEntry(key: reader, value: channels) in by.entries)
        'Şu an kendiliğinden okumayı $reader yapıyor '
            '(${channels.join(' ve ')}); bu bilgisayar onun okuduklarını alır.',
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([sync, PortalSync.autoReadersChanged]),
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
                    'listeniz haftada bir; dosyalarınızın web bilgileri her '
                    'gün yedide biri olmak üzere haftada bir tazelenir.'
              : 'Kapalı. Folio UYAP’a yalnız siz bir düğmeye bastığınızda '
                    'ya da bir dosyayı açtığınızda, bir tarayıcı gibi sorar.',
          trailing: settingsSwitch(sync.autoFetch, (on) async {
            if (on && !await askUyapAuto(context)) return;
            await sync.setAutoFetch(on);
          }, key: const ValueKey('settings-uyap-auto-switch')),
        ),
        for (final line in _leftTo())
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              line,
              key: const ValueKey('settings-uyap-auto-elsewhere'),
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
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
              'UYAP Web bağlıyken, web’den bir kez tamamlanmış açık '
                  'dosyalarınızın ayrıntılarını, taraflarını, evrak '
                  'listesini, harç, tahsilat ve icra bilgilerini: her gün '
                  'dosyaların yedide birini, böylece her dosyayı haftada '
                  'bir. İlk tamamlamayı her zaman siz başlatırsınız.',
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
              'Folio UYAP’a yalnız siz Yenile, Senkronize et ya da kurulum '
              'gibi bir düğmeye bastığınızda ya da bir dosyayı açtığınızda '
              'sorar; giriş yapmak tek başına hiçbir şey okumaz.',
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
      'Yalnız siz Yenile, Senkronize et ya da kurulum gibi bir düğmeye '
          'bastığınızda ve bir dosyanın sayfasını açtığınızda; dosyanın '
          'sayfası yalnız eksik, yarım kalmış ya da bir günden eski '
          'bilgileri yeniden sorar. Giriş '
          'yapmak, ajandayı ya da bildirimleri açmak tek başına UYAP’a '
          'sormaz. İlk girişte kurulum ekranı açılır: dosya listenizi, '
          'müvekkillerinizi ve evrak listelerini siz başlatınca getirir; '
          'para, icra hesabı ve Yargıtay dosyaları için UYAP Web ile '
          'tamamlamayı da siz başlatırsınız. “UYAP verilerini kendiliğinden '
          'al” ayarını açarsanız bunlara ek olarak bildirimler saatte bir, '
          'duruşmalar günde bir ve dosya listeniz haftada bir alınır; UYAP '
          'Web bağlıysa dosyalarınızın web bilgileri her gün yedide biri '
          'olmak üzere aşağı yukarı haftada bir yenilenir. Evrakın kendisi '
          'kendiliğinden indirilmez. Gece kendiliğinden hiçbir şey '
          'sorulmaz.',
    ),
    (
      'UYAP’ı yormamak için',
      'İstekler tek sıradan, birer ikişer saniye arayla gider; iki evrak '
          'indirmesi arasında en az üç saniye beklenir. UYAP yanıt '
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
