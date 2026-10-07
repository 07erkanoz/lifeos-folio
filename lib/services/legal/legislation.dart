import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';
import 'bedesten_legislation.dart';
import 'citation.dart';
import 'html_text.dart';
import 'rich_text.dart';

/// Where an article's text came from, named so a reader can weigh it.
enum ArticleSource {
  bedesten('UYAP/Bedesten · resmî metin'),
  mevzuatGov('mevzuat.gov.tr · resmî metin');

  const ArticleSource(this.label);

  final String label;
}

/// One article of a law, as the official text has it.
@immutable
class Article {
  const Article({
    required this.law,
    required this.number,
    required this.text,
    this.html,
    this.place = '',
    this.paragraphs = const [],
    this.headings = const [],
    this.source = ArticleSource.mevzuatGov,
    this.url = '',
    this.officialName = '',
  });

  final Law law;
  final int number;

  /// The article verbatim, headnote and all. Not a summary: a lawyer reading
  /// this is reading the law, and a paraphrase would be worse than nothing.
  final String text;

  /// Kept for a copy written before the app kept paragraphs.
  final String? html;

  /// Where in the law, as the citation put it: "m. 68/a", "geçici m. 3".
  final String place;

  /// The article as paragraphs, bold where the Official Gazette set it.
  /// Empty for the older plain copy, which is laid out from its own shape.
  final List<RichParagraph> paragraphs;

  /// The article's own headings: its side heading and the headings of the
  /// division it opens.
  final List<String> headings;

  final ArticleSource source;

  /// The law's page on mevzuat.gov.tr.
  final String url;

  /// The name the official source gives the law, for a law the table does
  /// not carry.
  final String officialName;

  /// The law's name as shown: the table's, or the official one.
  String get lawName => law.isKnown || officialName.isEmpty
      ? law.name
      : titleCaseTr(officialName);

  String get title =>
      '${law.number} s. $lawName ${place.isEmpty ? 'm. $number' : place}';

  /// The body to show and to copy.
  List<RichParagraph> get body => paragraphs.isNotEmpty
      ? paragraphs
      : articleParagraphsOf(text, firstLineHeading: headings.isEmpty);

  /// An article whose whole text is the note that repealed it:
  /// "MADDE 107– (Mülga:16/7/2026-7589/19 md.)".
  bool get repealed {
    final lines = body.map((one) => one.text.trim()).toList();
    return lines.length == 1 &&
        RegExp(
          r'[-–—]\s*\(\s*Mülga',
          caseSensitive: false,
        ).hasMatch(lines.single);
  }

  /// For an article [repealed] whole, what repealed it and what that leaves
  /// of it, in words; null for one in force.
  String? get repealNotice =>
      repealed ? repealNoticeOf(body.single.text) : null;
}

/// What a repeal note says, in words. "(Mülga:16/7/2026-7589/19 md.)" is the
/// 19th article of Law 7589 of 16 July 2026; "(Mülga: 2/7/2018-KHK-703/45
/// md.)" a decree-law's. A note in another form is not guessed at.
///
/// Said because the note alone reads like the article failed to load: the
/// official consolidated text keeps nothing of a repealed article but that
/// note, and the text it had before is not published there.
String repealNoticeOf(String note) {
  final m = RegExp(
    r'M[üu]lga\s*:\s*(\d{1,2})\s*/\s*(\d{1,2})\s*/\s*(\d{4})\s*[-–—]\s*'
    r'(KHK\s*[-–—]\s*)?(\d+)(?:\s*/\s*(\d+))?',
    caseSensitive: false,
  ).firstMatch(note);
  final String by;
  if (m == null) {
    by = 'Bu madde yürürlükten kaldırılmıştır.';
  } else {
    final decree = m.group(4) != null;
    final article = m.group(6);
    final what = article == null
        ? (decree ? 'Kanun Hükmünde Kararnameyle' : 'Kanunla')
        : '${decree ? 'Kanun Hükmünde Kararnamenin' : 'Kanunun'} '
              '$article. maddesiyle';
    by =
        'Bu madde, ${m.group(1)}/${m.group(2)}/${m.group(3)} tarihli ve '
        '${m.group(5)} sayılı $what yürürlükten kaldırılmıştır.';
  }
  return '$by Resmî güncel metinde maddenin yerinde yalnızca bu kayıt '
      'bulunur; kaldırılmadan önceki metni yer almaz.';
}

