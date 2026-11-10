import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/tiff/tiff_preview_session.dart';
import '../theme/app_theme.dart';
import '../../models/evrak_file.dart';
import '../../services/ocr/preview_ocr.dart';
import '../../services/search/library_controller.dart';
import 'ocr_text_panel.dart';
import 'page_jump.dart';
import 'viewer_bar.dart';
import 'viewer_shortcuts.dart';
import '../../services/platform/app_language.dart';

class TiffViewerWidget extends StatefulWidget {
  final String filePath;
  final VoidCallback? onConvertToPdfRequested;

  /// Supplies indexed OCR text when the document is in the archive. Without it
  /// the reader can still ask for the page to be read on demand.
  final LibraryController? library;

  /// The page this document was last left on. Zero based, the way the pages
  /// are held here.
  final int? initialPage;

  /// Reports the page being read, so it can be come back to.
  final void Function(int page)? onPageChanged;

  const TiffViewerWidget({
    super.key,
    required this.filePath,
    this.onConvertToPdfRequested,
    this.library,
    this.initialPage,
    this.onPageChanged,
  });

  @override
  State<TiffViewerWidget> createState() => _TiffViewerWidgetState();
}

class _TiffViewerWidgetState extends State<TiffViewerWidget> {
  late final _ocr = PreviewOcr(library: widget.library);
  bool _showText = false;
  TiffPreviewSession? _session;
  int _pageCount = 0;
  int _currentPage = 0;
  bool _isLoading = true;
  String? _errorMessage;

  final _pageCache = <int, ui.Image>{};
  final _pending = <int, Future<ui.Image?>>{};
  ui.Image? _activePage;
  String? _pageError;
  bool _pageLoading = false;

