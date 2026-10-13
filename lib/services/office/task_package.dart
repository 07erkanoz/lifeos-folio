import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import '../portal/observed.dart';
import '../portal/portal_case.dart';
import '../portal/portal_channel.dart';
import '../portal/portal_database.dart';
import '../portal/portal_hearing.dart';
import '../uyap/uyap_case_panel_controller.dart';
import '../uyap/uyap_case_store.dart';
import 'office_task.dart';

/// A task's case as it goes to those it is given to (docs/buro.md, Görev):
/// they cannot open it in UYAP, so its particulars, parties, list of
/// documents and money go with it, its hearings, deadlines, UETS notices
/// and the agenda's notes on it, and the documents chosen, those not yet
/// here fetched from UYAP first, one at a time.
class TaskPackage {
  const TaskPackage(this.paths, this.missing);

  /// The case's details as `dosya.json`, then its documents.
  final List<String> paths;

  /// Documents that could not be fetched: UYAP not connected, or refused.
  final List<String> missing;

  static const detailsName = 'dosya.json';

  /// The documents of [c] it would send that are not on this device yet:
  /// what has to come from UYAP before the task can go whole.
  static Future<int> notHere(TaskCase c, {UyapCaseStore? store}) async {
    final keep = store ?? UyapCaseStore.instance;
    final record = await keep.load(c.court, c.number);
    if (record == null) return 0;
    return [
      for (final k in _wanted(c, record))
        if (keep.fileOf(record, k) == null) k,
    ].length;
  }

  static List<String> _wanted(TaskCase c, UyapCaseRecord record) {
    final all = {
      for (final d in record.documents) ...[
        d.key,
        for (final a in d.attachments) a.key,
      ],
    };
    return switch (c.docs) {
      TaskDocs.all => all.toList(),
      TaskDocs.chosen => [
        for (final k in c.docKeys)
          if (all.contains(k)) k,
      ],
      TaskDocs.particulars => <String>[],
    };
  }

  /// [onProgress] hears what is being done: each document fetched, by its
  /// name and its place among them.
  static Future<TaskPackage> pack(
    TaskCase c, {
    UyapCaseStore? store,
    UyapCasePanelController? controller,
    Future<Directory> Function()? temp,
    Future<PortalDatabase?> Function()? database,
    void Function(String doing)? onProgress,
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
    final wanted = _wanted(c, record);
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
          // One at a time: one UYAP refuses does not keep the rest back.
          for (final (i, k) in notHere.indexed) {
            final d = all[k]!;
            onProgress?.call(
              'Evrak indiriliyor ${i + 1}/${notHere.length} · '
              '${d.type.isNotEmpty ? d.type : d.title}',
            );
            try {
              await panel.download([k]);
            } catch (_) {}
            if (i < notHere.length - 1) {
              await Future<void>.delayed(panel.pause);
            }
          }
          current = await keep.load(c.court, c.number) ?? current;
        } catch (_) {}
      }
    }
    onProgress?.call('${c.number} paketleniyor');
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
      ..['secili'] = wanted
      // Which file is which document, by its name: the documents come
      // beside it.
      ..['evrakAdlari'] = {
        for (final k in wanted)
          if (keep.fileOf(current, k) case final f?) k: p.basename(f.path),
      };
    try {
      final db = await (database ?? _database)();
      if (db != null) json.addAll(caseExtras(db, c.caseKey));
    } catch (_) {}
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

  static Future<PortalDatabase?> _database() async =>
      Platform.environment.containsKey('FLUTTER_TEST')
      ? null
      : PortalDatabase.shared();

  /// What the portals and the lawyer keep of the case beside its record:
  /// its hearings, the deadlines followed, its UETS notices and the
  /// agenda's notes and tasks on it. Plain words, as the other reads them.
  static Map<String, Object?> caseExtras(PortalDatabase db, String caseKey) {
    String? day(DateTime? at) => at?.toIso8601String();
    return {
      'durusmalar': [
        for (final h in db.hearings(caseKey: caseKey))
          {
            'tarih': day(h.at),
            'tur': h.kind?.value ?? '',
            'sonuc': h.result?.value ?? '',
          },
      ],
      'sureler': [
        for (final d in db.deadlines(decidedOnly: true))
          if (d.record.caseKey == caseKey && d.onAgenda && d.day != null)
            {
              'baslik': d.user?.titleOverride ?? d.record.title,
              'gun': d.day,
              'tamam': d.user?.done ?? false,
            },
        for (final a in db.agenda(caseKey: caseKey))
          if (a.kind == 'deadline')
            {'baslik': a.title, 'gun': day(a.at), 'tamam': a.done},
      ],
      'tebligatlar': [
        for (final n in db.notices(caseKey: caseKey))
          {
            'konu': n.message.subject,
            'gonderen': n.message.sender,
            'tarih': day(n.message.sent),
          },
      ],
      'notlar': [
        for (final a in db.agenda(caseKey: caseKey))
          if (a.kind != 'deadline')
            {
              'tur': a.kind,
              'baslik': a.title,
              'metin': a.body,
              'tarih': day(a.at),
              'tamam': a.done,
            },
      ],
    };
  }
}

