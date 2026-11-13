import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart'
    show ValueNotifier, compute, visibleForTesting;
import 'package:path/path.dart' as p;

import '../pdf/pdf_pages.dart';
import '../platform/app_directories.dart';
import '../platform/app_edition.dart';
import '../platform/atomic_file.dart';
import '../search/text_extractor.dart';
import '../editor/lawyer_profile.dart';
import 'ai_attachment.dart';
import 'ai_events.dart';
import 'ai_case.dart';
import 'ai_groq.dart';
import 'ai_usage.dart';
import 'ai_prompts.dart';
import 'folio_mcp.dart';

export 'ai_events.dart';
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
  ),

  /// Not programs: services' APIs, asked by Folio itself with the lawyer's
  /// own key (GroqChat). "Installed" is a key given; they run on every
  /// computer, Windows and macOS too.
  groq('', 'Groq (GPT OSS)', 'Groq', 'https://console.groq.com/keys'),
  gemini('', 'Gemini (API)', 'Google', 'https://aistudio.google.com/apikey'),
  openai('', 'ChatGPT (API)', 'OpenAI', 'https://platform.openai.com/api-keys'),
  anthropic(
    '',
    'Claude (API)',
    'Anthropic',
    'https://platform.claude.com/settings/keys',
  );

  const AiProvider(this.command, this.label, this.company, this.installPage);

  /// Whether this is a service Folio asks itself, with a key, rather than
  /// a program it runs.
  bool get viaApi => ApiService.of(this) != null;

  /// The programs run from a terminal: on Linux only, for now (Folio's
  /// tools are given them as an `--mcp` server, which only Folio on Linux
  /// starts).
  bool get isProgram => !viaApi;

  /// The providers this device can offer: the programs on Linux, the
  /// services' APIs everywhere — on a phone not Groq, kept for trying
  /// models on a computer.
  static List<AiProvider> get offered => [
    for (final p in values)
      if (AiAssistant.phone
          ? p.viaApi && p != AiProvider.groq
          : p.viaApi || Platform.isLinux)
        p,
  ];

  /// Whether it is given pages and pictures as they are. A scan read by
  /// OCR loses its tables and stamps; every program that sees pictures
  /// gets the pages. Groq's models and Antigravity take none.
  bool get seesPictures => switch (this) {
    AiProvider.claude ||
    AiProvider.codex ||
    AiProvider.gemini ||
    AiProvider.openai ||
    AiProvider.anthropic => true,
    AiProvider.groq || AiProvider.antigravity => false,
  };

  /// Whether a PDF goes to it whole, as a document (Claude reads its text
  /// layer and its pages both); the others get its pages as pictures.
  bool get readsPdf =>
      this == AiProvider.claude || this == AiProvider.anthropic;

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
  bool get signsInFromFolio =>
      this == AiProvider.claude || this == AiProvider.codex;

  /// Its page in LifeOS Mağaza (`lifeos-magaza --uygulama …`).
  String get storeId => switch (this) {
    AiProvider.claude => 'lifeos:claude-code',
    AiProvider.codex => 'lifeos:codex-cli',
    AiProvider.antigravity => 'lifeos:antigravity-cli',
    AiProvider.groq ||
    AiProvider.gemini ||
    AiProvider.openai ||
    AiProvider.anthropic => '',
  };

  /// The model each tier runs, unless the lawyer chose another.
  String defaultModel(AiTier tier) => switch ((this, tier)) {
    (AiProvider.claude, AiTier.normal) => 'sonnet',
    (AiProvider.claude, AiTier.strong) => 'opus',
    (AiProvider.codex, AiTier.normal) => 'gpt-6-luna',
    (AiProvider.codex, AiTier.strong) => 'gpt-6.1-sol',
    (AiProvider.antigravity, AiTier.normal) => 'gemini-3.8-flash-medium',
    (AiProvider.antigravity, AiTier.strong) => 'gemini-3.8-flash-high',
    (AiProvider.claude, AiTier.light) => 'haiku',
    (AiProvider.codex, AiTier.light) => 'gpt-6.1-terra',
    // Medium, as the light tier's effort: at low it missed the notices'
    // times (measured 13.11.2026).
    (AiProvider.antigravity, AiTier.light) => 'gemini-3.8-flash-medium',
    // The strong tier thinks harder (reasoning_effort high).
    (AiProvider.groq || AiProvider.gemini, _) => ApiService.of(
      this,
    )!.models.first,
    (AiProvider.openai, AiTier.strong) => 'gpt-6.1-sol',
    (AiProvider.openai, AiTier.normal) => 'gpt-6-luna',
    (AiProvider.openai, AiTier.light) => 'gpt-6.1-terra',
    (AiProvider.anthropic, AiTier.strong) => 'claude-opus-5-5',
    (AiProvider.anthropic, AiTier.normal) => 'claude-sonnet-5-5',
    (AiProvider.anthropic, AiTier.light) => 'claude-haiku-5-5',
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
  const AiFailure(this.message, {this.timedOut = false});
  final String message;

  /// The program did not answer in time: asking it again from the start
  /// would only wait as long once more.
  final bool timedOut;
  @override
  String toString() => message;
}

