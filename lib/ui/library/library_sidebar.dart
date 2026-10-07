import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/search/library_controller.dart';
import '../theme/theme_controller.dart';

class LibrarySidebar extends StatelessWidget {
  final LibraryController library;
  final ThemeController appearance;
  final bool compact;
  final String group;
  final VoidCallback pickFiles;
  final VoidCallback pickFolder;
  final VoidCallback showStatus;
  final ValueChanged<String> selectGroup;
  final ValueChanged<int> selectFolder;

  /// The UYAP cases kept on this computer, listed under UYAP when it is
  /// chosen: each case's key, number, court and how many documents came new
  /// at its last fetch.
  final List<(String, String, String, int)> uyapCases;

  /// The portfolio's open cases, as UYAP Dosyalarım counts them; null
  /// until it is read, and then [uyapCases], the cases kept in detail.
  final int? uyapCount;

  /// Where UYAP's documents are saved: the archive folder that stands as
  /// UYAP in the list of folders, not as one more folder.
  final String? uyapFolder;

  /// Whether UYAP can be reached from this Folio at all: on a phone only
  /// the cases already kept are shown.
  final bool uyapAvailable;

  /// The desktop's first page, at the top of the list.
  final bool showHome;

  /// The cases with something new in them: new to the portfolio, or with
  /// documents not yet looked at.
  final int uyapFresh;

  /// The agenda's hearings today, for the badge beside Ajanda.
  final int agendaToday;

  /// UETS notifications not yet opened, for the badge beside UETS.
  final int uetsUnread;

  /// UYAP's notifications not yet read, for the badge beside them.
  final int uyapNotices;

  /// Widens the panel folded on the UYAP pages, or folds it again; null
  /// where the window's width decides alone.
  final VoidCallback? onTogglePanel;
  const LibrarySidebar({
    super.key,
    required this.library,
    required this.appearance,
    required this.compact,
    required this.group,
    required this.pickFiles,
    required this.pickFolder,
    required this.showStatus,
    required this.selectGroup,
    required this.selectFolder,
    this.uyapCases = const [],
    this.uyapCount,
    this.uyapFolder,
    this.uyapAvailable = false,
    this.showHome = false,
    this.uyapFresh = 0,
    this.agendaToday = 0,
    this.uetsUnread = 0,
    this.uyapNotices = 0,
    this.onTogglePanel,
  });

  bool get _showUyap => uyapAvailable || uyapCases.isNotEmpty;

  bool _isUyapFolder(String path) =>
      uyapFolder != null && p.equals(path, uyapFolder!);
  @override
  Widget build(BuildContext context) => _content(context);