/// What asking for an article came to.
enum ArticleOutcome { found, absent, unreachable }

@immutable
class ArticleLookup {
  const ArticleLookup(this.outcome, {this.article, this.url = ''});

  final ArticleOutcome outcome;
  final Article? article;

  /// The law's official page, so a reader can look for themselves even
  /// when the text could not be had.
  final String url;
}

/// The text of a law, fetched once and then kept.
///
/// An article is asked of the Ministry's legislation bank first, which
/// answers for the one article and sets it as the Official Gazette did.
/// Failing that the whole law is fetched from mevzuat.gov.tr and the
/// article cut out of it by its text. Both are free to reproduce (FSEK m.
/// 31) and both are kept on disk, so a second look costs nothing.
///
/// The document being read never leaves the machine. What goes out is a law
/// number and an article number, and nothing else.
class Legislation {
  /// The named arguments are seams for tests; the app passes none. A test
  /// that hands in its own [download] is testing the page path, and is not
  /// sent to the bank.
  Legislation({
    @visibleForTesting Future<String> Function(Law law)? download,
    @visibleForTesting Directory? cache,
    @visibleForTesting BedestenLegislation? bedesten,
    // An initialising formal is what the analyser would rather see here, but
    // `this._download` cannot be called: a named argument may not begin with
    // an underscore.
    // ignore: prefer_initializing_formals
  }) : _download = download,
       _kept = cache,
       _bedesten =
           bedesten ?? (download == null ? BedestenLegislation() : null);

  /// How the text is fetched. A test hands its own in — and must, because
  /// flutter_test answers every real request with an empty 400.
  final Future<String> Function(Law law)? _download;

  final BedestenLegislation? _bedesten;

  /// Where the fetched laws are written. Worked out on first use, unless a
  /// test hands one in.
  Directory? _kept;

  /// How long a kept copy is trusted before it is fetched again. Laws change,
  /// but not by the week, and a reader with no network is better served by a
  /// slightly old article than by none.
  static const keepFor = Duration(days: 30);

  /// The bank's copy is kept for less: it is one request an article, and an
  /// amendment should reach the reader within the week.
  static const bankKeepFor = Duration(days: 7);

  static const _asset = 'assets/mevzuat/mevzuat-chain.pem';

  final _inMemory = <int, Map<String, String>>{};
  final _banks = <int, _BankCopy>{};

  /// The law's page on mevzuat.gov.tr, known without asking anyone.
  static String pageOf(Law law) => law.isKnown
      ? 'https://www.mevzuat.gov.tr/mevzuat?MevzuatNo=${law.number}'
            '&MevzuatTur=1&MevzuatTertip=${law.tertip}'
      : 'https://www.mevzuat.gov.tr/';

  /// The article a citation points at, or null when it cannot be had.
  Future<Article?> article(Citation citation) async =>
      (await lookup(citation)).article;

  /// The article a citation points at, and if there is none, why.
  Future<ArticleLookup> lookup(Citation citation) async {
    var reached = false;
    final bank = _bedesten;
    if (bank != null) {
      try {
        final found = await _fromBank(bank, citation);
        reached = true;
        if (found != null) {
          return ArticleLookup(
            ArticleOutcome.found,
            article: found,
            url: found.url,
          );
        }
      } on Object {
        // Asked of the page instead.
      }
    }
    final text = await _articles(citation.law);
    final one = text?[keyOf(citation)];
    if (one != null) {
      return ArticleLookup(
        ArticleOutcome.found,
        article: Article(
          law: citation.law,
          number: citation.article,
          text: one,
          place: citation.place,
          url: pageOf(citation.law),
        ),
        url: pageOf(citation.law),
      );
    }
    return ArticleLookup(
      reached || text != null
          ? ArticleOutcome.absent
          : ArticleOutcome.unreachable,
      url: _banks[citation.law.number]?.law.url ?? pageOf(citation.law),
    );
  }

  /// Whether this law is already on disk, so the caller can say whether a
  /// press will answer at once or will reach for the network.
  Future<bool> isKept(Law law) async {
    if (_inMemory.containsKey(law.number)) return true;
    if (_banks.containsKey(law.number)) return true;
    return (await _file(law)).exists();
  }

  /// How an article is filed in a kept copy: "166", "68/a", "geçici 3",
  /// "ek 1".
  static String keyOf(Citation citation) {
    final letter = citation.letter;
    final number = letter == null
        ? '${citation.article}'
        : '${citation.article}/${_lower(letter)}';
    return '${citation.kind.prefix}$number';
  }

