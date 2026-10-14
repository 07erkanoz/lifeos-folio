import 'package:flutter/material.dart';

import '../../services/notes/secret_notes.dart';
import '../../services/office/office_network.dart';
import '../../services/portal/portal_database.dart';
import '../agenda/agenda_page.dart' show AgendaColors;

/// The name of the office person [person]; the id when not known.
String _nameOf(String person) =>
    OfficeNetwork.instance.ledger.member(person)?.name ?? person;

/// "Gizli not · büroyla paylaşılmaz" (docs/senkron-plan.md R7): beside a
/// note's text, off at first. [full] says what it means under it.
class SecretNoteSwitch extends StatelessWidget {
  const SecretNoteSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.full = false,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final lock = Icon(
      Icons.lock_outline_rounded,
      size: full ? 18 : 16,
      color: AgendaColors.taskText,
    );
    final title = Text(
      'Gizli not · büroyla paylaşılmaz',
      style: TextStyle(
        fontSize: full ? 13.5 : 13,
        fontWeight: full ? FontWeight.w600 : FontWeight.normal,
      ),
    );
    final row = Row(
      crossAxisAlignment: full
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Padding(
          padding: EdgeInsets.only(top: full ? 2 : 0),
          child: lock,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: full
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 2),
                    Text(
                      'Yalnız sizin cihazlarınıza gider. Görevlere, paylaşılan '
                      'dosyaya ve üretilen belgelere girmez.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AgendaColors.muted,
                      ),
                    ),
                  ],
                )
              : title,
        ),
        const SizedBox(width: 8),
        Switch(
          key: const ValueKey('secret-note-switch'),
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
    if (!full) return row;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        border: Border.all(color: AgendaColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: row,
    );
  }
}

/// The small "Gizli" mark of a secret note on a list.
class SecretNoteMark extends StatelessWidget {
  const SecretNoteMark({super.key});

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('secret-note-mark'),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: AgendaColors.taskFill,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 12,
          color: AgendaColors.taskText,
        ),
        const SizedBox(width: 3),
        Text(
          'Gizli',
          style: TextStyle(fontSize: 11.5, color: AgendaColors.taskText),
        ),
      ],
    ),
  );
}

/// How far a note made secret was taken back of the office: "Geri çekildi:
/// 2/3 kişide · Bekleyen: …". Nothing while no one in the office held it.
class SecretNoteStatus extends StatelessWidget {
  const SecretNoteStatus({
    super.key,
    required this.db,
    required this.noteKey,
    this.caseKey,
  });

  final PortalDatabase db;
  final String noteKey;

  /// For an agenda note: its case, for the older packages of it.
  final String? caseKey;

  @override
  Widget build(BuildContext context) {
    final r = SecretNotes.recallOf(
      db,
      noteKey,
      caseKey: caseKey,
      nameOf: _nameOf,
    );
    if (r == null) return const SizedBox.shrink();
    final done = r.waiting.isEmpty;
    final text = done
        ? 'Geri çekildi: ${r.of}/${r.of} kişide · Folio kopyalarından '
              'kaldırıldı'
        : 'Geri çekildi: ${r.done}/${r.of} kişide · Bekleyen: '
              '${r.waiting.join(', ')}; cihazı bağlanınca tamamlanır';
    return Padding(
      key: const ValueKey('secret-note-status'),
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done ? Icons.check_rounded : Icons.undo_rounded,
            size: 16,
            color: done ? AgendaColors.ok : AgendaColors.taskText,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: done ? AgendaColors.muted : AgendaColors.taskText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Before a note shared with the office is made secret: to whom it went
/// and by which way, and what taking it back can and cannot do. True to go
/// on; true at once when no one in the office held it.
Future<bool> confirmSecretNote(
  BuildContext context,
  PortalDatabase db,
  String noteKey, {
  String? caseKey,
}) async {
  final ways = <String, Set<String>>{};
  for (final h in db.holdsOf(noteKey)) {
    if (h.person.isEmpty) continue;
    ways
        .putIfAbsent(h.person, () => {})
        .add(h.scope.startsWith('gorev:') ? 'görev' : 'paylaşılan kart');
  }
  if (caseKey != null) {
    for (final h in db.oldHoldsOf(caseKey)) {
      if (h.person.isEmpty) continue;
      ways.putIfAbsent(h.person, () => {}).add('eski görev paketi');
    }
  }
  if (ways.isEmpty) return true;
  final who = [
    for (final e in ways.entries) '${_nameOf(e.key)} (${e.value.join(', ')})',
  ];
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Not büroyla paylaşılmıştı'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bu not ${ways.length} kişiye gitti: ${who.join(', ')}. Gizli '
              'yaparsanız onların cihazlarından silinmesi istenir.',
              style: const TextStyle(fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: AgendaColors.taskFill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Her alıcıda, cihazı Folio’ya bağlanınca silinir. Dışarı '
                'aktarılmış belge ve ekran görüntüsü geri alınamaz.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AgendaColors.muted,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const ValueKey('secret-note-confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Gizli yap ve geri çek'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
