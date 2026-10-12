import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:url_launcher/url_launcher.dart';

import '../../services/platform/app_directories.dart';
import '../../services/portal/portal_channel.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/uyap/adalet_eimza.dart';
import '../../services/uyap/edevlet_window.dart';
import '../../services/uyap/uyap_mobile_api.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../agenda/mobile_connect.dart';
import 'edevlet_web_dialog.dart';
import 'folio_dialog.dart';

/// The channels that can do [op]: its primary, and its fallback where it
/// only reads. Null: anything UYAP.
Set<PortalChannel> uyapChannelsFor(UyapOp? op) {
  if (op == null) {
    return const {PortalChannel.uyapWeb, PortalChannel.uyapMobile};
  }
  final rule = ChannelTable.rule(op);
  return {
    rule.primary,
    if (!rule.writes && rule.fallback != null) rule.fallback!,
  };
}

/// UYAP's one door. Nothing is asked when a portal that can do [op] is
/// already connected; else one dialog offers the ways in that can, in this
/// device's order: the card and the web portal first on a computer, UYAP
/// Mobil first on a phone, and never a card on a phone. True once one is
/// connected.
Future<bool> ensureUyap(
  BuildContext context,
  UyapOp op, {
  String? why,
  UyapWebService? web,
  UyapMobileApi? mobile,
}) {
  final w = web ?? UyapWebService.instance;
  final m = mobile ?? UyapMobileApi.instance;
  final connected = {
    if (w.connected) PortalChannel.uyapWeb,
    if (m.connected) PortalChannel.uyapMobile,
  };
  if (ChannelTable.channels(op, connected).isNotEmpty) {
    return Future.value(true);
  }
  return connectUyap(context, op: op, why: why, mobile: m);
}

/// The door itself: a dialog with the ways into the portals that can do
/// [op] (any of them when null). True once one is connected.
Future<bool> connectUyap(
  BuildContext context, {
  UyapOp? op,
  Set<PortalChannel>? channels,
  String? why,
  UyapMobileApi? mobile,
  VoidCallback? onConnected,
}) async {
  if (!Platform.environment.containsKey('FLUTTER_TEST')) PortalSync.begin();
  final allowed = channels ?? uyapChannelsFor(op);
  final webOnly = !allowed.contains(PortalChannel.uyapMobile);
  final done = await showDialog<bool>(
    context: context,
    builder: (context) => FolioDialog(
      width: 540,
      icon: Icons.account_balance_outlined,
      title: webOnly ? 'UYAP Web’e bağlan' : 'UYAP’a bağlan',
      subtitle: webOnly ? 'Avukat Portalı' : 'Bir giriş yolu seçin',
      onClose: () => Navigator.pop(context, false),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Kapat'),
        ),
      ],
      child: UyapConnectView(
        heading: false,
        channels: allowed,
        mobile: mobile,
        note:
            why ??
            (webOnly
                ? 'UYAP Web her şeyi verir: dosya bilgileri, tam evrak '
                      'listesi, Yargıtay ve Cumhuriyet Başsavcılığı dosyaları.'
                : null),
        onConnected: (_) async {
          if (context.mounted) Navigator.pop(context, true);
          onConnected?.call();
        },
      ),
    ),
  );
  return done ?? false;
}

/// Opens a UYAP web portal session in a dialog: the card with Adalet
/// E-İmza on a computer, the mobile signature through e-Devlet anywhere.
Future<void> connectUyapWeb(
  BuildContext context, {
  VoidCallback? onConnected,
}) => connectUyap(
  context,
  channels: const {PortalChannel.uyapWeb},
  onConnected: onConnected,
);

/// The ways into UYAP, in one place for everything that needs a session.
/// On a computer: the card with its PIN through the Adalet E-İmza
/// application, the mobile or the e-signature through e-Devlet, and UYAP
/// Mobil. On a phone: UYAP Mobil and the web portal, both with the mobile
/// signature; never a card.
class UyapConnectView extends StatefulWidget {
  const UyapConnectView({
    super.key,
    required this.onConnected,
    this.note,
    this.heading = true,
    this.channels = const {PortalChannel.uyapWeb},
    this.mobile,
  });

