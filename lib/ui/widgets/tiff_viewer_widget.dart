import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/tiff/tiff_preview_session.dart';
import '../theme/app_theme.dart';
import '../../models/evrak_file.dart';
import '../../services/ocr/preview_ocr.dart';
import '../../services/search/library_controller.dart';
import 'ocr_text_panel.dart';
import 'page_jump.dart';
import 'viewer_shortcuts.dart';

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
    for (final image in _pageCache.values) {
      image.dispose();
    }
    _pageCache.clear();
    _zoomController.dispose();
    super.dispose();
  }

  void _release(ui.Image image) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  Future<void> _loadTiff() async {
    final generation = ++_generation;
    _session?.close();
    _session = null;
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
        if (image == null) _pageError = 'Bu sayfa açılamadı.';
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
          // Kontrol Çubuğu
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.first_page_rounded, size: 20),
                    tooltip: 'İlk Sayfa',
                    onPressed: _currentPage > 0 ? () => _loadPage(0) : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                    tooltip: 'Önceki Sayfa',
                    onPressed: _currentPage > 0
                        ? () => _loadPage(_currentPage - 1)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  PageJump(
                    label: 'Sayfa ${_currentPage + 1} / $_pageCount',
                    current: _currentPage + 1,
                    count: _pageCount,
                    width: 108,
                    fontSize: 13,
                    onGo: (page) => _loadPage(page - 1),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                    tooltip: 'Sonraki Sayfa',
                    onPressed: _currentPage < _pageCount - 1
                        ? () => _loadPage(_currentPage + 1)
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.last_page_rounded, size: 20),
                    tooltip: 'Son Sayfa',
                    onPressed: _currentPage < _pageCount - 1
                        ? () => _loadPage(_pageCount - 1)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  if (widget.onConvertToPdfRequested != null) ...[
                    FilledButton.tonalIcon(
                      onPressed: widget.onConvertToPdfRequested,
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                      label: const Text('TIF → PDF Dönüştür'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  IconButton(
                    tooltip: 'Sola 90° döndür',
                    icon: const Icon(Icons.rotate_left_rounded),
                    onPressed: () =>
                        setState(() => _quarterTurns = (_quarterTurns + 3) % 4),
                  ),
                  IconButton(
                    tooltip: 'Sağa 90° döndür',
                    icon: const Icon(Icons.rotate_right_rounded),
                    onPressed: () =>
                        setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
                  ),
                  IconButton(
                    icon: const Icon(Icons.zoom_out_rounded, size: 20),
                    tooltip: 'Uzaklaştır',
                    onPressed: () => _setScale(_scale - 0.25),
                  ),
                  IconButton(
                    icon: const Icon(Icons.zoom_in_rounded, size: 20),
                    tooltip: 'Yakınlaştır',
                    onPressed: () => _setScale(_scale + 0.25),
                  ),
                  IconButton(
                    icon: const Icon(Icons.fit_screen_rounded, size: 20),
                    tooltip: 'Sığdır',
                    onPressed: () => _setScale(1.0),
                  ),
                  const VerticalDivider(width: 16, indent: 10, endIndent: 10),
                  OcrTextButton(
                    ocr: _ocr,
                    format: EvrakFormat.tif,
                    showing: _showText,
                    onToggle: (v) => setState(() => _showText = v),
                  ),
                ],
              ),
            ),
          ),
          if (_showText && _ocr.text != null)
            Expanded(child: OcrTextPanel(text: _ocr.text!))
          else
            // Görüntüleme Alanı
            Expanded(
              child: Container(
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
        ],
      ),
    );
  }
}
