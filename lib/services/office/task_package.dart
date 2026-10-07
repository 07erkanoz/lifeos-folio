import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import '../uyap/uyap_case_panel_controller.dart';
import '../uyap/uyap_case_store.dart';
import 'office_task.dart';

/// A task's case as it goes to those it is given to (docs/buro.md, Görev):
/// they cannot open it in UYAP, so its particulars, parties, list of
/// documents, hearings and money go with it, and the documents chosen,
/// those not yet here fetched from UYAP first.
class TaskPackage {
  const TaskPackage(this.paths, this.missing);

  /// The case's details as `dosya.json`, then its documents.
  final List<String> paths;

  /// Documents that could not be fetched: UYAP not connected, or refused.
  final List<String> missing;

  static const detailsName = 'dosya.json';

  static Future<TaskPackage> pack(
    TaskCase c, {
    UyapCaseStore? store,
    UyapCasePanelController? controller,
    Future<Directory> Function()? temp,
  }) async {
    final keep = store ?? UyapCaseStore.instance;
    final record = await keep.load(c.court, c.number);
    if (record == null) return const TaskPackage([], ['dosyanın kaydı']);
    final all = {
      for (final d in record.documents) ...{
        d.key: d,
        for (final a in d.attachments) a.key: a,
      },
    };
    final wanted = switch (c.docs) {
      TaskDocs.all => all.keys.toList(),
      TaskDocs.chosen => [
        for (final k in c.docKeys)
          if (all.containsKey(k)) k,
      ],
      TaskDocs.particulars => <String>[],
    };
    var current = record;
    final notHere = [
      for (final k in wanted)
        if (keep.fileOf(current, k) == null) k,
    ];
    if (notHere.isNotEmpty) {
      final panel = controller ?? UyapCasePanelController(store: keep);
      if (panel.connected) {
        try {
          await panel.show(current);
          await panel.download(notHere);
          current = await keep.load(c.court, c.number) ?? current;
        } catch (_) {}
      }
    }
    final dir = Directory(
      p.join(
        (await (temp ?? _temp)()).path,
        'gorev-paketi',
        UyapCaseStore.keyOf(c.court, c.number),
      ),
    );
    await dir.create(recursive: true);
    final details = File(p.join(dir.path, detailsName));
    final json = current.toJson()
      // Paths on the giver's disk mean nothing on the other's.
      ..['dosyalar'] = const <String, String>{}
      ..['onizlemeler'] = const <String, String>{}
      ..['bag'] = null
      ..['secili'] = wanted;
    await details.writeAsString(jsonEncode(json));
    final paths = [details.path];
    final missing = <String>[];
    for (final k in wanted) {
      final f = keep.fileOf(current, k);
      if (f == null) {
        final d = all[k]!;
        missing.add(d.type.isNotEmpty ? d.type : d.title);
      } else {
        paths.add(f.path);
      }
    }
    return TaskPackage(paths, missing);
  }

  static Future<Directory> _temp() => folioSupportDirectory();
}

/// What came of a task's case on this device: its details and documents.
class ReceivedCase {
  const ReceivedCase(this.details, this.documents);
  final Map<String, Object?> details;
  final List<String> documents;

  String get court => '${details['mahkeme'] ?? ''}';
  String get number => '${details['esas'] ?? ''}';
  Map<String, Object?> get particulars =>
      (details['kunye'] as Map? ?? const {}).cast<String, Object?>();
  List<Map<String, Object?>> get parties => [
    for (final t in (details['taraflar'] as List? ?? const []))
      if (t is Map) t.cast<String, Object?>(),
  ];

  static ReceivedCase? fromPaths(List<String> saved) {
    // Each case comes to a folder of its own, its details by their name.
    final json = saved
        .where((s) => p.basename(s) == TaskPackage.detailsName)
        .firstOrNull;
    if (json == null) return null;
    try {
      final d = jsonDecode(File(json).readAsStringSync());
      if (d is! Map) return null;
      return ReceivedCase(d.cast<String, Object?>(), [
        for (final s in saved)
          if (s != json) s,
      ]);
    } catch (_) {
      return null;
    }
  }
}

/// Which task cases are still to reach whom, and what came of those given
/// to this device; kept beside Folio's settings.
class TaskPackages {
  TaskPackages({Future<File> Function()? file}) : _file = file ?? _default;

  static Future<File> _default() async =>
      File(p.join((await folioSupportDirectory()).path, 'buro_paketler.json'));

  final Future<File> Function() _file;

  /// "task|case|device" → the files to send.
  final pending = <String, List<String>>{};

  /// "task|case" → the files that came.
  final _received = <String, List<String>>{};
  bool _loaded = false;

  ReceivedCase? received(String task, String caseKey) {
    final saved = _received['$task|$caseKey'];
    return saved == null ? null : ReceivedCase.fromPaths(saved);
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final j = jsonDecode(await file.readAsString());
      if (j is! Map) return;
      (j['bekleyen'] as Map? ?? const {}).forEach(
        (k, v) => pending['$k'] = [for (final x in v as List) '$x'],
      );
      (j['gelen'] as Map? ?? const {}).forEach(
        (k, v) => _received['$k'] = [for (final x in v as List) '$x'],
      );
    } catch (_) {}
  }

  Future<void> _saving = Future.value();
  Future<void> save() => _saving = _saving
      .then((_) async {
        final file = await _file();
        await file.parent.create(recursive: true);
        final part = File('${file.path}.part');
        await part.writeAsString(
          jsonEncode({'bekleyen': pending, 'gelen': _received}),
          flush: true,
        );
        await part.rename(file.path);
      })
      .catchError((Object _) {});

  Future<void> came(String task, String caseKey, List<String> saved) async {
    _received['$task|$caseKey'] = [...saved];
    await save();
  }
}
