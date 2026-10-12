import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../services/uyap/adalet_eimza.dart';
import '../../services/uyap/edevlet_window.dart';
import '../../services/uyap/uyap_web_service.dart';
import 'edevlet_web_dialog.dart';
import 'folio_dialog.dart';

/// Opens a UYAP web portal session in a dialog: the card with Adalet
/// E-İmza on a computer, the mobile signature or the e-signature through
/// e-Devlet anywhere, a phone's own web view on a phone.
Future<void> connectUyapWeb(
  BuildContext context, {
  VoidCallback? onConnected,
}) => showDialog<void>(
  context: context,
  builder: (context) => FolioDialog(
    width: 540,
    icon: Icons.account_balance_outlined,
    title: 'UYAP Web’e bağlan',
    subtitle: 'Avukat Portalı',
    onClose: () => Navigator.pop(context),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Kapat'),
      ),
    ],
    child: UyapConnectView(
      heading: false,
      note:
          'UYAP Web her şeyi verir: dosya bilgileri, tam evrak listesi, '
          'Yargıtay ve Cumhuriyet Başsavcılığı dosyaları.',
      onConnected: (_) async {
        if (context.mounted) Navigator.pop(context);
        onConnected?.call();
      },
    ),
  ),
);

/// The ways into the Avukat Portal, in one place for everything that needs
/// a session: a mobile signature or an e-signature through e-Devlet, or the
/// card with its PIN through the Adalet E-İmza application.
class UyapConnectView extends StatefulWidget {
  const UyapConnectView({
    super.key,
    required this.onConnected,
    this.note,
    this.heading = true,
  });

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

enum _Route { tray, mobile, eSignature }

class _UyapConnectViewState extends State<UyapConnectView> {
  /// The way chosen last, offered first next time; until one is, the
  /// first of them that can be used.
  static _Route? _last;

  UyapWebService get _web => UyapWebService.instance;
  final _pin = TextEditingController();
  _Route _route = _last ?? _Route.tray;
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

  /// A phone signs in through e-Devlet in its own web view; it has no card
  /// reader for Adalet E-İmza.
  static bool get _phone => Platform.isAndroid || Platform.isIOS;

  Future<void> _check() async {
    final (edevlet, tray) = await (
      Platform.isWindows || _phone
          ? EdevletWebDialog.available()
          : Future.value(EdevletWindow.available),
      _phone ? Future.value(false) : AdaletEimza.installed(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _edevlet = edevlet;
      _tray = tray;
      if (!_available(_route)) {
        _route = _Route.values.firstWhere(_available, orElse: () => _route);
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

  static const _hint =
      'e-Devlet’te Mobil İmza ya da Elektronik İmza ile giriş yapın. '
      'Giriş tamamlanınca bu pencere kendiliğinden kapanır.';

  Future<void> _connect() async {
    if (_route == _Route.tray && _pin.text.isEmpty) {
      setState(() => _error = 'E-imza PIN kodunu girin.');
      return;
    }
    _last = _route;
    setState(() {
      _busy = true;
      _error = null;
      _stage = 'Bağlantı hazırlanıyor';
    });
    _loggingIn = true;
    try {
      final String user;
      if (_route == _Route.tray) {
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
    _web.cancelConnect();
  }

  Widget _choice(_Route route, String title, String detail, IconData icon) {
    final enabled = !_busy && _available(route);
    final colors = Theme.of(context).colorScheme;
    final selected = route == _route && _available(route);
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
        title: Text(
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
        subtitle: Text(
          detail,
          style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
        ),
        enabled: enabled,
      ),
    );
  }

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
        const FolioSectionLabel('Giriş yöntemi'),
        RadioGroup<_Route>(
          groupValue: _route,
          onChanged: (value) {
            if (value != null && !_busy) setState(() => _route = value);
          },
          child: Column(
            children: [
              if (!_phone)
                _choice(
                  _Route.tray,
                  'Adalet E-İmza ile',
                  'Kartınız ve PIN’inizle, bu bilgisayardaki Adalet E-İmza '
                      'uygulaması üzerinden.',
                  Icons.credit_card_rounded,
                ),
              if (_tray == false && !_phone)
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
              _choice(
                _Route.mobile,
                'Mobil imza ile',
                'e-Devlet üzerinden; telefonunuza gelen onayı verirsiniz.',
                Icons.phone_iphone_rounded,
              ),
              _choice(
                _Route.eSignature,
                'E-imza ile, e-Devlet üzerinden',
                'Kartınız takılıyken e-Devlet’in e-imza girişiyle.',
                Icons.badge_outlined,
              ),
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
          'Oturum yaklaşık 2 saat 55 dakika açık kalır; bu sürede gönderme ve '
          'dosya işlemleri için yeniden imza gerekmez.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
