import 'dart:io';

import 'package:evrak_convert/services/editor/lawyer_profile.dart';
import 'package:evrak_convert/services/editor/suggestions/phrase_memory.dart';
import 'package:evrak_convert/services/editor/suggestions/phrases.dart';
import 'package:evrak_convert/services/editor/suggestions/suggestion_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('phrases', () {
    test('Turkish letters fold together, circumflexes too', () {
      expect(foldPhrase('İcra ve İflas'), foldPhrase('icra ve iflas'));
      expect(foldPhrase('Şikâyet'), 'sikayet');
      expect(foldPhrase('IĞDIR'), 'igdir');
    });

    test('a document is cut into clauses, not at ordinals or "m."', () {
      final found = phrasesIn(
        'MANAVGAT 1. ASLİYE HUKUK MAHKEMESİNE\n'
        'Davalının TMK m. 166 uyarınca kusurlu olduğu açıktır. '
        'Yukarıda açıklanan nedenlerle, davanın kabulüne karar verilmesini '
        'saygılarımla arz ederim.',
      ).values;
      expect(found, contains('MANAVGAT 1. ASLİYE HUKUK MAHKEMESİNE'));
      expect(
        found,
        contains('Davalının TMK m. 166 uyarınca kusurlu olduğu açıktır'),
      );
      expect(found, contains('Yukarıda açıklanan nedenlerle'));
      expect(
        found,
        contains('davanın kabulüne karar verilmesini saygılarımla arz ederim'),
      );
    });

    test('one word, a stray number or a long paragraph is not a phrase', () {
      expect(phrasesIn('Açıklamalar\n12 Ocak\n${'uzun ' * 40}'), isEmpty);
    });

    test('personal data is never learned', () {
      for (final line in [
        'Davacı Ahmet YILMAZ vekili olarak',
        'AHMET YILMAZ TC 12345678901',
        'T.C. kimlik numarası belirtilmiştir',
        'Bahçelievler Mah Çetin Emeç Cad',
        'Konyaaltı/ANTALYA adresinde oturan',
        'telefon numarası 0532 123 45 67 olan',
        'e-posta adresine avukat@example.com ile',
        'IBAN TR12 0006 1005 1978 6457 8413 26 hesabına',
        '2023/456 Esas sayılı dosyada',
        'görüşme 12.03.2024 tarihinde yapıldı',
        'Arabulucu 19275 sicil numaralı',
      ]) {
        expect(isPersonal(line), isTrue, reason: line);
      }
      for (final line in [
        '7036 sayılı İş Mahkemeleri Kanunu uyarınca',
        'Kira bedelinin zamanında ödenmemesi durumunda %15 temerrüt faizi',
        'Kat Mülkiyeti Kanunu hükümleri',
        'Yargıtay 3. Hukuk Dairesi kararı',
      ]) {
        expect(isPersonal(line), isFalse, reason: line);
      }
    });

    test('the words to complete are the end of the clause, at most six', () {
      expect(
        typedTail('Sonuç olarak gereğini say'),
        'Sonuç olarak gereğini say',
      );
      expect(
        typedTail('bir iki üç dört beş altı yedi'),
        'iki üç dört beş altı yedi',
      );
      expect(typedTail('kabul edilmiştir. Yukarıda aç'), 'Yukarıda aç');
      expect(typedTail('TMK m. 166 uyarınca ku'), 'TMK m. 166 uyarınca ku');
      // Nothing to complete after a space, or after one letter.
      expect(typedTail('davanın '), isNull);
      expect(typedTail('davanın k'), isNull);
    });
  });

  group('suggestions', () {
    test('"icra" finds İcra ve İflas Kanunu', () {
      final found = SuggestionEngine().suggest('Borçlu hakkında icra');
      expect(found.map((s) => s.text), contains('İcra ve İflas Kanunu'));
      expect(found.first.typed, 'icra'.length);
    });

    test('the longest typed run matches first', () {
      final found = SuggestionEngine().suggest('Sonuç olarak gereğini say');
      expect(found.first.text, 'gereğini saygılarımla arz ederim');
      expect(found.first.typed, 'gereğini say'.length);
    });

    test('a phrase starts the way the reader started it', () {
      expect(
        SuggestionEngine().suggest('Talep: davanın kab').first.text,
        'davanın kabulüne karar verilmesini',
      );
      expect(
        SuggestionEngine().suggest('Davanın kab').first.text,
        'Davanın kabulüne karar verilmesini',
      );
    });

    test('the profile comes before the built-in phrases', () {
      final found = SuggestionEngine(
        profile: const LawyerProfile(
          lawyers: [Lawyer(name: 'Deniz Yılmaz', bar: 'Antalya')],
        ),
      ).suggest('Av');
      expect(found.first.text, 'Av. Deniz Yılmaz');
      expect(found.first.source, SuggestionSource.profile);
    });

    test('a learned phrase is offered once two documents have it', () {
      final memory = PhraseMemory.memory();
      addTearDown(memory.dispose);
      const text = 'Müvekkilin kiracı olduğu taşınmazda tespit yapılmasını';
      memory.learnSaved('/a.udf', text);
      expect(
        SuggestionEngine(memory: memory).suggest('Müvekkilin kira'),
        isEmpty,
      );
      memory.learnSaved('/b.udf', text);
      final found = SuggestionEngine(memory: memory).suggest('Müvekkilin kira');
      expect(found.single.text, text);
      expect(found.single.label, '2 belgede');
    });
  });

  group('memory', () {
    late PhraseMemory memory;
    setUp(() => memory = PhraseMemory.memory());
    tearDown(() => memory.dispose());

    const phrase = 'Kira bedelinin zamanında ödenmemesi halinde';

    test('saving the same document again counts it once', () {
      for (var i = 0; i < 5; i++) {
        memory.learnSaved('/dilekce.udf', phrase);
      }
      expect(memory.phrases.single.saved, 1);
    });

    test('what a document no longer says, it no longer teaches', () {
      memory.learnSaved('/dilekce.udf', phrase);
      memory.learnSaved('/dilekce.udf', 'Tamamen başka bir cümle yazıldı');
      expect(memory.phrases.map((p) => p.text), [
        'Tamamen başka bir cümle yazıldı',
      ]);
    });

    test('taking a phrase counts; blocking hides it for good', () {
      memory.learnSaved('/a.udf', phrase);
      final key = memory.phrases.single.key;
      memory.accepted(key);
      expect(memory.phrases.single.accepted, 1);
      memory.block(key, phrase);
      expect(memory.phrases, isEmpty);
      memory.learnSaved('/b.udf', phrase);
      expect(memory.phrases, isEmpty);
      memory.unblock(key);
      expect(memory.phrases.single.saved, 2);
    });

    test('the archive teaches what is in at least three documents', () async {
      final dir = Directory.systemTemp.createTempSync('folio-oneri-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final index = '${dir.path}/evrak_index.sqlite';
      final db = sqlite3.open(index);
      db.execute(
        '''CREATE TABLE documents (id INTEGER PRIMARY KEY,
        extension TEXT, modified INTEGER, text TEXT, state TEXT, ocr INTEGER)''',
      );
      void add(
        String ext,
        String text, {
        int ocr = 0,
        String state = 'ready',
      }) => db.execute(
        'INSERT INTO documents(extension, modified, text, state, ocr) '
        'VALUES(?, 0, ?, ?, ?)',
        [ext, text, state, ocr],
      );
      const common = 'Yargılama giderlerinin davalıya yükletilmesine';
      const twice = 'Bu ifade yalnızca iki belgede geçiyor';
      add('udf', '$common. $twice.');
      add('docx', '$common. $twice.');
      add('pdf', common);
      // Read by OCR, or not read yet: not counted.
      add('pdf', 'Tarama ile okunmuş bir ifade burada', ocr: 1);
      add('udf', common, state: 'pending');
      db.dispose();

      expect(countArchive(index), [(foldPhrase(common), common, 3)]);
      expect(await memory.learnArchive(index), 1);
      expect(memory.phrases.single.archive, 3);
      expect(memory.archiveLearned, isNotNull);
    });
  });
}
