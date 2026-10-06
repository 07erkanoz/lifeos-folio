import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/uyap/uyap_mobile_api.dart';
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
    return false;
  }
  if (!context.mounted) return false;
  final state = UyapMobileApi.newState();
  final code = await EdevletWebDialog.show(
    context,
    page: UyapMobileApi.loginPage(state),
    hint: 'UYAP Mobil için e-Devlet girişi: e-imza ya da mobil imzayı seçin.',
    isReturn: UyapMobileApi.isReturn,
    state: state,
  );
  if (code == null) return false;
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
