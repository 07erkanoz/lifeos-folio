import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../platform/app_directories.dart';

/// One lawyer of the office.
@immutable
class Lawyer {
  const Lawyer({
    this.name = '',
    this.bar = '',
    this.barNumber = '',
    this.tbbNumber = '',
    this.idNumber = '',
  });

  final String name, bar, barNumber, tbbNumber, idNumber;

  bool get isEmpty => name.trim().isEmpty;

  /// "Av. Deniz Yılmaz", as a filing names its lawyer.
  String get titled => isEmpty ? '' : 'Av. ${name.trim()}';

  /// "Antalya Barosu", whether "Antalya" or the whole name was typed.
  String get barName {
    final typed = bar.trim();
    if (typed.isEmpty) return '';
    return RegExp(r'barosu$', caseSensitive: false).hasMatch(typed)
        ? typed
        : '$typed Barosu';
  }

  Map<String, Object?> toJson() => {
    'ad': name,
    'baro': bar,
    'baroSicil': barNumber,
    'tbbSicil': tbbNumber,
    'tc': idNumber,
  };

  static Lawyer fromJson(Map<String, Object?> json) {
    String text(String key) => json[key] is String ? json[key] as String : '';
    return Lawyer(
      name: text('ad'),
      bar: text('baro'),
      barNumber: text('baroSicil'),
      tbbNumber: text('tbbSicil'),
      idNumber: text('tc'),
    );
  }
}

/// The office and its lawyers: what a filing repeats in every copy, typed
/// once. Kept on this computer only, in the app's own folder, and used for
/// nothing but filling the blanks of snippets and, later, suggestions.
@immutable
class LawyerProfile {
  const LawyerProfile({
    this.lawyers = const [],
    this.main = 0,
    this.address = '',
    this.phone = '',
    this.email = '',
    this.kep = '',
    this.officeName = '',
  });

  /// The lawyers of the office; [main] is the one a filing is signed by.
  final List<Lawyer> lawyers;
  final int main;

  /// The office's own details.
  final String address, phone, email, kep;

  /// "Kaya Hukuk Bürosu": shown on the lock screen when no office of the
  /// network names it.
  final String officeName;

  Lawyer? get lawyer {
    final named = lawyers.where((one) => !one.isEmpty).toList();
    if (named.isEmpty) return null;
    final chosen = main >= 0 && main < lawyers.length ? lawyers[main] : null;
    return chosen == null || chosen.isEmpty ? named.first : chosen;
  }

  bool get isEmpty =>
      lawyer == null &&
      address.trim().isEmpty &&
      phone.trim().isEmpty &&
      email.trim().isEmpty &&
      kep.trim().isEmpty &&
      officeName.trim().isEmpty;

  /// The snippet blanks this profile can answer, by name. Only those it has
  /// a value for: a blank the profile cannot fill is asked, not emptied.
  /// Today's date is always known.
  ///
  /// The lawyer's identity number is [AVUKAT TC], not [TC]: a snippet
  /// harvested from the archive turns a client's number into [TC], and the
  /// two must never be confused.
  Map<String, String> blanks({DateTime? today}) {
    final one = lawyer;
    final all = [
      for (final each in lawyers)
        if (!each.isEmpty) each.titled,
    ];
    final values = {
      'AVUKAT': one?.titled ?? '',
      'VEKİLLER': all.join(' - '),
      'BARO': one?.barName ?? '',
      'BARO SİCİL NO': one?.barNumber.trim() ?? '',
      'TBB SİCİL NO': one?.tbbNumber.trim() ?? '',
      'AVUKAT TC': one?.idNumber.trim() ?? '',
      'BÜRO ADRESİ': address.trim(),
      'BÜRO TELEFONU': phone.trim(),
      'EPOSTA': email.trim(),
      'KEP': kep.trim(),
      'BUGÜN': DateFormat('dd.MM.yyyy').format(today ?? DateTime.now()),
    };
    values.removeWhere((_, value) => value.isEmpty);
    return values;
  }

  /// What each blank is called where the reader picks it: the palette's
  /// "Profilden" row, and the note when the profile lacks one.
  static const labels = {
    'AVUKAT': 'Avukat',
    'VEKİLLER': 'Vekiller',
    'BARO': 'Baro',
    'BARO SİCİL NO': 'Baro sicil no',
    'TBB SİCİL NO': 'TBB sicil no',
    'AVUKAT TC': 'Avukat TC kimlik no',
    'BÜRO ADRESİ': 'Büro adresi',
    'BÜRO TELEFONU': 'Büro telefonu',
    'EPOSTA': 'E-posta',
    'KEP': 'KEP adresi',
    'BUGÜN': 'Bugünün tarihi',
  };

  /// The profile's values as the reader picks them, labelled, in the order
  /// of [known]; only those it has.
  List<(String, String)> entries({DateTime? today}) {
    final values = blanks(today: today);
    return [
      for (final name in known)
        if (values[name] case final value?) (labels[name]!, value),
    ];
  }

  /// The blanks [blanks] can answer, for help texts.
  static const known = [
    'AVUKAT',
    'VEKİLLER',
    'BARO',
    'BARO SİCİL NO',
    'TBB SİCİL NO',
    'AVUKAT TC',
    'BÜRO ADRESİ',
    'BÜRO TELEFONU',
    'EPOSTA',
    'KEP',
    'BUGÜN',
  ];

  Map<String, Object?> toJson() => {
    'avukatlar': [for (final one in lawyers) one.toJson()],
    'varsayilan': main,
    'adres': address,
    'telefon': phone,
    'eposta': email,
    'kep': kep,
    'buro': officeName,
  };

  static LawyerProfile fromJson(Map<String, Object?> json) {
    String text(String key) => json[key] is String ? json[key] as String : '';
    final listed = json['avukatlar'];
    return LawyerProfile(
      lawyers: [
        if (listed is List)
          for (final one in listed)
            if (one is Map) Lawyer.fromJson(one.cast<String, Object?>()),
      ],
      main: json['varsayilan'] is int ? json['varsayilan'] as int : 0,
      address: text('adres'),
      phone: text('telefon'),
      email: text('eposta'),
      kep: text('kep'),
      officeName: text('buro'),
    );
  }

  static LawyerProfile? _held;

  /// The profile as last loaded or saved, without waiting; null before the
  /// first [load]. For deciding within a keystroke.
  static LawyerProfile? get cached => _held;

  static Future<File> _file() async =>
      File(p.join((await folioSupportDirectory()).path, 'profil.json'));

  /// The profile as last saved; an empty one when there is none or it cannot
  /// be read, so a snippet still goes in and asks for its blanks.
  static Future<LawyerProfile> load() async {
    final held = _held;
    if (held != null) return held;
    try {
      final file = await _file();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map) {
          return _held = fromJson(json.cast<String, Object?>());
        }
      }
    } catch (_) {
      // Unreadable is treated as unset; the reader can fill it in again.
    }
    return _held = const LawyerProfile();
  }

  /// Keeps this profile. Written whole or not at all: a half-written file
  /// would read as no profile.
  Future<void> save() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.tmp');
    await pending.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
      flush: true,
    );
    await pending.rename(file.path);
    _held = this;
  }

  /// For tests: the profile to answer with, or null to read the file again.
  @visibleForTesting
  static void use(LawyerProfile? profile) => _held = profile;

  /// The profile already read or set, if it is; null before.
  static LawyerProfile? get held => _held;
}
