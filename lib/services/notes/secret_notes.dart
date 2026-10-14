import '../clients/client.dart';
import '../enforcement/ledger_book.dart';
import '../portal/portal_database.dart';
import '../sync/hlc.dart';
import '../../models/json_shape.dart';

/// What of the lawyer's notes may leave their own devices (docs/senkron-
/// plan.md R7, §3 decision 1): a secret note goes to their other devices
/// and nowhere else, not to the office's tasks, a shared case, a card
/// shared, the calendar written out nor a document. Every one of those
/// asks here.
abstract final class SecretNotes {
  /// Whether agenda row [i] is kept off everything but the lawyer's own
  /// devices, its title too: a note or task of theirs that is secret. A
  /// notice's deadline is not: only its body is ([bodyHidden]).
  /// One made secret on another own device, its text not yet come here
  /// (the agenda's part off), is kept off too, by the mark that came.
  static bool rowHidden(PortalDatabase db, AgendaItem i) {
    if (db.deadline(i.id) != null) return false;
    if (i.secret) return true;
    final hide = db.hideOf('ajanda:${i.id}');
    if (hide == null) return false;
    final body = db.agendaBodyVersion(i.id);
    return body == null || body <= hide;
  }

  /// Whether [i]'s body is kept off: a secret row's, or a notice's
  /// deadline's own body made secret.
  static bool bodyHidden(AgendaItem i) => i.secret;

  /// [c] as a card shared with the office shows it: a secret note, and
  /// each secret note on a case, left empty with its version, so that a
  /// member's copy of before is written over and no older copy brings it
  /// back.
  static Map<String, Object?> cardForOffice(PortalDatabase db, Client c) {
    bool hidden(String key, bool secret, Hlc version) {
      if (secret) return true;
      final hide = db.hideOf(key);
      return hide != null && version <= hide;
    }

    final j = c.toJson();
    if (hidden('kartNotu:${c.id}', c.noteSecret, c.versionOf('not'))) {
      j['not'] = '';
      j['notGizli'] = true;
    }
    j['dosyaNotlari'] = {
      for (final k in c.caseNotes.keys.toList()..sort())
        k: {
          ...c.caseNotes[k]!.toJson(),
          if (hidden(
            'dosyaNotu:${c.id}:$k',
            c.caseNotes[k]!.secret,
            c.caseNotes[k]!.versionOf,
          )) ...{
            'metin': '',
            'gizliNot': true,
          },
        },
    };
    return j;
  }

  /// [r] as a record sent to the office: a secret description left empty.
  /// Whether enforcement payment [r]'s description is secret: so marked,
  /// or made secret on another own device at a version not older than its
  /// own (the mark that came).
  static bool descriptionHidden(PortalDatabase db, ClientRecord r) {
    if (r.data['aciklamaGizli'] == true) return true;
    if (r.kind != ClientRecordKind.enforcement) return false;
    final hide = db.hideOf('aciklama:${r.id}');
    return hide != null && LedgerBook.versionOf(r, 'bilgi') <= hide;
  }

  static Map<String, Object?> recordForOffice(
    PortalDatabase db,
    ClientRecord r,
  ) {
    final j = r.toJson();
    if (descriptionHidden(db, r) && j['veri'] is Map) {
      j['veri'] = {...j['veri'] as Map, 'aciklama': '', 'aciklamaGizli': true};
    }
    return j;
  }

  /// That the office member [person]'s [device] may hold the notes of the
  /// cards in [sent], a `muvekkil-buro` export to it: each note not empty,
  /// for what is taken back of it later to be counted there.
  /// Every device of [person]'s ([devices]) is taken as holding it: a
  /// copy goes from one of theirs to another (R7). True when anything new
  /// was kept.
  static bool recordCardHolds(
    PortalDatabase db,
    Map<String, Object?> sent,
    String device,
    String person, {
    List<String> devices = const [],
  }) {
    if (person.isEmpty) return false;
    var changed = false;
    final all = {device, ...devices};
    void hold(String key, String scope) {
      for (final d in all) {
        if (db.recordHold(key, d, person, scope)) changed = true;
      }
    }

    for (final j in jsonList(sent['muvekkiller'])) {
      if (j is! Map || j['buro'] != true || j['id'] is! String) continue;
      final id = j['id'] as String, scope = 'kart:$id';
      if ('${j['not'] ?? ''}'.isNotEmpty) hold('kartNotu:$id', scope);
      (j['dosyaNotlari'] as Map? ?? const {}).forEach((k, n) {
        if (n is Map && '${n['metin'] ?? ''}'.isNotEmpty) {
          hold('dosyaNotu:$id:$k', scope);
        }
      });
    }
    for (final j in jsonList(sent['muvekkilKayitlari'])) {
      if (j is! Map || j['id'] is! String || j['veri'] is! Map) continue;
      if ('${(j['veri'] as Map)['aciklama'] ?? ''}'.isEmpty) continue;
      hold('aciklama:${j['id']}', 'kart:${j['muvekkil']}');
    }
    return changed;
  }

  /// How far [noteKey], made secret, was taken back of the office: of the
  /// people who held it or may have, how many took it back on every
  /// device of theirs that did; and the others' names (by [nameOf]). Null
  /// while it is not secret, or no one held it. [caseKey], for an agenda
  /// note, brings in the older packages of its case.
  static ({int done, int of, List<String> waiting})? recallOf(
    PortalDatabase db,
    String noteKey, {
    String? caseKey,
    String Function(String person)? nameOf,
  }) {
    final hide = db.hideOf(noteKey);
    if (hide == null) return null;
    final byPerson = <String, List<bool>>{};
    for (final h in db.holdsOf(noteKey)) {
      final done = h.applied != null && h.applied! >= hide;
      byPerson.putIfAbsent(h.person, () => []).add(done);
    }
    if (caseKey != null) {
      for (final h in db.oldHoldsOf(caseKey)) {
        byPerson.putIfAbsent(h.person, () => []).add(h.applied != null);
      }
    }
    byPerson.remove('');
    if (byPerson.isEmpty) return null;
    final waiting = [
      for (final e in byPerson.entries)
        if (e.value.contains(false)) nameOf?.call(e.key) ?? e.key,
    ];
    return (
      done: byPerson.length - waiting.length,
      of: byPerson.length,
      waiting: waiting,
    );
  }
}
