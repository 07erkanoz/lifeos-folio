import 'dart:io';

import 'package:evrak_convert/services/platform/whatsapp.dart';
import 'package:flutter_test/flutter_test.dart';

// How a text opens in WhatsApp: on a computer the program installed is
// tried first (it takes whatsapp: links), WhatsApp Web after it.
void main() {
  test('a computer tries its own WhatsApp, then the page', () {
    final links = whatsAppLinks('Merhaba, kod: K7Q', digits: '905320000041');
    if (Platform.isAndroid || Platform.isIOS) {
      expect(links.single.host, 'wa.me');
      return;
    }
    expect(links, hasLength(2));
    expect(links.first.scheme, 'whatsapp');
    expect(links.first.queryParameters['phone'], '905320000041');
    expect(links.first.queryParameters['text'], 'Merhaba, kod: K7Q');
    expect(links.last.host, 'web.whatsapp.com');
    expect(links.last.queryParameters['text'], 'Merhaba, kod: K7Q');
  });

  test('with no number the sender picks who it goes to', () {
    final links = whatsAppLinks('Davet');
    expect(links.first.queryParameters.containsKey('phone'), isFalse);
  });

  test('LifeOS WhatsApp is found on the path where it is installed', () async {
    final dir = await Directory.systemTemp.createTemp('wa');
    addTearDown(() => dir.delete(recursive: true));
    expect(lifeosWhatsApp({'PATH': '/yok:${dir.path}'}), isNull);
    File('${dir.path}/lifeos-whatsapp').writeAsStringSync('#!/bin/sh\n');
    expect(
      lifeosWhatsApp({'PATH': '/yok:${dir.path}'}),
      '${dir.path}/lifeos-whatsapp',
    );
  });
}
