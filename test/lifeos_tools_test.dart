import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evrak_convert/services/voice/lifeos_tools.dart';

/// A stand-in `lifeos mcp sun`: lists a reading tool, a changing one and a
/// support one, and answers a call with the tool's name.
const _fake = r'''#!/usr/bin/env bash
while IFS= read -r line; do
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
  [ -z "$id" ] && continue
  case "$line" in
    *'"initialize"'*) echo '{"jsonrpc":"2.0","id":'$id',"result":{}}' ;;
    *'"tools/list"'*) echo '{"jsonrpc":"2.0","id":'$id',"result":{"tools":[
{"name":"esign","description":"E-imza","annotations":{"readOnlyHint":true}},
{"name":"support_fix","description":"Destek","annotations":{"readOnlyHint":false}},
{"name":"server_exec","description":"Sunucu","annotations":{"readOnlyHint":true}},
{"name":"printers","description":"Yazıcı","annotations":{"readOnlyHint":false}}]}}' | tr -d '\n'; echo ;;
    *'"tools/call"'*) echo '{"jsonrpc":"2.0","id":'$id',"result":{"content":[{"type":"text","text":"kart takili"}]}}' ;;
  esac
done
''';

void main() {
  late Directory dir;
  late LifeosTools tools;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('lifeos');
    final f = File('${dir.path}/lifeos')..writeAsStringSync(_fake);
    Process.runSync('chmod', ['+x', f.path]);
    tools = LifeosTools(executable: f.path);
  });
  tearDown(() {
    tools.close();
    dir.deleteSync(recursive: true);
  });

  test('only what reads this computer is given', () async {
    final names = [for (final t in await tools.declarations()) t['name']];
    expect(names, ['lifeos_esign']);
  });

  test('a call is answered; one not given is refused', () async {
    expect(await tools.call('lifeos_esign', {}), 'kart takili');
    final refused = jsonDecode(await tools.call('lifeos_support_fix', {}));
    expect(refused['durum'], 'izin_yok');
  });
}
