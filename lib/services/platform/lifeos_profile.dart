import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../editor/lawyer_profile.dart';

/// What LifeOS asked the lawyer while it was installed (or in its Karşılama),
/// for Folio's first start not to ask again: `folio-profil.json` in LifeOS's
/// own settings folder, written by the installer and never by Folio.
///
/// Only a suggestion: it fills the profile step's blanks while Folio has no
/// lawyer of its own, and once the profile is kept the file is not read
/// again.
abstract final class LifeosProfile {
  /// `$XDG_CONFIG_HOME/lifeos/folio-profil.json`, `~/.config/…` when it is
  /// not set (a relative one does not count). Null with neither.
  static File? file([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final config = env['XDG_CONFIG_HOME'];
    final home = env['HOME'];
    final base = config != null && p.isAbsolute(config)
        ? config
        : home == null || home.isEmpty
        ? null
        : p.join(home, '.config');
    return base == null
        ? null
        : File(p.join(base, 'lifeos', 'folio-profil.json'));
  }

  /// The file's details as Folio keeps them; null when it says nothing
  /// Folio can use. Its keys: ad, baro, sicil, tbb, buro, tel, eposta, kep,
  /// adres (and kaynak, who wrote it, not needed here).
  static LawyerProfile? parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final json = decoded;
    String value(String key) {
      final one = json[key];
      return one is String ? one.trim() : '';
    }

    final lawyer = Lawyer(
      name: value('ad'),
      bar: value('baro'),
      barNumber: value('sicil'),
      tbbNumber: value('tbb'),
    );
    final profile = LawyerProfile(
      lawyers: [if (!lawyer.isEmpty) lawyer],
      address: value('adres'),
      phone: value('tel'),
      email: value('eposta'),
      kep: value('kep'),
      officeName: value('buro'),
    );
    return profile.isEmpty ? null : profile;
  }

  /// The file read, on Linux only; null when it is not there or cannot be
  /// read, and Folio asks as it always did.
  static Future<LawyerProfile?> read([File? from]) async {
    if (from == null && !Platform.isLinux) return null;
    final source = from ?? file();
    if (source == null) return null;
    try {
      if (!await source.exists()) return null;
      return parse(await source.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// [kept] with its blanks filled from [lifeos]: what Folio already has
  /// stays as it is. Only for a profile with no lawyer; one with a lawyer
  /// is the lawyer's own and is returned unchanged.
  static LawyerProfile fill(LawyerProfile kept, LawyerProfile lifeos) {
    if (kept.lawyer != null) return kept;
    String either(String own, String given) => own.trim().isEmpty ? given : own;
    return LawyerProfile(
      lawyers: lifeos.lawyers,
      address: either(kept.address, lifeos.address),
      phone: either(kept.phone, lifeos.phone),
      email: either(kept.email, lifeos.email),
      kep: either(kept.kep, lifeos.kep),
      officeName: either(kept.officeName, lifeos.officeName),
    );
  }
}