abstract final class AiAssistant {
  /// Folio's alone, not Ofis's; on a computer (the programs on Linux, the
  /// services' APIs everywhere); and not in a test,
  /// which runs no real program unless it asks ([availableForTest]).
  static bool get available =>
      availableForTest ??
      (!AppEdition.isOfis &&
          (phone
              ? phoneKey.value
              : Platform.isLinux || Platform.isWindows || Platform.isMacOS) &&
          !Platform.environment.containsKey('FLUTTER_TEST'));

  @visibleForTesting
  static bool? availableForTest;

  /// A phone or a tablet: Android, iOS.
  static bool get phone =>
      phoneForTest ?? (Platform.isAndroid || Platform.isIOS);

  @visibleForTesting
  static bool? phoneForTest;

  /// On a phone: whether it has a key of its own (Gemini, ChatGPT, Claude).
  /// With one it asks the service itself; without, what it asks waits for
  /// the lawyer's computer (AiRelay).
  static final phoneKey = ValueNotifier<bool>(false);

  /// [phoneKey] looked at again: at the start, and when a key is kept or
  /// taken off.
  static Future<void> lookForPhoneKey() async {
    if (!phone) return;
    var any = false;
    for (final p in AiProvider.offered) {
      if (ApiService.of(p) case final api?
          when await GroqChat.key(api) != null) {
        any = true;
        break;
      }
    }
    phoneKey.value = any;
  }

  /// Whether the AI settings are shown: where the features run, and on a
  /// phone, for its key to be given.
  static bool get configurable =>
      available ||
      (!AppEdition.isOfis &&
          phone &&
          !Platform.environment.containsKey('FLUTTER_TEST'));

  /// Whether the AI features are shown: [available], and turned on by the
  /// lawyer ([AiSettings.enabled]).
  static bool get shown => available && AiSettings.on.value;

  /// The most of a document's text sent: the rest is left out, and said so.
  static const maxCharacters = 200000;

  /// How long a program may go quiet: no word of its work, no tool's
  /// answer (a tool waits at most three minutes for Folio). A program
  /// still working is not stopped, however long the case takes it.
  static const timeout = Duration(minutes: 6);