  Widget _content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Container(
        width: compact ? 76 : 236,
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: scheme.outlineVariant)),
        ),
        // The whole list scrolls in a low window; in a tall one the index
        // and Ayarlar stay at the bottom.
        child: CustomScrollView(
          slivers: [
            SliverList.list(
              children: [
                const SizedBox(height: 16),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (compact) ...[
                        IconButton.filled(
                          tooltip: 'Dosya Aç',
                          onPressed: pickFiles,
                          icon: const Icon(Icons.add_rounded),
                        ),
                        const SizedBox(height: 8),
                        IconButton.outlined(
                          tooltip: 'Klasör Ekle',
                          onPressed: pickFolder,
                          icon: const Icon(Icons.create_new_folder_outlined),
                        ),
                      ] else ...[
                        FilledButton.icon(
                          onPressed: pickFiles,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Dosya Aç'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: pickFolder,
                          icon: const Icon(
                            Icons.create_new_folder_outlined,
                            size: 18,
                          ),
                          label: const Text('Klasör Ekle'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                if (showHome)
                  _nav(
                    context,
                    Icons.home_outlined,
                    'Anasayfa',
                    'home',
                    null,
                    key: const ValueKey('nav-home'),
                  ),
                _nav(
                  context,
                  Icons.grid_view_rounded,
                  'Tüm Evraklar',
                  'all',
                  library.total,
                ),
                _nav(
                  context,
                  Icons.description_outlined,
                  'Belgeler',
                  'documents',
                  null,
                ),
                _nav(
                  context,
                  Icons.photo_library_outlined,
                  'Galeri',
                  'images',
                  null,
                ),
                // İçtihat araması buradan kaldırıldı: bu liste arşivin
                // görünümlerini sayar, o ise dışarıdaki bir bankaya sorulan
                // ayrı bir soru. Yazarken sorulur, editörün araç çubuğundan.
                // The office: the cases, the agenda and the notifications, one
                // under another (UYGULAMAPLANI §10).
                if (!compact) _heading(context, 'BÜRO'),
                if (_showUyap)
                  _nav(
                    context,
                    Icons.gavel_rounded,
                    'UYAP Dosyalarım',
                    'uyap',
                    uyapCount ?? uyapCases.length,
                    key: const ValueKey('uyap-folder'),
                    selected: group == 'uyap' || group.startsWith('uyap:'),
                    badge: uyapFresh > 0
                        ? _badge(context, '$uyapFresh yeni', danger: false)
                        : null,
                  ),
                if (_showUyap)
                  _nav(
                    context,
                    Icons.notifications_outlined,
                    'UYAP Bildirimleri',
                    'bildirim',
                    null,
                    key: const ValueKey('uyap-notices'),
                    badge: uyapNotices > 0
                        ? _badge(context, '$uyapNotices', danger: false)
                        : null,
                  ),
                _nav(
                  context,
                  Icons.event_note_rounded,
                  'Ajanda',
                  'agenda',
                  null,
                  key: const ValueKey('agenda'),
                  badge: agendaToday > 0
                      ? _badge(context, 'Bugün $agendaToday', danger: false)
                      : null,
                ),
                _nav(
                  context,
                  Icons.mark_email_unread_outlined,
                  'UETS Tebligatlarım',
                  'uets',
                  null,
                  key: const ValueKey('uets'),
                  badge: uetsUnread > 0
                      ? _badge(context, '$uetsUnread', danger: true)
                      : null,
                ),
                const SizedBox(height: 14),
                if (!compact)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Row(
                      children: [
                        Text(
                          'KLASÖRLER',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Klasör Ekle',
                          onPressed: pickFolder,
                          icon: const Icon(Icons.add, size: 16),
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!compact)
                  ListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    children: [
                      for (final source in library.sources.where(
                        (s) => s.folder && !_isUyapFolder(s.path),
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Tooltip(
                            message: source.path,
                            child: ListTile(
                              dense: true,
                              minTileHeight: 42,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              selected: library.sourceId == source.id,
                              selectedTileColor: scheme.primary.withValues(
                                alpha: .08,
                              ),
                              leading: Icon(
                                source.error == null
                                    ? Icons.folder_outlined
                                    : Icons.folder_off_outlined,
                                size: 18,
                                color: source.error == null
                                    ? scheme.onSurfaceVariant
                                    : scheme.error,
                              ),
                              minLeadingWidth: 18,
                              title: Text(
                                source.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: Text(
                                '${source.count}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              onTap: () => selectFolder(source.id),
                            ),
                          ),
                        ),
                      if (library.sources.where((s) => s.folder).isEmpty &&
                          !_showUyap)
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            'Klasörleriniz tek yerde.\nEkleyin, içeriklerinde arayın.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.6,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.all(compact ? 12 : 16),
                  child: Column(
                    children: [
                      if (!compact)
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: showStatus,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  library.active
                                      ? Icons.sync
                                      : Icons.offline_bolt_outlined,
                                  color: scheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        library.active
                                            ? 'İndeksleniyor'
                                            : 'Yerel arşiv',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      ListenableBuilder(
                                        listenable: library.progress,
                                        builder: (context, _) => Text(
                                          library.active
                                              ? '${library.processed} / ${library.toProcess}'
                                              : '${library.searchable} içerik aranabilir',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (onTogglePanel != null)
                        IconButton(
                          key: const ValueKey('sidebar-toggle'),
                          tooltip: compact ? 'Paneli aç' : 'Paneli daralt',
                          onPressed: onTogglePanel,
                          icon: Icon(
                            compact
                                ? Icons.keyboard_double_arrow_right_rounded
                                : Icons.keyboard_double_arrow_left_rounded,
                            size: 18,
                          ),
                        ),
                      if (compact)
                        IconButton(
                          tooltip: 'İndeks durumu',
                          onPressed: showStatus,
                          icon: const Icon(Icons.storage_outlined),
                        ),
                      if (!compact)
                        TextButton.icon(
                          onPressed: pickFolder,
                          icon: const Icon(Icons.settings_outlined, size: 18),
                          label: const Text('Ayarlar'),
                        )
                      else
                        IconButton(
                          tooltip: 'Ayarlar',
                          onPressed: pickFolder,
                          icon: const Icon(Icons.settings_outlined, size: 18),
                        ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: compact
                            ? _themeButton(
                                context,
                                appearance.mode == ThemeMode.dark
                                    ? ThemeMode.light
                                    : ThemeMode.dark,
                              )
                            : Row(
                                children: [
                                  for (final mode in ThemeMode.values)
                                    Expanded(
                                      child: _themeButton(context, mode),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeButton(BuildContext context, ThemeMode mode) {
    final scheme = Theme.of(context).colorScheme;
    final selected = appearance.mode == mode;
    return Tooltip(
      message: switch (mode) {
        ThemeMode.system => 'Sistem teması',
        ThemeMode.light => 'Beyaz tema',
        ThemeMode.dark => 'Siyah tema',
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => appearance.setMode(mode),
        child: Container(
          height: 32,
          decoration: BoxDecoration(
            color: selected ? scheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: Icon(
            switch (mode) {
              ThemeMode.system => Icons.brightness_auto_outlined,
              ThemeMode.light => Icons.light_mode_outlined,
              ThemeMode.dark => Icons.dark_mode_outlined,
            },
            size: 17,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(26, 14, 16, 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  /// The pill beside Ajanda and UETS: the accent for today's hearings, red
  /// for unread notifications.
  Widget _badge(BuildContext context, String text, {required bool danger}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: danger
              ? const Color(0xFFD93B3B)
              : Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      );

  Widget _nav(
    BuildContext context,
    IconData icon,
    String title,
    String value,
    int? count, {
    Key? key,
    bool? selected,
    Widget? badge,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = selected ?? (group == value && library.sourceId == null);
    return Padding(
      key: key,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 12, vertical: 3),
      child: Tooltip(
        message: compact ? title : '',
        child: Material(
          color: isSelected
              ? scheme.primary.withValues(alpha: .09)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () => selectGroup(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    size: 19,
                    color: isSelected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                    ),
                    ?badge,
                    if (count != null && badge == null)
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
