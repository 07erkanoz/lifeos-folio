import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../portal/portal_case.dart';
import '../portal/portal_database.dart';
import 'ai_case.dart';
import 'ai_memory.dart';

/// Folio's tools for the lawyer's whole practice, in the AI program Folio
/// runs for a question ([AiCaseSession] names it): the agenda (hearings,
/// deadlines, tasks and notes), the e-notices (UETS), UYAP's notifications,
/// the cases, and a refresh from UYAP the running Folio does when asked.
/// What is secret is not given.
class FolioOfficeTools {
  FolioOfficeTools(
    this.folder, {
    Future<PortalDatabase> Function()? database,
    this.patience = const Duration(minutes: 3),
    this.every = const Duration(milliseconds: 500),
    DateTime Function()? now,
  }) : _database = database ?? _shared,
       _now = now ?? DateTime.now;

  static FolioOfficeTools? fromEnvironment([Map<String, String>? environment]) {
    final path = (environment ?? Platform.environment)[AiCaseSession.variable];
    if (path == null || path.isEmpty || !Directory(path).existsSync()) {
      return null;
    }
    return FolioOfficeTools(Directory(path));
  }

  final Directory folder;
  final Future<PortalDatabase> Function() _database;
  final DateTime Function() _now;
  final Duration patience, every;

  static Future<PortalDatabase> _shared() =>
      PortalDatabase.shared().timeout(const Duration(seconds: 20));

  static const _reads = {
    'readOnlyHint': true,
    'idempotentHint': true,
    'openWorldHint': false,
  };

