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

  /// Where UYAP's documents are saved: the archive folder that stands as
  /// UYAP in the list of folders, not as one more folder.
  final String? uyapFolder;

  /// Whether UYAP can be reached from this Folio at all: on a phone only
  /// the cases already kept are shown.
  final bool uyapAvailable;
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
    this.uyapFolder,
    this.uyapAvailable = false,
  });

  bool get _showUyap => uyapAvailable || uyapCases.isNotEmpty;

  bool _isUyapFolder(String path) =>
      uyapFolder != null && p.equals(path, uyapFolder!);
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final content = _content(context);
      return constraints.maxHeight < 650
          ? SingleChildScrollView(child: SizedBox(height: 650, child: content))
          : content;
    },
  );

  Widget _content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Container(
        width: compact ? 76 : 224,
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Column(
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
            if (compact && _showUyap)
              _nav(
                context,
                Icons.gavel_rounded,
                'UYAP Dosyalarım',
                'uyap',
                uyapCases.length,
              ),
            const SizedBox(height: 20),
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
            Expanded(
              child: compact
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      children: [
                        if (_showUyap) ..._uyap(context),
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
            ),
            Padding(
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                Expanded(child: _themeButton(context, mode)),
                            ],
                          ),
                  ),
                ],
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

  /// UYAP among the folders: its cases open beneath it once it is chosen.
  List<Widget> _uyap(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final open = group == 'uyap' || group.startsWith('uyap:');
    final folder = library.sources
        .where((s) => s.folder && _isUyapFolder(s.path))
        .firstOrNull;
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Tooltip(
          message: folder?.path ?? 'UYAP dosyaları',
          child: ListTile(
            key: const ValueKey('uyap-folder'),
            dense: true,
            minTileHeight: 42,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            selected: group == 'uyap',
            selectedTileColor: scheme.primary.withValues(alpha: .08),
            leading: Icon(
              open ? Icons.folder_open_rounded : Icons.folder_special_outlined,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            minLeadingWidth: 18,
            title: const Text(
              'UYAP Dosyalarım',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12),
            ),
            trailing: Text(
              '${uyapCases.length}',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
            onTap: () => selectGroup('uyap'),
          ),
        ),
      ),
      if (open)
        for (final (key, number, court, fresh) in uyapCases)
          Padding(
            padding: const EdgeInsets.only(left: 14, bottom: 3),
            child: Tooltip(
              message: '$court $number',
              child: ListTile(
                key: ValueKey('uyap-case-$key'),
                dense: true,
                minTileHeight: 44,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                selected: group == 'uyap:$key',
                selectedTileColor: scheme.primary.withValues(alpha: .08),
                leading: Icon(
                  Icons.gavel_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                minLeadingWidth: 16,
                title: Text(
                  number,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  court,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: fresh == 0
                    ? null
                    : Text(
                        '$fresh yeni',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                onTap: () => selectGroup('uyap:$key'),
              ),
            ),
          ),
    ];
  }

  Widget _nav(
    BuildContext context,
    IconData icon,
    String title,
    String value,
    int? count,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final selected = group == value && library.sourceId == null;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 12, vertical: 3),
      child: Tooltip(
        message: compact ? title : '',
        child: Material(
          color: selected
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
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                    ),
                    if (count != null)
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
