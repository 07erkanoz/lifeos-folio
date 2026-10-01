import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../models/evrak_file.dart';
import '../../services/platform/heif_images.dart';
import '../../services/platform/picture_folders.dart';
import '../../services/search/library_controller.dart';
import '../../services/search/search_models.dart';

/// Photographs, shown the way a gallery shows them.
///
/// The same archive underneath: a picture folder is an indexed folder like any
/// other, and anything found in one is searchable with everything else. What
/// changes is the looking — a wall of thumbnails rather than a list of file
/// names, because a name tells you nothing about a photograph.
class GalleryView extends StatefulWidget {
  final List<SearchHit> hits;
  final LibraryController library;
  final String? selectedPath;
  final bool compact;
  final bool hasMore;
  final VoidCallback loadMore;
  final ValueChanged<EvrakFile> onOpen;

  /// Asks for a folder, the same picker the archive uses.
  final Future<String?> Function() pickFolder;

  const GalleryView({
    super.key,
    required this.hits,
    required this.library,
    required this.onOpen,
    required this.loadMore,
    required this.pickFolder,
    this.selectedPath,
    this.compact = false,
    this.hasMore = false,
  });

  @override
  State<GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends State<GalleryView> {
  bool _busy = false;
  String? _error;

  /// The folders in the archive that look like picture folders: the ones the
  /// gallery offered, and anything the reader added while here.
  List<LibrarySource> get _folders => [
    for (final source in widget.library.sources)
      if (source.folder) source,
  ];

  Future<void> _addKnown() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final folders = await PictureFolders.find();
      if (folders.isEmpty) {
        setState(
          () => _error = Platform.isAndroid
              ? 'Resimlere erişim izni verilmedi. Telefon ayarlarından '
                    'izin verip yeniden deneyin.'
              : 'Resim klasörü bulunamadı. Kendiniz ekleyebilirsiniz.',
        );
        return;
      }
      final known = {for (final source in _folders) p.normalize(source.path)};
      final fresh = [
        for (final folder in folders)
          if (!known.contains(p.normalize(folder))) folder,
      ];
      if (fresh.isEmpty) {
        setState(() => _error = 'Resim klasörleriniz zaten ekli.');
        return;
      }
      await widget.library.addPaths(fresh, recursive: true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Klasör eklenemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addOne() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = await widget.pickFolder();
      if (path != null) await widget.library.addPaths([path], recursive: true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Klasör eklenemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(LibrarySource source) async {
    final name = p.basename(source.path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$name galeriden çıkarılsın mı?'),
        content: const Text(
          'Yalnızca bu uygulamanın listesinden çıkar. Klasördeki hiçbir '
          'dosyaya dokunulmaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Çıkar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.library.removeSource(source.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bar(scheme),
        if (_error case final message?)
          Padding(
            padding: EdgeInsets.fromLTRB(widget.compact ? 12 : 24, 0, 12, 8),
            child: Text(
              message,
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ),
        Expanded(child: widget.hits.isEmpty ? _empty(scheme) : _grid(scheme)),
      ],
    );
  }

  /// Shows one folder alone, or all of them again.
  ///
  /// A gallery of several folders run together is a gallery of nobody's
  /// holiday: the pictures were kept apart for a reason. Pressing a folder
  /// shows that one; pressing it again lets the others back in.
  void _only(LibrarySource? source) {
    final chosen = source?.id;
    widget.library.filter(
      folder: chosen,
      clearFolder: chosen == null || chosen == widget.library.sourceId,
    );
  }

  /// The folders on show, each one a way of looking at the gallery and each
  /// removable, and the ways to add another.
  Widget _bar(ColorScheme scheme) {
    final showing = widget.library.sourceId;
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: widget.compact ? 12 : 24),
        children: [
          if (_folders.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
              child: FilterChip(
                key: const ValueKey('gallery-folder-all'),
                label: const Text('Tümü'),
                selected: showing == null,
                onSelected: _busy ? null : (_) => _only(null),
              ),
            ),
          for (final source in _folders)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
              child: InputChip(
                key: ValueKey('gallery-folder-${source.id}'),
                avatar: Icon(
                  showing == source.id
                      ? Icons.folder_rounded
                      : Icons.folder_outlined,
                  size: 17,
                ),
                label: Text(p.basename(source.path)),
                selected: showing == source.id,
                showCheckmark: false,
                onSelected: _busy ? null : (_) => _only(source),
                onDeleted: _busy ? null : () => _remove(source),
                deleteIcon: Icon(
                  Icons.close_rounded,
                  size: 16,
                  key: ValueKey('gallery-remove-${source.id}'),
                ),
                tooltip: source.path,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 17),
              label: const Text('Klasör ekle'),
              onPressed: _busy ? null : _addOne,
            ),
          ),
        ],
      ),
    );
  }

  /// Scrollable: on a phone, once the search bar and the filters have taken
  /// their share, what is left is shorter than this.
  Widget _empty(ColorScheme scheme) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 44,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          Text(
            'Galeri boş',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            Platform.isAndroid
                ? 'Telefonunuzdaki fotoğraf klasörlerini ekleyin; '
                      'dosyalar yerinde kalır, kopyalanmaz.'
                : 'Resim klasörünüzü ekleyin; dosyalar yerinde kalır.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _addKnown,
            icon: _busy
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text('Resim klasörlerimi ekle'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ? null : _addOne,
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: const Text('Başka bir klasör seç'),
          ),
        ],
      ),
    ),
  );

  Widget _grid(ColorScheme scheme) => GridView.builder(
    key: const PageStorageKey('gallery-grid'),
    padding: EdgeInsets.fromLTRB(
      widget.compact ? 8 : 20,
      4,
      widget.compact ? 8 : 20,
      24,
    ),
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: widget.compact ? 120 : 164,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
    ),
    itemCount: widget.hits.length + (widget.hasMore ? 1 : 0),
    itemBuilder: (context, index) {
      if (index == widget.hits.length) {
        return Center(
          child: TextButton(
            onPressed: widget.loadMore,
            child: const Text('Daha fazla'),
          ),
        );
      }
      final file = widget.hits[index].file;
      return _Thumbnail(
        file: file,
        selected: file.path == widget.selectedPath,
        onOpen: () => widget.onOpen(file),
      );
    },
  );
}

