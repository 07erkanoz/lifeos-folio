import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:path/path.dart' as p;

import '../pdf/pdf_pages.dart';
import '../platform/app_directories.dart';
import '../platform/atomic_file.dart';
import '../search/text_extractor.dart';
import 'ai_prompts.dart';
import 'folio_mcp.dart';

export 'ai_prompts.dart';

/// The AI programs a lawyer may have on this computer, each signed in with
/// the lawyer's own subscription. Folio runs them itself, with no terminal:
/// read-only, every tool turned off, in an empty folder, given only the text
/// Folio took out of the document the lawyer chose.
enum AiProvider {
  claude(
    'claude',
    'Claude',
    'Anthropic',
    'https://claude.com/product/claude-code',
  ),
  codex(
    'codex',
    'Codex (ChatGPT)',
    'OpenAI',
    'https://developers.openai.com/codex/cli',
  ),
  antigravity(
    'agy',
    'Google Antigravity',
    'Google',
    'https://antigravity.google',
  );

  const AiProvider(this.command, this.label, this.company, this.installPage);

  /// The program's name on the PATH.
  final String command;
  final String label;

  /// Who the text goes to.
  final String company;

  /// Its maker's page on how to install it, for a Linux without LifeOS's
  /// Store.
  final String installPage;

  /// Whether Folio can sign the lawyer in itself; Antigravity asks only in
  /// its own screen, the first time it is run.
  bool get signsInFromFolio => this != AiProvider.antigravity;

  /// Its page in LifeOS Mağaza (`lifeos-magaza --uygulama …`).
  String get storeId => switch (this) {
    AiProvider.claude => 'lifeos:claude-code',
    AiProvider.codex => 'lifeos:codex-cli',
    AiProvider.antigravity => 'lifeos:antigravity-cli',
  };

  /// The model each tier runs, unless the lawyer chose another.
  String defaultModel(AiTier tier) => switch ((this, tier)) {
    (AiProvider.claude, AiTier.normal) => 'sonnet',
    (AiProvider.claude, AiTier.strong) => 'opus',
    (AiProvider.codex, AiTier.normal) => 'gpt-6-luna',
    (AiProvider.codex, AiTier.strong) => 'gpt-6.1-sol',
    (AiProvider.antigravity, AiTier.normal) => 'gemini-3.8-flash-medium',
    (AiProvider.antigravity, AiTier.strong) => 'gemini-4-argon-high',
  };
}

/// What Folio found of one [AiProvider].
class AiStatus {
  const AiStatus(this.provider, {this.path, this.signedIn, this.account});

  final AiProvider provider;

  /// The program, when installed.
  final String? path;

  /// Whether a session is open; null when the program cannot say
  /// (Antigravity), and found out at the first question.
  final bool? signedIn;

  /// The account, when the program names it.
  final String? account;

  bool get installed => path != null;

  /// Whether it is worth offering: installed, and not known to be signed
  /// out.
  bool get usable => installed && signedIn != false;
}