  static String _lower(String value) =>
      value.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

  // -- the bank ------------------------------------------------------------

  Future<Article?> _fromBank(
    BedestenLegislation bank,
    Citation citation,
  ) async {
    final copy = await _bankCopy(bank, citation.law);
    if (copy == null) return null;
    for (final node in BedestenLegislation.candidates(copy.tree, citation)) {
      final page = richParagraphsOf(
        await _pageOf(bank, copy, node.id),
        headings: false,
      );
      final cut = cutArticle(page, citation);
      if (cut == null) continue;
      var headings = cut.before;
      if (headings.isEmpty) {
        // Filed at the foot of the article before this one.
        final at = copy.tree.indexOf(node);
        final before = copy.tree
            .sublist(0, at < 0 ? 0 : at)
            .lastWhere((one) => one.isArticle, orElse: () => node);
        if (!identical(before, node)) {
          headings = trailingHeadings(
            richParagraphsOf(
              await _pageOf(bank, copy, before.id),
              headings: false,
            ),
          );
        }
      }
      if (headings.isEmpty &&
          citation.kind == ArticleKind.plain &&
          citation.letter == null &&
          node.sideHeading.isNotEmpty) {
        headings = [node.sideHeading];
      }
      unawaited(_saveBank(citation.law, copy));
      return Article(
        law: citation.law,
        number: citation.article,
        text: [...headings, plainTextOfParagraphs(cut.body)].join('\n'),
        place: citation.place,
        paragraphs: cut.body,
        headings: headings,
        source: ArticleSource.bedesten,
        url: copy.law.url.isEmpty ? pageOf(citation.law) : copy.law.url,
        officialName: copy.law.name,
      );
    }
    unawaited(_saveBank(citation.law, copy));
    return null;
  }

  Future<String> _pageOf(
    BedestenLegislation bank,
    _BankCopy copy,
    String nodeId,
  ) async => copy.pages[nodeId] ??= await bank.page(nodeId);

  Future<_BankCopy?> _bankCopy(BedestenLegislation bank, Law law) async {
    final held = _banks[law.number];
    if (held != null && DateTime.now().difference(held.at) < bankKeepFor) {
      return held;
    }
    final kept = await _readBank(law);
    if (kept != null && DateTime.now().difference(kept.at) < bankKeepFor) {
      return _banks[law.number] = kept;
    }
    // Older than a week: asked for anew, but the copy kept still answers
    // when the bank cannot be reached, offline above all. An article on
    // disk is not "unreachable".
    final stale = held ?? kept;
    try {
      final found = await bank.law(law.number);
      if (found == null) return stale;
      final tree = await bank.tree(found.id);
      return _banks[law.number] = _BankCopy(
        law: found,
        tree: tree,
        pages: {},
        at: DateTime.now(),
      );
    } catch (_) {
      if (stale == null) rethrow;
      return _banks[law.number] = stale;
    }
  }

  Future<File> _bankFile(Law law) async {
    final dir = _kept ??= Directory(
      p.join((await folioSupportDirectory()).path, 'mevzuat'),
    );
    return File(p.join(dir.path, 'bedesten', '${law.number}.json'));
  }

