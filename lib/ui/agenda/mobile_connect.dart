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
  final code = await _edevletCode(context, messenger);
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
  final code = await _edevletCode(context, messenger);
  if (code == null) return null;
  try {
    final session = await mobile.login(code);
    return session.tckn.isEmpty ? null : session.tckn;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('e-Devlet girişi: $e')));
    return null;
  }
}

/// e-Devlet's code for UYAP Mobil: in a window of its own on a Mac and
/// Linux, in a dialog elsewhere.
Future<String?> _edevletCode(
  BuildContext context,
  ScaffoldMessengerState? messenger,
) async {
  if ((Platform.isMacOS || Platform.isLinux) && EdevletWindow.available) {
    final state = UyapMobileApi.newState();
    try {
      final window = await EdevletWindow.open(
        UyapMobileApi.loginPage(state),
        hint:
            'UYAP Mobil için e-Devlet girişi: e-imza ya da mobil imzayı seçin.',
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
    hint: 'UYAP Mobil için e-Devlet girişi: e-imza ya da mobil imzayı seçin.',
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