/// What came of a task's case on this device: its details and documents.
class ReceivedCase {
  /// The meta key under which a case that came with a task is marked.
  static String markOf(String caseKey) => 'gorevle|$caseKey';

  /// The case kept on this device as one that came with a task (docs/
  /// buro.md, Görev): in Dava Dosyalarım with its hearings, its record
  /// and documents beside it, so that its page opens here as any case's
  /// does. Marked as such, by whom and with what task. Its key; null when
  /// it could not be kept.
  Future<String?> adopt({
    required String task,
    required String from,
    UyapCaseStore? store,
    Future<PortalDatabase?> Function()? database,
  }) async {
    if (store == null && Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }
    if (court.isEmpty || number.isEmpty) return null;
    final key = caseKey(number, court);
    try {
      final names = (details['evrakAdlari'] as Map? ?? const {});
      final byName = {for (final d in documents) p.basename(d): d};
      final files = <String, String>{
        for (final e in names.entries) '${e.key}': ?byName['${e.value}'],
      };
      await (store ?? UyapCaseStore.instance).adoptReceived(details, files);
    } catch (_) {}
    try {
      final db = await (database ?? PortalDatabase.shared)();
      if (db == null) return key;
      db.mergeCases([PortalCase.create(number: number, court: court)]);
      final now = DateTime.now();
      final came = [
        for (final h in hearings)
          if (DateTime.tryParse('${h['tarih']}') case final at?)
            PortalHearing.create(
              number: number,
              court: court,
              at: at,
              kind: '${h['tur'] ?? ''}'.isEmpty
                  ? null
                  : Observed(
                      '${h['tur']}',
                      PortalChannel.uyapWeb,
                      now,
                      complete: false,
                    ),
            ),
      ];
      if (came.isNotEmpty) {
        final days = came.map((h) => h.at).toList()..sort();
        db.mergeHearings(
          PortalChannel.uyapWeb,
          days.first,
          days.last,
          came,
          complete: false,
        );
      }
      db.setMeta(markOf(key), jsonEncode({'gorev': task, 'veren': from}));
    } catch (_) {}
    return key;
  }

  /// Whose task brought the case of [caseKey] here, and which; null for a
  /// case of the lawyer's own.
  static ({String task, String from})? markIn(
    PortalDatabase db,
    String caseKey,
  ) {
    final raw = db.meta(markOf(caseKey));
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      return (task: '${j['gorev'] ?? ''}', from: '${j['veren'] ?? ''}');
    } catch (_) {
      return null;
    }
  }

  const ReceivedCase(this.details, this.documents);
  final Map<String, Object?> details;
  final List<String> documents;

  String get court => '${details['mahkeme'] ?? ''}';
  String get number => '${details['esas'] ?? ''}';
  Map<String, Object?> get particulars =>
      (details['kunye'] as Map? ?? const {}).cast<String, Object?>();
  List<Map<String, Object?>> get parties => _list('taraflar');

  /// The case's hearings, newest last, as the giver's portals had them.
  List<Map<String, Object?>> get hearings =>
      _list('durusmalar')
        ..sort((a, b) => '${a['tarih']}'.compareTo('${b['tarih']}'));

  /// The deadlines the giver follows on it, by their last day.
  List<Map<String, Object?>> get deadlines =>
      _list('sureler')..sort((a, b) => '${a['gun']}'.compareTo('${b['gun']}'));

  /// Its UETS notices.
  List<Map<String, Object?>> get notices => _list('tebligatlar');

  /// The agenda's notes and tasks on it.
  List<Map<String, Object?>> get notes => _list('notlar');

  List<Map<String, Object?>> _list(String key) => [
    for (final t in (details[key] as List? ?? const []))
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

  /// "task|case" → the files a task given here sends: for a device its
  /// person adds later.
  final sources = <String, List<String>>{};

  /// "task|case|device" that came whole there.
  final delivered = <String>{};

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
      (j['kaynak'] as Map? ?? const {}).forEach(
        (k, v) => sources['$k'] = [for (final x in v as List) '$x'],
      );
      delivered.addAll([
        for (final x in (j['teslim'] as List? ?? const [])) '$x',
      ]);
    } catch (_) {}
  }

  Future<void> _saving = Future.value();
  Future<void> save() => _saving = _saving
      .then((_) async {
        final file = await _file();
        await file.parent.create(recursive: true);
        final part = File('${file.path}.part');
        await part.writeAsString(
          jsonEncode({
            'bekleyen': pending,
            'gelen': _received,
            'kaynak': sources,
            'teslim': delivered.toList(),
          }),
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
