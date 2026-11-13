import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

/// A document's annexes filed apart from its text, read from mevzuat.gov.tr:
/// a tariff's tables (the Avukatlık Asgari Ücret Tarifesi's amounts are all
/// in its "-Ek.doc"), a regulation's forms and specifications. The bank's
/// text says only "Eki için tıklayınız"; without the annex a model is left
/// to guess the figures. The rules are banaozel's (server/mevzuat_belge.py):
/// only the Mevzuat Bilgi Sistemi's own files, at most [mostBytes] each, the
/// text read by Folio's own reader.
class LegislationAnnexes {
  LegislationAnnexes({
    required this.textOf,
    @visibleForTesting Future<Uint8List> Function(Uri uri)? download,
  }) : _download = download ?? _get;

  /// A file's text by Folio's reader (.doc, .docx, .pdf, .rtf, .xlsx…).
  final Future<String> Function(String path) textOf;
  final Future<Uint8List> Function(Uri uri) _download;

  static const hosts = {'mevzuat.gov.tr', 'www.mevzuat.gov.tr'};
  static const mostBytes = 25 * 1024 * 1024;

  /// The most annexes read with one document, and the most of each.
  static const mostAnnexes = 8, mostText = 180000;

  static const _extensions = {
    '.doc',
    '.docx',
    '.pdf',
    '.rtf',
    '.txt',
    '.htm',
    '.html',
    '.xls',
    '.xlsx',
    '.csv',
    '.odt',
  };

  final _read = <String, Future<Annex>>{};
  final _packages = <String, Future<List<Annex>>>{};

  /// Whether [u] is one of the Mevzuat Bilgi Sistemi's own annexes.
  static bool allowed(Uri u) {
    if (u.scheme != 'https' || !hosts.contains(u.host.toLowerCase())) {
      return false;
    }
    final path = Uri.decodeFull(u.path).toLowerCase();
    return path.startsWith('/mevzuatmetin/') &&
        _extensions.contains(p.extension(path));
  }

  /// The annexes [html] links to, made whole against the bank's folder.
  static List<Uri> linksIn(String html) {
    final out = <Uri>[];
    final base = Uri.parse(
      'https://www.mevzuat.gov.tr/MevzuatMetin/yonetmelik/',
    );
    for (final m in RegExp(
      r'''<a\b[^>]*?href\s*=\s*(?:"([^"]+)"|'([^']+)')''',
      caseSensitive: false,
    ).allMatches(html)) {
      final href = (m[1] ?? m[2] ?? '').replaceAll('&amp;', '&').trim();
      if (href.isEmpty || href.startsWith('#')) continue;
      final u = Uri.tryParse(href);
      if (u == null) continue;
      final whole = u.hasScheme ? u : base.resolveUri(u);
      if (allowed(whole) && !out.contains(whole)) out.add(whole);
    }
    return out;
  }

