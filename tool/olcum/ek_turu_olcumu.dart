// Ölçüm: UETS eklerinin kaçının türü yalnız adından tanınıyor. Yalnız
// sayı yazar; ad ya da içerik yazmaz.
import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/legal/deadlines/belge_turu.dart';
import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  final db = sqlite3.open(args.single, mode: OpenMode.readOnly);
  var known = 0, unknown = 0;
  final kinds = <String, int>{};
  for (final row in db.select('SELECT attachments FROM uets_envelope')) {
    for (final a in jsonDecode(row['attachments'] as String? ?? '[]')) {
      final name = '${a['ad']}';
      if (name.toLowerCase().endsWith('.xml')) continue;
      final t = BelgeTuruTespit.ekTurleri([name]);
      if (t.isEmpty) {
        unknown++;
      } else {
        known++;
        kinds.update(t.single.tur.name, (v) => v + 1, ifAbsent: () => 1);
      }
    }
  }
  stdout.writeln('tanınan $known, tanınmayan $unknown');
  stdout.writeln(kinds);
}
