// Feeds synthesised Turkish speech through Folio's Vosk binding. Run on
// purpose: FOLIO_VOSK=<folder with libvosk.so, the model and *.pcm>.
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/voice/vosk.dart';

void main() {
  final dir = Platform.environment['FOLIO_VOSK'];
  test('wake phrase', () {
    final v = Vosk.forTest(
      DynamicLibrary.open('$dir/vosk-linux-x86_64-0.3.45/libvosk.so'),
    );
    final model = v.model('$dir/vosk-model-small-tr-0.3');
    const phrases = ['ajan açıl', 'merhaba ajan'];
    final own = {for (final f in phrases) ...f.split(' ')};
    for (final file in Directory(dir!).listSync().whereType<File>()) {
      if (!file.path.endsWith('.pcm')) continue;
      final r = v.recognizer(model, [
        ...phrases,
        ...voskDecoys.where((k) => !own.contains(k)),
      ]);
      final pcm = file.readAsBytesSync();
      final silence = Uint8List(16000); // half a second, to end it
      var woke = false;
      final heard = <String>[];
      for (final piece in [
        for (var i = 0; i < pcm.length; i += 3200)
          pcm.sublist(i, (i + 3200).clamp(0, pcm.length)),
        for (var i = 0; i < 6; i++) silence,
      ]) {
        final (text, ended, conf) = r.feed(Uint8List.fromList(piece));
        if (text.isNotEmpty) heard.add("${ended ? "SON" : "ara"}:$text");
        if (phrases.any(
          (f) => isWakePhrase(text, ended, f, voiced: 1.2, confidence: conf),
        )) {
          woke = true;
        }
      }
      r.close();
      debugPrint('${file.uri.pathSegments.last}: uyandı=$woke  duyulan=$heard');
    }
    v.freeModel(model);
  }, skip: dir == null);
}
