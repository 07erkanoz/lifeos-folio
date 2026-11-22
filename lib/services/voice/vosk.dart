// Vosk's C API over dart:ffi: speech recognised on this computer, for the
// wake phrase alone. The library comes with Folio's build on Linux
// (linux/vosk.cmake puts lib/libvosk.so beside the executable). From
// AvukatOS Asistan's, where it worked well.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

typedef _ModelNewC = Pointer<Void> Function(Pointer<Utf8>);
typedef _RecNewC = Pointer<Void> Function(Pointer<Void>, Float, Pointer<Utf8>);
typedef _RecNewD = Pointer<Void> Function(Pointer<Void>, double, Pointer<Utf8>);
typedef _AcceptC = Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32);
typedef _AcceptD = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _StrC = Pointer<Utf8> Function(Pointer<Void>);
typedef _VoidC = Void Function(Pointer<Void>);
typedef _VoidD = void Function(Pointer<Void>);
typedef _LogC = Void Function(Int32);
typedef _LogD = void Function(int);
typedef _WordsC = Void Function(Pointer<Void>, Int32);
typedef _WordsD = void Function(Pointer<Void>, int);

class Vosk {
  final _ModelNewC _modelNew;
  final _RecNewD _recNew;
  final _AcceptD _accept;
  final _StrC _result, _partial;
  final _VoidD _reset, _recFree, _modelFree;
  final _WordsD _words;

  Vosk._(DynamicLibrary k)
    : _modelNew = k.lookupFunction<_ModelNewC, _ModelNewC>('vosk_model_new'),
      _recNew = k.lookupFunction<_RecNewC, _RecNewD>('vosk_recognizer_new_grm'),
      _accept = k.lookupFunction<_AcceptC, _AcceptD>(
        'vosk_recognizer_accept_waveform',
      ),
      _result = k.lookupFunction<_StrC, _StrC>('vosk_recognizer_result'),
      _partial = k.lookupFunction<_StrC, _StrC>(
        'vosk_recognizer_partial_result',
      ),
      _reset = k.lookupFunction<_VoidC, _VoidD>('vosk_recognizer_reset'),
      _recFree = k.lookupFunction<_VoidC, _VoidD>('vosk_recognizer_free'),
      _modelFree = k.lookupFunction<_VoidC, _VoidD>('vosk_model_free'),
      _words = k.lookupFunction<_WordsC, _WordsD>('vosk_recognizer_set_words') {
    k.lookupFunction<_LogC, _LogD>('vosk_set_log_level')(-1);
  }

  /// With a given library: the binding's probe in the tests.
  @visibleForTesting
  static Vosk forTest(DynamicLibrary library) => Vosk._(library);

  static Vosk? _one;

  /// None where the library is not (a build without it, macOS).
  static Vosk? load() {
    if (_one != null) return _one;
    final dir = File(Platform.resolvedExecutable).parent.path;
    final candidates = Platform.isWindows
        ? ['$dir\\libvosk.dll', 'libvosk.dll']
        : Platform.isLinux
        ? ['$dir/lib/libvosk.so', 'libvosk.so']
        : <String>[];
    for (final c in candidates) {
      try {
        return _one = Vosk._(DynamicLibrary.open(c));
      } catch (_) {}
    }
    return null;
  }

  Pointer<Void> model(String path) {
    final p = path.toNativeUtf8();
    try {
      final m = _modelNew(p);
      if (m == nullptr) throw Exception('Vosk modeli açılamadı: $path');
      return m;
    } finally {
      malloc.free(p);
    }
  }

  void freeModel(Pointer<Void> m) => _modelFree(m);

  /// A recogniser that knows only [phrases] (and "[unk]").
  VoskRecognizer recognizer(
    Pointer<Void> model,
    List<String> phrases, {
    int rate = 16000,
  }) {
    final g = jsonEncode([...phrases, '[unk]']).toNativeUtf8();
    try {
      final r = _recNew(model, rate.toDouble(), g);
      if (r == nullptr) throw Exception('Vosk tanıyıcısı açılamadı');
      _words(r, 1); // a confidence for each word of a final result
      return VoskRecognizer._(this, r);
    } finally {
      malloc.free(g);
    }
  }
}

class VoskRecognizer {
  final Vosk _v;
  final Pointer<Void> _r;
  Pointer<Uint8> _buffer = malloc<Uint8>(32000);
  int _size = 32000;
  bool _closed = false;

  VoskRecognizer._(this._v, this._r);

