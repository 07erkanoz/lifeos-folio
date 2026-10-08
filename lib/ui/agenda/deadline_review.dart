import 'package:flutter/material.dart';

import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_deadline.dart';
import 'agenda_page.dart' show AgendaColors;

/// The reasons a lawyer reads first, most telling first; the one every
/// notice has (the service day not yet checked against the evidence) is
/// left to the details.
const _order = [
  'onaySonrasiDegisti',
  'sayiCelisiyor',
  'olayBekleniyor',
  'tatilBelirsiz',
  'kesinSure',
  'gocEslesmedi',
  'eskiTamamlandi',
  'takipTuruBelirsiz',
  'kararTarihiBilinmiyor',
  'kategoriBelirsiz',
  'eskiKayitFarkli',
  'artikUretilmiyor',
  'turKonudan',
  'yarimGun',
  'takvimDisi',
  'maliTatilKaydi',
  'aidiyet',
];

List<DeadlineReason> leadingReasons(KeptDeadline d, {int count = 2}) {
  final rs = [...d.record.reasons]
    ..removeWhere((r) => r.code == 'besGunKurali' || r.code == 'dayanak');
  rs.sort((a, b) {
    int at(DeadlineReason r) {
      final i = _order.indexOf(r.code);
      return i < 0 ? _order.length : i;
    }

    return at(a).compareTo(at(b));
  });
  return rs.take(count).toList();
}

String _dayText(String key) {
  final p = key.split('-');
  return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : key;
}

/// What a deadline's state says to the lawyer.
String deadlineStateText(KeptDeadline d) => d.confirmed
    ? 'Onaylandı'
    : d.reconfirm
    ? switch (d.previousDay) {
        null => 'Yeniden onayınızı bekliyor',
        final before when d.record.state != 'aday' =>
          'Artık hesaplanmıyor; önce ${_dayText(before)} onaylanmıştı',
        final before =>
          'Yeniden onayınızı bekliyor; önce ${_dayText(before)} onaylanmıştı',
      }
    : switch (d.record.state) {
        'aday' => 'Onayınızı bekliyor',
        'olayBekleniyor' => 'Başlangıç olayı bekleniyor',
        'desteklenmiyor' => 'Bu sürümde hesaplanmıyor',
        'eski' => 'Önceki hesap',
        _ => d.record.state,
      };

/// One deadline to be looked at: its day (or why it has none), the first
/// reasons, whose it seems to be, and what the lawyer can do.
class DeadlineReviewTile extends StatelessWidget {
  const DeadlineReviewTile({
    super.key,
    required this.deadline,
    required this.onConfirm,
    required this.onSetDay,
    required this.onDismiss,
    required this.onDetails,
    this.subtitle,
    this.onOpenCase,
    this.onOpenNotice,
    this.onChange,
  });

  final KeptDeadline deadline;
  final VoidCallback? onConfirm;
  final VoidCallback onSetDay;
  final VoidCallback onDismiss;
  final VoidCallback onDetails;

  /// The notice it came from ("Konya 14. Asliye Hukuk · 2026/441").
  final String? subtitle;

  /// Goes to its case in UYAP Dosyalarım; null when it is not kept there.
  final VoidCallback? onOpenCase;

  /// Goes to its notice on the UETS page.
  final VoidCallback? onOpenNotice;

