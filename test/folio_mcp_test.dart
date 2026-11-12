import 'dart:convert';
import 'dart:io';

import 'package:evrak_convert/services/ai/ai_assistant.dart';
import 'package:evrak_convert/services/ai/folio_mcp.dart';
import 'package:evrak_convert/services/legal/citation.dart';
import 'package:evrak_convert/services/legal/decision.dart';
import 'package:flutter_test/flutter_test.dart';

// Folio's own tools for the lawyer's AI program: the protocol spoken, the
// tools only reading, a law found by number, abbreviation or name, and
// nothing made up when nothing is found.
void main() {
  final laws = CitationScanner.parse(
    File('assets/mevzuat/laws.json').readAsStringSync(),
  );
  final courts = DecisionScanner.parse(
    File('assets/mevzuat/courts.json').readAsStringSync(),
  );
  FolioMcp server() =>
      FolioMcp(laws: () async => laws, courts: () async => courts);

  test(
    'the protocol: introduced, its tools listed, every one only reading',
    () async {
      final mcp = server();
      final hello = (await mcp.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': FolioMcp.protocol},
      }))!;
      final result = hello['result'] as Map;
      expect(result['protocolVersion'], FolioMcp.protocol);
      expect((result['serverInfo'] as Map)['name'], 'folio');
      expect(result['instructions'], contains('uydurma'));
      // A notification is answered by nothing.
      expect(
        await mcp.handle({
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        }),
        isNull,
      );
      final listed = (await mcp.handle({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
      }))!;
      final tools = ((listed['result'] as Map)['tools'] as List).cast<Map>();
      expect(
        tools.map((t) => t['name']),
        containsAll([
          'mevzuat_madde',
          'mevzuat_icindekiler',
          'mevzuat_ara',
          'karar_ara',
          'karar_getir',
          'atif_dogrula',
        ]),
      );
      for (final t in tools) {
        expect((t['annotations'] as Map)['readOnlyHint'], isTrue);
        expect(t['inputSchema'], isA<Map>());
      }
      final unknown = (await mcp.handle({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'resources/list',
      }))!;
      expect((unknown['error'] as Map)['code'], -32601);
      final badTool = (await mcp.handle({
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'tools/call',
        'params': {'name': 'dosya_sil', 'arguments': {}},
      }))!;
      expect((badTool['error'] as Map)['code'], -32602);
    },
  );

  test(
    'a law found by its number, its abbreviation or words of its name',
    () async {
      final mcp = server();
      final byWords = await mcp.call('mevzuat_ara', {
        'ifade': 'borçlar kanunu',
      });
      expect(byWords['durum'], 'bulundu');
      expect(
        (byWords['kanunlar'] as List).map((l) => (l as Map)['kanun_no']),
        contains(6098),
      );
      final byShort = await mcp.call('mevzuat_ara', {'ifade': 'HMK'});
      expect(
        (byShort['kanunlar'] as List).single,
        containsPair('kanun_no', 6100),
      );
      final byNumber = await mcp.call('mevzuat_ara', {'ifade': '2004'});
      expect(
        (byNumber['kanunlar'] as List).single,
        containsPair('kanun_no', 2004),
      );
      final none = await mcp.call('mevzuat_ara', {
        'ifade': 'olmayan zzz kanunu',
      });
      expect(none['durum'], 'yok');
    },
  );

  test('nothing found is said so, never filled in', () async {
    final mcp = server();
    final unknownLaw = await mcp.call('mevzuat_madde', {
      'kanun': 'Uydurma Kanunu',
      'madde': '5',
    });
    expect(unknownLaw['durum'], 'yok');
    expect(unknownLaw.containsKey('metin'), isFalse);
    final noArticle = await mcp.call('mevzuat_madde', {
      'kanun': 'TBK',
      'madde': 'dokuz',
    });
    expect(noArticle['durum'], 'yok');
    // A decision's id is taken only from this session's search.
    final made = await mcp.call('karar_getir', {'kimlik': 'karar:X:123'});
    expect(made['durum'], 'yok');
    final unread = await mcp.call('karar_getir', {'kunye': 'bir karar'});
    expect(unread['durum'], 'yok');
    final empty = await mcp.call('atif_dogrula', {'metin': 'Atıf yok.'});
    expect(empty['atiflar'], isEmpty);
  });

  test('a decision with no court, or another court, beside it is said to '
      'be so', () async {
    final got = await server().call('atif_dogrula', {
      'metin':
          'Yargıtay HGK, davayı asliye ticarete gönderen direnme kararını '
          'onadı (E.2017/2348 K.2019/82, 07.02.2019).',
    });
    // The nearest court named is where the case was sent: said, so that
    // the program can name the right one.
    final one = (got['atiflar'] as List).single as Map;
    expect(one['durum'], 'yayimlanmamis');
    expect(one['mahkeme'], 'asliye ticaret');
    final bare = await server().call('atif_dogrula', {
      'metin': 'Bkz. (E.2017/2348 K.2019/82).',
    });
    expect(
      ((bare['atiflar'] as List).single as Map)['durum'],
      'mahkeme_belirsiz',
    );
  });

  test('Claude and Codex are given Folio\'s tools and no others; '
      'Antigravity is not given them', () {
    final claude = AiAssistant.arguments(
      AiProvider.claude,
      '/tmp/x',
      folio: '/opt/folio/lifeos_folio',
    );
    final config = claude[claude.indexOf('--mcp-config') + 1];
    expect(config, contains('"command":"/opt/folio/lifeos_folio"'));
    expect(config, contains('"args":["--mcp"]'));
    final allowed = claude[claude.indexOf('--allowedTools') + 1];
    expect(allowed.split(','), everyElement(startsWith('mcp__folio__')));
    expect(allowed, contains('mcp__folio__mevzuat_madde'));
    // Its built-in tools stay off.
    expect(claude[claude.indexOf('--tools') + 1], '');
    expect(claude, contains('--strict-mcp-config'));

    final codex = AiAssistant.arguments(
      AiProvider.codex,
      '/tmp/x',
      folio: '/opt/folio/lifeos_folio',
    );
    expect(
      codex,
      contains('mcp_servers.folio.command="/opt/folio/lifeos_folio"'),
    );
    expect(codex, contains('mcp_servers.folio.args=["--mcp"]'));
    expect(codex.any((a) => a.startsWith('mcp_servers.folio.env={')), isTrue);
    expect(AiAssistant.takesTools(AiProvider.antigravity), isFalse);
    // Antigravity's own list holds them; for the question Folio's are let
    // through, and no command or file written.
    final agy = AiAssistant.arguments(
      AiProvider.antigravity,
      '/tmp/x',
      folio: '/opt/folio/lifeos_folio',
    );
    final settings =
        jsonDecode(agy[agy.indexOf('--settings') + 1]) as Map<String, dynamic>;
    expect(settings['permissions']['allow'], ['mcp(folio/*)']);
    expect(
      settings['permissions']['deny'],
      containsAll(['command(*)', 'write_file(*)']),
    );
    final bare = AiAssistant.arguments(AiProvider.antigravity, '/tmp/x');
    expect(
      (jsonDecode(bare[bare.indexOf('--settings') + 1])
          as Map)['permissions']['allow'],
      isEmpty,
    );
    // Without Folio's program (a test), none.
    expect(
      AiAssistant.arguments(AiProvider.claude, '/tmp/x'),
      isNot(contains('--mcp-config')),
    );
  });

  test('Folio on Antigravity\'s list: only when there, turned on and given '
      'its flag', () async {
    final dir = await Directory.systemTemp.createTemp('agy-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/mcp_config.json');
    Future<String?> listed(Object? json) async {
      await file.writeAsString(json is String ? json : jsonEncode(json));
      return AiAssistant.antigravityFolio(file);
    }

    expect(await AiAssistant.antigravityFolio(file), isNull);
    expect(await listed(''), isNull);
    expect(
      await listed({
        'mcpServers': {
          'folio': {
            'command': '/opt/folio/lifeos_folio',
            'args': ['--mcp'],
            'disabled': false,
          },
        },
      }),
      '/opt/folio/lifeos_folio',
    );
    expect(
      await listed({
        'mcpServers': {
          'folio': {
            'command': '/opt/folio/lifeos_folio',
            'args': ['--mcp'],
            'disabled': true,
          },
        },
      }),
      isNull,
    );
    expect(
      await listed({
        'mcpServers': {
          'folio': {'command': '/usr/bin/npx', 'args': []},
        },
      }),
      isNull,
    );
  });
}