  static const tools = <Map<String, Object?>>[
    {
      'name': 'ajanda',
      'title': 'Ajanda',
      'description':
          'Avukatın bütün dosyalarındaki duruşmalar, süreler, görevler ve '
          'notlar, tarih aralığıyla. Verilmezse bugünden itibaren yedi gün. '
          '"Bu hafta duruşmam var mı", "yarın ne var", "son günü yaklaşan '
          'süreler" gibi sorular için. Bilgi Folio\'nun son aldığı hâlidir; '
          'güncel değilse uyap_guncelle ile tazele.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'bas': {'type': 'string', 'description': 'YYYY-AA-GG'},
          'bit': {'type': 'string', 'description': 'YYYY-AA-GG (dahil)'},
        },
      },
      'annotations': _reads,
    },
    {
      'name': 'tebligatlar',
      'title': 'Elektronik tebligatlar',
      'description':
          'UETS\'ten gelen elektronik tebligatlar: konu, gönderen, tarih, '
          'okunup okunmadığı ve bağlı olduğu dosya.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'gun': {
            'type': 'integer',
            'minimum': 1,
            'description': 'Son kaç gün; varsayılan 30',
          },
          'okunmamis': {'type': 'boolean'},
        },
      },
      'annotations': _reads,
    },
    {
      'name': 'uyap_bildirimleri',
      'title': 'UYAP bildirimleri',
      'description':
          'UYAP\'ın gönderdiği bildirimler (yeni evrak, duruşma, karar): '
          'başlık, metin, tarih ve bağlı olduğu dosya.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'gun': {
            'type': 'integer',
            'minimum': 1,
            'description': 'Son kaç gün; varsayılan 14',
          },
          'okunmamis': {'type': 'boolean'},
        },
      },
      'annotations': _reads,
    },
    {
      'name': 'dosyalar',
      'title': 'Dosyalar',
      'description':
          'Avukatın dava ve icra dosyalarının listesi: esas no, mahkeme, '
          'durum, sıradaki duruşma ve anahtar. Sözcük verilirse yalnız ona '
          'uyanlar. Bir dosyanın ayrıntısı için dosya_ara ve dosya_sec.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'ifade': {'type': 'string'},
          'durum': {
            'type': 'string',
            'enum': ['acik', 'kapali', 'hepsi'],
          },
        },
      },
      'annotations': _reads,
    },
    {
      'name': 'uyap_baglantilari',
      'title': 'UYAP bağlantıları',
      'description':
          'Folio\'nun şu an hangi portallara bağlı olduğu: UYAP Web (e-imza '
          'ya da mobil imzayla; dosyaların tamamı, icra hesabı, tahsilat, '
          'Yargıtay ve savcılık dosyaları), UYAP Mobil (e-Devlet ile; dosya '
          'listesi, evrak, duruşmalar) ve UETS (tebligatlar). Güncelleme '
          'istemeden önce neyin alınabileceğini bilmek için.',
      'inputSchema': {'type': 'object', 'properties': <String, Object?>{}},
      'annotations': _reads,
    },
    {
      'name': 'uyap_guncelle',
      'title': 'UYAP\'tan güncelle',
      'description':
          'Açık Folio\'ya UYAP\'tan ya da UETS\'ten güncel bilgiyi aldırır: '
          'durusmalar (bütün duruşmalar), tebligatlar (UETS), bildirimler '
          '(UYAP bildirimleri), portfoy (yeni açılan dosyalar) ya da dosya '
          '(tek dosyanın bilgileri ve evrak listesi; UYAP Web bağlıysa icra '
          'hesabı, dosya borcu ve tahsilat da; anahtar gerekir). '
          'Yalnız bilgi eski görünüyorsa ya da avukat güncelini istiyorsa '
          'kullan; aynı şeyi tekrar tekrar isteme. Folio UYAP\'a bağlı '
          'değilse durum bunu söyler.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'kapsam': {
            'type': 'string',
            'enum': [
              'durusmalar',
              'tebligatlar',
              'bildirimler',
              'portfoy',
              'dosya',
            ],
          },
          'anahtar': {
            'type': 'string',
            'description': 'kapsam dosya ise dosyanın anahtarı',
          },
        },
        'required': ['kapsam'],
      },
      'annotations': {
        'readOnlyHint': false,
        'destructiveHint': false,
        'idempotentHint': true,
        'openWorldHint': true,
      },
    },
  ];

  static bool owns(String name) => tools.any((t) => t['name'] == name);

  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> args,
  ) async {
    if (name == 'uyap_guncelle') {
      return _refresh('${args['kapsam'] ?? ''}', '${args['anahtar'] ?? ''}');
    }
    if (name == 'uyap_baglantilari') return _refresh('baglantilar', '');
    final db = await _database();
    final cases = db.cases();
    Map<String, Object?> named(String? key) {
      final c = key == null ? null : cases[key];
      return c == null ? const {} : {'esas': c.number, 'mahkeme': c.court};
    }

    int days(Object? v, int fallback) =>
        v is num && v > 0 ? v.toInt() : fallback;
    switch (name) {
      case 'ajanda':
        return _agenda(db, args, named);
      case 'tebligatlar':
        final since = _now().subtract(Duration(days: days(args['gun'], 30)));
        return {
          'tebligatlar': [
            for (final n in db.notices())
              if ((n.message.sent ?? _now()).isAfter(since) &&
                  (args['okunmamis'] != true || !n.seen))
                {
                  'konu': n.message.subject,
                  'gonderen': n.message.sender,
                  'tarih': n.message.sent?.toIso8601String().substring(0, 16),
                  'okundu': n.seen,
                  ...named(n.caseKey),
                },
          ],
        };
      case 'uyap_bildirimleri':
        final since = _now().subtract(Duration(days: days(args['gun'], 14)));
        return {
          'bildirimler': [
            for (final n in db.uyapNotices(since: since))
              if (args['okunmamis'] != true || !n.read)
                {
                  'baslik': n.title,
                  'tarih': n.sentAt?.toIso8601String().substring(0, 16),
                  'okundu': n.read,
                  ...named(n.caseKey),
                  if (n.caseKey == null && n.named != null)
                    'adi_gecen_dosya': '${n.named!.number} ${n.named!.court}',
                },
          ],
        };
      case 'dosyalar':
        return _cases(db, cases, args);
    }
    throw StateError('Bilinmeyen araç: $name');
  }

  DateTime? _day(Object? text) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('${text ?? ''}');
    return m == null
        ? null
        : DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  static String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  Map<String, Object?> _agenda(
    PortalDatabase db,
    Map<String, Object?> args,
    Map<String, Object?> Function(String?) named,
  ) {
    final today = _now();
    final from =
        _day(args['bas']) ?? DateTime(today.year, today.month, today.day);
    final last = _day(args['bit']) ?? from.add(const Duration(days: 6));
    final to = last.add(const Duration(days: 1));
    final hearings = [
      for (final h in db.hearings(from: from, to: to))
        {
          'tarih': h.at.toIso8601String().substring(0, 16),
          'tur': ?h.kind?.value,
          'sonuc': ?h.result?.value,
          'esas': h.number,
          'mahkeme': h.court,
        },
    ]..sort((a, b) => '${a['tarih']}'.compareTo('${b['tarih']}'));
    final items = [
      for (final i in db.agenda(from: from, to: to))
        if (!i.secret)
          {
            'tur': switch (i.kind) {
              'task' => 'görev',
              'deadline' => 'süre',
              'note' => 'not',
              _ => i.kind,
            },
            'baslik': i.title,
            if (i.body.trim().isNotEmpty) 'aciklama': i.body,
            'tarih': i.at?.toIso8601String().substring(0, i.allDay ? 10 : 16),
            'bitti': i.done,
            ...named(i.caseKey),
          },
    ];
    final deadlines = [
      for (final d in db.deadlines())
        if (d.record.dueDay case final due?
            when due.compareTo(_iso(from)) >= 0 &&
                due.compareTo(_iso(last)) <= 0)
          {
            'son_gun': due,
            'baslik': d.record.title,
            if (d.record.law.isNotEmpty) 'dayanak': d.record.law,
            'onaylandi': d.confirmed,
            ...named(d.record.caseKey),
          },
    ]..sort((a, b) => '${a['son_gun']}'.compareTo('${b['son_gun']}'));
    return {
      'aralik': '${_iso(from)} – ${_iso(last)}',
      'durusmalar': hearings,
      'sureler': deadlines,
      'gorev_ve_notlar': items,
      'not':
          'Süreler Folio\'nun hesapladığıdır; onaylanmamış olanı avukat '
          'denetlemedi.',
    };
  }

  Map<String, Object?> _cases(
    PortalDatabase db,
    Map<String, PortalCase> cases,
    Map<String, Object?> args,
  ) {
    final now = _now();
    final next = <String, DateTime>{};
    for (final h in db.hearings(
      from: now,
      to: now.add(const Duration(days: 365)),
    )) {
      final kept = next[h.caseKey];
      if (kept == null || h.at.isBefore(kept)) next[h.caseKey] = h.at;
    }
    final words = '${args['ifade'] ?? ''}'.trim();
    final wanted = words.isEmpty
        ? cases.values.toList()
        : [
            for (final e in AiCaseEntry.match(words, [
              for (final c in cases.values)
                AiCaseEntry(key: c.key, number: c.number, court: c.court),
            ]))
              cases[e.key]!,
          ];
    final which = '${args['durum'] ?? 'acik'}';
    bool open(PortalCase c) {
      final s = (c.status?.value ?? '').toLowerCase();
      return !(s.contains('kapal') ||
          s.contains('karar') && s.contains('kesin'));
    }

    final out =
        [
          for (final c in wanted)
            if (which == 'hepsi' || (which == 'kapali') != open(c))
              {
                'anahtar': c.key,
                'esas': c.number,
                'mahkeme': c.court,
                if (c.status?.value case final s? when s.isNotEmpty) 'durum': s,
                if (next[c.key] case final at?)
                  'siradaki_durusma': at.toIso8601String().substring(0, 16),
              },
        ]..sort(
          (a, b) => (a['siradaki_durusma'] ?? '9').compareTo(
            b['siradaki_durusma'] ?? '9',
          ),
        );
    return {
      'toplam': out.length,
      'dosyalar': out.take(300).toList(),
      if (out.length > 300) 'not': 'İlk 300 dosya verildi; ifade ile daralt.',
    };
  }

  /// A refresh asked of the running Folio, waited for.
  Future<Map<String, Object?>> _refresh(String scope, String key) async {
    if (!const {
      'durusmalar',
      'tebligatlar',
      'bildirimler',
      'portfoy',
      'dosya',
      'baglantilar',
    }.contains(scope)) {
      return {'durum': 'yok', 'aciklama': 'Bilinmeyen kapsam.'};
    }
    if (scope == 'dosya' && key.isEmpty) {
      return {'durum': 'yok', 'aciklama': 'Dosyanın anahtarı gerekir.'};
    }
    final id = AiMemory.id();
    final asked = File(p.join(folder.path, 'guncelle-$id.json'));
    final part = File('${asked.path}.part');
    await part.writeAsString(
      jsonEncode({'kapsam': scope, if (key.isNotEmpty) 'anahtar': key}),
    );
    await part.rename(asked.path);
    final answer = File(p.join(folder.path, 'guncelle-$id.sonuc.json'));
    final until = DateTime.now().add(patience);
    while (DateTime.now().isBefore(until)) {
      if (await answer.exists()) {
        try {
          return (jsonDecode(await answer.readAsString()) as Map)
              .cast<String, Object?>();
        } on FormatException {
          // Being written.
        }
      }
      await Future<void>.delayed(every);
    }
    return {
      'durum': 'yanitsiz',
      'aciklama': 'Güncelleme zamanında bitmedi; elindeki bilgiyle sürdür.',
    };
  }
}
