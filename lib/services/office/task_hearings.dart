import '../portal/portal_database.dart';
import '../portal/portal_hearing.dart';
import 'office_task.dart';

/// A task whose due day goes by a hearing that is no longer where it was
/// (docs/buro.md, Görev: "duruşma kayarsa görev sessizce kaymaz, sorulur"):
/// [next] is the case's next hearing, null when it has none; [due] the day
/// it would give.
class HearingMove {
  const HearingMove(this.task, this.next, this.due);
  final OfficeTask task;
  final PortalHearing? next;
  final DateTime? due;
}

/// The tasks [me] gave whose due day goes by a hearing [db] no longer
/// holds: a hearing moved to another time is another hearing, and the old
/// one leaves when UYAP no longer lists it (the web portal's sync). Each
/// is asked until the giver moves the day or keeps it; the giver's answer
/// names the hearing it went by, so it is not asked again.
List<HearingMove> hearingMoves(
  Iterable<OfficeTask> tasks,
  String me,
  PortalDatabase db,
  DateTime now,
) {
  final out = <HearingMove>[];
  final today = DateTime(now.year, now.month, now.day);
  for (final t in tasks) {
    final h = t.hearing;
    final key = t.hearingKey;
    if (h == null || key == null || t.by != me || !t.open) continue;
    final kept = db.hearings(caseKey: h.caseKey);
    if (kept.any((x) => x.key == key)) continue;
    final next = [
      for (final x in kept)
        if (!x.at.isBefore(today)) x,
    ]..sort((a, b) => a.at.compareTo(b.at));
    final first = next.firstOrNull;
    // Kept on the old day once there was no hearing: asked again only
    // when a new one comes.
    if (first == null && key == 'yok') continue;
    out.add(
      HearingMove(
        t,
        first,
        first == null ? null : TaskHearing.dueFor(first.at, h.daysBefore),
      ),
    );
  }
  return out;
}
