import 'package:flutter/material.dart';

import '../../services/clients/client.dart';
import '../../services/clients/client_accounts.dart';
import '../../services/office/office_network.dart';
import '../../services/office/proposals.dart';
import '../../services/portal/portal_database.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import 'notice.dart';

/// The proposals as this device sees them: of this person, on this
/// device (docs/senkron-plan.md R6).
ProposalService proposalsHere(PortalDatabase db) => proposalsFor(db);

/// How [proposalsHere] is made: the office's network's person and device;
/// another in tests.
ProposalService Function(PortalDatabase db) proposalsFor = (db) {
  final net = OfficeNetwork.instance;
  return ProposalService(
    db,
    me: net.me,
    device: net.self?.deviceId ?? '',
    myName: net.self?.name ?? '',
    kept: net.kept,
  );
};

String _nameOf(String person) =>
    OfficeNetwork.instance.ledger.member(person)?.name ?? person;

String _day(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';

/// What [p] would change, field by field: what it says now, what it would.
List<({String label, String now, String then})> proposalChanges(
  PortalDatabase db,
  Proposal p,
) {
  String money(Object? v) => v is int ? lira(v) : '';
  String day(Object? v) => switch (DateTime.tryParse('$v')) {
    final d? => _day(d),
    null => '',
  };
  switch (p.kind) {
    case 'icra':
      final r = db.clientRecord(p.target);
      if (r == null) return const [];
      if (p.remove) {
        return [(label: 'Kayıt', now: 'duruyor', then: 'silinsin')];
      }
      final now = r.data;
      return [
        for (final (key, label, show) in [
          ('tutar', 'Tutar', money),
          ('zaman', 'Tarih', day),
          ('borclu', 'Borçlu', (Object? v) => '${v ?? ''}'),
          ('odeme', 'Ödeme', (Object? v) => '${v ?? ''}'),
          ('aciklama', 'Açıklama', (Object? v) => '${v ?? ''}'),
          ('tamami', 'Tamamı', (Object? v) => v == true ? 'evet' : 'hayır'),
        ])
          if (p.fields.containsKey(key) &&
              show(p.fields[key]) != show(now[key]))
            (label: label, now: show(now[key]), then: show(p.fields[key])),
      ];
    case 'kartNotu' || 'dosyaNotu':
      final card = db.clientCard(p.target);
      final now = p.kind == 'kartNotu'
          ? card?.note ?? ''
          : card?.caseNotes[p.caseKey]?.text ?? '';
      return [
        (
          label: 'Not',
          now: now.isEmpty ? '—' : now,
          then: '${p.fields['metin'] ?? ''}',
        ),
      ];
  }
  return const [];
}

/// What [p] is of, in words.
String proposalTitle(PortalDatabase db, Proposal p) {
  switch (p.kind) {
    case 'icra':
      final r = db.clientRecord(p.target);
      final what = r?.data['tur'] == 'feragat' ? 'Feragat' : 'Haricen tahsilat';
      return '$what · ${r?.text('dosya') ?? ''}';
    case 'kartNotu':
      return 'Müvekkil notu · ${db.clientCard(p.target)?.name ?? ''}';
    case 'dosyaNotu':
      return 'Dosya notu · ${db.clientCard(p.target)?.name ?? ''} · '
          '${p.caseKey}';
  }
  return p.kind;
}

/// Under a record of a colleague's: this person's latest proposal of it,
/// waiting, taken or not.
class ProposalStatus extends StatelessWidget {
  const ProposalStatus({
    super.key,
    required this.db,
    required this.target,
    this.caseKey = '',
  });

  final PortalDatabase db;
  final String target, caseKey;

  @override
  Widget build(BuildContext context) {
    final me = proposalsHere(db).me;
    final mine = [
      for (final p in db.proposals(by: me))
        if (p.target == target && p.caseKey == caseKey) p,
    ];
    if (mine.isEmpty) return const SizedBox.shrink();
    final p = mine.first;
    final d = db.decisionOf(p.id);
    final changes = proposalChanges(db, p);
    final what = changes.isEmpty
        ? (p.remove ? 'Silinmesi' : 'Değişiklik')
        : changes.map((c) => '${c.label} ${c.then}').join(', ');
    final (text, fill, ink, detail) = switch (d) {
      null || ProposalDecision(void_: true) => (
        'Öneriniz bekliyor',
        AgendaColors.taskFill,
        AgendaColors.taskText,
        '$what · ${_day(p.at)}',
      ),
      ProposalDecision(approved: true) => (
        'Onaylandı',
        AgendaColors.hearingFill,
        AgendaColors.ok,
        '${_nameOf(p.owner)}, ${_day(d.at)}',
      ),
      ProposalDecision(stale: true) => (
        'Kayıt bu arada değişti',
        AgendaColors.taskFill,
        AgendaColors.taskText,
        'Öneri eski kaldı; yeniden bakıp önerin.',
      ),
      _ => (
        'Reddedildi',
        AgendaColors.deadlineFill,
        AgendaColors.deadlineText,
        [
          if (d.reason.isNotEmpty) '"${d.reason}"',
          _nameOf(p.owner),
        ].join(' · '),
      ),
    };
    return Padding(
      key: ValueKey('proposal-status-$target'),
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(text, style: TextStyle(fontSize: 11.5, color: ink)),
          ),
          Text(
            detail,
            style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
          ),
        ],
      ),
    );
  }
}