  final TransformationController _zoomController = TransformationController();
  double _scale = 1.0;
  int _quarterTurns = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadTiff();
    _ocr.attach(widget.filePath, EvrakFormat.tif);
  }

  @override
  void didUpdateWidget(covariant TiffViewerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _showText = false;
      _loadTiff();
      _ocr.attach(widget.filePath, EvrakFormat.tif);
    }
  }

  @override
  void dispose() {
    _ocr.dispose();
    _generation++;
    _session?.close();
    _thumbSession?.close();
    for (final image in _thumbs.values) {
      image.dispose();
    }
    for (final image in _pageCache.values) {
      image.dispose();
    }
    _pageCache.clear();
    _zoomController.dispose();
    super.dispose();
  }

  void _release(ui.Image image) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());

  /// Whether the pages are listed as small pictures beside the one read.
  bool _thumbnails = false;

  /// The small pages, made by a decoder of their own so that the page read
  /// never waits behind them: asked for as each comes into view, one at a
  /// time, and kept small (a scanned page whole is tens of megabytes).
  TiffPreviewSession? _thumbSession;
  Future<TiffPreviewSession>? _thumbOpening;
  final _thumbs = <int, ui.Image>{};
  final _thumbAsked = <int>{};

  void _dropThumbnails() {
    _thumbSession?.close();
    _thumbSession = null;
    _thumbOpening = null;
    for (final image in _thumbs.values) {
      _release(image);
    }
    _thumbs.clear();
    _thumbAsked.clear();
  }

  Future<void> _askThumbnail(int index) async {
    if (!_thumbAsked.add(index)) return;
    final generation = _generation;
    try {
      final session = await (_thumbOpening ??= TiffPreviewSession.open(
        widget.filePath,
      ));
      if (!mounted || generation != _generation) {
        if (!identical(session, _thumbSession)) session.close();
        return;
      }
      _thumbSession = session;
      final raster = await session.page(index, priority: false);
      if (!mounted || generation != _generation) return;
      final ready = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        raster.rgba,
        raster.width,
        raster.height,
        ui.PixelFormat.rgba8888,
        ready.complete,
        // Twice the panel's width: sharp on a dense screen.
        targetWidth: raster.width >= raster.height ? 232 : null,
        targetHeight: raster.width >= raster.height ? null : 328,
      );
      final image = await ready.future;
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      setState(() => _thumbs[index] = image);
    } catch (_) {
      // A page that cannot be drawn small is left blank in the list; the
      // page itself says what is wrong with it when it is opened.
    }
  }

  /// [page] with the list of small pages at its left when it is open.
  Widget _besideThumbnails(Widget page) {
    if (!_thumbnails || _pageCount < 2) return page;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('tiff-thumbnail-panel'),
          width: 148,
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(right: BorderSide(color: scheme.outlineVariant)),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: _pageCount,
            itemBuilder: (context, i) {
              final on = i == _currentPage;
              final image = _thumbs[i];
              if (image == null) unawaited(_askThumbnail(i));
              return InkWell(
                key: ValueKey('tiff-thumbnail-${i + 1}'),
                onTap: () => _loadPage(i),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                  child: Column(
                    children: [
                      AspectRatio(
                        aspectRatio: image == null
                            ? 210 / 297
                            : image.width / image.height,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(
                              color: on
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                              width: on ? 2.5 : 1,
                            ),
                          ),
                          child: image == null
                              ? null
                              : Padding(
                                  padding: const EdgeInsets.all(2.5),
                                  child: RawImage(
                                    image: image,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                          color: on ? scheme.primary : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(child: page),
      ],
    );
  }

  Future<void> _loadTiff() async {
    final generation = ++_generation;
    _session?.close();
    _session = null;
    _dropThumbnails();
    for (final image in _pageCache.values) {
      _release(image);
    }
    _pageCache.clear();
    _pending.clear();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _pageError = null;
      _activePage = null;
      _currentPage = 0;
    });
    try {
      final session = await TiffPreviewSession.open(widget.filePath);
      if (!mounted || generation != _generation) {
        session.close();
        return;
      }
      _session = session;
      setState(() {
        _pageCount = session.pageCount;
        _isLoading = false;
      });
      await _loadPage((widget.initialPage ?? 0).clamp(0, _pageCount - 1));
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _isLoading = false;
          _errorMessage = '$e';
        });
      }
    }
  }

  Future<ui.Image?> _preparePage(int index, {bool priority = false}) {
    final cached = _pageCache[index];
    if (cached != null) return Future.value(cached);
    final existing = _pending[index];
    if (existing != null) {
      // Promote a prefetch already in progress instead of decoding it twice.
      if (priority) _session!.promote(index);
      return existing;
    }
    final generation = _generation;
    final future = () async {
      try {
        final raster = await _session!.page(index, priority: priority);
        if (!mounted || generation != _generation) return null;
        final ready = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          raster.rgba,
          raster.width,
          raster.height,
          ui.PixelFormat.rgba8888,
          ready.complete,
        );
        final image = await ready.future;
        if (!mounted ||
            generation != _generation ||
            (index - _currentPage).abs() > 2) {
          image.dispose();
          return null;
        }
        _pageCache[index] = image;
        _trimCache();
        return image;
      } finally {
        if (generation == _generation) _pending.remove(index);
      }
    }();
    _pending[index] = future;
    return future;
  }

  void _trimCache() {
    var bytes = _pageCache.values.fold<int>(
      0,
      (sum, image) => sum + image.width * image.height * 4,
    );
    final indices = _pageCache.keys.toList()
      ..sort(
        (a, b) => (b - _currentPage).abs().compareTo((a - _currentPage).abs()),
      );
    for (final index in indices) {
      if (index == _currentPage || _pageCache[index] == _activePage) continue;
      if ((index - _currentPage).abs() > 2 ||
          bytes > 48 * 1024 * 1024 ||
          _pageCache.length > 5) {
        final image = _pageCache.remove(index)!;
        bytes -= image.width * image.height * 4;
        _release(image);
      }
    }
  }

  Future<void> _loadPage(int pageIndex) async {
    if (_session == null || pageIndex < 0 || pageIndex >= _pageCount) return;
    final generation = _generation;
    final cached = _pageCache[pageIndex];
    widget.onPageChanged?.call(pageIndex);
    setState(() {
      _currentPage = pageIndex;
      _pageError = null;
      _pageLoading = cached == null;
      if (cached != null) _activePage = cached;
    });
    if (cached != null) {
      _preloadNeighbors(pageIndex);
      return;
    }
    try {
      final image = await _preparePage(pageIndex, priority: true);
      if (!mounted || generation != _generation || _currentPage != pageIndex) {
        return;
      }
      setState(() {
        _activePage = image;
        _pageLoading = false;
        if (image == null) _pageError = context.l.viewPageOpenFailed;
      });
      _preloadNeighbors(pageIndex);
    } catch (e) {
      if (mounted && generation == _generation && _currentPage == pageIndex) {
        setState(() {
          _pageLoading = false;
          _pageError = '$e';
        });
      }
    }
  }

  void _preloadNeighbors(int current) {
    _trimCache();
    for (final index in [current + 1, current - 1]) {
      if (index >= 0 && index < _pageCount) {
        _preparePage(index).then((_) {}, onError: (Object _) {});
      }
    }
  }

  void _setScale(double s) {
    s = s.clamp(0.5, 4.0);
    _zoomController.value = Matrix4.identity()
      ..setEntry(0, 0, s)
      ..setEntry(1, 1, s);
    setState(() => _scale = s);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_rounded,
                size: 48,
                color: AppColors.error,
              ),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return ViewerShortcuts(
      onPrevious: _currentPage > 0 ? () => _loadPage(_currentPage - 1) : null,
      onNext: _currentPage < _pageCount - 1
          ? () => _loadPage(_currentPage + 1)
          : null,
      onFirst: () => _loadPage(0),
      onLast: () => _loadPage(_pageCount - 1),
      onZoomIn: () => _setScale(_scale + 0.25),
      onZoomOut: () => _setScale(_scale - 0.25),
      onFit: () => _setScale(1),
      child: Column(
        children: [
          ViewerToolbar(
            children: [
              ViewerPill(
                children: [
                  ViewerButton(
                    key: const ValueKey('tiff-thumbnails'),
                    icon: Icons.view_sidebar_outlined,
                    tooltip: context.l.viewThumbnails,
                    selected: _thumbnails,
                    onPressed: _pageCount > 1
                        ? () => setState(() => _thumbnails = !_thumbnails)
                        : null,
                  ),
                ],
              ),
              ViewerPill(
                children: [
                  ViewerButton(
                    icon: Icons.first_page_rounded,
                    tooltip: context.l.viewFirstPage,
                    onPressed: _currentPage > 0 ? () => _loadPage(0) : null,
                  ),
                  ViewerButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: context.l.viewPreviousPage,
                    onPressed: _currentPage > 0
                        ? () => _loadPage(_currentPage - 1)
                        : null,
                  ),
                  PageJump(
                    label: '${_currentPage + 1} / $_pageCount',
                    current: _currentPage + 1,
                    count: _pageCount,
                    onGo: (page) => _loadPage(page - 1),
                  ),
                  ViewerButton(
                    icon: Icons.chevron_right_rounded,
                    tooltip: context.l.viewNextPage,
                    onPressed: _currentPage < _pageCount - 1
                        ? () => _loadPage(_currentPage + 1)
                        : null,
                  ),
                  ViewerButton(
                    icon: Icons.last_page_rounded,
                    tooltip: context.l.viewLastPage,
                    onPressed: _currentPage < _pageCount - 1
                        ? () => _loadPage(_pageCount - 1)
                        : null,
                  ),
                ],
              ),
              ViewerPill(
                children: [
                  ViewerButton(
                    icon: Icons.remove_rounded,
                    tooltip: context.l.viewZoomOut,
                    onPressed: () => _setScale(_scale - 0.25),
                  ),
                  ViewerButton(
                    icon: Icons.add_rounded,
                    tooltip: context.l.viewZoomIn,
                    onPressed: () => _setScale(_scale + 0.25),
                  ),
                  ViewerButton(
                    icon: Icons.fit_screen_rounded,
                    tooltip: context.l.viewFit,
                    onPressed: () => _setScale(1.0),
                  ),
                ],
              ),
              ViewerPill(
                children: [
                  ViewerButton(
                    tooltip: context.l.viewRotateLeft,
                    icon: Icons.rotate_left_rounded,
                    onPressed: () =>
                        setState(() => _quarterTurns = (_quarterTurns + 3) % 4),
                  ),
                  ViewerButton(
                    tooltip: context.l.viewRotateRight,
                    icon: Icons.rotate_right_rounded,
                    onPressed: () =>
                        setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
                  ),
                ],
              ),
              if (widget.onConvertToPdfRequested != null)
                FilledButton.tonalIcon(
                  onPressed: widget.onConvertToPdfRequested,
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                  label: Text(context.l.viewTifToPdf),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              OcrTextButton(
                ocr: _ocr,
                format: EvrakFormat.tif,
                showing: _showText,
                onToggle: (v) => setState(() => _showText = v),
              ),
            ],
          ),
          if (_showText && _ocr.text != null)
            Expanded(child: OcrTextPanel(text: _ocr.text!))
          else
            // Görüntüleme Alanı
            Expanded(
              child: _besideThumbnails(
                Container(
                  color: isDark ? AppColors.darkBg : AppColors.lightPanel,
                  child: _pageError != null
                      ? Center(child: Text(_pageError!))
                      : _activePage == null
                      ? const Center(child: CircularProgressIndicator())
                      : Stack(
                          children: [
                            InteractiveViewer(
                              transformationController: _zoomController,
                              minScale: 0.5,
                              maxScale: 4.0,
                              onInteractionEnd: (_) {
                                final s = _zoomController.value
                                    .getMaxScaleOnAxis();
                                if ((s - _scale).abs() > 0.01) {
                                  setState(() => _scale = s);
                                }
                              },
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Material(
                                    elevation: 4,
                                    borderRadius: BorderRadius.circular(4),
                                    child: RotatedBox(
                                      quarterTurns: _quarterTurns,
                                      child: RawImage(
                                        image: _activePage,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (_pageLoading)
                              const Positioned(
                                top: 16,
                                right: 16,
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ViewerStatusBar(
            items: [
              context.l.viewPageOf(_currentPage + 1, _pageCount),
              if (_activePage case final page?)
                context.l.viewPixels(page.width, page.height),
              'TIFF',
              _weight,
            ],
            trailing: '%${(_scale * 100).round()}',
          ),
        ],
      ),
    );
  }

  String? get _weight {
    try {
      return viewerFileSize(File(widget.filePath).lengthSync());
    } catch (_) {
      return null;
    }
  }
}
