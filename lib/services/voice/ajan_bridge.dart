import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../ai/ai_case.dart';
import '../ai/ai_external.dart';
import '../desktop/desktop_instance.dart';
import '../platform/app_directories.dart';

/// Folio and Folio Ajan are two programs (22 Kasım 2026): Folio Ajan's
/// screen stuttered whenever Folio worked, and Folio waited on Folio Ajan's
/// tools. `lifeos_ajan` is built from Folio's runner and bundle and keeps
/// to its own window, its own microphone and its own lock; what only the
/// open Folio can do (UYAP, UETS, Senkron) it asks of Folio here.
///
/// They tell each other things the way a second Folio tells the first:
/// over the loopback socket each one's [DesktopInstance] holds, with its
/// token. The e-signature PIN goes that way too, never through a file.
abstract final class AjanBridge {
  /// Put first by `lifeos_ajan`'s runner: this program is Folio Ajan.
  static const flag = '--ajan';

  /// Folio Ajan's full screen.
  static const show = '--goster';

  /// Started with no window: listening for "Ajan açıl" only.
  static const background = '--arka';

  /// The voice's settings changed in Folio: read again.
  static const settings = '--ayar';

  /// An activation token from the desktop, for the window to come forward.
  static const tokenPrefix = '--etkin=';

  /// Folio → Folio Ajan: Folio is ending; Folio Ajan ends with it.
  static const quit = '--kapan';

  /// Folio → Folio Ajan: UYAP or UETS is needed (need, why).
  static const askLink = '--baglanti-iste';

  /// Folio → Folio Ajan: where the connection is.
  static const linkStage = '--baglanti-asama';

  /// Folio → Folio Ajan: connected (`tamam`) or not (`hata`, why).
  static const linkResult = '--baglanti-sonuc';

  /// Folio → Folio Ajan: the connection is no longer asked for.
  static const linkGone = '--baglanti-bitti';

  /// Folio Ajan → Folio: the lawyer's PIN for the connection asked (need,
  /// PIN).
  static const pin = '--ajan-pin';

  /// Folio Ajan → Folio: the lawyer closed the PIN box.
  static const pinCancel = '--ajan-vazgec';

  /// Folio Ajan's program beside Folio's.
  static const binary = 'lifeos_ajan';
  static const folioBinary = 'lifeos_folio';

  /// Whether this program is Folio Ajan (its executable's name, without
  /// Windows' `.exe`).
  static bool get isAjan =>
      p.basenameWithoutExtension(Platform.resolvedExecutable) == binary;

  static String _beside(String name) => p.join(
    p.dirname(Platform.resolvedExecutable),
    Platform.isWindows ? '$name.exe' : name,
  );

  /// Folio's program, where Folio's tools (`--mcp`) are run from too.
  static String get folioExecutable =>
      isAjan ? _beside(folioBinary) : Platform.resolvedExecutable;

  /// Folio Ajan's own folder: its lock and what it says of itself.
  static Future<Directory> folder() async {
    final dir = Directory(p.join((await folioSupportDirectory()).path, 'ajan'));
    await dir.create(recursive: true);
    return dir;
  }

  /// The folder Folio Ajan's tools ask Folio through ([ExternalHost]): the
  /// case chosen, the refreshes and downloads, Folio's word on itself.
  static Future<Directory> sessionFolder() async {
    final dir = Directory(p.join((await folder()).path, 'oturum'));
    await dir.create(recursive: true);
    final bound = File(p.join(dir.path, 'dosya.json'));
    if (!await bound.exists()) await bound.writeAsString('{}');
    return dir;
  }

  /// The open Folio's side of Folio Ajan's folder: says it is open (and
  /// whether this person sees money), does the refreshes and downloads
  /// asked, hands what was added to Senkron.
  static final host = ExternalHost(
    folder: sessionFolder,
    open: () async => true,
  );

  static Future<AiCaseSession> session() async =>
      AiCaseSession.at(await sessionFolder());

  static Future<File> _state() async =>
      File(p.join((await folder()).path, 'durum.json'));

  /// Folio Ajan says whether its window is on screen: Folio asks for the
  /// PIN there only then.
  static Future<void> setShown(bool shown) async {
    try {
      final file = await _state();
      final part = File('${file.path}.part');
      await part.writeAsString(
        jsonEncode({'gorunur': shown, 'pid': pid}),
        flush: true,
      );
      await part.rename(file.path);
    } catch (_) {}
  }

  /// Whether Folio Ajan's window is on screen, as it last said and while
  /// its program is still running.
  static Future<bool> shown() async {
    try {
      final json = jsonDecode(await (await _state()).readAsString());
      if (json is! Map || json['gorunur'] != true) return false;
      final owner = json['pid'];
      if (owner is! int) return false;
      if (Platform.isLinux) return Directory('/proc/$owner').existsSync();
      if (Platform.isWindows) return await _runningOnWindows(owner);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether the program [pid] still runs on Windows, and is Folio Ajan
  /// (a number Windows gave again is not it).
  static Future<bool> _runningOnWindows(int pid) async {
    try {
      final r = await Process.run('tasklist', [
        '/FI',
        'PID eq $pid',
        '/FO',
        'CSV',
        '/NH',
      ]).timeout(const Duration(seconds: 5));
      return '${r.stdout}'.toLowerCase().contains('"$binary.exe"');
    } catch (_) {
      return true;
    }
  }

  /// Whether the open Folio is there to do what Folio Ajan asks of it.
  static Future<bool> folioOpen() async =>
      (await FolioExternal.status(await sessionFolder())).open;

  /// [args] told to Folio Ajan; false when it is not running.
  static Future<bool> toAjan(List<String> args) async =>
      DesktopInstance.send(args, directory: await folder());

  /// [args] told to the open Folio; false when it is not open.
  static Future<bool> toFolio(List<String> args) => DesktopInstance.send(args);

  /// Folio Ajan shown ([args] empty) or told [args]; started when it is not
  /// running.
  static Future<void> openAjan({
    List<String> args = const [],
    String? token,
  }) async {
    final told = [
      if (args.isEmpty) show else ...args,
      if (token != null && token.isNotEmpty) '$tokenPrefix$token',
    ];
    if (await toAjan(told)) return;
    await _start(_beside(binary), told, token);
  }

  /// Folio running for what Folio Ajan asks of it (UYAP, UETS), in the
  /// tray with no window: the lawyer is talking to Folio Ajan, and Folio
  /// coming forward took them away from it (22 Kasım 2026).
  static Future<void> wakeFolio() async {
    if (await toFolio(const [background])) return;
    await _start(folioExecutable, const [background], null);
  }

  /// Whether Folio is running (its window shown or not): Folio Ajan does
  /// not listen on behind it when it is gone.
  static Future<bool> folioRunning() => toFolio(const [background]);

  /// Folio's window, started when Folio is not open.
  static Future<void> openFolio({String? token}) async {
    if (await toFolio(const [])) return;
    await _start(folioExecutable, const [], token);
  }

  static Future<void> _start(
    String executable,
    List<String> args,
    String? token,
  ) async {
    if (!File(executable).existsSync()) return;
    await Process.start(
      executable,
      args,
      mode: ProcessStartMode.detached,
      environment: {
        if (token != null && token.isNotEmpty) ...{
          'XDG_ACTIVATION_TOKEN': token,
          'DESKTOP_STARTUP_ID': token,
        },
      },
    );
  }
}
