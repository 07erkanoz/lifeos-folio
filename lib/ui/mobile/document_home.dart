import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/evrak_file.dart';
import '../agenda/agenda_page.dart' show AgendaColors;

/// The next hearing as the first page shows it, under the agenda's card:
/// "09:20 · Antalya 3. Asliye Hukuk · 2025/412" over "Ön inceleme
/// duruşması · 2 sa sonra".
class NextHearingLine {
  const NextHearingLine(this.title, this.detail);
  final String title, detail;
}

/// The phone's first page (UYGULAMAPLANI §13, docs/design/mobil-anasayfa-
/// taslak.png): the day and the portals, the office (the agenda with the
/// next hearing, UETS, the UYAP cases, each with what waits in it), what
/// is done with documents, and the documents opened last.
class MobileDocumentHome extends StatelessWidget {
  final List<EvrakFile> recent;
  final VoidCallback onOpen, onNew, onArchive, onRecovery;

  /// The phone's photographs. On a desktop the gallery is a place in the
  /// sidebar; a phone has no sidebar, so it needs a door of its own here.
  final VoidCallback onGallery;

  /// Camera to PDF; null where there is no scanner (off Android).
  final VoidCallback? onScan;
  final ValueChanged<EvrakFile> onRecent, onShare;
  final int recoveryCount;

  /// "Av. Erkan Öz", for the greeting; empty for none.
  final String name;

  /// The portals' state, under the greeting.
  final Widget? channels;

  /// The office: the hearings and deadlines today and the next hearing,
  /// the UETS notices unread, the cases kept and their new documents; and
  /// the way to each.
  final int agendaToday, deadlinesToday, uetsUnread, uyapCases, uyapFresh;
  final NextHearingLine? next;
  final VoidCallback? onAgenda, onUets, onUyap;

  final DateTime Function()? now;

  const MobileDocumentHome({
    super.key,
    required this.recent,
    required this.onOpen,
    required this.onNew,
    required this.onArchive,
    required this.onGallery,
    this.onScan,
    required this.onRecovery,
    required this.onRecent,
    required this.onShare,
    required this.recoveryCount,
    this.name = '',
    this.channels,
    this.agendaToday = 0,
    this.deadlinesToday = 0,
    this.uetsUnread = 0,
    this.uyapCases = 0,
    this.uyapFresh = 0,
    this.next,
    this.onAgenda,
    this.onUets,
    this.onUyap,
    this.now,
  });

