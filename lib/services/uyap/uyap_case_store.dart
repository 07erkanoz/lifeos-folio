import 'uyap_enforcement.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import '../platform/atomic_file.dart';
import 'uyap_case_links.dart';
import 'uyap_web_service.dart';

/// Where UYAP's documents are kept, and whether they are kept at all.
class UyapSettings extends ChangeNotifier {
  UyapSettings({this._directory, this._home});

  static UyapSettings instance = UyapSettings();

  final Directory? _directory;
  final String? _home;

  bool _saveDocuments = true;
  String? _folder;
  bool _loaded = false;

  /// Documents fetched from UYAP are saved where Folio searches, unless the
  /// lawyer says otherwise; then they stay in Folio's own cache.
  bool get saveDocuments => _saveDocuments;

  /// Folio's folder in the home folder rather than under Documents: Windows
  /// moves Documents into OneDrive, and a client's papers are not to be
  /// sent to a cloud by the way they were put away.
  String get folder => _folder ?? defaultFolder;

  String get defaultFolder {
    final home =
        _home ??
        Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ??
        Directory.systemTemp.path;
    // On an iPhone, in Folio's Documents: the one folder of an app's that
    // the Files app shows ("Bu iPhone'da › LifeOS Folio").
    if (Platform.isIOS && _home == null) {
      return p.join(home, 'Documents', 'UYAP');
    }
    return p.join(home, 'Folio', 'UYAP');
  }

  Future<File> _file() async => File(
    p.join((_directory ?? await folioSharedDirectory()).path, 'uyap.json'),
  );

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final json = jsonDecode(await (await _file()).readAsString());
      if (json is Map) {
        _saveDocuments = json['kaydet'] != false;
        final folder = json['klasor'];
        _folder = folder is String && folder.isNotEmpty
            ? ownPath(folder)
            : null;
      }
    } catch (_) {
      // None yet, or unreadable: the defaults.
    }
    notifyListeners();
  }

  Future<void> update({bool? saveDocuments, String? folder}) async {
    if (saveDocuments != null) _saveDocuments = saveDocuments;
    if (folder != null) _folder = folder;
    notifyListeners();
    final file = await _file();
    await replaceFileIfChanged(
      file,
      utf8.encode(jsonEncode({'kaydet': _saveDocuments, 'klasor': _folder})),
    );
  }
}

/// A case as it was last fetched: its particulars, parties and documents,
/// when they were fetched, what came new then, and which documents are on
/// disk. Enough to work with the case without a connection.
class UyapCaseRecord {
  const UyapCaseRecord({
    required this.court,
    required this.number,
    required this.fetchedAt,
    this.previousFetchedAt,
    this.details = const UyapCaseDetails(),
    this.parties = const [],
    this.documents = const [],
    this.withheld,
    this.fresh = const {},
    this.files = const {},
    this.previews = const {},
    this.link,
    this.money,
    this.enforcement,
    this.hidden = const {},
  });

  /// An enforcement file's account and debtors, when UYAP gave them.
  final UyapEnforcement? enforcement;

  final String court, number;

  /// Where the case is in UYAP, to find it again in a later session:
  /// without it the case can be shown but not fetched again. Null in a
  /// record an earlier Folio kept.
  final UyapCaseLink? link;

  /// The fees, collections and payments out, when UYAP gave them.
  final UyapCaseMoney? money;

  /// What UYAP does not show of a case of this kind: 'ayrinti_bilgileri'
  /// for a criminal case's particulars, and the like. Said, not left blank.
  final Set<String> hidden;
  final DateTime fetchedAt;

  /// When it was fetched the time before: what is [fresh] came after it.
  final DateTime? previousFetchedAt;
  final UyapCaseDetails details;
  final List<UyapParty> parties;
  final List<UyapCaseDocument> documents;
  final String? withheld;

  /// The keys of documents that were not there the time before.
  final Set<String> fresh;

  /// Documents on disk, by key.
  final Map<String, String> files;

  /// What an earlier Folio saved in their place: the PDF the portal shows a
  /// document as, not the document. Not taken for the document; replaced by
  /// it when it is fetched.
  final Map<String, String> previews;

  String get key => UyapCaseStore.keyOf(court, number);

