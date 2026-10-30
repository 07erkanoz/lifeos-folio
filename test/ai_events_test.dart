import 'dart:convert';

import 'package:evrak_convert/services/ai/ai_events.dart';
import 'package:evrak_convert/ui/ai/ai_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// What the programs say on their way to an answer, read as the lawyer sees
// it: Folio's tools called and done, what they think, the answer as it
// comes; and the answer drawn as Markdown.
void main() {
  String line(Object json) => jsonEncode(json);

  test('Claude: a tool started, its question, done; the answer by letters', () {
    final events = [
      for (final l in [
        line({
          'type': 'stream_event',
          'event': {'type': 'message_start'},
        }),
        line({
          'type': 'stream_event',
          'event': {
            'type': 'content_block_start',
            'content_block': {
              'type': 'tool_use',
              'id': 't1',
              'name': 'mcp__folio__mevzuat_madde',
            },
          },
        }),
        line({
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 't1',
                'name': 'mcp__folio__mevzuat_madde',
                'input': {'kanun': 'TBK', 'madde': '49'},
              },
            ],
          },
        }),
        line({
          'type': 'user',
          'message': {
            'content': [
              {'type': 'tool_result', 'tool_use_id': 't1'},
            ],
          },
        }),
        line({
          'type': 'stream_event',
          'event': {
            'type': 'content_block_delta',
            'delta': {'type': 'text_delta', 'text': 'TBK'},
          },
        }),
        line({
          'type': 'stream_event',
          'event': {
            'type': 'content_block_delta',
            'delta': {'type': 'thinking_delta', 'thinking': 'Madde…'},
          },
        }),
        'not json',
      ])
        ...AiEvents.claude(l),
    ];
    expect(
      events[0],
      isA<AiWriting>().having((w) => w.restart, 'restart', true),
    );
    expect((events[1] as AiStep).tool, 'mevzuat_madde');
    final asked = events[2] as AiStep;
    expect(asked.label, 'Kanun maddesi okunuyor · TBK m.49');
    final done = events[3] as AiStep;
    expect(done.done, isTrue);
    expect(done.id, 't1');
    expect((events[4] as AiWriting).text, 'TBK');
    expect((events[5] as AiThought).text, 'Madde…');
    expect(events, hasLength(6));
  });

  test('Codex and Antigravity: Folio\'s tools started and done, a remark '
      'on the way', () {
    final codex = [
      ...AiEvents.codex(
        line({
          'type': 'item.completed',
          'item': {'type': 'agent_message', 'text': 'Maddeyi arayacağım.'},
        }),
      ),
      ...AiEvents.codex(
        line({
          'type': 'item.started',
          'item': {
            'id': 'i1',
            'type': 'mcp_tool_call',
            'server': 'folio',
            'tool': 'ajanda',
            'arguments': {},
          },
        }),
      ),
      ...AiEvents.codex(
        line({
          'type': 'item.completed',
          'item': {
            'id': 'i1',
            'type': 'mcp_tool_call',
            'tool': 'ajanda',
            'arguments': {},
          },
        }),
      ),
    ];
    expect((codex[0] as AiThought).text, contains('Maddeyi arayacağım.'));
    expect((codex[1] as AiStep).label, 'Ajanda okunuyor');
    expect((codex[2] as AiStep).label, 'Ajanda okundu');

    final agy = AiEvents.antigravity(
      line({
        'event': 'step_update',
        'step_update': {
          'step_index': 4,
          'state': 'DONE',
          'tool_name': 'call_mcp_tool',
          'tool_info': {
            'parameters': {
              'ServerName': 'folio',
              'ToolName': 'karar_ara',
              'Arguments': {'sorgu': 'yıllık izin'},
            },
          },
        },
      }),
    );
    expect((agy.single as AiStep).label, 'Karar arşivi arandı · yıllık izin');
    expect(
      AiEvents.antigravity(
        line({
          'event': 'step_update',
          'step_update': {'tool_name': 'read_file'},
        }),
      ),
      isEmpty,
    );
  });

  testWidgets('an answer drawn: heading, bold, list and table', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiMarkdown(
              '## İtiraz\n\n'
              'Rapor **eksik** hesaplamış.\n\n'
              '- İhbar süresi\n- Yıllık izin\n\n'
              '| Kalem | Tutar |\n|---|---|\n| Kıdem | 189.000 TL |\n',
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('İtiraz'), findsOneWidget);
    expect(find.textContaining('eksik'), findsOneWidget);
    expect(find.textContaining('Yıllık izin'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.textContaining('189.000 TL'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
  });
}