  /// The portals offered: the web portal alone where only it can do what
  /// is asked (sending, the operations), else both.
  final Set<PortalChannel> channels;

  /// UYAP Mobil's client; the app's own when null.
  final UyapMobileApi? mobile;

  /// Runs once the session is open, with the name of the lawyer in it:
  /// what the caller loads first, while the view still says it is busy.
  final Future<void> Function(String user) onConnected;

  /// What the session is wanted for, said above the choices.
  final String? note;

  /// Whether the view names the portal itself; a dialog that already does
  /// in its own heading leaves it out.
  final bool heading;

  @override
  State<UyapConnectView> createState() => _UyapConnectViewState();
}

/// A way in: the portal it opens, and how the lawyer signs.
enum _Route {
  /// The web portal, the card and its PIN through Adalet E-İmza.
  tray,

  /// The web portal, the mobile signature through e-Devlet.
  mobile,

  /// The web portal, the card through e-Devlet's own e-signature page.
  eSignature,

  /// UYAP Mobil, through e-Devlet.
  mobileApi,
}

/// The way in this device's lawyer chose last: kept in `baglanti.json`, so
/// the door opens on it next time, also after Folio is started again.
abstract final class UyapDoorMemory {
  static String? _route;
  static bool _loaded = false;

  /// As if [route] had been kept; nothing is read from the disk after.
  @visibleForTesting
  static void reset([String? route]) {
    _route = route;
    _loaded = true;
  }

  static Future<File> _file() async =>
      File(p.join((await folioSupportDirectory()).path, 'baglanti.json'));

  static Future<String?> load() async {
    if (_loaded) return _route;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        _route = (jsonDecode(await f.readAsString()) as Map)['yol'] as String?;
      }
    } catch (_) {}
    return _route;
  }

  static Future<void> save(String route) async {
    _route = route;
    _loaded = true;
    try {
      await (await _file()).writeAsString(jsonEncode({'yol': route}));
    } catch (_) {}
  }
}

class _UyapConnectViewState extends State<UyapConnectView> {
  UyapWebService get _web => UyapWebService.instance;
  UyapMobileApi get _mobile => widget.mobile ?? UyapMobileApi.instance;
  final _pin = TextEditingController();
  late _Route _route = _order.first;
  bool _busy = false;

  /// While the login itself is under way, and closing the view would leave
  /// it half done. Once the session is open, the view going away — as it
  /// does the moment its caller sees the session — must not touch it.
  bool _loggingIn = false;
  bool? _edevlet;

  /// Whether the Adalet E-İmza application is on this computer.
  bool? _tray;
  String? _stage;
  String? _error;
  EdevletWindow? _window;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  /// A phone signs in through e-Devlet in its own web view, with the mobile
  /// signature: it has no card reader, for Adalet E-İmza or for e-Devlet.
  static bool get _phone => onPhone;

  /// The ways offered, the recommended first: on a computer the card and
  /// the web portal, which give everything and can send; on a phone UYAP
  /// Mobil, whose session lasts a week. Only those of the portals asked.
  List<_Route> get _order {
    final web = widget.channels.contains(PortalChannel.uyapWeb);
    final mobile = widget.channels.contains(PortalChannel.uyapMobile);
    return _phone
        ? [if (mobile) _Route.mobileApi, if (web) _Route.mobile]
        : [
            if (web) ...[_Route.tray, _Route.mobile, _Route.eSignature],
            if (mobile) _Route.mobileApi,
          ];
  }

  Future<void> _check() async {
    final (edevlet, tray) = await (
      Platform.isWindows || _phone
          ? EdevletWebDialog.available()
          : Future.value(EdevletWindow.available),
      _phone ? Future.value(false) : AdaletEimza.installed(),
    ).wait;
    final kept = await UyapDoorMemory.load();
    if (!mounted) return;
    setState(() {
      _edevlet = edevlet;
      _tray = tray;
      final order = _order;
      final remembered = order.where((r) => r.name == kept).firstOrNull;
      if (remembered != null && _available(remembered)) {
        _route = remembered;
      } else if (!_available(_route)) {
        _route = order.firstWhere(_available, orElse: () => _route);
      }
    });
  }