class _Thumbnail extends StatelessWidget {
  final EvrakFile file;
  final bool selected;
  final VoidCallback onOpen;
  const _Thumbnail({
    required this.file,
    required this.selected,
    required this.onOpen,
  });

  /// Formats a thumbnail can be drawn from directly. The rest — a TIFF, an
  /// SVG, a document — show what they are instead of a picture of nothing.
  static const _drawable = {'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extension = p
        .extension(file.path)
        .toLowerCase()
        .replaceFirst('.', '');
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (HeifImages.isHeif(file.path))
              _HeifThumbnail(path: file.path, ratio: ratio)
            else if (_drawable.contains(extension))
              Image.file(
                File(file.path),
                fit: BoxFit.cover,
                // A thumbnail needs a thumbnail's worth of pixels; decoding a
                // whole camera roll at full size would exhaust a phone.
                cacheWidth: (180 * ratio).round(),
                filterQuality: FilterQuality.low,
                errorBuilder: (_, _, _) => _fallback(scheme, extension),
              )
            else
              _fallback(scheme, extension),
            if (selected)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.primary, width: 3),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(ColorScheme scheme, String extension) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          file.format.isVisual
              ? Icons.image_outlined
              : Icons.description_outlined,
          color: scheme.onSurfaceVariant,
          size: 26,
        ),
        const SizedBox(height: 6),
        Text(
          extension.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

/// An iPhone photograph in a gallery tile, decoded by the system the first
/// time it is looked at and kept afterwards.
class _HeifThumbnail extends StatefulWidget {
  final String path;
  final double ratio;
  const _HeifThumbnail({required this.path, required this.ratio});

  @override
  State<_HeifThumbnail> createState() => _HeifThumbnailState();
}

class _HeifThumbnailState extends State<_HeifThumbnail> {
  late Future<String?> _decoded = HeifImages.decoded(widget.path);

  @override
  void didUpdateWidget(covariant _HeifThumbnail old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _decoded = HeifImages.decoded(widget.path);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _decoded,
    builder: (context, snapshot) {
      final path = snapshot.data;
      if (path == null) {
        return Center(
          child: Icon(
            snapshot.connectionState == ConnectionState.done
                ? Icons.image_not_supported_outlined
                : Icons.image_outlined,
            size: 24,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      }
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: (180 * widget.ratio).round(),
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    },
  );
}