/// A question Folio could not get answered, said in Turkish.
class AiFailure implements Exception {
  const AiFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract final class AiAssistant {
  /// Linux only, for now; and not in a test, which runs no real program
  /// unless it asks ([availableForTest]).
  static bool get available =>
      availableForTest ??
      (Platform.isLinux && !Platform.environment.containsKey('FLUTTER_TEST'));

  @visibleForTesting
  static bool? availableForTest;

  /// The most of a document's text sent: the rest is left out, and said so.
  static const maxCharacters = 200000;

  /// How long one answer may take.
  static const timeout = Duration(minutes: 4);

  /// Where the programs are looked for: the PATH Folio was started with
  /// (a desktop's is often short) and where their installers put them.
  @visibleForTesting
  static List<String> searchPath(Map<String, String> env) {
    final home = env['HOME'] ?? '';
    return {
      ...(env['PATH'] ?? '').split(':').where((d) => d.isNotEmpty),
      if (home.isNotEmpty) ...[
        p.join(home, '.local', 'bin'),
        p.join(home, '.npm-global', 'bin'),
        p.join(home, '.bun', 'bin'),
        p.join(home, '.volta', 'bin'),
      ],
      '/usr/local/bin',
      '/usr/bin',
    }.toList();
  }

  static String? find(String command, [Map<String, String>? environment]) {
    for (final dir in searchPath(environment ?? Platform.environment)) {
      final file = File(p.join(dir, command));
      if (file.existsSync()) return file.path;
    }
    return null;
  }

  /// The program's environment: the PATH it is found under made whole.
  static Map<String, String> environment() {
    final env = Map<String, String>.of(Platform.environment);
    env['PATH'] = searchPath(env).join(':');
    // No colours or progress for a reader that is not a terminal.
    env['NO_COLOR'] = '1';
    return env;
  }

  /// LifeOS Mağaza, when this is LifeOS: a missing program is installed
  /// from it rather than its maker's page.
  static bool get hasStore => find('lifeos-magaza') != null;

  /// Mağaza at [provider]'s page.
  static Future<void> openStore(AiProvider provider) async {
    final path = find('lifeos-magaza');
    if (path == null) return;
    await Process.start(path, [
      '--uygulama',
      provider.storeId,
    ], mode: ProcessStartMode.detached);
  }

  /// What each program says of itself.
  static Future<AiStatus> status(AiProvider provider) async {
    final path = find(provider.command);
    if (path == null) return AiStatus(provider);
    try {
      switch (provider) {
        case AiProvider.claude:
          final r = await Process.run(path, [
            'auth',
            'status',
            '--json',
          ], environment: environment()).timeout(const Duration(seconds: 20));
          final json = jsonDecode('${r.stdout}');
          if (json is! Map) return AiStatus(provider, path: path);
          return AiStatus(
            provider,
            path: path,
            signedIn: json['loggedIn'] == true,
            account: json['email'] as String?,
          );
        case AiProvider.codex:
          final r = await Process.run(path, [
            'login',
            'status',
          ], environment: environment()).timeout(const Duration(seconds: 20));
          final said = '${r.stdout}\n${r.stderr}'.toLowerCase();
          return AiStatus(
            provider,
            path: path,
            signedIn:
                said.contains('logged in') && !said.contains('not logged'),
          );
        case AiProvider.antigravity:
          return AiStatus(provider, path: path);
      }
    } catch (_) {
      return AiStatus(provider, path: path);
    }
  }

  static Future<List<AiStatus>> statuses() =>
      Future.wait([for (final p in AiProvider.values) status(p)]);

  /// The arguments that run [provider] once, read-only and with every tool
  /// it has turned off; the question comes on its standard input.
  @visibleForTesting
  static List<String> arguments(
    AiProvider provider,
    String folder, {
    String? model,
    String? folio,
  }) => switch (provider) {
    AiProvider.claude => [
      '-p',
      // Folio's rules in place of the program's own coding persona.
      '--system-prompt',
      AiPrompts.core,
      if (model != null && model.isNotEmpty) ...['--model', model],
      // Folio's own tools, and no others.
      if (folio != null) ...[
        '--mcp-config',
        jsonEncode({
          'mcpServers': {
            'folio': {
              'type': 'stdio',
              'command': folio,
              'args': [FolioMcp.flag],
            },
          },
        }),
        '--allowedTools',
        [for (final t in FolioMcp.tools) 'mcp__folio__${t['name']}'].join(','),
      ],
      '--output-format',
      'json',
      '--tools',
      '',
      '--restricted',
      '--strict-mcp-config',
      '--no-session-persistence',
      '--disable-slash-commands',
    ],
    AiProvider.codex => [
      'exec',
      '--json',
      '--ephemeral',
      '--ignore-user-config',
      '--skip-git-repo-check',
      '-s',
      'read-only',
      '-C',
      folder,
      // Read-only stops writing, not reading: every tool goes, the
      // shell's and the web's included (a document's words could
      // otherwise send it somewhere).
      for (final feature in const [
        'shell_tool',
        'unified_exec',
        'browser_use',
        'browser_use_external',
        'computer_use',
        'in_app_browser',
        'apps',
        'multi_agent',
        'plugins',
        'image_generation',
        'view_image',
      ]) ...['--disable', feature],
      '-c',
      'web_search="disabled"',
      '-c',
      'include_environment_context=false',
      '-c',
      'include_permissions_instructions=false',
      // Folio's rules in place of the coding agent's instructions.
      '-c',
      'model_instructions_file="${p.join(folder, 'talimat.md')}"',
      if (model != null && model.isNotEmpty) ...['-m', model],
      // Folio's own tools. Codex gives a tool's program none of its own
      // surroundings: the display and Folio's folders are passed on.
      if (folio != null) ...[
        '-c',
        'mcp_servers.folio.command=${jsonEncode(folio)}',
        '-c',
        'mcp_servers.folio.args=${jsonEncode([FolioMcp.flag])}',
        '-c',
        'mcp_servers.folio.startup_timeout_sec=30',
        '-c',
        'mcp_servers.folio.env={${[for (final key in mcpEnvironment)
          if (Platform.environment[key] case final v?) '$key=${jsonEncode(v)}'].join(',')}}',
      ],
      '-o',
      p.join(folder, '.yanit.txt'),
      '-',
    ],
    AiProvider.antigravity => [
      '--input-format',
      'stream-json',
      '--output-format',
      'stream-json',
      '--sandbox',
      '--disable-slash-commands',
      '--print-timeout',
      '${timeout.inSeconds}s',
      if (model != null && model.isNotEmpty) ...['--model', model],
      // Written with its (empty) value: apart, agy takes the next flag
      // for the prompt.
      '--print=',
    ],
  };

  /// What Folio's MCP server needs of its surroundings: a display for the
  /// engine, the folders Folio keeps its caches in.
  static const mcpEnvironment = [
    'DISPLAY',
    'WAYLAND_DISPLAY',
    'XAUTHORITY',
    'XDG_RUNTIME_DIR',
    'HOME',
    'XDG_DATA_HOME',
    'XDG_CONFIG_HOME',
    'XDG_CACHE_HOME',
  ];

  /// Whether [provider] can be given Folio's tools for one question:
  /// Antigravity keeps its MCP servers in a settings file of its own, for
  /// every session, which Folio does not change.
  static bool takesTools(AiProvider provider) =>
      provider != AiProvider.antigravity;

  /// The program Folio's tools run as: this Folio, given [FolioMcp.flag].
  /// Null in a test, whose program is not Folio.
  static String? get folioProgram =>
      Platform.environment.containsKey('FLUTTER_TEST')
      ? null
      : Platform.resolvedExecutable;

  /// [prompt] as [provider] reads it on its standard input.
  @visibleForTesting
  static String input(AiProvider provider, String prompt) => switch (provider) {
    AiProvider.antigravity =>
      // It takes no instructions of its own: Folio's rules lead the message.
      '${jsonEncode({
        'event': 'user',
        'message': {'role': 'user', 'content': '${AiPrompts.core}\n\n$prompt'},
      })}\n',
    _ => prompt,
  };

  /// The answer in [stdout] (and, for Codex, its [lastMessage] file).
  @visibleForTesting
  static String answer(
    AiProvider provider,
    String stdout,
    String? lastMessage,
  ) {
    switch (provider) {
      case AiProvider.claude:
        final Object? json;
        try {
          json = jsonDecode(stdout.trim());
        } on FormatException {
          throw const AiFailure('Claude’ın yanıtı okunamadı.');
        }
        if (json is! Map) throw const AiFailure('Claude’ın yanıtı okunamadı.');
        final result = '${json['result'] ?? ''}'.trim();
        if (json['is_error'] == true) {
          throw AiFailure(_said(result, 'Claude'));
        }
        return plain(result);
      case AiProvider.codex:
        final text = (lastMessage ?? '').trim();
        if (text.isNotEmpty) return plain(text);
        for (final line in stdout.split('\n').reversed) {
          if (!line.startsWith('{')) continue;
          try {
            final e = jsonDecode(line);
            if (e is Map && e['type'] == 'error') {
              throw AiFailure(_said('${e['message'] ?? ''}', 'Codex'));
            }
          } on FormatException {
            continue;
          }
        }
        throw const AiFailure('Codex yanıt vermedi.');
      case AiProvider.antigravity:
        for (final line in stdout.split('\n').reversed) {
          if (!line.startsWith('{')) continue;
          try {
            final e = jsonDecode(line);
            if (e is! Map || e['event'] != 'result') continue;
            final r = e['result'];
            if (r is Map) {
              if (r['status'] != 'SUCCESS') {
                throw AiFailure(
                  _said('${r['error'] ?? r['status']}', 'Antigravity'),
                );
              }
              return plain('${r['response'] ?? ''}');
            }
          } on FormatException {
            continue;
          }
        }
        throw const AiFailure('Antigravity yanıt vermedi.');
    }
  }

  /// [text] without the marks of Markdown a program writes anyway
  /// (bold, headings, code fences): Folio shows it as plain text.
  static String plain(String text) => text
      .replaceAll(RegExp(r'\*\*|__'), '')
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^```\w*\s*$', multiLine: true), '')
      .trim();

  static String _said(String what, String who) {
    final lower = what.toLowerCase();
    if (lower.contains('login') ||
        lower.contains('log in') ||
        lower.contains('auth') ||
        lower.contains('sign in') ||
        lower.contains('unauthorized')) {
      return '$who’da oturum açık değil. Ayarlar › Yapay zekâ’dan oturum açın.';
    }
    if (lower.contains('limit') || lower.contains('quota')) {
      return '$who kullanım sınırınız dolmuş görünüyor. Daha sonra yeniden deneyin.';
    }
    return what.isEmpty ? '$who yanıt veremedi.' : '$who yanıt veremedi: $what';
  }

  /// [prompt] answered by [provider]; [cancel] completed stops it.
  static Future<String> ask(
    AiProvider provider,
    String prompt, {
    String? model,
    bool tools = true,
    Future<void>? cancel,
  }) async {
    final path = find(provider.command);
    if (path == null) {
      throw AiFailure('${provider.label} bu bilgisayarda kurulu değil.');
    }
    // An empty folder of its own: nothing of the lawyer's for it to see.
    final folder = await Directory.systemTemp.createTemp('folio-yz-');
    try {
      if (provider == AiProvider.codex) {
        await File(p.join(folder.path, 'talimat.md'))
            .writeAsString(AiPrompts.core);
      }
      final process = await Process.start(
        path,
        arguments(
          provider,
          folder.path,
          model: model,
          folio: tools && takesTools(provider) ? folioProgram : null,
        ),
        workingDirectory: folder.path,
        environment: environment(),
      );
      final out = StringBuffer();
      final err = StringBuffer();
      final reading = Future.wait([
        process.stdout.transform(utf8.decoder).forEach(out.write),
        process.stderr.transform(utf8.decoder).forEach(err.write),
      ]);
      process.stdin.write(input(provider, prompt));
      await process.stdin.close();
      var stopped = false;
      unawaited(
        cancel?.then((_) {
          stopped = true;
          process.kill();
        }),
      );
      final code = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill();
          throw AiFailure(
            '${provider.label} ${timeout.inMinutes} dakikada yanıt vermedi.',
          );
        },
      );
      await reading;
      if (stopped) throw const AiFailure('Durduruldu.');
      final last = File(p.join(folder.path, '.yanit.txt'));
      final lastMessage = await last.exists()
          ? await last.readAsString()
          : null;
      try {
        return answer(provider, '$out', lastMessage);
      } on AiFailure {
        if (code != 0 && err.isNotEmpty) {
          throw AiFailure(_said(_lastLine('$err'), provider.label));
        }
        rethrow;
      }
    } finally {
      unawaited(
        folder.delete(recursive: true).catchError((Object _) => folder),
      );
    }
  }

  static String _lastLine(String text) => text
      .split('\n')
      .map((l) => l.trim())
      .lastWhere(
        (l) => l.isNotEmpty && !l.startsWith('WARNING'),
        orElse: () => '',
      );

  /// The message for [task] about the document [name] whose [text] Folio
  /// took out; [history] the questions and answers before it. Folio's
  /// rules ([AiPrompts.core]) go apart, as the program's instructions.
  static String prompt({
    required AiTask task,
    required String name,
    required String text,
    String question = '',
    List<({String question, String answer})> history = const [],
  }) {
    final cut = text.length > maxCharacters;
    final body = cut ? text.substring(0, maxCharacters) : text;
    return [
      '<belge ad="${name.replaceAll('"', "'")}">',
      body,
      if (cut) '[Belgenin geri kalanı uzunluğu yüzünden gönderilmedi.]',
      '</belge>',
      for (final h in history) ...[
        '',
        'Önceki soru: ${h.question}',
        'Önceki yanıt: ${h.answer}',
      ],
      '',
      AiPrompts.task(task, question: question),
    ].join('\n');
  }

  /// The models [provider] offers, for the lawyer to choose from: Claude's
  /// names that always lead to its newest, the others' own lists.
  static Future<List<String>> models(AiProvider provider) async {
    try {
      switch (provider) {
        case AiProvider.claude:
          return const ['fable', 'opus', 'sonnet', 'haiku'];
        case AiProvider.codex:
          final home =
              Platform.environment['CODEX_HOME'] ??
              p.join(Platform.environment['HOME'] ?? '', '.codex');
          final cache = File(p.join(home, 'models_cache.json'));
          if (!await cache.exists()) return const [];
          final json = jsonDecode(await cache.readAsString());
          final list = json is Map ? json['models'] : json;
          return [
            if (list is List)
              for (final m in list)
                if (m is Map && (m['slug'] ?? m['id']) is String)
                  (m['slug'] ?? m['id']) as String,
          ];
        case AiProvider.antigravity:
          final path = find(provider.command);
          if (path == null) return const [];
          final r = await Process.run(path, [
            'models',
          ], environment: environment()).timeout(const Duration(seconds: 30));
          return [
            for (final line in '${r.stdout}'.split('\n'))
              if (line.contains('\t')) line.split('\t').first.trim(),
          ];
      }
    } catch (_) {
      return const [];
    }
  }

  /// The text of the document at [path], read away from the screen (a
  /// scan through OCR); empty when it has none.
  static Future<String> documentText(String path) async {
    final got = await compute(_read, (
      path: path,
      pdfium: PdfPagesHost.start(),
    ));
    return got;
  }

  static Future<String> _read(({String path, SendPort pdfium}) request) async {
    PdfPages.host = request.pdfium;
    final got = await IndexTextExtractor.extract(request.path, ocr: true);
    return '${got['text'] ?? ''}';
  }

  /// [text] with Turkish identity numbers (11 digits that check out) hidden.
  static String maskIdentityNumbers(String text) => text.replaceAllMapped(
    RegExp(r'(?<!\d)[1-9]\d{10}(?!\d)'),
    (m) => _isIdentityNumber(m[0]!) ? '***********' : m[0]!,
  );

  static bool _isIdentityNumber(String n) {
    final d = [for (final c in n.codeUnits) c - 48];
    final odd = d[0] + d[2] + d[4] + d[6] + d[8];
    final even = d[1] + d[3] + d[5] + d[7];
    if ((odd * 7 - even) % 10 != d[9]) return false;
    return d.take(10).reduce((a, b) => a + b) % 10 == d[10];
  }
}

/// What the lawyer agreed to once, and how Folio uses the AI programs; in
/// Folio's own folder.
class AiSettings {
  const AiSettings({
    this.consentVersion,
    this.consentAt,
    this.consentBy,
    this.mask = true,
    this.provider,
    this.models = const {},
  });

  /// The consent text's version; one given to an older text no longer
  /// counts.
  static const currentConsent = 1;

  final int? consentVersion;
  final DateTime? consentAt;
  final String? consentBy;

  /// Identity numbers hidden before a document is sent.
  final bool mask;

  /// The program the lawyer chose; the first usable one when null.
  final AiProvider? provider;

  /// Models the lawyer chose, by `<program>.<tier>` (`codex.strong`).
  final Map<String, String> models;

  /// The model [provider] runs for [tier].
  String modelFor(AiProvider provider, AiTier tier) =>
      models['${provider.name}.${tier.name}'] ?? provider.defaultModel(tier);

  bool get consented => consentVersion == currentConsent;

  AiSettings copyWith({
    int? consentVersion,
    DateTime? consentAt,
    String? consentBy,
    bool? mask,
    AiProvider? provider,
    Map<String, String>? models,
    bool revoke = false,
  }) => AiSettings(
    consentVersion: revoke ? null : consentVersion ?? this.consentVersion,
    consentAt: revoke ? null : consentAt ?? this.consentAt,
    consentBy: revoke ? null : consentBy ?? this.consentBy,
    mask: mask ?? this.mask,
    provider: provider ?? this.provider,
    models: models ?? this.models,
  );

  Map<String, Object?> toJson() => {
    if (consentVersion != null) 'onaySurumu': consentVersion,
    if (consentAt != null) 'onayZamani': consentAt!.toIso8601String(),
    if (consentBy != null) 'onaylayan': consentBy,
    'tcGizle': mask,
    if (provider != null) 'saglayici': provider!.name,
    if (models.isNotEmpty) 'modeller': models,
  };

  static AiSettings fromJson(Object? json) {
    if (json is! Map) return const AiSettings();
    final version = json['onaySurumu'];
    return AiSettings(
      consentVersion: version is int ? version : null,
      consentAt: DateTime.tryParse('${json['onayZamani'] ?? ''}'),
      consentBy: json['onaylayan'] as String?,
      mask: json['tcGizle'] != false,
      provider: AiProvider.values.asNameMap()['${json['saglayici']}'],
      models: {
        if (json['modeller'] case final Map m)
          for (final e in m.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
      },
    );
  }

  static Future<File> _file() async =>
      File(p.join((await folioSupportDirectory()).path, 'yapay-zeka.json'));

  static AiSettings? _held;

  static Future<AiSettings> load() async {
    if (_held case final held?) return held;
    try {
      final file = await _file();
      if (await file.exists()) {
        return _held = fromJson(jsonDecode(await file.readAsString()));
      }
    } catch (_) {}
    return _held = const AiSettings();
  }

  Future<void> save() async {
    await replaceFileIfChanged(
      await _file(),
      utf8.encode(const JsonEncoder.withIndent('  ').convert(toJson())),
    );
    _held = this;
  }
}

/// The consent the lawyer gives once, before the first document is sent.
/// [AiSettings.currentConsent] goes up when this text changes, and the
/// lawyer is asked again then only.
const aiConsentPoints = [
  'Yapay zekâ özelliklerinde, seçtiğiniz belgenin metni sizin '
      'bilgisayarınızdan, sizin hesabınızla kullandığınız sağlayıcıya '
      '(Anthropic, OpenAI ya da Google) doğrudan gönderilir.',
  'LifeOS bu metni görmez, saklamaz ve kimseye aktarmaz. Sağlayıcıyla ilişki '
      'sizinle o şirket arasındadır.',
  'Belgelerdeki kişisel verilerin veri sorumlusu sizsiniz. Gönderimin '
      'KVKK’ya, avukatlık sırrına ve meslek kurallarına uygunluğundan siz '
      'sorumlusunuz.',
  'Yapay zekânın yanıtları yanlış ya da eksik olabilir; denetlemek ve '
      'kullanmak sizin kararınızdır.',
];
