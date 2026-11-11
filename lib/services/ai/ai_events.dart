import 'dart:convert';

/// What the lawyer's AI program does on its way to the answer, as Folio
/// shows it while it works: a tool of Folio's it calls ([AiStep]), what it
/// thinks or remarks on the way ([AiThought]), and the answer as it writes
/// it ([AiWriting]).
sealed class AiEvent {
  const AiEvent();
}

class AiStep extends AiEvent {
  const AiStep(this.id, this.tool, {this.args = const {}, this.done = false});
  final String id, tool;
  final Map<String, Object?> args;
  final bool done;

  /// The step as the lawyer reads it: "Kanun maddesi okunuyor · TBK m.49",
  /// in the past once done.
  String get label {
    final (now, past) = _labels[tool] ?? ('$tool çalışıyor', '$tool çalıştı');
    final what = switch (tool) {
      'mevzuat_madde' => '${args['kanun'] ?? ''} m.${args['madde'] ?? ''}',
      'mevzuat_icindekiler' ||
      'mevzuat_ara' => '${args['kanun'] ?? args['ifade'] ?? ''}',
      'karar_ara' => '${args['sorgu'] ?? ''}',
      'karar_getir' => '${args['kunye'] ?? ''}',
      'dosya_ara' || 'dosyalar' => '${args['ifade'] ?? ''}',
      'uyap_guncelle' => '${args['kapsam'] ?? ''}',
      _ => '',
    }.trim();
    return [
      done ? past : now,
      if (what.isNotEmpty && what != 'm.') what,
    ].join(' · ');
  }

  /// What the step looked at, as the lawyer counts them under an answer:
  /// "mevzuat", "karar", "evrak", "dosya", "ajanda"; empty for the rest.
  String get kind => switch (tool) {
    'mevzuat_madde' || 'mevzuat_icindekiler' || 'mevzuat_ara' => 'mevzuat',
    'karar_ara' || 'karar_getir' => 'karar',
    'evrak_oku' => 'evrak',
    'dosya_bilgisi' ||
    'dosya_evraklari' ||
    'dosya_hafizasi' ||
    'dosya_ara' ||
    'dosya_sec' ||
    'dosyalar' => 'dosya',
    'ajanda' || 'tebligatlar' || 'uyap_bildirimleri' => 'ajanda',
    _ => '',
  };

  static const _labels = {
    'mevzuat_madde': ('Kanun maddesi okunuyor', 'Kanun maddesi okundu'),
    'mevzuat_icindekiler': (
      'Kanunun içindekiler okunuyor',
      'Kanunun içindekiler okundu',
    ),
    'mevzuat_ara': ('Kanun aranıyor', 'Kanun arandı'),
    'karar_ara': ('Karar arşivi aranıyor', 'Karar arşivi arandı'),
    'karar_getir': ('Kararın metni okunuyor', 'Kararın metni okundu'),
    'atif_dogrula': ('Atıflar denetleniyor', 'Atıflar denetlendi'),
    'dosya_bilgisi': (
      'Dosyanın bilgileri okunuyor',
      'Dosyanın bilgileri okundu',
    ),
    'dosya_evraklari': ('Evrak listesi okunuyor', 'Evrak listesi okundu'),
    'evrak_oku': ('Evrak okunuyor', 'Evrak okundu'),
    'evrak_indir': ('Evrak indirme isteniyor', 'Evrak indirme istendi'),
    'dosya_hafizasi': ('Dosya hafızası okunuyor', 'Dosya hafızası okundu'),
    'bulgu_oner': ('Bulgular hazırlanıyor', 'Bulgular hazırlandı'),
    'taslak_oner': ('Belge hazırlanıyor', 'Belge hazırlandı'),
    'dosya_ara': ('Dosya aranıyor', 'Dosya arandı'),
    'dosya_sec': ('Dosya bağlanıyor', 'Dosya bağlandı'),
    'ajanda': ('Ajanda okunuyor', 'Ajanda okundu'),
    'tebligatlar': ('Tebligatlar okunuyor', 'Tebligatlar okundu'),
    'uyap_bildirimleri': (
      'UYAP bildirimleri okunuyor',
      'UYAP bildirimleri okundu',
    ),
    'dosyalar': ('Dosya listesi okunuyor', 'Dosya listesi okundu'),
    'uyap_baglantilari': (
      'UYAP bağlantıları okunuyor',
      'UYAP bağlantıları okundu',
    ),
    'uyap_guncelle': ('UYAP’tan güncelleniyor', 'UYAP’tan güncellendi'),
  };
}

class AiThought extends AiEvent {
  const AiThought(this.text);
  final String text;
}