  UyapCaseRecord copyWith({
    Map<String, String>? files,
    Map<String, String>? previews,
    Set<String>? fresh,
    UyapCaseLink? link,
  }) => UyapCaseRecord(
    court: court,
    number: number,
    fetchedAt: fetchedAt,
    previousFetchedAt: previousFetchedAt,
    details: details,
    parties: parties,
    documents: documents,
    withheld: withheld,
    fresh: fresh ?? this.fresh,
    files: files ?? this.files,
    previews: previews ?? this.previews,
    link: link ?? this.link,
    money: money,
    enforcement: enforcement,
    hidden: hidden,
  );

  Map<String, Object?> toJson() => {
    // 2: the documents are the documents, not the portal's PDF of them.
    'surum': 2,
    'mahkeme': court,
    'esas': number,
    'cekildi': fetchedAt.toIso8601String(),
    'oncekiCekim': previousFetchedAt?.toIso8601String(),
    'kunye': details.toJson(),
    'taraflar': [
      for (final t in parties)
        {'ad': t.name, 'rol': t.role, 'vekil': t.lawyer, 'tur': t.kind},
    ],
    'evraklar': [for (final d in documents) d.toJson()],
    'engel': withheld,
    'yeni': fresh.toList(),
    'dosyalar': files,
    'onizlemeler': previews,
    'bag': link?.toJson(),
    'para': money?.toJson(),
    'icra': enforcement?.toJson(),
    'gizli': hidden.toList(),
  };

  factory UyapCaseRecord.fromJson(Map<String, Object?> json) => UyapCaseRecord(
    court: '${json['mahkeme'] ?? ''}',
    number: '${json['esas'] ?? ''}',
    fetchedAt: DateTime.parse('${json['cekildi']}'),
    previousFetchedAt: json['oncekiCekim'] == null
        ? null
        : DateTime.tryParse('${json['oncekiCekim']}'),
    details: UyapCaseDetails.stored(
      (json['kunye'] as Map? ?? const {}).cast<String, Object?>(),
    ),
    parties: [
      for (final t in (json['taraflar'] as List? ?? const []))
        if (t is Map)
          UyapParty(
            '${t['ad'] ?? ''}',
            '${t['rol'] ?? ''}',
            '${t['vekil'] ?? ''}',
            '${t['tur'] ?? ''}',
          ),
    ],
    documents: [
      for (final d in (json['evraklar'] as List? ?? const []))
        if (d is Map) UyapCaseDocument.stored(d.cast<String, Object?>()),
    ],
    withheld: json['engel'] as String?,
    fresh: {for (final k in (json['yeni'] as List? ?? const [])) '$k'},
    files: json['surum'] == 1 ? const {} : _paths(json['dosyalar']),
    previews: {
      ..._paths(json['onizlemeler']),
      if (json['surum'] == 1) ..._paths(json['dosyalar']),
    },
    link: UyapCaseLink.fromJson(json['bag']),
    money: json['para'] is Map
        ? UyapCaseMoney.stored(json['para'] as Map)
        : null,
    enforcement: json['icra'] is Map
        ? UyapEnforcement.stored(json['icra'] as Map)
        : null,
    hidden: {for (final k in (json['gizli'] as List? ?? const [])) '$k'},
  );

  static Map<String, String> _paths(Object? json) => {
    for (final e in (json as Map? ?? const {}).entries)
      '${e.key}': '${e.value}',
  };
}

/// The cases fetched from UYAP, kept on this computer.
class UyapCaseStore {
  UyapCaseStore({this._directory, this._settings});

  static final _real = UyapCaseStore();
  static UyapCaseStore instance = _real;

  /// Whether the store is the one on this computer's own folders, rather
  /// than one a test put in its place.
  static bool get isReal => identical(instance, _real);

  /// Ticks when a case is kept or a document saved, for what lists them.
  static final changes = ValueNotifier<int>(0);

  final Directory? _directory;
  final UyapSettings? _settings;
  UyapSettings get settings => _settings ?? UyapSettings.instance;

  Future<Directory> _root() async => Directory(
    p.join((_directory ?? await folioSharedDirectory()).path, 'uyap'),
  );

  /// A case is known by its court and number: the ids UYAP gives it are
  /// the session's.
  static String keyOf(String court, String number) => sha256
      .convert(
        utf8.encode(
          '${UyapWebService.fold(number)}|${UyapWebService.fold(court)}',
        ),
      )
      .toString()
      .substring(0, 32);

  Future<File> _recordFile(String key) async =>
      File(p.join((await _root()).path, 'dosyalar', '$key.json'));