/// "Bekleyen öneriler · n": what colleagues proposed of this person's
/// records, to be decided; pressed, the list. Nothing while none waits.
class ProposalsStrip extends StatelessWidget {
  const ProposalsStrip({super.key, required this.db, this.onChanged});

  final PortalDatabase db;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final service = proposalsHere(db);
    final waiting = service.waiting.length + service.conflicts.length;
    if (waiting == 0) return const SizedBox.shrink();
    return Material(
      key: const ValueKey('proposals-strip'),
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AgendaColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await showProposals(context, db);
          onChanged?.call();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              Icon(Icons.inbox_outlined, size: 18, color: AgendaColors.hearing),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bekleyen öneriler · $waiting',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AgendaColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The proposals waiting for this person, each to be taken or refused on
/// the device for deciding; elsewhere only shown.
Future<void> showProposals(
  BuildContext context,
  PortalDatabase db,
) => showDialog<void>(
  context: context,
  builder: (context) => StatefulBuilder(
    builder: (context, set) {
      final service = proposalsHere(db);
      final waiting = service.waiting;
      final conflicts = service.conflicts;
      final here = service.decidesHere;
      final deciding = service.deciding(service.me).device;
      final where =
          OfficeNetwork.instance.ledger.member(deciding)?.device ?? '';
      Future<void> decide(Proposal p, bool approve) async {
        var reason = '';
        if (!approve && service.current(p)) {
          final said = await _reasonOf(context);
          if (said == null) return;
          reason = said;
        }
        final d = service.decide(p.id, approve: approve, reason: reason);
        if (d == null && context.mounted) {
          showNotice(context, 'Bu öneri bu cihazda karara bağlanamaz.');
        }
        set(() {});
      }

      return AlertDialog(
        title: Text('Bekleyen öneriler · ${waiting.length + conflicts.length}'),
        content: SizedBox(
          width: 520,
          child: waiting.isEmpty && conflicts.isEmpty
              ? const Text('Bekleyen öneri yok.')
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!here)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Öneriler ${where.isEmpty ? 'karar cihazınızda' : '$where cihazınızda'} '
                            'karara bağlanır; burada yalnız görünür.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AgendaColors.muted,
                            ),
                          ),
                        ),
                      for (final d in conflicts)
                        if (db.proposal(d.proposal) case final p?)
                          _ConflictItem(
                            db: db,
                            proposal: p,
                            onSeen: () =>
                                set(() => db.clearDecisionConflict(p.id)),
                          ),
                      for (final p in waiting)
                        _ProposalItem(
                          db: db,
                          proposal: p,
                          current: service.current(p),
                          decides: here,
                          onDecide: (approve) => decide(p, approve),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      );
    },
  ),
);

Future<String?> _reasonOf(BuildContext context) {
  final text = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reddet'),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const ValueKey('proposal-reason'),
          controller: text,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Neden (isteğe bağlı)'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const ValueKey('proposal-refuse'),
          onPressed: () => Navigator.pop(context, text.text.trim()),
          child: const Text('Reddet'),
        ),
      ],
    ),
  );
}

class _ProposalItem extends StatelessWidget {
  const _ProposalItem({
    required this.db,
    required this.proposal,
    required this.current,
    required this.decides,
    required this.onDecide,
  });

