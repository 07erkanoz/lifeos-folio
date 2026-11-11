import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// The ways [text] may open in WhatsApp, in the order to try them: on a
/// computer the program installed (WhatsApp on Windows and a Mac, LifeOS
/// WhatsApp or WhatSie on Linux: each takes `whatsapp:` links), else
/// WhatsApp Web; on a phone the link that opens the app. [digits] is who
/// it goes to (phoneDigits); empty, the sender picks there.
List<Uri> whatsAppLinks(String text, {String digits = ''}) {
  final said = Uri.encodeComponent(text);
  final to = digits.isEmpty ? '' : 'phone=$digits&';
  return Platform.isAndroid || Platform.isIOS
      ? [Uri.parse('https://wa.me/$digits?text=$said')]
      : [
          Uri.parse('whatsapp://send?${to}text=$said'),
          Uri.parse('https://web.whatsapp.com/send?${to}text=$said'),
        ];
}

/// Opens the first of [links] this device takes: a program's own link
/// only where a program is there for it, the last whatever is there.
Future<bool> openFirst(List<Uri> links) async {
  for (final (i, uri) in links.indexed) {
    try {
      if (i < links.length - 1 && !await canLaunchUrl(uri)) continue;
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {}
  }
  return false;
}

/// [text] opened in WhatsApp, for the sender to pick who it goes to.
Future<bool> openWhatsApp(String text, {String digits = ''}) =>
    openFirst(whatsAppLinks(text, digits: digits));
