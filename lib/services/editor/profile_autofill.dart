import 'dart:convert';

import 'lawyer_profile.dart';

/// "ERKAN ÖZ" as "Erkan Öz", with Turkish's dotted and dotless i.
String titleCaseTr(String text) => text
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) {
      final rest = w
          .substring(1)
          .replaceAll('I', 'ı')
          .replaceAll('İ', 'i')
          .toLowerCase();
      return '${w[0]}$rest';
    })
    .join(' ');

bool _isTc(String s) => RegExp(r'^\d{11}$').hasMatch(s.trim());

/// [profile] with what a portal told of the lawyer written where it was
/// empty: what the lawyer typed is never written over. The main lawyer is
/// the one filled, or added when there is none.
LawyerProfile fillProfileBlanks(
  LawyerProfile profile, {
  String name = '',
  String bar = '',
  String barNumber = '',
  String tbbNumber = '',
  String tckn = '',
  String phone = '',
  String email = '',
}) {
  String keep(String old, String fresh) =>
      old.trim().isNotEmpty ? old : fresh.trim();
  final lawyers = [...profile.lawyers];
  final at = lawyers.isEmpty
      ? -1
      : profile.main >= 0 && profile.main < lawyers.length
      ? profile.main
      : 0;
  final old = at < 0 ? const Lawyer() : lawyers[at];
  final barShort = bar.trim().replaceFirst(
    RegExp(r'\s+barosu$', caseSensitive: false),
    '',
  );
  final filled = Lawyer(
    name: keep(old.name, titleCaseTr(name)),
    bar: keep(
      old.bar,
      barShort.isEmpty ? '' : '${titleCaseTr(barShort)} Barosu',
    ),
    barNumber: keep(old.barNumber, barNumber),
    tbbNumber: keep(old.tbbNumber, tbbNumber),
    idNumber: keep(old.idNumber, _isTc(tckn) ? tckn.trim() : ''),
  );
  if (filled.name.trim().isEmpty && at < 0) return profile;
  if (at < 0) {
    lawyers.add(filled);
  } else {
    lawyers[at] = filled;
  }
  return LawyerProfile(
    lawyers: lawyers,
    main: at < 0 ? 0 : profile.main,
    address: profile.address,
    phone: keep(profile.phone, phone),
    email: keep(profile.email, email.contains('@') ? email : ''),
    kep: profile.kep,
  );
}

/// The profile saved with the blanks filled, when anything was blank.
Future<void> rememberLawyer({
  String name = '',
  String bar = '',
  String barNumber = '',
  String tbbNumber = '',
  String tckn = '',
  String phone = '',
  String email = '',
}) async {
  final profile = await LawyerProfile.load();
  final next = fillProfileBlanks(
    profile,
    name: name,
    bar: bar,
    barNumber: barNumber,
    tbbNumber: tbbNumber,
    tckn: tckn,
    phone: phone,
    email: email,
  );
  if (jsonEncode(next.toJson()) == jsonEncode(profile.toJson())) return;
  await next.save();
}

/// The lawyer's own TC number as the profile keeps it; empty when unknown.
Future<String> profileTc() async {
  final tc = (await LawyerProfile.load()).lawyer?.idNumber.trim() ?? '';
  return _isTc(tc) ? tc : '';
}