  /// A piece of PCM in → (what was heard, whether the utterance ended,
  /// each word's confidence 0–1, and how long its words took in seconds;
  /// the last two only for an ended one).
  (String, bool, List<(String, double)>, double) feed(Uint8List pcm) {
    if (_closed) return ('', false, const [], 0);
    if (pcm.length > _size) {
      malloc.free(_buffer);
      _size = pcm.length;
      _buffer = malloc<Uint8>(_size);
    }
    _buffer.asTypedList(pcm.length).setAll(0, pcm);
    final ended = _v._accept(_r, _buffer, pcm.length) == 1;
    final json = (ended ? _v._result(_r) : _v._partial(_r)).toDartString();
    try {
      final m = decode(json);
      final words = (m['result'] as List? ?? []).whereType<Map>().toList();
      final confidence = [
        for (final k in words)
          ('${k['word']}', (k['conf'] as num?)?.toDouble() ?? 0),
      ];
      // From the first word's start to the last one's end: the room's hum
      // around them is not counted (it held every wake back as "too long").
      final span = words.isEmpty
          ? 0.0
          : ((words.last['end'] as num?)?.toDouble() ?? 0) -
                ((words.first['start'] as num?)?.toDouble() ?? 0);
      return ('${m['text'] ?? m['partial'] ?? ''}', ended, confidence, span);
    } catch (_) {
      return ('', ended, const <(String, double)>[], 0.0);
    }
  }

  /// Vosk writes numbers in the C library's locale: on a Turkish Linux
  /// (GTK calls setlocale) a confidence is `1,000000` and the JSON breaks —
  /// AvukatOS's wake word never fired for it. The comma becomes a point.
  static Map decode(String json) {
    try {
      return jsonDecode(json) as Map;
    } on FormatException {
      return jsonDecode(
        json.replaceAllMapped(
          RegExp(r'(:\s*-?\d+),(\d)'),
          (m) => '${m[1]}.${m[2]}',
        ),
      ) as Map;
    }
  }

  void reset() {
    if (!_closed) _v._reset(_r);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _v._recFree(_r);
    malloc.free(_buffer);
  }
}

/// Words added to the wake grammar as decoys: with the phrase alone, Vosk
/// rounded every sound (TV, talk) to the nearest match — the phrase. With
/// common words there, random speech falls on them; the phrase comes only
/// when said. (All in the small Turkish model; one missing is ignored.)
const voskDecoys = [
  'merhaba', 'selam', 'tamam', 'evet', 'hayır', 'bir', 'bu', 'şu', 'o', //
  'ne', 'nasıl', 'var', 'yok', 'için', 'ile', 'ama', 'çok', 'daha', 'gibi',
  'sonra', 'şimdi', 'bugün', 'yarın', 'akşam', 'sabah', 'haber', 'maç',
  'film', 'dizi', 'program', 'televizyon', 'hayat', 'ankara', 'türkiye',
  'araba', 'para', 'kadın', 'adam', 'çocuk', 'anne', 'baba', 'abi', 'abla',
  'hoca', 'doktor', 'avukat', 'hakim', 'savcı', 'mahkeme', 'dava', 'polis',
  'asker', 'oyun', 'gol', 'takım', 'istiyorum', 'geliyor', 'gidiyor',
  'diyor', 'dedi', 'oldu', 'olur', 'bak', 'bakalım', 'tabii', 'neden',
  'çünkü', 'herkes', 'insan', 'dünya', 'ülke', 'devlet', 'başkan', 'bakan',
  'seçim', 'ekonomi', 'dolar', 'euro', 'faiz', 'hava', 'yağmur', 'güneş',
  'saat', 'dakika', 'hafta', 'yıl', 'ay', 'gün', 'gece', 'yemek', 'su',
  'ev', 'iş', 'okul', 'öğretmen', 'öğrenci', 'kız', 'oğlan', 'arkadaş',
  'sevgili', 'aşk', 'sistem', 'istasyon', 'aslan', 'hasta', 'asi', 'astım',
  'açık', 'aç', 'kapı', 'acil', 'ajans', 'çıl', 'aşil',
];

/// Wake sensitivity → the least confidence for each word.
const voskThresholds = {'dusuk': .92, 'orta': .82, 'yuksek': .68};

/// The trigger: the utterance ended, what was heard is exactly the phrase
/// (no word before or after), every word passes [threshold], and its words
/// took ≤ 2.5 s. A sentence on TV with the word in it does not.
bool isWakePhrase(
  String heard,
  bool ended,
  String phrase, {
  double voiced = 0,
  List<(String, double)> confidence = const [],
  double threshold = .82,
}) {
  if (!ended || voiced > 2.5) return false;
  final m = heard
      .trim()
      .split(RegExp(r'\s+'))
      .where((k) => k.isNotEmpty)
      .join(' ');
  if (m != phrase.trim()) return false;
  if (confidence.isEmpty) return false;
  return confidence.every((k) => k.$2 >= threshold);
}