  /// Another deadline in its place, chosen by the lawyer; null where it
  /// cannot be changed from here.
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final d = deadline;
    final r = d.record;
    final day = d.day;
    final owner = switch (r.ownership) {
      'olasiBizim' => ('Sizin olabilir', AgendaColors.ok),
      'olasiKarsi' => ('Karşı tarafın olabilir', AgendaColors.muted),
      _ => null,
    };
    return Container(
      key: ValueKey('review-${r.id}'),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF1F3F6))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 82,
                child: Text(
                  day == null ? 'Tarih yok' : _dayText(day),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: day == null
                        ? AgendaColors.muted
                        : AgendaColors.deadlineText,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [
                        if (r.law.isNotEmpty) r.law,
                        deadlineStateText(d),
                        ?subtitle,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AgendaColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (owner != null)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: owner.$2.withValues(alpha: .5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    owner.$1,
                    style: TextStyle(fontSize: 10.5, color: owner.$2),
                  ),
                ),
            ],
          ),
          for (final reason in leadingReasons(d))
            Padding(
              padding: const EdgeInsets.only(left: 82, top: 3),
              child: Text(
                reason.text,
                style: const TextStyle(fontSize: 11.5, height: 1.3),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 74, top: 2),
            child: Wrap(
              spacing: 2,
              children: [
                if (onConfirm != null)
                  TextButton(
                    key: ValueKey('review-confirm-${r.id}'),
                    onPressed: onConfirm,
                    child: const Text('Onayla'),
                  ),
                if (onChange != null)
                  TextButton(
                    key: ValueKey('review-change-${r.id}'),
                    onPressed: onChange,
                    child: const Text('Süreyi değiştir'),
                  ),
                TextButton(
                  key: ValueKey('review-day-${r.id}'),
                  onPressed: onSetDay,
                  child: const Text('Tarih gir'),
                ),
                TextButton(onPressed: onDetails, child: const Text('Ayrıntı')),
                if (onOpenCase != null)
                  TextButton(
                    key: ValueKey('review-case-${r.id}'),
                    onPressed: onOpenCase,
                    child: const Text('Dosyaya git'),
                  ),
                if (onOpenNotice != null)
                  TextButton(
                    key: ValueKey('review-notice-${r.id}'),
                    onPressed: onOpenNotice,
                    child: const Text('Tebligatı aç'),
                  ),
                TextButton(
                  key: ValueKey('review-dismiss-${r.id}'),
                  onPressed: onDismiss,
                  child: const Text('Gerekmez'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The lawyer's own last day for [d]; null when given up.
Future<String?> askDeadlineDay(BuildContext context, KeptDeadline d) async {
  final now = DateTime.now();
  DateTime? initial;
  final day = d.day;
  if (day != null) {
    final p = day.split('-').map(int.parse).toList();
    initial = DateTime(p[0], p[1], p[2]);
  }
  final picked = await showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: DateTime(now.year - 5),
    lastDate: DateTime(now.year + 5),
    helpText: 'Son günü siz belirleyin',
  );
  if (picked == null) return null;
  return '${picked.year.toString().padLeft(4, '0')}-'
      '${picked.month.toString().padLeft(2, '0')}-'
      '${picked.day.toString().padLeft(2, '0')}';
}

/// Every reason of [d], the engine's and the lawyer's days, and what
/// changed it and when.
Future<void> showDeadlineDetails(
  BuildContext context,
  PortalDatabase db,
  KeptDeadline d,
) {
  final r = d.record;
  final history = db.deadlineHistory(r.id);
  final legacy = db.legacyOf(r.id);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(r.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [if (r.law.isNotEmpty) r.law, deadlineStateText(d)].join(' · '),
                style: const TextStyle(color: AgendaColors.muted),
              ),
              const SizedBox(height: 10),
              _row(
                'Başlangıç',
                r.startDay == null ? '—' : _dayText(r.startDay!),
              ),
              _row('Ham son gün', r.rawDay == null ? '—' : _dayText(r.rawDay!)),
              _row(
                'Motorun son günü',
                r.dueDay == null ? '—' : _dayText(r.dueDay!),
              ),
              if (d.user?.manualDay != null)
                _row('Sizin son gününüz', _dayText(d.user!.manualDay!)),
              if (legacy != null && legacy.at != null)
                _row(
                  'Önceki kayıt',
                  '${legacy.at!.day.toString().padLeft(2, '0')}.'
                      '${legacy.at!.month.toString().padLeft(2, '0')}.'
                      '${legacy.at!.year} · ${legacy.title}'
                      '${legacy.done ? ' · tamamlandı' : ''}',
                ),
              const SizedBox(height: 12),
              const Text(
                'Gerekçeler',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final reason in r.reasons)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('• ${reason.text}'),
                ),
              if (history.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Geçmiş',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final h in history)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${h.at.day.toString().padLeft(2, '0')}.'
                      '${h.at.month.toString().padLeft(2, '0')}.${h.at.year} '
                      '${h.at.hour.toString().padLeft(2, '0')}:'
                      '${h.at.minute.toString().padLeft(2, '0')} · ${h.change}'
                      '${h.dueDay == null ? '' : ' · ${_dayText(h.dueDay!)}'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AgendaColors.muted,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
    ),
  );
}

Widget _row(String label, String value) => Padding(
  padding: const EdgeInsets.only(top: 3),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 140,
        child: Text(label, style: const TextStyle(color: AgendaColors.muted)),
      ),
      Expanded(child: Text(value)),
    ],
  ),
);