  /// The longest one answer may take all told.
  static const longest = Duration(minutes: 30);

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
    if (ApiService.of(provider) case final api?) {
      return await GroqChat.key(api) == null
          ? AiStatus(provider)
          : AiStatus(provider, path: api.endpoint, signedIn: true);
    }
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
        case AiProvider.groq:
        case AiProvider.gemini:
        case AiProvider.openai:
        case AiProvider.anthropic:
          return AiStatus(provider, path: path);
      }
    } catch (_) {
      return AiStatus(provider, path: path);
    }
  }

  static Future<List<AiStatus>> statuses() => statusesForTest != null
      ? Future.value(statusesForTest)
      : Future.wait([for (final p in AiProvider.offered) status(p)]);

  /// The programs a test says are here, in place of looking for them.
  @visibleForTesting
  static List<AiStatus>? statusesForTest;

  /// The arguments that run [provider] once, read-only and with every tool
  /// it has turned off; the question comes on its standard input.
  @visibleForTesting
  static List<String> arguments(
    AiProvider provider,
    String folder, {
    String? model,
    String? folio,
    String? caseFolder,
    bool pictures = false,
    AiTier? tier,
    List<String> images = const [],
    String? resume,
    bool keep = false,
  }) => switch (provider) {
    AiProvider.claude => [
      '-p',
      // Folio's rules in place of the program's own coding persona.
      '--system-prompt',
      AiPrompts.core,
      if (model != null && model.isNotEmpty) ...['--model', model],
      // The strong tier thinks harder.
      if (tier != null) ...['--effort', tier.effort],
      // Folio's own tools, and no others.
      if (folio != null) ...[
        '--mcp-config',
        jsonEncode({
          'mcpServers': {
            'folio': {
              'type': 'stdio',
              'command': folio,
              'args': [FolioMcp.flag],
              if (caseFolder != null)
                'env': {AiCaseSession.variable: caseFolder},
            },
          },
        }),
        '--allowedTools',
        [for (final n in FolioMcp.names) 'mcp__folio__$n'].join(','),
      ],
      // The answer as events, for the lawyer to see it work; with pictures
      // the question comes as an event too.
      if (pictures) ...['--input-format', 'stream-json'],
      '--output-format',
      'stream-json',
      '--verbose',
      '--include-partial-messages',
      '--tools',
      '',
      '--restricted',
      '--strict-mcp-config',
      // A conversation the program goes on with keeps its own record, so
      // that the next question is not read from the start.
      if (resume != null) ...['--resume', resume],
      if (!keep && resume == null) '--no-session-persistence',
      '--disable-slash-commands',
    ],
    AiProvider.codex => [
      'exec',
      if (resume != null) 'resume',
      '--json',
      if (!keep && resume == null) '--ephemeral',
      '--ignore-user-config',
      '--skip-git-repo-check',
      // Going on, it takes neither: read-only said as a setting, the folder
      // it runs in its own.
      if (resume == null) ...[
        '-s',
        'read-only',
        '-C',
        folder,
      ] else ...[
        '-c',
        'sandbox_mode="read-only"',
      ],
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
      if (tier != null) ...['-c', 'model_reasoning_effort="${tier.effort}"'],
      // Folio's own tools. Codex gives a tool's program none of its own
      // surroundings: the display and Folio's folders are passed on.
      if (folio != null) ...[
        '-c',
        'mcp_servers.folio.command=${jsonEncode(folio)}',
        '-c',
        'mcp_servers.folio.args=${jsonEncode([FolioMcp.flag])}',
        '-c',
        'mcp_servers.folio.startup_timeout_sec=30',
        // Folio's tools run without Codex asking first: it would ask no one
        // here and say no. What needs the lawyer, Folio asks itself.
        '-c',
        'mcp_servers.folio.default_tools_approval_mode="approve"',
        '-c',
        'mcp_servers.folio.env={${[for (final key in mcpEnvironment)
          if (Platform.environment[key] case final v?) '$key=${jsonEncode(v)}', if (caseFolder != null) '${AiCaseSession.variable}=${jsonEncode(caseFolder)}'].join(',')}}',
      ],
      for (final i in images) ...['-i', i],
      '-o',
      p.join(folder, '.yanit.txt'),
      ?resume,
      '-',
    ],
    AiProvider.antigravity => [
      '--input-format',
      'stream-json',
      '--output-format',
      'stream-json',
      '--sandbox',
      '--disable-slash-commands',
      // Its tools come from its own settings (see [addToAntigravity]); for
      // this question Folio's may be called without asking, and it may
      // neither run a command nor write a file.
      '--settings',
      jsonEncode({
        'permissions': {
          'allow': [if (folio != null) 'mcp(${FolioMcp.name}/*)'],
          'deny': ['command(*)', 'write_file(*)'],
        },
      }),
      '--print-timeout',
      '${longest.inSeconds}s',
      // A model named with its effort ("gemini-3.8-flash-low") is given
      // none beside it: agy refuses the two when they differ.
      if (tier != null &&
          !RegExp(r'-(low|medium|high)$').hasMatch(model ?? '')) ...[
        '--effort',
        tier.effort,
      ],
      if (model != null && model.isNotEmpty) ...['--model', model],
      if (resume != null) ...['--conversation', resume],
      // Written with its (empty) value: apart, agy takes the next flag
      // for the prompt.
      '--print=',
    ],
    // Asked by Folio itself (GroqChat), no program run.
    AiProvider.groq ||
    AiProvider.gemini ||
    AiProvider.openai ||
    AiProvider.anthropic => const [],
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

  /// Whether [provider] is given Folio's tools with each question. Antigravity
  /// is not: it keeps its MCP servers in a settings file of its own, for all
  /// its sessions, which Folio adds itself to only when the lawyer says so
  /// ([addToAntigravity]).
  static bool takesTools(AiProvider provider) =>
      provider != AiProvider.antigravity;

  /// Antigravity's own list of MCP servers.
  @visibleForTesting
  static File antigravityServers([Map<String, String>? environment]) => File(
    p.join(
      (environment ?? Platform.environment)['HOME'] ?? '',
      '.gemini',
      'config',
      'mcp_config.json',
    ),
  );

  /// The program Antigravity runs as Folio's tools, when Folio is on its
  /// list and turned on there.
  static Future<String?> antigravityFolio([File? servers]) async {
    try {
      final json = jsonDecode(
        await (servers ?? antigravityServers()).readAsString(),
      );
      final folio = (json as Map)['mcpServers']?[FolioMcp.name];
      if (folio is! Map || folio['disabled'] == true) return null;
      final args = folio['args'];
      if (args is! List || !args.contains(FolioMcp.flag)) return null;
      return folio['command'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Puts Folio's tools on Antigravity's list, through its own command, for
  /// all its sessions. Asked of the lawyer first.
  static Future<void> addToAntigravity() async {
    final agy = find(AiProvider.antigravity.command);
    final folio = folioProgram;
    if (agy == null || folio == null) {
      throw const AiFailure('Antigravity bu bilgisayarda kurulu değil.');
    }
    final r = await Process.run(agy, [
      'mcp',
      'add',
      FolioMcp.name,
      folio,
      '--',
      FolioMcp.flag,
    ], environment: environment()).timeout(const Duration(seconds: 20));
    if (r.exitCode != 0) {
      throw AiFailure(
        _said(_lastLine('${r.stderr}\n${r.stdout}'), 'Antigravity'),
      );
    }
  }

  /// Takes Folio's tools off Antigravity's list.
  static Future<void> removeFromAntigravity() async {
    final agy = find(AiProvider.antigravity.command);
    if (agy == null) return;
    await Process.run(agy, [
      'mcp',
      'remove',
      FolioMcp.name,
    ], environment: environment()).timeout(const Duration(seconds: 20));
  }

  /// Whether Antigravity can be given Folio's tools with this question: on
  /// its list, as this Folio. A Folio moved since (an update to another
  /// folder) is put back on it, the lawyer having agreed once.
  static Future<bool> antigravityHasTools() async {
    final listed = await antigravityFolio();
    final folio = folioProgram;
    if (listed == null || folio == null) return false;
    if (listed == folio) return true;
    try {
      await addToAntigravity();
      return await antigravityFolio() == folio;
    } on Object {
      return false;
    }
  }

  /// The program Folio's tools run as: this Folio, given [FolioMcp.flag].
  /// Null in a test, whose program is not Folio.
  static String? get folioProgram =>
      Platform.environment.containsKey('FLUTTER_TEST')
      ? null
      : Platform.resolvedExecutable;

  /// [prompt] as [provider] reads it on its standard input.
  @visibleForTesting
  static String input(
    AiProvider provider,
    String prompt, {
    List<AiAttachment> attachments = const [],
  }) => switch (provider) {
    // Pages and pictures as they are, the question after them.
    AiProvider.claude when attachments.any((a) => a.visual) =>
      '${jsonEncode({
        'type': 'user',
        'message': {
          'role': 'user',
          'content': [
            for (final a in attachments) ...[
              if (a.pdf case final pdf?) {
                  'type': 'document',
                  'title': a.name,
                  'source': {'type': 'base64', 'media_type': 'application/pdf', 'data': base64Encode(pdf)},
                },
              for (final i in a.images) {
                  'type': 'image',
                  'source': {'type': 'base64', 'media_type': i.mime, 'data': base64Encode(i.bytes)},
                },
            ],
            {'type': 'text', 'text': prompt},
          ],
        },
      })}\n',
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
        Object? json;
        try {
          json = jsonDecode(stdout.trim());
        } on FormatException {
          // With pictures it answers a line an event: the result is last.
          for (final line in stdout.trim().split('\n').reversed) {
            try {
              final e = jsonDecode(line);
              if (e is Map && e['type'] == 'result') {
                json = e;
                break;
              }
            } on FormatException {
              continue;
            }
          }
          if (json == null) {
            throw const AiFailure('Claude’ın yanıtı okunamadı.');
          }
        }
        if (json is! Map) throw const AiFailure('Claude’ın yanıtı okunamadı.');
        final result = '${json['result'] ?? ''}'.trim();
        if (json['is_error'] == true) {
          throw AiFailure(_said(result, 'Claude'));
        }
        return result;
      case AiProvider.codex:
        final text = (lastMessage ?? '').trim();
        if (text.isNotEmpty) return text;
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
              return '${r['response'] ?? ''}'.trim();
            }
          } on FormatException {
            continue;
          }
        }
        throw const AiFailure('Antigravity yanıt vermedi.');
      case AiProvider.groq:
      case AiProvider.gemini:
      case AiProvider.openai:
      case AiProvider.anthropic:
        return stdout.trim();
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
    AiTier? tier,
    bool tools = true,
    AiCaseSession? caseSession,
    List<AiAttachment> attachments = const [],
    void Function(AiEvent event)? onEvent,
    Future<void>? cancel,
    AiThread? thread,
  }) async {
    if (provider.viaApi) {
      await AiUsage.checkLimit();
      return GroqChat.ask(
        prompt,
        model: model,
        tier: tier,
        tools: tools,
        caseSession: caseSession,
        attachments: attachments,
        onEvent: onEvent,
        cancel: cancel,
        thread: thread,
        service: ApiService.of(provider)!,
      );
    }
    final path = find(provider.command);
    if (path == null) {
      throw AiFailure('${provider.label} bu bilgisayarda kurulu değil.');
    }
    // An empty folder of its own: nothing of the lawyer's for it to see.
    // A conversation it goes on with has the same one each time: Claude
    // keeps its record by the folder it ran in.
    final folder = thread == null
        ? await Directory.systemTemp.createTemp('folio-yz-')
        : await Directory(
            p.join(Directory.systemTemp.path, 'folio-yz-${thread.place}'),
          ).create(recursive: true);
    // An Antigravity that does not go on with a conversation is not asked
    // to: its id is not kept, and each question carries what was said.
    final keeps =
        provider != AiProvider.antigravity || await antigravityResumes();
    final resume = keeps ? thread?.ids[provider] : null;
    try {
      if (provider == AiProvider.codex) {
        await File(p.join(folder.path, 'talimat.md'))
            .writeAsString(AiPrompts.core);
      }
      // Codex is given pictures as files of its folder.
      final images = <String>[];
      if (provider == AiProvider.codex) {
        for (final a in attachments) {
          for (final i in a.images) {
            final file = File(
              p.join(
                folder.path,
                'ek-${images.length + 1}.${i.mime.split('/').last}',
              ),
            );
            await file.writeAsBytes(i.bytes);
            images.add(file.path);
          }
        }
      }
      final process = await Process.start(
        path,
        arguments(
          provider,
          folder.path,
          model: model,
          tier: tier,
          folio: !tools
              ? null
              : takesTools(provider)
              ? folioProgram
              : provider == AiProvider.antigravity &&
                    await antigravityHasTools()
              ? folioProgram
              : null,
          caseFolder: caseSession?.folder.path,
          pictures:
              provider == AiProvider.claude && attachments.any((a) => a.visual),
          images: images,
          resume: resume,
          keep: thread != null,
        ),
        workingDirectory: folder.path,
        // Antigravity's tools have its environment: the case is named there.
        environment: {
          ...environment(),
          AiCaseSession.variable: ?caseSession?.folder.path,
        },
      );
      final out = StringBuffer();
      final err = StringBuffer();
      final events = switch (provider) {
        AiProvider.claude => AiEvents.claude,
        AiProvider.codex => AiEvents.codex,
        AiProvider.antigravity => AiEvents.antigravity,
        AiProvider.groq ||
        AiProvider.gemini ||
        AiProvider.openai ||
        AiProvider.anthropic => (String _) => const <AiEvent>[],
      };
      var heard = DateTime.now();
      final began = heard;
      final reading = Future.wait([
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach((line) {
              heard = DateTime.now();
              out.writeln(line);
              if (thread != null && keeps) {
                if (threadIn(provider, line) case final id?) {
                  thread.ids[provider] = id;
                }
              }
              if (onEvent != null) {
                for (final e in events(line)) {
                  onEvent(e);
                }
              }
            }),
        process.stderr.transform(utf8.decoder).forEach(err.write),
      ]);
      process.stdin.write(input(provider, prompt, attachments: attachments));
      await process.stdin.close();
      var stopped = false;
      unawaited(
        cancel?.then((_) {
          stopped = true;
          process.kill();
        }),
      );
      // Stopped only when it has gone quiet, or taken far too long.
      final quiet = Completer<String>();
      final watch = Timer.periodic(const Duration(seconds: 5), (_) {
        final now = DateTime.now();
        if (quiet.isCompleted) return;
        if (now.difference(heard) > timeout) {
          quiet.complete(
            '${provider.label} ${timeout.inMinutes} dakikadır hiçbir şey '
            'yapmadı; durduruldu.',
          );
        } else if (now.difference(began) > longest) {
          quiet.complete(
            '${provider.label} ${longest.inMinutes} dakikada bitiremedi; '
            'durduruldu.',
          );
        }
      });
      final int code;
      try {
        final ended = await Future.any<Object>([
          process.exitCode,
          quiet.future,
        ]);
        if (ended is String) {
          process.kill();
          throw AiFailure(ended, timedOut: true);
        }
        code = ended as int;
      } finally {
        watch.cancel();
      }
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
      // The kept folder is cleared before the next question writes in it.
      if (thread != null) {
        await _clear(folder, whole: false);
      } else {
        unawaited(_clear(folder, whole: true));
      }
    }
  }

  static Future<void> _clear(Directory folder, {required bool whole}) async {
    try {
      if (whole) {
        await folder.delete(recursive: true);
        return;
      }
      // The folder stays for the conversation; what was put in it goes.
      await for (final f in folder.list()) {
        if (f is File) await f.delete();
      }
    } catch (_) {}
  }

  /// Whether this computer's Antigravity goes on with a conversation it is
  /// given (`--conversation`): seen to from 1.4.12; an older one is sent
  /// what was said instead.
  static Future<bool> antigravityResumes() async => _agyResumes ??= () async {
    final path = find(AiProvider.antigravity.command);
    if (path == null) return false;
    try {
      final r = await Process.run(path, [
        '--version',
      ], environment: environment()).timeout(const Duration(seconds: 15));
      final m = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch('${r.stdout}');
      if (m == null) return false;
      final v = [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
      return v[0] > 1 || (v[0] == 1 && (v[1] > 4 || (v[1] == 4 && v[2] >= 12)));
    } catch (_) {
      return false;
    }
  }();

  static Future<bool>? _agyResumes;

  /// Whether [provider] goes on with [thread] here: if not, its id is
  /// dropped, so that the question carries what was said.
  static Future<bool> goesOn(AiProvider provider, AiThread thread) async {
    if (provider == AiProvider.antigravity && !await antigravityResumes()) {
      thread.ids.remove(provider);
    }
    // Groq's conversation is held while Folio is open.
    if (provider.viaApi && !await GroqChat.has(thread.ids[provider] ?? '')) {
      thread.ids.remove(provider);
    }
    return thread.ids.containsKey(provider);
  }

  /// The id of the conversation [provider] says it keeps, in a line it
  /// writes: Claude's session, Codex's thread, Antigravity's conversation.
  static String? threadIn(AiProvider provider, String line) {
    if (!line.startsWith('{')) return null;
    try {
      final e = jsonDecode(line);
      if (e is! Map) return null;
      final id = switch (provider) {
        AiProvider.claude when e['type'] == 'system' => e['session_id'],
        AiProvider.codex when e['type'] == 'thread.started' => e['thread_id'],
        AiProvider.antigravity when e['event'] == 'init' =>
          e['conversation_id'] ??
              (e['init'] is Map ? (e['init'] as Map)['conversation_id'] : null),
        _ => null,
      };
      return id is String && id.isNotEmpty ? id : null;
    } on FormatException {
      return null;
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
    String? name,
    String? text,
    String question = '',
    String? caseName,
    String? note,
    String? attached,
    String? who,
    String? guide,
    List<({String question, String answer})> history = const [],
  }) {
    final cut = text != null && text.length > maxCharacters;
    final body = cut ? text.substring(0, maxCharacters) : text;
    return [
      if (body != null) ...[
        '<belge ad="${(name ?? 'belge').replaceAll('"', "'")}">',
        body,
        if (cut) '[Belgenin geri kalanı uzunluğu yüzünden gönderilmedi.]',
        '</belge>',
      ],
      for (final h in history) ...[
        '',
        'Önceki soru: ${h.question}',
        'Önceki yanıt: ${h.answer}',
      ],
      if (caseName != null) ...[
        '',
        body != null
            ? 'Bu belge $caseName dosyasına ait. Dosyanın bilgilerine ve diğer '
                  'evrakına Folio\'nun dosya araçlarıyla bakabilirsin.'
            : 'Soru $caseName dosyası hakkında. Dosyanın bilgilerine ve '
                  'evrakına Folio\'nun dosya araçlarıyla bakabilirsin.',
      ],
      if (who != null && who.isNotEmpty) ...['', who],
      if (note != null) ...['', note],
      // The documents the lawyer added to the conversation.
      if (attached != null && attached.isNotEmpty) ...['', attached],
      // The legal guide's topics the question names (LegalGuide).
      if (guide != null && guide.isNotEmpty) ...['', guide],
      '',
      AiPrompts.task(task, question: question),
    ].join('\n');
  }

  /// Who asks, for the program to answer them as the lawyer they are:
  /// "Kullanıcı: Av. Deniz Yılmaz, Antalya Barosu (sicil 1234), Yılmaz
  /// Hukuk Bürosu." Empty when the profile names no one.
  static Future<String> who() async {
    try {
      final profile = await LawyerProfile.load();
      final lawyer = profile.lawyer;
      if (lawyer == null) return '';
      final bar = [
        if (lawyer.barName.isNotEmpty) lawyer.barName,
        if (lawyer.barNumber.trim().isNotEmpty)
          '(sicil ${lawyer.barNumber.trim()})',
      ].join(' ');
      return 'Kullanıcı: ${[lawyer.titled, if (bar.isNotEmpty) bar, if (profile.officeName.trim().isNotEmpty) profile.officeName.trim()].join(', ')}.';
    } catch (_) {
      return '';
    }
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
        case AiProvider.groq:
        case AiProvider.gemini:
        case AiProvider.openai:
        case AiProvider.anthropic:
          return await GroqChat.listModels(ApiService.of(provider)!);
      }
    } catch (_) {
      return const [];
    }
  }

  /// The text of the document at [path], read away from the screen (a
  /// scan through OCR); empty when it has none.
  static Future<String> documentText(String path, {bool ocr = true}) async {
    final got = await compute(_read, (
      path: path,
      pdfium: PdfPagesHost.start(),
      ocr: ocr,
    ));
    return got;
  }

  static Future<String> _read(
    ({String path, SendPort pdfium, bool ocr}) request,
  ) async {
    PdfPages.host = request.pdfium;
    final got = await IndexTextExtractor.extract(
      request.path,
      ocr: request.ocr,
    );
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
    this.enabled = false,
    this.consentVersion,
    this.consentAt,
    this.consentBy,
    this.mask = true,
    this.provider,
    this.models = const {},
    this.monthlyTokens,
  });

  /// The most tokens the services' API keys may use a month, on every own
  /// device together; none when null.
  final int? monthlyTokens;

  /// The consent text's version; one given to an older text no longer
  /// counts.
  static const currentConsent = 4;

  /// Whether the lawyer turned the AI features on. Off, Folio shows none of
  /// them and its tools answer no AI program.
  final bool enabled;

  /// [enabled] as last loaded or saved, for what shows the features.
  static final on = ValueNotifier<bool>(false);

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
    bool? enabled,
    int? consentVersion,
    DateTime? consentAt,
    String? consentBy,
    bool? mask,
    AiProvider? provider,
    Map<String, String>? models,
    int? monthlyTokens,
    bool noLimit = false,
    bool revoke = false,
  }) => AiSettings(
    enabled: enabled ?? this.enabled,
    consentVersion: revoke ? null : consentVersion ?? this.consentVersion,
    consentAt: revoke ? null : consentAt ?? this.consentAt,
    consentBy: revoke ? null : consentBy ?? this.consentBy,
    mask: mask ?? this.mask,
    provider: provider ?? this.provider,
    models: models ?? this.models,
    monthlyTokens: noLimit ? null : monthlyTokens ?? this.monthlyTokens,
  );

  Map<String, Object?> toJson() => {
    'acik': enabled,
    if (consentVersion != null) 'onaySurumu': consentVersion,
    if (consentAt != null) 'onayZamani': consentAt!.toIso8601String(),
    if (consentBy != null) 'onaylayan': consentBy,
    'tcGizle': mask,
    if (provider != null) 'saglayici': provider!.name,
    if (models.isNotEmpty) 'modeller': models,
    if (monthlyTokens != null) 'aylikTokenSiniri': monthlyTokens,
  };

  static AiSettings fromJson(Object? json) {
    if (json is! Map) return const AiSettings();
    final version = json['onaySurumu'];
    return AiSettings(
      enabled: json['acik'] == true,
      consentVersion: version is int ? version : null,
      consentAt: DateTime.tryParse('${json['onayZamani'] ?? ''}'),
      consentBy: json['onaylayan'] as String?,
      mask: json['tcGizle'] != false,
      provider: AiProvider.values.asNameMap()['${json['saglayici']}'],
      monthlyTokens: (json['aylikTokenSiniri'] as num?)?.toInt(),
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
        return _hold(fromJson(jsonDecode(await file.readAsString())));
      }
    } catch (_) {}
    return _hold(const AiSettings());
  }

  /// Read again from its file: another own device's came (Senkron).
  static Future<AiSettings> reload() {
    _held = null;
    return load();
  }

  static AiSettings _hold(AiSettings settings) {
    on.value = settings.enabled;
    return _held = settings;
  }

  Future<void> save() async {
    await replaceFileIfChanged(
      await _file(),
      utf8.encode(const JsonEncoder.withIndent('  ').convert(toJson())),
    );
    _hold(this);
  }
}