  Future<UyapCaseRecord?> load(String court, String number) async {
    final file = await _recordFile(keyOf(court, number));
    try {
      final json = jsonDecode(await file.readAsString());
      return json is Map
          ? UyapCaseRecord.fromJson(json.cast<String, Object?>())
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(UyapCaseRecord record) async {
    await replaceFileIfChanged(
      await _recordFile(record.key),
      utf8.encode(jsonEncode(record.toJson())),
    );
    changes.value++;
  }

  /// The folder [record]'s documents are saved in, when they are saved.
  String folderOf(UyapCaseRecord record) =>
      p.join(settings.folder, caseFolderName(record));

  /// Every case kept on this computer, each with how many of its documents
  /// are saved where Folio searches; the last fetched first. A case is
  /// listed once it has been fetched, a document or none.
  Future<List<(UyapCaseRecord, int)>> cases({bool counted = true}) async {
    await settings.load();
    final folder = Directory(p.join((await _root()).path, 'dosyalar'));
    if (!await folder.exists()) return const [];
    final stats = <String, FileStat>{};
    await for (final entry in folder.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      stats[entry.path] = await entry.stat();
    }
    // Only what changed since it was last read is read again: hundreds of
    // cases are megabytes of JSON, most of it their documents' lists.
    bool same(String path) {
      final kept = _parsed[path], stat = stats[path]!;
      return kept != null && kept.$1 == stat.modified && kept.$2 == stat.size;
    }

    final stale = [
      for (final path in stats.keys)
        if (!same(path)) path,
    ];
    if (stale.isNotEmpty) {
      final bytes = stale.fold<int>(0, (n, path) => n + stats[path]!.size);
      // Much of it is read apart, for the window not to stand still.
      final read = bytes > 512 * 1024
          ? await _readApart(stale)
          : _readRecords(stale);
      for (final path in stale) {
        final record = read[path];
        if (record == null) {
          _parsed.remove(path);
        } else {
          _parsed[path] = (stats[path]!.modified, stats[path]!.size, record);
        }
      }
    }
    _parsed.removeWhere(
      (path, _) => p.isWithin(folder.path, path) && !stats.containsKey(path),
    );
    final out = <(UyapCaseRecord, int)>[
      for (final path in stats.keys)
        if (_parsed[path] case (_, _, final record))
          (record, counted ? savedFiles(record).length : 0),
    ];
    out.sort((a, b) => b.$1.fetchedAt.compareTo(a.$1.fetchedAt));
    return out;
  }

  /// Records read before, by file: when and how large the file was then.
  static final _parsed = <String, (DateTime, int, UyapCaseRecord)>{};

  // Not inside an async body: there the closure would hold its futures,
  // which cannot go to another isolate.
  static Future<Map<String, UyapCaseRecord>> _readApart(List<String> paths) =>
      Isolate.run(() => _readRecords(paths));

  static Map<String, UyapCaseRecord> _readRecords(List<String> paths) => {
    for (final path in paths) path: ?_readRecord(path),
  };

  static UyapCaseRecord? _readRecord(String path) {
    try {
      final json = jsonDecode(File(path).readAsStringSync());
      // A record that cannot be read is not listed.
      return json is Map
          ? UyapCaseRecord.fromJson(json.cast<String, Object?>())
          : null;
    } catch (_) {
      return null;
    }
  }

  /// [record]'s documents saved in its folder where Folio searches and
  /// still there, by key: what a case's page lists as downloaded.
  Map<String, File> savedFiles(UyapCaseRecord record) {
    final where = folderOf(record);
    return {
      for (final e in {...record.previews, ...record.files}.entries)
        if (p.isWithin(where, e.value) && File(e.value).existsSync())
          e.key: File(e.value),
    };
  }

  /// Forgets [record]: Folio no longer lists it, and UYAP is not touched.
  /// [documents] also deletes what was downloaded of it.
  Future<void> remove(UyapCaseRecord record, {bool documents = false}) async {
    if (documents) {
      for (final path in {...record.files.values, ...record.previews.values}) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      final folder = Directory(folderOf(record));
      if (await folder.exists() && await folder.list().isEmpty) {
        await folder.delete();
      }
    }
    final file = await _recordFile(record.key);
    if (await file.exists()) await file.delete();
    changes.value++;
  }

  /// Keeps what was just fetched of a case. What was not there the time
  /// before is marked new; what is on disk stays on disk.
  Future<UyapCaseRecord> keep({
    required UyapCase target,
    required UyapCaseDetails details,
    required List<UyapParty> parties,
    required UyapCaseDocuments documents,
    UyapCaseLink? link,
    UyapCaseMoney? money,
    UyapEnforcement? enforcement,
    Set<String> hidden = const {},
    DateTime? now,
  }) async {
    final before = await load(target.courtName, target.number);
    final previousKeys = before == null ? null : _keys(before.documents);
    final keys = _keys(documents.documents);
    final record = UyapCaseRecord(
      court: target.courtName,
      number: target.number,
      fetchedAt: now ?? DateTime.now(),
      previousFetchedAt: before?.fetchedAt,
      details: details,
      parties: parties,
      // Withheld is not "none": the list kept from before stays.
      documents: documents.withheld != null && before != null
          ? before.documents
          : documents.documents,
      withheld: documents.withheld,
      // The first time, nothing is new: everything is.
      fresh: previousKeys == null
          ? const {}
          : keys
                .difference(previousKeys)
                .union(before!.fresh.intersection(keys)),
      files: before?.files ?? const {},
      previews: before?.previews ?? const {},
      link: link ?? before?.link,
      // Money that could not be had this time is not money gone.
      money: money ?? before?.money,
      enforcement: enforcement ?? before?.enforcement,
      hidden: hidden,
    );
    // The same answer as before is not written again: only a new document,
    // party, sum or state is news, not the time it was asked.
    if (before != null && _sameContent(record, before)) return before;
    await _write(record);
    return record;
  }

  static bool _sameContent(UyapCaseRecord a, UyapCaseRecord b) {
    Map<String, Object?> content(UyapCaseRecord r) => r.toJson()
      ..remove('cekildi')
      ..remove('oncekiCekim');
    return jsonEncode(content(a)) == jsonEncode(content(b));
  }

  static Set<String> _keys(List<UyapCaseDocument> documents) => {
    for (final d in documents) ...[d.key, for (final a in d.attachments) a.key],
  };

  /// Takes every document off the new ones: the case has been opened.
  Future<UyapCaseRecord> seenAll(UyapCaseRecord record) async {
    if (record.fresh.isEmpty) return record;
    final next = record.copyWith(fresh: const {});
    await _write(next);
    return next;
  }

  /// Takes [key] off the new ones: it has been looked at.
  Future<UyapCaseRecord> seen(UyapCaseRecord record, String key) async {
    if (!record.fresh.contains(key)) return record;
    final next = record.copyWith(fresh: {...record.fresh}..remove(key));
    await _write(next);
    return next;
  }

  /// Whether [bytes] are already on disk as another document of [record]:
  /// two documents are never one file.
  bool sameAsAnother(UyapCaseRecord record, String key, List<int> bytes) {
    final digest = sha256.convert(bytes);
    for (final MapEntry(key: other, value: path) in record.files.entries) {
      if (other == key) continue;
      final file = File(path);
      try {
        if (file.lengthSync() == bytes.length &&
            sha256.convert(file.readAsBytesSync()) == digest) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  /// [record] without the files two documents or more share by content: an
  /// earlier Folio's mobile download could save one document's content for
  /// several. Those files Folio put in the case's folders are deleted, the
  /// documents are no longer marked downloaded, and are fetched again.
  ///
  /// Every file of the case is read and hashed, off the window's isolate,
  /// and only when the case's files changed since they were last looked
  /// at: done at each opening, it held the window for seconds.
  Future<UyapCaseRecord> dropSameContent(UyapCaseRecord record) async {
    if (record.files.length < 2) return record;
    final files = Map<String, String>.from(record.files);
    final signature =
        (files.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => '${e.key}=${e.value}')
            .join('|');
    if (_checkedFiles[record.key] == signature) return record;
    final digests = await Isolate.run(() {
      final out = <String, String>{};
      for (final MapEntry(key: key, value: path) in files.entries) {
        try {
          out[key] = sha256.convert(File(path).readAsBytesSync()).toString();
        } catch (_) {}
      }
      return out;
    });
    final byDigest = <String, List<String>>{};
    for (final MapEntry(key: key, value: digest) in digests.entries) {
      (byDigest[digest] ??= []).add(key);
    }
    final shared = {
      for (final keys in byDigest.values)
        if (keys.length > 1) ...keys,
    };
    if (shared.isEmpty) {
      _checkedFiles[record.key] = signature;
      return record;
    }
    await settings.load();
    final ours = [settings.folder, p.join((await _root()).path, 'belgeler')];
    for (final key in shared) {
      final path = files.remove(key)!;
      if (ours.any((root) => p.isWithin(root, path))) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
    final next = record.copyWith(files: files);
    await _write(next);
    return next;
  }

  /// Each case's files as they were when last found to hold no copies,
  /// in this run: looked at again only when they change.
  final _checkedFiles = <String, String>{};

  /// The document of [key] on disk, if it is there still.
  File? fileOf(UyapCaseRecord record, String key) {
    final path = record.files[key];
    if (path == null) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  /// Puts [bytes] of [document] on disk: in the case's own folder under
  /// the UYAP folder when documents are saved, in Folio's cache when not.
  Future<(UyapCaseRecord, File)> save(
    UyapCaseRecord record,
    UyapCaseDocument document,
    Uint8List bytes,
  ) async {
    await settings.load();
    final folder = settings.saveDocuments
        ? Directory(p.join(settings.folder, caseFolderName(record)))
        : Directory(p.join((await _root()).path, 'belgeler', record.key));
    await folder.create(recursive: true);
    final kind = kindOf(bytes);
    final existing = fileOf(record, document.key);
    final preview = record.previews[document.key];
    final File file;
    if (existing != null &&
        p.isWithin(folder.path, existing.path) &&
        p.extension(existing.path) == '.$kind') {
      file = existing;
    } else {
      file = _unique(folder, fileName(document, kind));
    }
    final part = File('${file.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(file.path);
    // What Folio itself put there before, the portal's PDF of it or the
    // same document under another kind, gives way to it.
    for (final old in [existing?.path, preview]) {
      if (old != null &&
          old != file.path &&
          p.isWithin(folder.path, old) &&
          File(old).existsSync()) {
        await File(old).delete();
      }
    }
    final next = record.copyWith(
      files: {...record.files, document.key: file.path},
      previews: {...record.previews}..remove(document.key),
    );
    await _write(next);
    return (next, file);
  }

  /// "İstanbul Anadolu 5. Aile Mahkemesi 2026-1204 Esas".
  static String caseFolderName(UyapCaseRecord record) =>
      _safe('${record.court} ${record.number.replaceAll('/', '-')} Esas');

  /// "2026-03-31 Bilirkişi Raporu.udf".
  static String fileName(UyapCaseDocument document, String extension) {
    final date = document.date;
    final day = date == null
        ? ''
        : '${date.year.toString().padLeft(4, '0')}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')} ';
    var name = _safe('$day${document.title}');
    if (name.length > 100) name = name.substring(0, 100).trimRight();
    return '${name.isEmpty ? 'Evrak' : name}.$extension';
  }

  static File _unique(Directory folder, String name) {
    var file = File(p.join(folder.path, name));
    final base = p.withoutExtension(name);
    final ext = p.extension(name);
    for (var i = 2; file.existsSync(); i++) {
      file = File(p.join(folder.path, '$base ($i)$ext'));
    }
    return file;
  }

  /// What Windows and Linux both allow in a name.
  static String _safe(String value) => value
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');

  /// What kind of file UYAP sent, by its first bytes: a UDF is a zip with
  /// content.xml in it, a Word file one with word/document.xml.
  static String kindOf(Uint8List bytes) {
    bool starts(List<int> magic) =>
        bytes.length >= magic.length &&
        [for (var i = 0; i < magic.length; i++) bytes[i]].join(',') ==
            magic.join(',');
    if (starts([0x25, 0x50, 0x44, 0x46])) return 'pdf';
    if (starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A])) {
      return 'tif';
    }
    if (starts([0x50, 0x4B])) {
      try {
        final names = ZipDecoder().decodeBytes(bytes).files.map((f) => f.name);
        if (names.contains('content.xml')) return 'udf';
        if (names.contains('word/document.xml')) return 'docx';
      } catch (_) {}
      return 'zip';
    }
    if (starts([0xFF, 0xD8, 0xFF])) return 'jpg';
    if (starts([0x89, 0x50, 0x4E, 0x47])) return 'png';
    final head = utf8
        .decode(bytes.take(64).toList(), allowMalformed: true)
        .trimLeft();
    if (head.startsWith('<?xml') || head.startsWith('<')) return 'xml';
    return 'bin';
  }
}