/// The answer's text as it comes; [restart] when a new message begins
/// (what came before was a remark on the way).
class AiWriting extends AiEvent {
  const AiWriting(this.text, {this.restart = false});
  final String text;
  final bool restart;
}

/// How much of the lawyer's allowance with the program is used, as the
/// program itself says on the way: by window ("five_hour", "seven_day"),
/// each from 0 to 1.
class AiQuota extends AiEvent {
  const AiQuota(this.used);
  final Map<String, double> used;

  /// The fullest window, as the lawyer reads it: "Haftalık %42".
  String? get label {
    if (used.isEmpty) return null;
    final most = used.entries.reduce((a, b) => b.value > a.value ? b : a);
    final name = switch (most.key) {
      'five_hour' => '5 saatlik',
      'seven_day' => 'Haftalık',
      _ => 'Kullanım',
    };
    return '$name %${(most.value * 100).round()}';
  }

  /// The fullest window's share, from 0 to 1.
  double get most =>
      used.values.fold<double>(0, (a, b) => b > a ? b : a).clamp(0.0, 1.0);
}

/// One line of a program's output read for its events.
abstract final class AiEvents {
  static const _prefix = 'mcp__folio__';

  static String _tool(String name) =>
      name.startsWith(_prefix) ? name.substring(_prefix.length) : name;

  static Map<String, Object?> _map(Object? v) =>
      v is Map ? v.cast<String, Object?>() : const {};

  /// Claude Code's stream-json line.
  static List<AiEvent> claude(String line) {
    final e = _decode(line);
    if (e == null) return const [];
    switch (e['type']) {
      case 'rate_limit_event':
        final windows = _map(_map(e['rate_limit_info'])['unifiedWindows']);
        final used = {
          for (final w in windows.entries)
            if (_map(w.value)['utilization'] case final num u)
              w.key: u.toDouble(),
        };
        return used.isEmpty ? const [] : [AiQuota(used)];
      case 'stream_event':
        final ev = _map(e['event']);
        switch (ev['type']) {
          case 'message_start':
            return const [AiWriting('', restart: true)];
          case 'content_block_start':
            final block = _map(ev['content_block']);
            if (block['type'] == 'tool_use') {
              return [AiStep('${block['id']}', _tool('${block['name']}'))];
            }
          case 'content_block_delta':
            final d = _map(ev['delta']);
            if (d['type'] == 'text_delta') return [AiWriting('${d['text']}')];
            if (d['type'] == 'thinking_delta') {
              return [AiThought('${d['thinking']}')];
            }
        }
      case 'assistant':
        return [
          for (final c in (_map(e['message'])['content'] as List? ?? const []))
            if (c is Map && c['type'] == 'tool_use')
              AiStep(
                '${c['id']}',
                _tool('${c['name']}'),
                args: _map(c['input']),
              ),
        ];
      case 'user':
        return [
          for (final c in (_map(e['message'])['content'] as List? ?? const []))
            if (c is Map && c['type'] == 'tool_result')
              AiStep('${c['tool_use_id']}', '', done: true),
        ];
    }
    return const [];
  }

  /// Codex's --json line.
  static List<AiEvent> codex(String line) {
    final e = _decode(line);
    if (e == null) return const [];
    final item = _map(e['item']);
    switch ((e['type'], item['type'])) {
      case ('item.started', 'mcp_tool_call'):
        return [
          AiStep(
            '${item['id']}',
            '${item['tool']}',
            args: _map(item['arguments']),
          ),
        ];
      case ('item.completed', 'mcp_tool_call'):
        return [
          AiStep(
            '${item['id']}',
            '${item['tool']}',
            args: _map(item['arguments']),
            done: true,
          ),
        ];
      case ('item.completed', 'agent_message' || 'reasoning'):
        final text = '${item['text'] ?? ''}'.trim();
        return text.isEmpty ? const [] : [AiThought('$text\n\n')];
    }
    return const [];
  }

  /// Antigravity's stream-json line.
  static List<AiEvent> antigravity(String line) {
    final e = _decode(line);
    if (e == null || e['event'] != 'step_update') return const [];
    final step = _map(e['step_update']);
    if (step['tool_name'] != 'call_mcp_tool') return const [];
    final info = _map(_map(step['tool_info'])['parameters']);
    if (info['ServerName'] != 'folio') return const [];
    return [
      AiStep(
        '${step['step_index']}',
        '${info['ToolName']}',
        args: _map(info['Arguments']),
        done: step['state'] == 'DONE',
      ),
    ];
  }

  static Map<String, Object?>? _decode(String line) {
    if (!line.startsWith('{')) return null;
    try {
      final e = jsonDecode(line);
      return e is Map ? e.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    }
  }
}
