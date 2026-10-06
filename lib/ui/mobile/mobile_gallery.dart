import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../models/evrak_file.dart';
import '../../services/platform/heif_images.dart';
import '../../services/search/library_controller.dart';
import '../../services/search/search_models.dart';
import 'scroll_chrome.dart';

/// The phone's gallery (docs/design/mobil-galeri-taslak.png): the
/// photographs edge to edge, three a row, under the days they were taken;
/// the folders as chips; a long press chooses, the order chosen being the
/// order of the pages a PDF is made of.
class MobileGallery extends StatefulWidget {
  const MobileGallery({
    super.key,
    required this.hits,
    required this.library,
    required this.hasMore,
    required this.loadMore,
    required this.pickFolder,
    required this.onOpen,
    required this.onMakePdf,
    required this.onShare,
    required this.onToCase,
    this.onScan,
    this.onMenu,
    this.now,
  });

  final List<SearchHit> hits;
  final LibraryController library;
  final bool hasMore;
  final VoidCallback loadMore;
  final Future<String?> Function() pickFolder;

  /// Opens the [index]th photograph full screen.
  final ValueChanged<int> onOpen;
  final ValueChanged<List<EvrakFile>> onMakePdf, onShare, onToCase;
  final VoidCallback? onScan, onMenu;
  final DateTime Function()? now;

  @override
  State<MobileGallery> createState() => _MobileGalleryState();
}