  bool _available(_Route route) =>
      route == _Route.tray ? _tray == true : _edevlet == true;

  @override
  void dispose() {
    if (_loggingIn) _cancel();
    _pin.dispose();
    super.dispose();
  }

  static String get _hint => _phone
      ? 'e-Devlet’te Mobil İmza ile giriş yapın. Giriş tamamlanınca bu '
            'pencere kendiliğinden kapanır.'
      : 'e-Devlet’te Mobil İmza ya da Elektronik İmza ile giriş yapın. '
            'Giriş tamamlanınca bu pencere kendiliğinden kapanır.';

  Future<void> _connect() async {
    if (_route == _Route.tray && _pin.text.isEmpty) {
      setState(() => _error = 'E-imza PIN kodunu girin.');
      return;
    }
    unawaited(UyapDoorMemory.save(_route.name));
    setState(() {
      _busy = true;
      _error = null;
      _stage = 'Bağlantı hazırlanıyor';
    });
    _loggingIn = true;
    try {
      final String user;
      if (_route == _Route.mobileApi) {
        setState(() => _stage = 'e-Devlet penceresinde girişi tamamlayın');
        final code = await uyapMobileCode(
          context,
          messenger: ScaffoldMessenger.maybeOf(context),
        );
        if (code == null) {
          if (mounted) setState(() => _stage = null);
          return;
        }
        if (mounted) setState(() => _stage = 'UYAP Mobil oturumu açılıyor');
        user = (await _mobile.login(code)).user;
      } else if (_route == _Route.tray) {
        user = await _web.connect(
          _pin.text,
          onProgress: (stage) {
            if (mounted) setState(() => _stage = stage);
          },
        );
      } else {
        final login = await _web.beginEdevlet(
          _route == _Route.mobile
              ? EdevletMethod.mobile
              : EdevletMethod.eSignature,
        );
        if (!mounted) return;
        setState(() => _stage = 'e-Devlet penceresinde girişi tamamlayın');
        final code = await _edevletCode(login.page);
        if (code == null) {
          _web.disconnect();
          if (mounted) setState(() => _stage = null);
          return;
        }
        if (mounted) setState(() => _stage = 'UYAP oturumu açılıyor');
        user = await _web.finishEdevlet(login, code);
      }
      _loggingIn = false;
      if (mounted) setState(() => _stage = 'Bilgiler yükleniyor');
      await widget.onConnected(user);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('Bad state: ', ''));
      }
    } finally {
      _loggingIn = false;
      _window = null;
      if (mounted) _pin.clear();
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = null;
        });
      }
    }
  }

  Future<String?> _edevletCode(Uri page) async {
    if (Platform.isWindows || _phone) {
      return EdevletWebDialog.show(context, page: page, hint: _hint);
    }
    final window = _window = await EdevletWindow.open(page, hint: _hint);
    return window.code;
  }

  void _cancel() {
    _window?.close();
    if (_route != _Route.mobileApi) _web.cancelConnect();
  }

  Widget _choice(_Route route, String title, String detail, IconData icon) {
    final enabled = !_busy && _available(route);
    final colors = Theme.of(context).colorScheme;
    final selected = route == _route && _available(route);
    final recommended = _order.length > 1 && route == _order.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RadioListTile<_Route>(
        value: route,
        dense: true,
        selected: selected,
        contentPadding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
        tileColor: colors.surface,
        selectedTileColor: colors.primaryContainer.withValues(alpha: .6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        secondary: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: (selected ? colors.primary : colors.onSurfaceVariant)
                .withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 18,
            color: selected ? colors.primary : colors.onSurfaceVariant,
          ),
        ),
        controlAffinity: ListTileControlAffinity.trailing,
        title: Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: !enabled && !selected
                    ? colors.onSurfaceVariant
                    : selected
                    ? colors.primary
                    : colors.onSurface,
              ),
            ),
            if (recommended)
              Container(
                key: const ValueKey('uyap-route-recommended'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Önerilen',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          detail,
          style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
        ),
        enabled: enabled,
      ),
    );
  }

  static String _portal(_Route route) =>
      route == _Route.mobileApi ? 'UYAP Mobil' : 'UYAP Web Portal';

  Widget _routeChoice(_Route route, ThemeData theme) => switch (route) {
    _Route.tray => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _choice(
          _Route.tray,
          'Adalet E-İmza ile',
          'Kartınız ve PIN’inizle, bu bilgisayardaki Adalet E-İmza '
              'uygulaması üzerinden. Her şey bununla: dosyalar, evraklar, '
              'gönderim.',
          Icons.credit_card_rounded,
        ),
        if (_tray == false)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 0, 10),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text(
                  'Bu bilgisayarda kurulu değil.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('adalet-eimza-download'),
                  onPressed: () => unawaited(
                    launchUrl(
                      Uri.parse(AdaletEimza.downloadPage),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('İndirme sayfasını aç'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => unawaited(_check()),
                  child: const Text('Yeniden denetle'),
                ),
              ],
            ),
          ),
      ],
    ),
    _Route.mobile => _choice(
      _Route.mobile,
      'Mobil imza ile',
      'e-Devlet üzerinden; telefonunuza gelen onayı verirsiniz.',
      Icons.phone_iphone_rounded,
    ),
    _Route.eSignature => _choice(
      _Route.eSignature,
      'E-imza ile, e-Devlet üzerinden',
      'Kartınız takılıyken e-Devlet’in e-imza girişiyle.',
      Icons.badge_outlined,
    ),
    _Route.mobileApi => _choice(
      _Route.mobileApi,
      'UYAP Mobil ile',
      _phone
          ? 'e-Devlet’te mobil imzayla; oturum bir hafta açık kalır.'
          : 'e-Devlet üzerinden; oturum bir hafta açık kalır. Dosya ve '
                'evraklara yeter, UYAP’a gönderim için Web Portal gerekir.',
      Icons.smartphone_rounded,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('uyap-connect'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.heading)
          Text(
            'UYAP Avukat Portalı’na bağlanın',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        if (widget.note != null) ...[
          if (widget.heading) const SizedBox(height: 4),
          Text(
            widget.note!,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 16),
        RadioGroup<_Route>(
          groupValue: _route,
          onChanged: (value) {
            if (value != null && !_busy) setState(() => _route = value);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, route) in _order.indexed) ...[
                // Each portal's ways under its name, where both are offered.
                if (widget.channels.length > 1 &&
                    (i == 0 || _portal(_order[i - 1]) != _portal(route)))
                  FolioSectionLabel(_portal(route)),
                _routeChoice(route, theme),
              ],
            ],
          ),
        ),
        if (_edevlet == false)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              Platform.isWindows
                  ? 'e-Devlet girişi için Microsoft Edge WebView2 gerekiyor.'
                  : Platform.isMacOS
                  ? 'e-Devlet penceresi bu Folio paketinde bulunamadı; '
                        'Folio\'yu yeniden kurun.'
                  : 'e-Devlet girişi için sistemde WebKitGTK '
                        '(libwebkit2gtk-4.1) gerekiyor.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (_route == _Route.tray && _available(_Route.tray)) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _pin,
            obscureText: true,
            enabled: !_busy,
            onSubmitted: (_) {
              if (!_busy) unawaited(_connect());
            },
            decoration: const InputDecoration(
              labelText: 'E-imza PIN',
              prefixIcon: Icon(Icons.lock_outline_rounded, size: 19),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (_stage != null)
          Row(
            children: [
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _stage!,
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
              ),
              TextButton(onPressed: _cancel, child: const Text('Vazgeç')),
            ],
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('uyap-connect-button'),
              onPressed: _busy || !_available(_route)
                  ? null
                  : () => unawaited(_connect()),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Bağlan'),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          FolioCallout(tone: CalloutTone.error, child: Text(_error!)),
        ],
        const SizedBox(height: 10),
        Text(
          _route == _Route.mobileApi
              ? 'UYAP Mobil oturumu bir hafta açık kalır; kendiliğinden '
                    'yenilenir.'
              : 'Web Portal oturumu yaklaşık 2 saat 55 dakika açık kalır; bu '
                    'sürede gönderme ve dosya işlemleri için yeniden imza '
                    'gerekmez.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
