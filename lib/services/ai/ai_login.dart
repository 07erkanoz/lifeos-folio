import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'ai_assistant.dart';

/// A sign-in to an [AiProvider] run by Folio, with no terminal: the program
/// is started as its own sign-in asks, and what it says (the address to
/// open, a code to type there) is shown in Folio's window. The sign-in is
/// the program's and its maker's alone: Folio opens the address and waits,
/// and never takes a code, a password or a token in between (Anthropic
/// allows no app to). Claude's browser sign-in comes back to Claude Code
/// itself, on this computer.
class AiLogin extends ChangeNotifier {
  AiLogin(this.provider);

  final AiProvider provider;

  /// The address the lawyer approves the sign-in at.
  String? address;

  /// The code to type at [address], when the program gives one.
  String? code;

  /// Null while it runs; then whether the lawyer is signed in.
  bool? done;
  String? error;

  Process? _process;

  /// The program's own sign-in, as Folio runs it.
  @visibleForTesting
  static List<String> arguments(AiProvider provider) => switch (provider) {
    AiProvider.claude => ['auth', 'login', '--claudeai'],
    AiProvider.codex => ['login', '--device-auth'],
    AiProvider.antigravity ||
    AiProvider.groq ||
    AiProvider.gemini ||
    AiProvider.openai ||
    AiProvider.anthropic => throw StateError('no sign-in from Folio'),
  };

  static final _address = RegExp(r'https://[^\s"<>]+');

  /// A device code as the programs print it: `ABCD-1234`, `KXQ4-7TPM`.
  static final _code = RegExp(r'\b[A-Z0-9]{4,5}-[A-Z0-9]{4,5}\b');

  /// What one line the program said tells: an address, a code, a question.
  @visibleForTesting
  void read(String line) {
    final clean = line.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '');
    if (address == null) {
      if (_address.firstMatch(clean) case final m?) {
        address = m[0];
      }
    }
    if (code == null) {
      if (_code.firstMatch(clean) case final m?) code = m[0];
    }
    notifyListeners();
  }

  /// Started; [open] is given the address once it is known.
  Future<void> start(Future<void> Function(Uri address) open) async {
    final path = AiAssistant.find(provider.command);
    if (path == null) {
      error = '${provider.label} bu bilgisayarda kurulu değil.';
      done = false;
      notifyListeners();
      return;
    }
    // Claude Code opens its sign-in in a browser, which comes back to it
    // on this computer; the address it prints instead is the one whose code
    // is pasted, which Folio does not take. Its browser is Folio here: a
    // script that only hands the address over.
    final folder = await Directory.systemTemp.createTemp('folio-giris-');
    final given = File(p.join(folder.path, 'adres'));
    final browser = File(p.join(folder.path, 'tarayici'));
    await browser.writeAsString(
      '#!/bin/sh\nprintf \'%s\' "\$1" > "${given.path}.part" && '
      'mv "${given.path}.part" "${given.path}"\n',
    );
    await Process.run('chmod', ['700', browser.path]);
    final viaBrowser = provider == AiProvider.claude;
    final process = _process = await Process.start(
      path,
      arguments(provider),
      environment: {
        ...AiAssistant.environment(),
        'BROWSER': viaBrowser ? browser.path : 'true',
      },
    );
    // Nothing is ever typed to it.
    unawaited(process.stdin.close().catchError((Object _) {}));
    var opened = false;
    void show(String at) {
      if (opened) return;
      opened = true;
      address = at;
      notifyListeners();
      unawaited(open(Uri.parse(at)).catchError((Object _) {}));
    }

    void each(String line) {
      if (viaBrowser) return;
      read(line);
      if (address case final at?) show(at);
    }

    final watch = !viaBrowser
        ? null
        : Timer.periodic(const Duration(milliseconds: 300), (_) {
            if (!opened && given.existsSync()) {
              show(given.readAsStringSync().trim());
            }
          });

    final reading = Future.wait([
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(each),
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(each),
    ]);
    final exit = await process.exitCode;
    await reading;
    watch?.cancel();
    unawaited(folder.delete(recursive: true).catchError((Object _) => folder));
    _process = null;
    final status = await AiAssistant.status(provider);
    done = exit == 0 && status.signedIn != false;
    if (done != true) {
      error ??= '${provider.label} oturumu açılamadı.';
    }
    notifyListeners();
  }

  void cancel() {
    _process?.kill();
    _process = null;
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}