  static const _days = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];
  static const _months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', //
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];

  static String _greeting(DateTime t) => t.hour >= 5 && t.hour < 12
      ? 'Günaydın'
      : t.hour >= 12 && t.hour < 18
      ? 'İyi günler'
      : 'İyi akşamlar';

  /// "dün", "3 gün önce": when a document was last changed.
  static String _ago(String path, DateTime now) {
    try {
      final t = File(path).lastModifiedSync();
      final days = DateTime(
        now.year,
        now.month,
        now.day,
      ).difference(DateTime(t.year, t.month, t.day)).inDays;
      if (days <= 0) return 'bugün';
      if (days == 1) return 'dün';
      if (days < 30) return '$days gün önce';
      return '${t.day} ${_months[t.month - 1]} ${t.year}';
    } catch (_) {
      return '';
    }
  }

  /// "UDF", "PDF": the file's own kind, as short as its extension.
  static String _kind(EvrakFile file) {
    final dot = file.path.lastIndexOf('.');
    final ext = dot < 0 ? '' : file.path.substring(dot + 1).toUpperCase();
    return ext.isEmpty || ext.length > 4 ? file.format.label : ext;
  }

  Widget _heading(String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
              color: AgendaColors.muted,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _office(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required Color fill,
    required Color tint,
    required String title,
    required String detail,
    bool urgent = false,
    int count = 0,
    VoidCallback? onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: tint, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: urgent
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: urgent ? tint : AgendaColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (count > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: primary ? colors.primary : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: primary
            ? BorderSide.none
            : BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: primary ? colors.onPrimary : colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: primary ? colors.onPrimary : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final today = (now ?? DateTime.now)();
    final actions = [
      _action(
        context,
        key: const ValueKey('mobile-open'),
        icon: Icons.upload_file_outlined,
        label: 'Belge aç',
        onTap: onOpen,
        primary: true,
      ),
      _action(
        context,
        key: const ValueKey('mobile-new'),
        icon: Icons.add_rounded,
        label: 'Yeni belge',
        onTap: onNew,
      ),
      if (onScan != null)
        _action(
          context,
          key: const ValueKey('mobile-scan'),
          icon: Icons.document_scanner_outlined,
          label: 'Tara (PDF)',
          onTap: onScan!,
        ),
      _action(
        context,
        key: const ValueKey('mobile-gallery'),
        icon: Icons.photo_library_outlined,
        label: 'Galeri',
        onTap: onGallery,
      ),
    ];
    final agenda = [
      agendaToday > 0 ? 'Bugün $agendaToday duruşma' : 'Bugün duruşma yok',
      if (deadlinesToday > 0) '$deadlinesToday süre dolacak',
    ].join(' · ');
    return ColoredBox(
      color: Theme.of(context).brightness == Brightness.dark
          ? colors.surface
          : AgendaColors.page,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
            child: Text(
              '${today.day} ${_months[today.month - 1]} '
              '${_days[today.weekday - 1]}',
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -.3,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
            child: Text(
              name.isEmpty ? _greeting(today) : '${_greeting(today)}, $name',
              style: const TextStyle(fontSize: 12.5, color: AgendaColors.muted),
            ),
          ),
          if (channels != null) ...[channels!, const SizedBox(height: 14)],
          _heading('BÜRO'),
          _office(
            context,
            key: const ValueKey('mobile-agenda'),
            icon: Icons.event_note_rounded,
            fill: AgendaColors.hearingFill,
            tint: AgendaColors.hearing,
            title: 'Ajanda',
            detail: agenda,
            urgent: agendaToday > 0 || deadlinesToday > 0,
            onTap: onAgenda,
          ),
          if (next != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                key: const ValueKey('mobile-next-hearing'),
                onTap: onAgenda,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: const BoxDecoration(
                    color: AgendaColors.hearingFill,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    border: Border(
                      left: BorderSide(color: AgendaColors.hearing, width: 3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        next!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AgendaColors.hearingText,
                        ),
                      ),
                      Text(
                        next!.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AgendaColors.hearingText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          _office(
            context,
            key: const ValueKey('mobile-uets'),
            icon: Icons.mark_email_unread_outlined,
            fill: AgendaColors.deadlineFill,
            tint: AgendaColors.deadline,
            title: 'UETS Tebligatlarım',
            detail: uetsUnread > 0
                ? '$uetsUnread okunmamış tebligat'
                : 'Okunmamış tebligat yok',
            urgent: uetsUnread > 0,
            count: uetsUnread,
            onTap: onUets,
          ),
          _office(
            context,
            key: const ValueKey('mobile-uyap'),
            icon: Icons.gavel_rounded,
            fill: AgendaColors.eHearingFill,
            tint: AgendaColors.eHearing,
            title: 'UYAP Dosyalarım',
            detail: uyapCases == 0
                ? 'Portföyünüzden dosya ekleyin'
                : [
                    '$uyapCases dosya',
                    if (uyapFresh > 0) '$uyapFresh yeni evrak',
                  ].join(' · '),
            onTap: onUyap,
          ),
          const SizedBox(height: 14),
          _heading('BELGELER'),
          LayoutBuilder(
            builder: (context, box) {
              final width = (box.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in actions) SizedBox(width: width, child: a),
                ],
              );
            },
          ),
          if (recoveryCount > 0) ...[
            const SizedBox(height: 12),
            Material(
              color: colors.primaryContainer.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                leading: Icon(Icons.restore_rounded, color: colors.primary),
                title: Text('$recoveryCount taslak kurtarılabilir'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onRecovery,
              ),
            ),
          ],
          const SizedBox(height: 18),
          _heading(
            'SON AÇILANLAR',
            trailing: TextButton.icon(
              onPressed: onArchive,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontFamily: 'LiberationSans', 
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.search, size: 17),
              label: const Text('Arşivde ara'),
            ),
          ),
          if (recent.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border.all(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Açtığınız belgeler burada görünür. Başka bir uygulamadaki '
                '“Birlikte aç” ile de Folio’ya gelebilirsiniz.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          for (final file in recent)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onRecent(file),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AgendaColors.hearingFill,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _kind(file),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: colors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  _kind(file),
                                  _ago(file.path, today),
                                ].where((s) => s.isNotEmpty).join(' · '),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AgendaColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Belgeyi paylaş',
                          onPressed: () => onShare(file),
                          icon: const Icon(Icons.ios_share_rounded, size: 19),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
