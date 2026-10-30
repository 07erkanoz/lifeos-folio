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
