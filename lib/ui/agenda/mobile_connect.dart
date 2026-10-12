import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/uyap/uyap_mobile_api.dart';
import '../../services/uyap/edevlet_window.dart';
import '../widgets/edevlet_web_dialog.dart';

/// Logs into the UYAP mobile API with e-Devlet, on its own: no web portal
/// login is started, and none is used (UYGULAMAPLANI §3). The lawyer
/// chooses e-imza or mobil imza on e-Devlet's own page.
Future<bool> connectUyapMobile(
  BuildContext context, {
  UyapMobileApi? api,
}) async {
  final mobile = api ?? UyapMobileApi.instance;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final code = await uyapMobileCode(context, messenger: messenger);
  if (code == null) return false;
  return _login(mobile, code, messenger);
}

/// "Şifremi unuttum" by e-Devlet: the TC number of who signed in, with
/// e-imza or mobil imza; UYAP Mobil is connected on the way. Null when it
/// was given up or did not go.
Future<String?> edevletIdentity(
  BuildContext context, {
  UyapMobileApi? api,
}) async {
  final mobile = api ?? UyapMobileApi.instance;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final code = await uyapMobileCode(context, messenger: messenger);
  if (code == null) return null;
  try {
    final session = await mobile.login(code);
    return session.tckn.isEmpty ? null : session.tckn;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('e-Devlet girişi: $e')));
    return null;
  }
}

/// Whether this is a phone: e-Devlet is entered with the mobile signature
/// there, never with a card (a phone has no reader for one).
@visibleForTesting
bool? phoneOverride;

bool get onPhone => phoneOverride ?? (Platform.isAndroid || Platform.isIOS);

/// What the e-Devlet page is told to say: a phone's lawyer signs with the
/// mobile signature alone.
String get uyapMobileHint => onPhone
    ? 'UYAP Mobil için e-Devlet girişi: Mobil İmza ile giriş yapın.'
    : 'UYAP Mobil için e-Devlet girişi: e-imza ya da mobil imzayı seçin.';

/// Whether e-Devlet's page can be shown here: a window of its own on a Mac
/// and Linux, WebView2 on Windows, the phone's own web view on a phone.
Future<bool> uyapMobileAvailable() async =>
    (Platform.isMacOS || Platform.isLinux) && EdevletWindow.available ||
    await EdevletWebDialog.available();

/// e-Devlet's code for UYAP Mobil: in a window of its own on a Mac and
/// Linux, in a dialog elsewhere. Null when it was given up.
Future<String?> uyapMobileCode(
  BuildContext context, {
  ScaffoldMessengerState? messenger,
}) async {
  if ((Platform.isMacOS || Platform.isLinux) && EdevletWindow.available) {
    final state = UyapMobileApi.newState();
    try {
      final window = await EdevletWindow.open(
        UyapMobileApi.loginPage(state),
        hint: uyapMobileHint,
        redirect: '${UyapMobileApi.edevletReturn}',
      );
      return await window.code;
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('UYAP Mobil girişi açılamadı: $e')),
      );
      return null;
    }
  }
  if (!await EdevletWebDialog.available()) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          Platform.isWindows
              ? 'UYAP Mobil girişi bu bilgisayarda Microsoft WebView2 ile '
                    'açılır; WebView2 bulunamadı.'
              : 'UYAP Mobil girişi bu cihazda henüz açılamıyor.',
        ),
      ),
    );
    return null;
  }
  if (!context.mounted) return null;
  final state = UyapMobileApi.newState();
  return EdevletWebDialog.show(
    context,
    page: UyapMobileApi.loginPage(state),
    hint: uyapMobileHint,
    isReturn: UyapMobileApi.isReturn,
    state: state,
  );
}

Future<bool> _login(
  UyapMobileApi mobile,
  String code,
  ScaffoldMessengerState? messenger,
) async {
  try {
    final session = await mobile.login(code);
    messenger?.showSnackBar(
      SnackBar(content: Text('UYAP Mobil bağlandı: ${session.user}')),
    );
    return true;
  } catch (e) {
    messenger?.showSnackBar(
      SnackBar(content: Text('UYAP Mobil bağlanamadı: $e')),
    );
    return false;
  }
}
