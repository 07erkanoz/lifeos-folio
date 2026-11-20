import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import '../portal/portal_database.dart';
import '../uyap/uyap_case_store.dart';
import 'ai_case.dart';
import 'ai_refresh.dart';

/// Folio's tools for the AI programs on this computer that Folio does not
/// start itself: Folio Ajan, Claude Code, Codex or any other MCP client the
/// lawyer adds `lifeos_folio --mcp --dis` to. They have what the lawyer
/// can see in Folio, read, and may add an agenda entry or a note; nothing
/// else is written.
///
/// Off until the lawyer turns it on (Ayarlar › Yapay zekâ). The switch is
/// this computer's alone: it lives in `dis-erisim.json`, which Senkron does
/// not carry, so turning it on here does not open the lawyer's other
/// devices.
///
/// The programs share one folder, `dis-ajan`, as a question Folio runs has
/// a folder of its own ([AiCaseSession]): the case they chose (dosya.json),
/// the refreshes and downloads they asked the open Folio for, and what the
/// open Folio says of itself ([status]).
abstract final class FolioExternal {
  /// After [FolioMcp.flag]: the tools for the programs on this computer.
  static const flag = '--dis';

  /// The switch as last read or set, for the settings page.
  static final on = ValueNotifier<bool>(false);

  static Future<File> _settings() async =>
      File(p.join((await folioSupportDirectory()).path, 'dis-erisim.json'));

  /// Whether the lawyer turned it on; read from its file every time, as
  /// the open Folio may have turned it off since.
  static Future<bool> enabled() async {
    try {
      final file = await _settings();
      if (!await file.exists()) return on.value = false;
      final json = jsonDecode(await file.readAsString());
      return on.value = json is Map && json['acik'] == true;
    } catch (_) {
      return on.value = false;
    }
  }

  static Future<void> setEnabled(bool value) async {
    final file = await _settings();
    await file.parent.create(recursive: true);
    await _writeWhole(
      file,
      utf8.encode(
        jsonEncode({
          'acik': value,
          'degisti': DateTime.now().toIso8601String(),
        }),
      ),
    );
    on.value = value;
  }

  /// The programs' folder, made with an unbound case when it is not there.
  static Future<Directory> folder() async {
    final dir = Directory(
      p.join((await folioSupportDirectory()).path, 'dis-ajan'),
    );
    await dir.create(recursive: true);
    final bound = File(p.join(dir.path, 'dosya.json'));
    if (!await bound.exists()) {
      await _writeWhole(bound, utf8.encode('{}'));
    }
    return dir;
  }

  /// What the open Folio last wrote of itself; older than this, it is
  /// taken as closed.
  static const alive = Duration(seconds: 15);

  /// The open Folio, as it wrote of itself in [dir]: whether it is open,
  /// and whether the person may see the clients' money (an office member
  /// without that right may not). With no open Folio, the money is seen
  /// only by a lawyer of no office: who may see it is the office's word,
  /// which the open Folio holds.
  static Future<({bool open, bool money})> status(
    Directory dir, {
    DateTime? now,
  }) async {
    final file = File(p.join(dir.path, 'durum.json'));
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map) {
        final at = DateTime.tryParse('${json['zaman']}');
        final open =
            at != null && (now ?? DateTime.now()).difference(at) < alive;
        if (open) return (open: true, money: json['para'] != false);
        return (open: false, money: json['buro'] != true);
      }
    } catch (_) {}
    return (open: false, money: !await _inOffice());
  }

  static Future<bool> _inOffice() async {
    try {
      final file = File(
        p.join((await folioSupportDirectory()).path, 'buro_defter.json'),
      );
      return await file.exists() && (await file.length()) > 2;
    } catch (_) {
      return true;
    }
  }

  /// Written by a program after it added to the agenda: the open Folio
  /// hands the change to Senkron ([ExternalHost]).
  static Future<void> changed(Directory dir) => _writeWhole(
    File(p.join(dir.path, 'degisti-${DateTime.now().microsecondsSinceEpoch}')),
    const [],
  );
}

/// The open Folio's side: while the programs may use Folio, it says it is
/// open, does the refreshes and downloads they ask for, and hands what they
/// added to the agenda to Senkron.
class ExternalHost {
  ExternalHost({this._store});

  static final instance = ExternalHost();

  final UyapCaseStore? _store;
  UyapCaseStore get store => _store ?? UyapCaseStore.instance;

  /// Whether this person sees the clients' money, and is in an office;
  /// set by Folio's network once it is up.
  static bool Function() seesMoney = () =>
      PortalDatabase.clientMoneyAllowed?.call() ?? true;
  static bool Function() inOffice = () => false;

  Timer? _timer;
  bool _busy = false;
  AiCaseSession? _session;
  DateTime _said = DateTime.fromMillisecondsSinceEpoch(0);

  void start() {
    _timer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(tick()),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One look: nothing while the switch is off.
  Future<void> tick({DateTime? now}) async {
    if (_busy) return;
    _busy = true;
    try {
      if (!await FolioExternal.enabled()) return;
      final dir = await FolioExternal.folder();
      final at = now ?? DateTime.now();
      if (at.difference(_said) >= const Duration(seconds: 5)) {
        _said = at;
        await _writeWhole(
          File(p.join(dir.path, 'durum.json')),
          utf8.encode(
            jsonEncode({
              'zaman': at.toIso8601String(),
              'para': seesMoney(),
              'buro': inOffice(),
            }),
          ),
        );
      }
      final session = _session ??= AiCaseSession.at(dir);
      final bound = await session.bound();
      session.record = bound == null
          ? null
          : await store.load(bound.court, bound.number);
      await AiRefresh.serve(session);
      await AiRefresh.serveDownloads(session);
      var added = false;
      await for (final entry in dir.list()) {
        if (entry is File && p.basename(entry.path).startsWith('degisti-')) {
          added = true;
          try {
            await entry.delete();
          } catch (_) {}
        }
      }
      if (added) PortalDatabase.changed?.call();
    } catch (e) {
      debugPrint('Dış yapay zekâ: $e');
    } finally {
      _busy = false;
    }
  }
}

/// [bytes] in [file], seen by the other side only once whole.
Future<void> _writeWhole(File file, List<int> bytes) async {
  final part = File('${file.path}.part');
  await part.writeAsBytes(bytes, flush: true);
  await part.rename(file.path);
}
