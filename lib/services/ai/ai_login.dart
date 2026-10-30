import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ai_assistant.dart';

/// A sign-in to an [AiProvider] run by Folio, with no terminal: the program
/// is started as its own sign-in asks, and what it says (the address to
/// open, a code to type there) is shown in Folio's window. A code the
/// browser gives back is handed to it with [answer].
class AiLogin extends ChangeNotifier {
  AiLogin(this.provider);

  final AiProvider provider;

  /// The address the lawyer approves the sign-in at.
  String? address;

  /// The code to type at [address], when the program gives one.
  String? code;

  /// Whether the program asks for a code from the browser back.
  bool wantsCode = false;

  /// Null while it runs; then whether the lawyer is signed in.
  bool? done;
  String? error;

  Process? _process;

  /// The program's own sign-in, as Folio runs it.
  @visibleForTesting
  static List<String> arguments(AiProvider provider) => switch (provider) {
    AiProvider.claude => ['auth', 'login', '--claudeai'],
    AiProvider.codex => ['login', '--device-auth'],
    AiProvider.antigravity => throw StateError('no sign-in from Folio'),
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
    final lower = clean.toLowerCase();
    if (lower.contains('paste') && lower.contains('code')) wantsCode = true;
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
    final process = _process = await Process.start(
      path,
      arguments(provider),
      environment: {...AiAssistant.environment(), 'BROWSER': 'true'},
    );
    var opened = false;
    void each(String line) {
      read(line);
      if (!opened && address != null) {
        opened = true;
        unawaited(open(Uri.parse(address!)).catchError((Object _) {}));
      }
    }

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
    _process = null;
    final status = await AiAssistant.status(provider);
    done = exit == 0 && status.signedIn != false;
    if (done != true) {
      error ??= '${provider.label} oturumu açılamadı.';
    }
    notifyListeners();
  }

  /// The code the browser showed, handed to the program.
  void answer(String text) {
    final process = _process;
    if (process == null) return;
    process.stdin.writeln(text.trim());
    wantsCode = false;
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