  Future<_BankCopy?> _readBank(Law law) async {
    try {
      final file = await _bankFile(law);
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final at = DateTime.tryParse(json['alindi'] as String? ?? '');
      if (at == null) return null;
      final pages = json['sayfalar'] as Map<String, Object?>? ?? const {};
      return _BankCopy(
        law: BedestenLaw.fromJson(json['belge'] as Map<String, Object?>),
        tree: [
          for (final node in json['agac'] as List? ?? const [])
            BedestenNode.fromJson(node as Map<String, Object?>),
        ],
        pages: {for (final entry in pages.entries) entry.key: '${entry.value}'},
        at: at,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _saving = Future.value();

  /// Written one after another, so two articles of the same law opened
  /// together do not write over each other.
  Future<void> _saveBank(Law law, _BankCopy copy) =>
      _saving = _saving.then((_) async {
        try {
          final file = await _bankFile(law);
          await file.parent.create(recursive: true);
          await file.writeAsString(
            jsonEncode({
              'kanun': law.number,
              'alindi': copy.at.toUtc().toIso8601String(),
              'belge': copy.law.toJson(),
              'agac': [for (final node in copy.tree) node.toJson()],
              'sayfalar': copy.pages,
            }),
          );
        } on Object {
          // Keeping it is a kindness, not a requirement.
        }
      });

  // -- the page on mevzuat.gov.tr ------------------------------------------

  Future<Map<String, String>?> _articles(Law law) async {
    final held = _inMemory[law.number];
    if (held != null) return held;
    // A law the table does not carry has no known place in the Düstur, so
    // its page cannot be asked for.
    if (!law.isKnown) return null;

    final kept = await _read(law);
    if (kept != null) {
      _inMemory[law.number] = kept;
      return kept;
    }

    final String raw;
    try {
      raw = await (_download ?? _fetch)(law);
    } on Object {
      // No network, a refused connection, a certificate that has run out:
      // none of it is something the reader should be stopped by. An older
      // copy is used if there is one, and otherwise nothing is shown.
      return _read(law, ignoreAge: true);
    }
    final split = articlesKeyedIn(plainTextOf(raw));
    if (split.isEmpty) return _read(law, ignoreAge: true);
    _inMemory[law.number] = split;
    await _write(law, split);
    return split;
  }

  static Future<SecurityContext> _context() async {
    // mevzuat.gov.tr does not send its intermediate certificate, and Dart,
    // unlike a browser, will not go and fetch the missing one. It is carried
    // with the app instead; see assets/mevzuat/README.md.
    final pem = await rootBundle.load(_asset);
    return SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(pem.buffer.asUint8List());
  }

  static Future<String> _fetch(Law law) async {
    final client = HttpClient(context: await _context())
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(
        Uri.https('www.mevzuat.gov.tr', '/anasayfa/MevzuatFihristDetayIframe', {
          'MevzuatTur': '1',
          'MevzuatNo': '${law.number}',
          'MevzuatTertip': '${law.tertip}',
        }),
      );
      // The site serves an unnamed caller just as well, but saying who is
      // asking is the courtesy owed to somebody else's server.
      request.headers.set(HttpHeaders.userAgentHeader, 'Folio');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('${response.statusCode}', uri: request.uri);
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  // -- reading the page ----------------------------------------------------

  /// Where each article begins.
  ///
  /// The older laws write "Madde 89 –" with a long dash, the newer ones
  /// "MADDE 3-", with a space in between or without. A dash is required,
  /// because "Madde 89/1" is one article pointing at another from inside its
  /// own text and must not be taken for the start of one. A letter after
  /// the slash is another matter: "Madde 68/a –" is an article of its own.
  ///
  /// What must not be required is that the heading sit on a line of its own.
  /// These pages sometimes put it on the same line as the article — and
  /// sometimes with no space at all, "…şartlarıMADDE 132-" — and demanding a
  /// line start made those articles invisible, so the one before swallowed
  /// them whole.
  static final _boundary = RegExp(
    r'(EK|Ek|GEÇİCİ|Geçici)?[ \t]*(?:MADDE|Madde)[ \t]*(\d{1,4})'
    r'(?:[ \t]*/[ \t]*([A-Za-zÇĞİÖŞÜçğıöşü])(?![A-Za-zÇĞİÖŞÜçğıöşü0-9]))?'
    r'[ \t]*[-–—]',
  );

  /// The plain articles of [body], by number.
  @visibleForTesting
  static Map<int, String> articlesIn(String body) => {
    for (final entry in articlesKeyedIn(body).entries)
      if (int.tryParse(entry.key) != null) int.parse(entry.key): entry.value,
  };

  /// Every article of [body], filed as [keyOf] files it: the plain ones by
  /// number, and the lettered, provisional and added ones each under their
  /// own name, so that none is filed under a number that belongs to
  /// another.
  @visibleForTesting
  static Map<String, String> articlesKeyedIn(String body) {
    final marks = _boundary.allMatches(body).toList();
    final out = <String, String>{};
    for (var i = 0; i < marks.length; i++) {
      final to = i + 1 < marks.length
          ? _openingOf(body, marks[i + 1])
          : body.length;
      final special = marks[i].group(1);
      final letter = marks[i].group(3);
      final number = marks[i].group(2)!.replaceFirst(RegExp('^0+(?=.)'), '');
      final key = [
        if (special != null) upperTr(special) == 'EK' ? 'ek ' : 'geçici ',
        letter == null ? number : '$number/${_lower(letter)}',
      ].join();
      // An amended law repeats an article number in its closing notes; the
      // first appearance is the article itself.
      if (out.containsKey(key)) continue;
      out[key] = _withoutClosingNotes(
        body.substring(_openingOf(body, marks[i]), to).trim(),
      );
    }
    return out;
  }

  /// Where a law stops being law and starts being a record of itself.
  ///
  /// After the last article every one of these documents prints its tables —
  /// which law amended which article and when, and the provisions never
  /// written into the text. The last article would otherwise carry all of
  /// it: the Commercial Code's closing article came to twenty-eight thousand
  /// characters, almost none of them the article.
  static final _closingNotes = RegExp(
    r'SAYILI\s+(?:ANA\s+)?KANUNA\s+(?:EK VE DEĞİŞİKLİK|İŞLENEMEYEN)',
  );

  static String _withoutClosingNotes(String article) {
    final note = _closingNotes.firstMatch(article);
    if (note == null) return article;
    // Back to the start of the line the tables begin on.
    final from = article.lastIndexOf('\n', note.start);
    return (from < 0 ? article : article.substring(0, from)).trim();
  }

  /// Where an article really begins.
  ///
  /// These laws print an article's side heading just before the article
  /// itself — Tanımlar, İspat yükü, Haciz ihbarnamesi — and that heading is
  /// how a lawyer knows at a glance what they are looking at. It is taken
  /// with the article it names rather than left at the foot of the one
  /// before, whether it sits on its own line or runs straight into it.
  static int _openingOf(String body, RegExpMatch mark) {
    final at = mark.start;
    if (at <= 0) return at;
    // Back to the start of the line, and no further.
    final lineStart = body.lastIndexOf('\n', at - 1) + 1;
    if (lineStart == at) {
      // The heading, if there is one, is the line above.
      final above = body.lastIndexOf('\n', at - 2);
      return _isHeading(body.substring(above + 1, at)) ? above : at;
    }
    // Same line: the heading is whatever follows the last sentence that
    // ended before it. A run too long for a heading is the article's own
    // text, and is left where it is.
    final before = body.substring(lineStart, at);
    final stop = before.lastIndexOf(RegExp(r'[.:;]'));
    final candidate = before.substring(stop + 1);
    return _isHeading(candidate) ? at - candidate.length : at;
  }

  /// A heading is a short name, never a sentence and never another
  /// article's closing words.
  static bool _isHeading(String value) {
    final heading = value.trim();
    return heading.isNotEmpty &&
        heading.length <= 80 &&
        !heading.endsWith('.') &&
        !heading.endsWith(',') &&
        !heading.endsWith(';') &&
        !heading.contains(RegExp('MADDE|Madde'));
  }

  // -- what is kept on disk ------------------------------------------------

  /// The shape of a kept page. Without it, a copy was cut before lettered,
  /// provisional and added articles were kept apart.
  static const _version = 2;

  Future<File> _file(Law law) async {
    final dir = _kept ??= Directory(
      p.join((await folioSupportDirectory()).path, 'mevzuat'),
    );
    return File(p.join(dir.path, '${law.number}.json'));
  }

  Future<Map<String, String>?> _read(Law law, {bool ignoreAge = false}) async {
    try {
      final file = await _file(law);
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final at = DateTime.tryParse(json['alindi'] as String? ?? '');
      if (!ignoreAge &&
          (at == null || DateTime.now().difference(at) > keepFor)) {
        return null;
      }
      final held = json['maddeler'] as Map<String, Object?>;
      return {
        for (final entry in held.entries) entry.key: entry.value as String,
      };
    } on Object {
      // A half-written or hand-edited file is simply fetched again.
      return null;
    }
  }

  Future<void> _write(Law law, Map<String, String> articles) async {
    try {
      final file = await _file(law);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'kanun': law.number,
          'surum': _version,
          'alindi': DateTime.now().toUtc().toIso8601String(),
          'maddeler': articles,
        }),
      );
    } on Object {
      // Keeping it is a kindness, not a requirement.
    }
  }
}

/// A law's copy from the bank: the law, its tree, and the pages read so far.
class _BankCopy {
  _BankCopy({
    required this.law,
    required this.tree,
    required this.pages,
    required this.at,
  });

  final BedestenLaw law;
  final List<BedestenNode> tree;
  final Map<String, String> pages;
  final DateTime at;
}