class _MobileGalleryState extends State<MobileGallery> {
  /// The paths chosen, in the order they were.
  final _chosen = <String>[];
  bool _choosing = false;
  bool _searching = false;
  final _query = TextEditingController();
  int _askedAt = -1;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  static const _months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', //
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];
  static const _days = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  static DateTime _when(SearchHit hit) {
    final m = hit.modified;
    if (m <= 0) {
      try {
        return File(hit.file.path).lastModifiedSync();
      } catch (_) {
        return DateTime(1970);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(m > 100000000000 ? m : m * 1000);
  }

  /// "Bugün", "Dün", "5 Ekim Pazartesi" this month, "Eylül 2026" before.
  String _day(DateTime t) {
    final now = (widget.now ?? DateTime.now)();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    if (day == today) return 'Bugün';
    if (day == today.subtract(const Duration(days: 1))) return 'Dün';
    if (t.year == now.year && t.month == now.month) {
      return '${t.day} ${_months[t.month - 1]} ${_days[t.weekday - 1]}';
    }
    return '${_months[t.month - 1]} ${t.year}';
  }

  void _toggle(String path) => setState(() {
    if (!_chosen.remove(path)) _chosen.add(path);
    _choosing = _chosen.isNotEmpty;
  });

  void _clear() => setState(() {
    _chosen.clear();
    _choosing = false;
  });

  List<EvrakFile> get _files => [
    for (final path in _chosen)
      for (final h in widget.hits)
        if (h.file.path == path) h.file,
  ];

  List<LibrarySource> get _folders => [
    for (final s in widget.library.sources)
      if (s.folder) s,
  ];

  void _only(LibrarySource? source) {
    final chosen = source?.id;
    widget.library.filter(
      folder: chosen,
      clearFolder: chosen == null || chosen == widget.library.sourceId,
    );
  }

  Future<void> _addFolder() async {
    final path = await widget.pickFolder();
    if (path != null) await widget.library.addPaths([path], recursive: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The days, each with its photographs, in the order the archive gives.
    final groups = <(String, List<int>)>[];
    for (var i = 0; i < widget.hits.length; i++) {
      final day = _day(_when(widget.hits[i]));
      if (groups.isEmpty || groups.last.$1 != day) groups.add((day, []));
      groups.last.$2.add(i);
    }
    return ColoredBox(
      color: scheme.surface,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _choosing
                  ? _choiceBar(scheme)
                  : FoldingChrome(child: _bar(scheme)),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (widget.hasMore &&
                        n.metrics.axis == Axis.vertical &&
                        n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
                      // Once per page: a scroll sends this on every frame.
                      if (_askedAt != widget.hits.length) {
                        _askedAt = widget.hits.length;
                        widget.loadMore();
                      }
                    }
                    return false;
                  },
                  child: widget.hits.isEmpty
                      ? _empty(scheme)
                      : CustomScrollView(
                          key: const PageStorageKey('mobile-gallery'),
                          slivers: [
                            for (final (day, indexes) in groups) ...[
                              SliverToBoxAdapter(
                                child: _dayHeading(scheme, day, indexes),
                              ),
                              SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      mainAxisSpacing: 2,
                                      crossAxisSpacing: 2,
                                    ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, i) => _tile(indexes[i]),
                                  childCount: indexes.length,
                                ),
                              ),
                            ],
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 96),
                            ),
                          ],
                        ),
                ),
              ),
              if (_choosing) _actions(scheme),
            ],
          ),
          if (!_choosing && widget.onScan != null)
            Positioned(
              right: 16,
              bottom: 22,
              child: FloatingActionButton.extended(
                key: const ValueKey('gallery-scan'),
                heroTag: 'gallery-scan',
                onPressed: widget.onScan,
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Tara'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bar(ColorScheme scheme) {
    final showing = widget.library.sourceId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('gallery-menu'),
                tooltip: 'Menü',
                onPressed:
                    widget.onMenu ??
                    () => Scaffold.maybeOf(context)?.openDrawer(),
                icon: const Icon(Icons.menu_rounded),
              ),
              const Expanded(
                child: Text(
                  'Galeri',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.3,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('gallery-search'),
                tooltip: 'Ara',
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching && _query.text.isNotEmpty) {
                    _query.clear();
                    widget.library.setQuery('');
                  }
                }),
                icon: Icon(_searching ? Icons.close : Icons.search_rounded),
              ),
              IconButton(
                key: const ValueKey('gallery-choose'),
                tooltip: 'Seç',
                onPressed: widget.hits.isEmpty
                    ? null
                    : () => setState(() => _choosing = true),
                icon: const Icon(Icons.check_box_outlined),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        if (_searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: TextField(
              controller: _query,
              autofocus: true,
              onChanged: widget.library.setQuery,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Ad ya da içindeki yazı',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            children: [
              _chip(
                scheme,
                key: const ValueKey('gallery-folder-all'),
                label: 'Tümü · ${widget.library.matches}',
                on: showing == null,
                onTap: () => _only(null),
              ),
              for (final s in _folders)
                _chip(
                  scheme,
                  key: ValueKey('gallery-folder-${s.id}'),
                  label: p.basename(s.path),
                  on: showing == s.id,
                  onTap: () => _only(s),
                ),
              _chip(
                scheme,
                key: const ValueKey('gallery-folder-add'),
                label: '+ Klasör',
                on: false,
                onTap: _addFolder,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(
    ColorScheme scheme, {
    required Key key,
    required String label,
    required bool on,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Material(
      color: on ? const Color(0xFFEAF0F9) : scheme.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: on ? const Color(0xFFCFDDF1) : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        key: key,
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: on ? FontWeight.w700 : FontWeight.w400,
              color: on ? scheme.primary : null,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _choiceBar(ColorScheme scheme) => Container(
    height: 56,
    color: const Color(0xFFEAF0F9),
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      children: [
        IconButton(
          key: const ValueKey('gallery-choose-close'),
          tooltip: 'Seçimi bırak',
          onPressed: _clear,
          icon: const Icon(Icons.close_rounded),
        ),
        Expanded(
          child: Text(
            _chosen.isEmpty ? 'Seçin' : '${_chosen.length} seçili',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Tümünü seç',
          onPressed: () => setState(() {
            for (final h in widget.hits) {
              if (!_chosen.contains(h.file.path)) _chosen.add(h.file.path);
            }
          }),
          icon: Icon(Icons.check_box_outlined, color: scheme.primary),
        ),
      ],
    ),
  );

  Widget _dayHeading(
    ColorScheme scheme,
    String day,
    List<int> indexes,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            day,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        if (_choosing)
          InkWell(
            onTap: () => setState(() {
              for (final i in indexes) {
                final path = widget.hits[i].file.path;
                if (!_chosen.contains(path)) _chosen.add(path);
              }
            }),
            child: Text(
              'Tümünü seç',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          )
        else
          Text(
            '${indexes.length} öğe',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
      ],
    ),
  );

  /// "TARAMA" on a scan; "PDF'e çevrildi" when a PDF of it sits beside it.
  final _converted = <String, bool>{};

  String? _badge(EvrakFile file) {
    final stem = p.basenameWithoutExtension(file.path);
    if (stem.toLowerCase().startsWith('tarama')) return 'TARAMA';
    final converted = _converted.putIfAbsent(
      file.path,
      () => File(p.join(p.dirname(file.path), '$stem.pdf')).existsSync(),
    );
    return converted ? 'PDF’e çevrildi' : null;
  }

  Widget _tile(int index) {
    final scheme = Theme.of(context).colorScheme;
    final file = widget.hits[index].file;
    final order = _chosen.indexOf(file.path);
    final chosen = order >= 0;
    final badge = _badge(file);
    return GestureDetector(
      key: ValueKey('gallery-tile-$index'),
      onTap: () => _choosing ? _toggle(file.path) : widget.onOpen(index),
      onLongPress: () => _toggle(file.path),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: _Picture(file: file),
          ),
          if (chosen)
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .16),
                border: Border.all(color: scheme.primary, width: 3),
              ),
            ),
          if (badge != null)
            Positioned(
              left: 5,
              bottom: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (_choosing)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: chosen
                      ? scheme.primary
                      : Colors.black.withValues(alpha: .15),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: chosen
                    ? Text(
                        '${order + 1}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _actions(ColorScheme scheme) {
    Widget action(
      Key key,
      IconData icon,
      String label,
      VoidCallback? onTap, {
      bool primary = false,
    }) => Expanded(
      child: InkWell(
        key: key,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 21,
                color: primary ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: primary ? FontWeight.w700 : FontWeight.w400,
                  color: primary ? scheme.primary : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final some = _chosen.isNotEmpty;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: Row(
          children: [
            action(
              const ValueKey('gallery-make-pdf'),
              Icons.picture_as_pdf_outlined,
              'Tek PDF yap',
              some ? () => widget.onMakePdf(_files) : null,
              primary: true,
            ),
            action(
              const ValueKey('gallery-share'),
              Icons.ios_share_rounded,
              'Paylaş',
              some ? () => widget.onShare(_files) : null,
            ),
            action(
              const ValueKey('gallery-to-case'),
              Icons.drive_file_move_outline,
              'UYAP dosyasına',
              some ? () => widget.onToCase(_files) : null,
            ),
            action(
              const ValueKey('gallery-more'),
              Icons.more_horiz_rounded,
              'Diğer',
              () => _more(scheme),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _more(ColorScheme scheme) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.select_all_rounded),
            title: const Text('Tümünü seç'),
            onTap: () {
              Navigator.pop(sheet);
              setState(() {
                for (final h in widget.hits) {
                  if (!_chosen.contains(h.file.path)) _chosen.add(h.file.path);
                }
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.deselect_rounded),
            title: const Text('Seçimi temizle'),
            onTap: () {
              Navigator.pop(sheet);
              setState(_chosen.clear);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  Widget _empty(ColorScheme scheme) => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      Icon(
        Icons.photo_library_outlined,
        size: 44,
        color: scheme.onSurfaceVariant,
      ),
      const SizedBox(height: 14),
      const Text(
        'Galeri boş',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Text(
        'Telefonunuzdaki fotoğraf klasörlerini ekleyin; dosyalar yerinde '
        'kalır, kopyalanmaz.',
        textAlign: TextAlign.center,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      ),
      const SizedBox(height: 18),
      Center(
        child: FilledButton.icon(
          onPressed: _addFolder,
          icon: const Icon(Icons.create_new_folder_outlined, size: 18),
          label: const Text('Klasör ekle'),
        ),
      ),
    ],
  );
}

/// A photograph as a tile: decoded small, a phone's camera roll at full
/// size would exhaust it; an iPhone photograph through the system.
class _Picture extends StatelessWidget {
  const _Picture({required this.file});
  final EvrakFile file;

  static const _drawable = {'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'};

  @override
  Widget build(BuildContext context) {
    final ext = p.extension(file.path).toLowerCase().replaceFirst('.', '');
    final width = (180 * MediaQuery.devicePixelRatioOf(context)).round();
    final scheme = Theme.of(context).colorScheme;
    Widget fallback() => Center(
      child: Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
    );
    if (HeifImages.isHeif(file.path)) {
      return FutureBuilder<String?>(
        future: HeifImages.decoded(file.path),
        builder: (context, s) => s.data == null
            ? fallback()
            : Image.file(
                File(s.data!),
                fit: BoxFit.cover,
                cacheWidth: width,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, _, _) => fallback(),
              ),
      );
    }
    if (!_drawable.contains(ext)) return fallback();
    return Image.file(
      File(file.path),
      fit: BoxFit.cover,
      cacheWidth: width,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, _, _) => fallback(),
    );
  }
}
