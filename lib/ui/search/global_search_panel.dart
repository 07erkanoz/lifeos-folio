import 'package:flutter/material.dart';

import '../../models/evrak_file.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../portfolio/portfolio_rows.dart';
import 'global_search.dart';

/// What the home page's search found, a group at a time, at most five in
/// each: a row opens its one place, "tümünü göster" the rest.
class GlobalSearchPanel extends StatelessWidget {
  const GlobalSearchPanel({
    super.key,
    required this.results,
    required this.selected,
    required this.onPick,
    required this.onShowCases,
    required this.onShowFiles,
    required this.onOpenGroup,
    this.searching = false,
    this.scrolls = true,
  });

  final GlobalSearchResults results;

  /// The row the arrows are on, in [GlobalSearchResults.shown].
  final int selected;
  final ValueChanged<Found> onPick;

  /// UYAP Dosyalarım searched for the query; the archive searched for it.
  final VoidCallback onShowCases, onShowFiles;

  /// The documents' or the agenda's group shown whole, in place.
  final void Function({bool documents, bool agenda}) onOpenGroup;
  final bool searching;

  /// False where the page around it scrolls.
  final bool scrolls;

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _date(DateTime t) =>
      '${_two(t.day)}.${_two(t.month)}.${t.year}';
  static String _when(DateTime t) => t.hour == 0 && t.minute == 0
      ? _date(t)
      : '${_date(t)} ${_two(t.hour)}:${_two(t.minute)}';

  static IconData _fileIcon(EvrakFormat format) => switch (format) {
    EvrakFormat.udf => Icons.edit_note_rounded,
    EvrakFormat.pdf => Icons.picture_as_pdf_rounded,
    EvrakFormat.docx || EvrakFormat.doc => Icons.description_rounded,
    _ when format.isVisual => Icons.image_outlined,
    _ => Icons.article_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          searching
              ? 'Aranıyor…'
              : '“${results.query}” için bir şey bulunamadı.',
          style: const TextStyle(fontSize: 13, color: AgendaColors.muted),
        ),
      );
    }
    var index = 0;
    final children = <Widget>[];

    void group<T extends Found>(
      String title,
      FoundGroup<T> found,
      int total,
      Widget Function(T, bool selected) row, {
      String? more,
      VoidCallback? onMore,
    }) {
      if (found.isEmpty) return;
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '$title · $total',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: .6,
              color: AgendaColors.muted,
            ),
          ),
        ),
      );
      for (final f in found.first) {
        final i = index++;
        children.add(
          KeyedSubtree(key: ValueKey('found-$i'), child: row(f, i == selected)),
        );
      }
      if (more != null && onMore != null) {
        children.add(
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: TextButton(
                key: ValueKey('found-more-$title'),
                onPressed: onMore,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(more),
              ),
            ),
          ),
        );
      }
    }

    group(
      'UYAP DOSYALARI',
      results.cases,
      results.cases.total,
      (f, on) => _row(
        context,
        on,
        Icons.folder_outlined,
        '${f.row.kase.number} · ${f.row.kase.court}',
        [
          if (f.row.type.isNotEmpty) f.row.type,
          for (final p in [...f.row.ours, ...f.row.others].take(2))
            titleName(p.name),
        ].join(' · '),
        () => onPick(f),
      ),
      more: results.cases.more
          ? '${results.cases.total} dosyanın tümünü göster'
          : null,
      onMore: onShowCases,
    );
    group(
      'TARAFLAR',
      results.parties,
      results.parties.total,
      (f, on) => _row(
        context,
        on,
        Icons.person_outline_rounded,
        titleName(f.name),
        f.cases.length == 1
            ? [
                if (f.role.isNotEmpty) titleName(f.role),
                '${f.cases.single.kase.number} · ${f.cases.single.kase.court}',
              ].join(' · ')
            : [
                if (f.role.isNotEmpty) titleName(f.role),
                '${f.cases.length} dosyada',
              ].join(' · '),
        () => onPick(f),
      ),
      more: results.parties.more
          ? '${results.parties.total} tarafın tümünü göster'
          : null,
      onMore: onShowCases,
    );
    group(
      'UYAP EVRAKLARI',
      results.documents,
      results.documents.total,
      (f, on) => _row(
        context,
        on,
        Icons.description_outlined,
        f.document.title,
        [
          '${f.row.kase.number} · ${f.row.kase.court}',
          if (f.document.date != null) _date(f.document.date!),
        ].join(' · '),
        () => onPick(f),
      ),
      more: results.documents.more
          ? '${results.documents.total} evrakın tümünü göster'
          : null,
      onMore: () => onOpenGroup(documents: true),
    );
    group(
      'ARŞİV BELGELERİ',
      results.files,
      results.filesTotal,
      (f, on) => _row(
        context,
        on,
        _fileIcon(f.hit.file.format),
        f.hit.file.name,
        f.hit.excerpt.replaceAll(RegExp(r'\s+'), ' ').trim(),
        () => onPick(f),
      ),
      more: results.filesTotal > results.files.first.length
          ? '${results.filesTotal} belgenin tümünü göster'
          : null,
      onMore: onShowFiles,
    );
    group(
      'AJANDA',
      results.agenda,
      results.agenda.total,
      (f, on) {
        final h = f.hearing;
        final item = f.item;
        return _row(
          context,
          on,
          h != null
              ? Icons.gavel_rounded
              : item?.kind == 'deadline'
              ? Icons.timer_outlined
              : Icons.event_note_outlined,
          h != null ? 'Duruşma · ${h.number}' : item!.title,
          [
            if (f.day != null) _when(f.day!) else 'Tarihsiz not',
            if (h != null) h.court,
          ].join(' · '),
          () => onPick(f),
        );
      },
      more: results.agenda.more
          ? '${results.agenda.total} kaydın tümünü göster'
          : null,
      onMore: () => onOpenGroup(agenda: true),
    );
    children.add(const SizedBox(height: 8));
    final list = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    return Material(
      color: scheme.surface,
      child: scrolls ? SingleChildScrollView(child: list) : list,
    );
  }

  Widget _row(
    BuildContext context,
    bool selected,
    IconData icon,
    String title,
    String detail,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? scheme.primary.withValues(alpha: .08) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 19, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AgendaColors.muted,
                      ),
                    ),
                ],
              ),
            ),
            if (selected)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.keyboard_return_rounded,
                  size: 16,
                  color: AgendaColors.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
