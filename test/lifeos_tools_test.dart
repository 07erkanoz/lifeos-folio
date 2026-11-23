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
  late File fake;
  late LifeosTools tools;
  final asked = <String>[];
  bool? answer;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('lifeos');
    fake = File('${dir.path}/lifeos')..writeAsStringSync(_fake);
    Process.runSync('chmod', ['+x', fake.path]);
    asked.clear();
    answer = true;
    tools = LifeosTools(
      executable: fake.path,
      approve: (title, detail) async {
        asked.add('$title|$detail');
        return answer;
      },
    );
  });
  tearDown(() {
    tools.close();
    dir.deleteSync(recursive: true);
  });

  test('every tool is given; those that change are marked so', () async {
    final declared = {
      for (final t in await tools.declarations())
        t['name']: (t['annotations'] as Map)['readOnlyHint'],
    };
    expect(declared, {
      'lifeos_esign': true,
      'lifeos_support_fix': false,
      // Runs any command: not read-only, whatever LifeOS says.
      'lifeos_server_exec': false,
      'lifeos_printers': false,
    });
  });

  test('a reading tool runs without asking', () async {
    expect(await tools.call('lifeos_esign', {}), 'kart takili');
    expect(asked, isEmpty);
  });

  test('a changing tool runs only after the yes', () async {
    expect(
      await tools.call('lifeos_server_exec', {
        'name': 'sunucu2',
        'command': 'uptime',
      }),
      'kart takili',
    );
    expect(asked, ['server_exec|name: sunucu2\ncommand: uptime']);

    answer = false;
    final no = jsonDecode(await tools.call('lifeos_support_fix', {}));
    expect(no['durum'], 'onaylanmadi');

    answer = null;
    final none = jsonDecode(await tools.call('lifeos_printers', {}));
    expect(none['durum'], 'onay_sorulamadi');
  });

  test('without an approver nothing that changes runs', () async {
    final bare = LifeosTools(executable: fake.path);
    addTearDown(bare.close);
    final r = jsonDecode(await bare.call('lifeos_support_fix', {}));
    expect(r['durum'], 'onay_sorulamadi');
  });

  test('a tool LifeOS does not list is refused', () async {
    final r = jsonDecode(await tools.call('lifeos_yok', {}));
    expect(r['durum'], 'yok');
  });
}