  final PortalDatabase db;
  final Proposal proposal;
  final bool current, decides;
  final void Function(bool approve) onDecide;

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    final changes = proposalChanges(db, p);
    final muted = TextStyle(fontSize: 12.5, color: AgendaColors.muted);
    return Container(
      key: ValueKey('proposal-${p.id}'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AgendaColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${p.byName.isEmpty ? _nameOf(p.by) : p.byName} · '
            '${proposalTitle(db, p)}',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          for (final c in changes)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${c.label}: ', style: muted),
                    TextSpan(text: c.now),
                    const TextSpan(text: ' → '),
                    TextSpan(
                      text: c.then,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              [
                if (p.reason.isNotEmpty) 'Neden: ${p.reason}',
                _day(p.at),
              ].join(' · '),
              style: muted,
            ),
          ),
          if (!current)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Kayıt bu arada değişti; öneri eski.',
                key: ValueKey('proposal-stale-${p.id}'),
                style: TextStyle(fontSize: 12.5, color: AgendaColors.taskText),
              ),
            ),
          if (decides)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: current
                    ? [
                        OutlinedButton(
                          key: ValueKey('proposal-no-${p.id}'),
                          onPressed: () => onDecide(false),
                          child: const Text('Reddet'),
                        ),
                        FilledButton(
                          key: ValueKey('proposal-yes-${p.id}'),
                          onPressed: () => onDecide(true),
                          child: const Text('Onayla'),
                        ),
                      ]
                    : [
                        OutlinedButton(
                          key: ValueKey('proposal-close-${p.id}'),
                          onPressed: () => onDecide(true),
                          child: const Text('Kapat'),
                        ),
                      ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A decision that did not hold whose change was changed again since: the
/// record left as it is now, for the owner to look at.
class _ConflictItem extends StatelessWidget {
  const _ConflictItem({
    required this.db,
    required this.proposal,
    required this.onSeen,
  });

  final PortalDatabase db;
  final Proposal proposal;
  final VoidCallback onSeen;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('proposal-conflict-${proposal.id}'),
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: AgendaColors.line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          proposalTitle(db, proposal),
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Kaybolan cihazın bu öneriye verdiği karar geçersiz sayıldı. '
          'Kararın yaptığı değişiklik sonra yeniden değiştiği için geri '
          'alınmadı; kayda elle bakın.',
          style: TextStyle(fontSize: 12.5, color: AgendaColors.taskText),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: onSeen, child: const Text('Tamam')),
        ),
      ],
    ),
  );
}

/// The card of a colleague's [c], for the notice of what is theirs.
bool othersCard(Client c) {
  final me = OfficeNetwork.instance.me;
  return c.person.isNotEmpty && me.isNotEmpty && c.person != me;
}

/// Which of this person's devices decides on the colleagues' proposals
/// (R6): given over from it to another of theirs, both on; or, it lost,
/// this one chosen anew.
class DecisionDeviceBox extends StatefulWidget {
  const DecisionDeviceBox({super.key, required this.network, this.database});

  final OfficeNetwork network;
  final PortalDatabase? database;

  @override
  State<DecisionDeviceBox> createState() => _DecisionDeviceBoxState();
}

class _DecisionDeviceBoxState extends State<DecisionDeviceBox> {
  PortalDatabase? _db;

  @override
  void initState() {
    super.initState();
    _db = widget.database;
    if (_db == null) {
      PortalDatabase.shared().then((db) {
        if (mounted) setState(() => _db = db);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = _db;
    final net = widget.network;
    if (db == null || !net.ledger.exists) return const SizedBox.shrink();
    final service = ProposalService(
      db,
      me: net.me,
      device: net.self?.deviceId ?? '',
      kept: net.kept,
    );
    final deciding = service.deciding(net.me).device;
    final here = service.decidesHere;
    final name = here
        ? 'bu cihaz'
        : net.ledger.member(deciding)?.device ??
              net.ownKnown
                  .where((d) => d.deviceId == deciding)
                  .firstOrNull
                  ?.device ??
              'ilk cihazınız';
    final muted = TextStyle(fontSize: 12.5, color: AgendaColors.muted);
    return Container(
      key: const ValueKey('decision-device'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border.all(color: AgendaColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Meslektaşların önerileri $name'
                  '${here ? 'da' : ' cihazınızda'} karara bağlanır.',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Diğer cihazlarınızda öneriler görünür; onay ve red buradan '
            'verilir.',
            style: muted,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (here)
                for (final d in net.ownOnline)
                  OutlinedButton(
                    key: ValueKey('decision-give-${d.deviceId}'),
                    onPressed: () {
                      service.giveTo(d.deviceId);
                      net.ownChanged();
                      setState(() {});
                    },
                    child: Text(
                      '${d.device.isEmpty ? d.name : d.device} cihazına devret',
                    ),
                  ),
              // A device seen anew at each start never decides.
              if (!here && net.kept)
                OutlinedButton(
                  key: const ValueKey('decision-lost'),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('$name kayboldu mu?'),
                        content: const Text(
                          'Öneriler bundan sonra bu cihazda karara bağlanır. '
                          'Kaybolan cihazın verip henüz diğer cihazlarınıza '
                          'ulaşmamış kararları geçersiz olur; o öneriler '
                          'yeniden karara açılır.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Vazgeç'),
                          ),
                          FilledButton(
                            key: const ValueKey('decision-lost-ok'),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text(
                              'Kayboldu, bu cihaz karar versin',
                            ),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    service.lost();
                    net.ownChanged();
                    if (mounted) setState(() {});
                  },
                  child: Text('$name kayboldu'),
                ),
            ],
          ),
          if (here && net.ownOnline.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Devretmek için diğer cihazınız da açık olmalı.',
                style: muted,
              ),
            ),
        ],
      ),
    );
  }
}