/// The consent the lawyer gives once, before the first document is sent.
/// [AiSettings.currentConsent] goes up when this text changes, and the
/// lawyer is asked again then only.
const aiConsentPoints = [
  'Yapay zekâ özelliklerinde, seçtiğiniz belgenin metni sizin '
      'cihazınızdan (bilgisayarınız ya da telefonunuz), sizin hesabınızla '
      'kullandığınız sağlayıcıya '
      '(Anthropic, OpenAI ya da Google) ya da kendi API anahtarınızla '
      'kullandığınız hizmete (Google Gemini, OpenAI, Anthropic Claude ya da '
      'Groq) doğrudan gönderilir. Belge bir '
      'dosyaya aitse yapay zekânın okuduğu dosya bilgileri ve evrak da '
      'gönderilir.',
  'LifeOS bu metni görmez, saklamaz ve kimseye aktarmaz. Sağlayıcıyla ilişki '
      'sizinle o şirket arasındadır.',
  'Yapay zekâyla yaptığınız sohbetler, kaydettiğiniz bulgular ve taslaklar '
      'ilgili dosyanın kaydında tutulur: bu cihazda ve Senkron açıksa '
      'yalnız kendi cihazlarınızda. Telefonunuza API anahtarı girdiyseniz '
      'telefondan sorduğunuz soru oradan doğrudan sağlayıcıya gider; '
      'girmediyseniz bilgisayarınızdaki Folio ile gönderilir.',
  'Belgelerdeki kişisel verilerin veri sorumlusu sizsiniz. Gönderimin '
      'KVKK’ya, avukatlık sırrına ve meslek kurallarına uygunluğundan siz '
      'sorumlusunuz.',
  'Yapay zekânın yanıtları yanlış ya da eksik olabilir; denetlemek ve '
      'kullanmak sizin kararınızdır.',
];

/// A conversation each program goes on with from one question to the
/// next, so that it does not read the case and the earlier answers again:
/// [place] names it (the chat's id), [ids] holds each program's own id of
/// it once it has said one.
class AiThread {
  AiThread(this.place, [Map<AiProvider, String>? ids]) : ids = ids ?? {};

  final String place;
  final Map<AiProvider, String> ids;

  /// As kept with the chat: {"claude": "…", "codex": "…"}.
  Map<String, String> toJson() => {
    for (final e in ids.entries) e.key.name: e.value,
  };

  static AiThread of(String place, Object? kept) => AiThread(place, {
    if (kept is Map)
      for (final p in AiProvider.values)
        if (kept[p.name] case final String id when id.isNotEmpty) p: id,
  });
}