  /// The annex at [url], read once in a session.
  Future<Annex> read(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || !allowed(u)) {
      return Future.value(
        Annex(url, nameOf(url), error: 'İzinli bir resmî mevzuat eki değil.'),
      );
    }
    return _read[url] ??= () async {
      try {
        final bytes = await _download(u);
        final text = await _text(bytes, p.extension(u.path));
        if (text.isEmpty) {
          return Annex(
            url,
            nameOf(url),
            error: 'Dosya indirildi ama metni çıkarılamadı.',
          );
        }
        return Annex(url, nameOf(url), text: text);
      } catch (e) {
        // Not kept: the next question tries again.
        _read.remove(url);
        return Annex(url, nameOf(url), error: 'İndirilemedi ($e).');
      }
    }();
  }

  /// [urls] read and set after [text], each said where it is from; what
  /// could not be read said so, for the program not to guess at it.
  Future<String> withAnnexes(String text, List<String> urls) async {
    final unique = <String>[];
    for (final u in urls) {
      if (u.trim().isNotEmpty && !unique.contains(u.trim())) {
        unique.add(u.trim());
      }
    }
    if (unique.isEmpty) return text;
    final taken = unique.take(mostAnnexes).toList();
    final parts = [text.trim()];
    for (var i = 0; i < taken.length; i++) {
      final a = await read(taken[i]);
      final head =
          'EK BELGE ${i + 1}/${taken.length} — ${a.name}\n'
          'Resmî kaynak: ${a.url}';
      parts.add(
        a.text.isNotEmpty
            ? '$head\n\n${a.text}'
            : '$head\nEk okunamadı: ${a.error.replaceFirst(RegExp(r'\.$'), '')}. '
                  'İçeriğini tahmin etme; '
                  'avukata bu bağlantıyı göster.',
      );
    }
    if (unique.length > taken.length) {
      parts.add(
        '[EK KAPSAMI KISMİ: ${unique.length} ekten ilk ${taken.length}\'i '
        'okundu.]',
      );
    }
    return parts.join('\n\n');
  }

  /// A regulation's or communiqué's package of annexes ("7.5.12916-Ek.zip"),
  /// which the bank leaves out: the Yapım İşleri Genel Şartnamesi is the
  /// Yapım İşleri İhaleleri Uygulama Yönetmeliği's eighth. Empty when there
  /// is none.
  Future<List<Annex>> package(String number, String kind) {
    final url = packageUrl(number, kind);
    if (url == null) return Future.value(const []);
    return _packages[url] ??= () async {
      try {
        final bytes = await _download(Uri.parse(url));
        return await openPackage(bytes, url);
      } catch (_) {
        _packages.remove(url);
        return const <Annex>[];
      }
    }();
  }

  /// Where the package of [kind]'s [number] is; null for a kind that has
  /// none.
  static String? packageUrl(String number, String kind) {
    final code = const {
      'KKY': '7',
      'TEBLIGLER': '9',
    }[kind.trim().toUpperCase()];
    if (code == null || !RegExp(r'^\d+$').hasMatch(number.trim())) return null;
    return 'https://www.mevzuat.gov.tr/MevzuatMetin/yonetmelik/'
        '$code.5.${number.trim()}-Ek.zip';
  }

  /// The annexes in the zip [bytes] from [url]; the main text's own copies
  /// ("7.5.12916.htm") left out.
  @visibleForTesting
  Future<List<Annex>> openPackage(Uint8List bytes, String url) async {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      return const [];
    }
    final root = url.split('/').last.replaceFirst(RegExp(r'-Ek\.zip$'), '');
    final out = <Annex>[];
    for (final f in ZipDecoder().decodeBytes(bytes).files) {
      if (!f.isFile || f.size > mostBytes) continue;
      final name = turkishName(f.name.split('/').last);
      if (name.isEmpty || (root.isNotEmpty && name.startsWith(root))) continue;
      final content = f.readBytes();
      final text = content == null
          ? ''
          : await _text(content, p.extension(name));
      out.add(
        Annex(
          url,
          name,
          text: text,
          error: text.isEmpty ? 'metni çıkarılamıyor' : '',
        ),
      );
    }
    return out;
  }

  /// The annex of [package] asked for: by its number ("8": "8- …",
  /// "Ek 8 …", "EK-8 …"), or by a part of its name.
  static Annex? pick(List<Annex> package, String asked) {
    final a = asked.trim();
    if (a.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(a)) {
      final n = int.parse(a);
      for (final e in package) {
        final m = RegExp(r'\d+').firstMatch(e.name);
        if (m != null && m.start <= 6 && int.parse(m[0]!) == n) return e;
      }
      return null;
    }
    final want = _fold(a);
    for (final e in package) {
      if (_fold(e.name).contains(want)) return e;
    }
    return null;
  }

  /// A zip's name without the UTF-8 flag comes as DOS code page bytes; the
  /// Turkish one (857) gives back its letters.
  @visibleForTesting
  static String turkishName(String raw) {
    const cp857 = {
      0x80: 'Ç',
      0x81: 'ü',
      0x87: 'ç',
      0x8D: 'ı',
      0x94: 'ö',
      0x98: 'İ',
      0x99: 'Ö',
      0x9A: 'Ü',
      0x9E: 'Ş',
      0x9F: 'ş',
      0xA6: 'Ğ',
      0xA7: 'ğ',
    };
    if (!raw.codeUnits.any((c) => c >= 0x80 && c <= 0xFF)) return raw;
    // Already read as UTF-8: Turkish letters past 0xFF are there.
    if (raw.codeUnits.any((c) => c > 0xFF)) return raw;
    return String.fromCharCodes(raw.codeUnits).split('').map((ch) {
      final c = ch.codeUnitAt(0);
      return cp857[c] ?? ch;
    }).join();
  }

  static String _fold(String s) => s
      .replaceAll('İ', 'i')
      .replaceAll('I', 'ı')
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');

  static String nameOf(String url) {
    final last = Uri.tryParse(url)?.pathSegments.lastOrNull ?? '';
    return last.isEmpty ? 'Mevzuat eki' : Uri.decodeComponent(last);
  }

  /// [bytes]' text, by what they are rather than what the name says.
  Future<String> _text(Uint8List bytes, String extension) async {
    var ext = extension.toLowerCase();
    if (bytes.length >= 4) {
      if (bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44) {
        ext = '.pdf';
      } else if (bytes[0] == 0xD0 && bytes[1] == 0xCF) {
        // An OLE file: Word 97 or Excel 97, as its name says.
        if (ext != '.xls') ext = '.doc';
      } else if (bytes[0] == 0x50 && bytes[1] == 0x4B) {
        if (ext != '.xlsx' && ext != '.odt') ext = '.docx';
      }
    }
    if (!_extensions.contains(ext)) return '';
    final dir = await Directory.systemTemp.createTemp('folio-ek-');
    try {
      final file = File(p.join(dir.path, 'ek$ext'));
      await file.writeAsBytes(bytes);
      final text = (await textOf(file.path)).trim();
      return text.length > mostText
          ? '${text.substring(0, mostText)}\n[Ekin geri kalanı uzunluğu '
                'yüzünden okunmadı.]'
          : text;
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// mevzuat.gov.tr answers a program without a browser's name with
  /// nothing at all (measured: curl hung, the same with a browser's
  /// answered in 0.1 s).
  static Future<Uint8List> _get(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(uri);
      req.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/130.0 Safari/537.36 LifeOS-Folio',
      );
      final res = await req.close().timeout(const Duration(seconds: 40));
      // Sent on elsewhere: not the Ministry's file.
      for (final r in res.redirects) {
        final to = uri.resolveUri(r.location);
        if (to.scheme != 'https' || !hosts.contains(to.host.toLowerCase())) {
          await res.drain<void>();
          throw const HttpException('izinli olmayan bir adrese yönlendirildi');
        }
      }
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw HttpException('HTTP ${res.statusCode}', uri: uri);
      }
      final out = BytesBuilder(copy: false);
      await for (final c in res.timeout(const Duration(seconds: 60))) {
        out.add(c);
        if (out.length > mostBytes) {
          throw const HttpException('25 MB sınırını aşıyor');
        }
      }
      return out.takeBytes();
    } finally {
      client.close(force: true);
    }
  }
}

/// One annex: where it is, its name, its text or why there is none.
class Annex {
  const Annex(this.url, this.name, {this.text = '', this.error = ''});
  final String url, name, text, error;
}
