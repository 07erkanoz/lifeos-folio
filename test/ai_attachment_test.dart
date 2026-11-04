import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:evrak_convert/services/ai/ai_assistant.dart';
import 'package:evrak_convert/services/ai/ai_attachment.dart';
import 'package:evrak_convert/services/ai/ai_memory.dart';
import 'package:evrak_convert/services/portal/portal_database.dart';
import 'package:flutter_test/flutter_test.dart';

// Documents added to a conversation: one with text goes as its text, a
// scan or a picture as it is to a program that takes pictures, and the
// conversation's name the lawyer gave stays.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('folio-yz-ek-');
  });
  tearDown(() => dir.delete(recursive: true));

  test('a text file as its text, identity numbers hidden; a picture as it '
      'is to Claude and Codex', () async {
    final note = File('${dir.path}/not.txt')
      ..writeAsStringSync('Müvekkil TC 10000000146, ara karar 05.05.2026.');
    final text = await AiAttachment.prepare(note.path, AiProvider.claude);
    expect(text.visual, isFalse);
    expect(text.text, contains('ara karar'));
    expect(text.text, isNot(contains('10000000146')));

    final png = File('${dir.path}/tarama.png')
      ..writeAsBytesSync(Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]));
    for (final provider in [AiProvider.claude, AiProvider.codex]) {
      final picture = await AiAttachment.prepare(png.path, provider);
      expect(picture.visual, isTrue);
      expect(picture.images.single.mime, 'image/png');
    }
    final block = AiAttachment.block([
      text,
      await AiAttachment.prepare(png.path, AiProvider.claude),
    ]);
    expect(block, contains('<ek ad="not.txt">'));
    expect(
      block,
      contains('[Ek: tarama.png — sayfaları görsel olarak eklendi.]'),
    );
  });

  test('Claude given pages as blocks before the question, answering as '
      'events; Codex given pictures as files', () {
    final attachments = [
      AiAttachment(path: '/x/rapor.pdf', pdf: Uint8List.fromList([1, 2, 3])),
      AiAttachment(
        path: '/x/tarama.png',
        images: [
          AiImage('image/png', Uint8List.fromList([4, 5])),
        ],
      ),
    ];
    final line = AiAssistant.input(
      AiProvider.claude,
      'Soru',
      attachments: attachments,
    );
    final content =
        ((jsonDecode(line) as Map)['message'] as Map)['content'] as List;
    expect(content.map((c) => (c as Map)['type']), [
      'document',
      'image',
      'text',
    ]);
    expect((content.last as Map)['text'], 'Soru');
    // With no pictures, the question as it is.
    expect(AiAssistant.input(AiProvider.claude, 'Soru'), 'Soru');

    final claude = AiAssistant.arguments(
      AiProvider.claude,
      '/tmp/x',
      pictures: true,
    );
    expect(claude, containsAll(['--input-format', 'stream-json', '--verbose']));
    expect(claude, isNot(contains('json')));
    final codex = AiAssistant.arguments(
      AiProvider.codex,
      '/tmp/x',
      images: ['/tmp/x/ek-1.png', '/tmp/x/ek-2.png'],
    );
    expect(codex.join(' '), contains('-i /tmp/x/ek-1.png -i /tmp/x/ek-2.png'));
    expect(codex.last, '-');

    final events = [
      jsonEncode({'type': 'system', 'subtype': 'init'}),
      jsonEncode({
        'type': 'result',
        'subtype': 'success',
        'is_error': false,
        'result': 'Raporda izin hesabı yok.',
      }),
    ].join('\n');
    expect(
      AiAssistant.answer(AiProvider.claude, events, null),
      'Raporda izin hesabı yok.',
    );
  });

  test('pictures in a PDF read from their dictionaries; a screenshot is '
      'evidence, a QR code or a logo is not, a thumbnail cannot be read', () {
    final pdf = Uint8List.fromList(
      latin1.encode(
        '%PDF-1.7\n'
        '5 0 obj\n<< /Type /XObject /Subtype /Image /Width 1366 '
        '/Height 768 /BitsPerComponent 8 >>\nstream\nxx\nendstream\n'
        '6 0 obj\n<</Subtype/Image/Width 51/Height 51>>stream\nendstream\n'
        '7 0 obj\n<< /Subtype /Form /BBox [0 0 1 1] >>\nstream\nendstream\n',
      ),
    );
    expect(AiAttachment.embeddedImages(pdf), [(1366, 768), (51, 51)]);
    expect(AiAttachment.meaningfulPicture(1366, 768), isTrue);
    expect(AiAttachment.meaningfulPicture(2023, 171), isFalse);
    expect(AiAttachment.meaningfulPicture(289, 289), isFalse);

    // UYAP's QR code and marks, a bank's logo: nothing said.
    expect(
      AiAttachment.unreadablePictures([(51, 51), (16, 17), (232, 29)]),
      isNull,
    );
    expect(AiAttachment.unreadablePictures([(1366, 768), (76, 166)]), isNull);
    // An e-mail's print, its attachments as thumbnails: said.
    final note = AiAttachment.unreadablePictures([
      (76, 166),
      (221, 166),
      (16, 16),
    ]);
    expect(note, contains('2 küçük gömülü görsel'));
    expect(note, contains('221 piksel'));

    final block = AiAttachment.block([
      AiAttachment(path: '/x/mail.pdf', text: 'Gönderilen e-posta', note: note),
      AiAttachment(
        path: '/x/tarama.pdf',
        text: 'Okunan',
        ocr: true,
        pagesLeft: 12,
      ),
    ]);
    expect(block, contains('[Not: Belgede 2 küçük gömülü görsel'));
    expect(block, contains('[Taramanın son 12 sayfası okunmadı.]'));
  });

  test('a conversation read by its id; taken off, none', () {
    final db = PortalDatabase.memory();
    addTearDown(db.dispose);
    db.putAiRecord('c1', AiMemory.chat, 'k', {'baslik': 'Rapora itiraz'});
    expect(db.aiRecord('c1')?['baslik'], 'Rapora itiraz');
    expect(db.aiRecord('c1')?['dosya'], 'k');
    db.removeAiRecord('c1');
    expect(db.aiRecord('c1'), isNull);
  });
}
