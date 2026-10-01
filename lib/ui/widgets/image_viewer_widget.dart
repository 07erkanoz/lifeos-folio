import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';

import '../../services/preview/svg_source.dart';

import 'package:flutter/material.dart';

import '../../services/search/library_controller.dart';
import '../../models/evrak_file.dart';
import '../../services/ocr/preview_ocr.dart';
import '../../services/platform/heif_images.dart';
import '../../services/preview/image_crop.dart';
import 'image_crop_overlay.dart';
import 'notice.dart';
import 'ocr_text_panel.dart';
import 'swipe_pages.dart';
import 'viewer_shortcuts.dart';

class ImageViewerWidget extends StatefulWidget {
  final String filePath;

  /// Supplies the text OCR read from this file, when it was read that way.
  /// Null in previews that have no archive behind them.
  final LibraryController? library;

  /// A sideways swipe on a picture has nowhere to go inside the picture, so
  /// it carries the reader to the one beside it.
  final void Function(bool forward)? onPastEnd;

  /// Whether to show the viewer's own row of buttons. In full screen the
  /// photograph is the point, and every strip of chrome is screen it does not
  /// get.
  final bool chrome;

  /// Where this picture sits in the folder, counting from one, and how many
  /// there are. Shown so a reader knows whether there is more to come, and
  /// left out where there is no folder behind the picture.
  final int? position, total;

  /// Full screen and back, when the place showing this can give it.
  final VoidCallback? onFullScreen;

  /// Told where a crop was written, so the archive can be shown it.
  final void Function(String path)? onCropped;

  /// Whether the picture should take the keyboard the moment it opens.
  /// True from the gallery, where the next arrow key can only mean the next
  /// photograph.
  final bool grabFocus;

  const ImageViewerWidget({
    super.key,
    required this.filePath,
    this.library,
    this.onPastEnd,
    this.chrome = true,
    this.position,
    this.total,
    this.onFullScreen,
    this.onCropped,
    this.grabFocus = false,
  });
  @override
  State<ImageViewerWidget> createState() => _ImageViewerWidgetState();
}

class _ImageViewerWidgetState extends State<ImageViewerWidget> {
  int _turns = 0;
  late final Future<String>? _svg =
      widget.filePath.toLowerCase().endsWith('.svg')
      ? SvgSource.load(widget.filePath)
      : null;

  /// What to draw from. An iPhone photograph has to go through the system
  /// decoder first; everything else is the file itself.
  String? _source;
  String? _sourceError;

  /// The picture's own size in pixels, read from the file's header rather
  /// than by decoding it. Cropping needs it to turn a frame dragged on the
  /// screen into a rectangle of the photograph; nothing else does, so a
  /// picture that cannot be measured is still shown, just not cropped.
  Size? _intrinsic;

  /// Whether the frame is being drawn, and what has been framed so far as
  /// a share of the picture — a share, not pixels, so that turning the
  /// window does not throw it away.
  bool _cropping = false;
  Rect? _crop;
  bool _saving = false;
  final _transform = TransformationController();

  /// Whether the picture is being shown at full resolution.
  ///
  /// Fitted to the screen, a photograph needs no more pixels than the screen
  /// has: decoding all twelve million of a phone photograph costs some 48 MB
  /// of memory to draw four hundred pixels across. Zoomed in, every one of
  /// them matters, so the full picture is decoded then and only then.
  bool _detailed = false;

  @override
  void initState() {
    super.initState();
    _ocr.attach(widget.filePath, _format);
    _transform.addListener(_zoomed);
    _prepare();
  }

  /// Prepares the file the picture is drawn from, decoding a HEIF photograph
  /// if that is what this is.
  Future<void> _prepare() async {
    final path = widget.filePath;
    if (!HeifImages.isHeif(path)) {
      if (mounted) setState(() => _source = path);
      if (_svg == null) await _measure(path, path);
      return;
    }
    if (!HeifImages.supported) {
      if (mounted) {
        setState(
          () => _sourceError =
              'iPhone fotoğrafları (HEIC) şimdilik yalnız Android’de açılıyor.',
        );
      }
      return;
    }
    final decoded = await HeifImages.decoded(path);
    if (!mounted || widget.filePath != path) return;
    setState(() {
      _source = decoded;
      _sourceError = decoded == null ? 'Fotoğraf çözülemedi.' : null;
    });
    if (decoded != null) await _measure(decoded, path);
  }

  /// Reads how big the picture is without decoding it. A twelve megapixel
  /// photograph costs nothing to measure this way and some 48 MB to decode.
  Future<void> _measure(String from, String of) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromFilePath(from);
      final described = await ui.ImageDescriptor.encoded(buffer);
      final size = Size(
        described.width.toDouble(),
        described.height.toDouble(),
      );
      described.dispose();
      buffer.dispose();
      if (mounted && widget.filePath == of) {
        setState(() => _intrinsic = size);
      }
    } on Object {
      // Unmeasurable is not unshowable. Only the crop button waits on this.
    }
  }

  void _zoomed() {
    final detailed = _transform.value.getMaxScaleOnAxis() > 1.2;
    if (detailed != _detailed && mounted) setState(() => _detailed = detailed);
  }

  @override
  void dispose() {
    _ocr.dispose();
    _transform.removeListener(_zoomed);
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double scale) {
    final value = (_transform.value.getMaxScaleOnAxis() * scale).clamp(
      .25,
      8.0,
    );
    _transform.value = Matrix4.diagonal3Values(value, value, 1);
  }

  late final _ocr = PreviewOcr(library: widget.library);
  bool _showText = false;
  EvrakFormat get _format =>
      EvrakFormat.fromExtension(widget.filePath.split('.').last);

  @override
  void didUpdateWidget(covariant ImageViewerWidget old) {
    super.didUpdateWidget(old);
    if (old.filePath != widget.filePath) {
      _showText = false;
      _turns = 0;
      _detailed = false;
      _source = null;
      _sourceError = null;
      _intrinsic = null;
      _cropping = false;
      _crop = null;
      _transform.value = Matrix4.identity();
      _ocr.attach(widget.filePath, _format);
      _prepare();
    }
  }

  /// Half again what the screen can show, so a small zoom stays sharp before
  /// the full picture is decoded.
  static int _decodeWidth(BuildContext context, BoxConstraints constraints) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
        ? constraints.maxWidth
        : MediaQuery.sizeOf(context).width;
    return (width * ratio * 1.5).round().clamp(320, 4096);
  }

  void _fit() {
    _transform.value = Matrix4.identity();
    setState(() => _turns = 0);
  }

  /// Whether there is anywhere to step to. A lone preview has no
  /// neighbours, and arrows pointing at nothing are worse than none.
  bool get _canStep =>
      widget.onPastEnd != null && (widget.total ?? 2) > 1 && !_cropping;

  /// The picture's size as it is being looked at: a quarter turn swaps it.
  Size get _shown {
    final size = _intrinsic!;
    return _turns.isOdd ? Size(size.height, size.width) : size;
  }

  /// Where the photograph actually lies inside [box]. It is fitted, so
  /// there is a letterbox either side of it, and a frame dragged over the
  /// letterbox would cut out nothing.
  Rect _frameIn(Size box) {
    final shown = _shown;
    final scale = math.min(box.width / shown.width, box.height / shown.height);
    final width = shown.width * scale, height = shown.height * scale;
    return Rect.fromLTWH(
      (box.width - width) / 2,
      (box.height - height) / 2,
      width,
      height,
    );
  }

  void _toggleCrop() => setState(() {
    _cropping = !_cropping;
    _crop = null;
    // The frame is mapped against a fitted picture, so the zoom goes back
    // to where the mapping holds.
    if (_cropping) _transform.value = Matrix4.identity();
  });

  Future<void> _saveCrop() async {
    final share = _crop;
    final source = _source;
    if (share == null || source == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving = true);
    try {
      final saved = await ImageCrop.save(
        source: source,
        original: widget.filePath,
        quarterTurns: _turns,
        fraction: share,
      );
      if (!mounted) return;
      setState(() {
        _cropping = false;
        _crop = null;
        _saving = false;
      });
      widget.onCropped?.call(saved.path);
    } on Object catch (trouble) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger
        ?..clearSnackBars()
        ..showSnackBar(
          noticeBar(
            'Kırpılamadı',
            detail: '$trouble',
            kind: NoticeKind.error,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (widget.chrome) _tools(),
      if (_showText && _ocr.text != null)
        Expanded(child: OcrTextPanel(text: _ocr.text!))
      else
        Expanded(
          child: ViewerShortcuts(
            grabFocus: widget.grabFocus,
            // While a frame is being drawn the keys that would move off
            // this picture, or move the picture under the frame, are put
            // away. The frame is a share of what is on screen; turning or
            // zooming under it would quietly crop somewhere else.
            onPrevious: _cropping ? null : () => widget.onPastEnd?.call(false),
            onNext: _cropping ? null : () => widget.onPastEnd?.call(true),
            onZoomIn: _cropping ? null : () => _zoom(1.25),
            onZoomOut: _cropping ? null : () => _zoom(.8),
            onFit: _cropping ? null : _fit,
            onRotate: _cropping
                ? null
                : () => setState(() => _turns = (_turns + 1) % 4),
            onFullScreen: _cropping ? null : widget.onFullScreen,
            child: Stack(
              children: [
                Positioned.fill(child: _picture()),
                if (_cropping) Positioned.fill(child: _cropLayer()),
                // Over the picture rather than beside it. In full screen
                // there is no chrome to put them in, and a gallery that can
                // only be walked with a keyboard is no gallery on a phone.
                if (_canStep) _arrow(forward: false),
                if (_canStep) _arrow(forward: true),
                if (!_cropping &&
                    widget.position != null &&
                    (widget.total ?? 0) > 1)
                  _counter(),
                if (_cropping) _cropBar(),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _tools() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        IconButton(
          tooltip: 'Sola 90° döndür',
          icon: const Icon(Icons.rotate_left_rounded),
          onPressed: _cropping
              ? null
              : () => setState(() => _turns = (_turns + 3) % 4),
        ),
        IconButton(
          tooltip: 'Sağa 90° döndür (R)',
          icon: const Icon(Icons.rotate_right_rounded),
          onPressed: _cropping
              ? null
              : () => setState(() => _turns = (_turns + 1) % 4),
        ),
        IconButton(
          tooltip: 'Uzaklaştır (−)',
          icon: const Icon(Icons.zoom_out_rounded),
          onPressed: _cropping ? null : () => _zoom(.8),
        ),
        IconButton(
          tooltip: 'Yakınlaştır (+)',
          icon: const Icon(Icons.zoom_in_rounded),
          onPressed: _cropping ? null : () => _zoom(1.25),
        ),
        IconButton(
          tooltip: 'Sığdır (0)',
          icon: const Icon(Icons.fit_screen_rounded),
          onPressed: _cropping ? null : _fit,
        ),
        if (_svg == null)
          IconButton(
            key: const ValueKey('image-crop'),
            tooltip: _intrinsic == null
                ? 'Bu görsel ölçülemedi, kırpılamıyor'
                : 'Kırp',
            isSelected: _cropping,
            icon: const Icon(Icons.crop_rounded),
            onPressed: _intrinsic == null ? null : _toggleCrop,
          ),
        if (widget.onFullScreen != null)
          IconButton(
            key: const ValueKey('image-fullscreen'),
            tooltip: 'Tam ekran (F, ya da çift tık)',
            icon: const Icon(Icons.fullscreen_rounded),
            onPressed: widget.onFullScreen,
          ),
        const VerticalDivider(width: 16, indent: 10, endIndent: 10),
        OcrTextButton(
          ocr: _ocr,
          format: _format,
          showing: _showText,
          onToggle: (v) => setState(() => _showText = v),
        ),
      ],
    ),
  );

  Widget _arrow({required bool forward}) => Positioned(
    left: forward ? null : 10,
    right: forward ? 10 : null,
    top: 0,
    bottom: 0,
    child: Center(
      child: _EdgeButton(
        buttonKey: ValueKey(forward ? 'image-next' : 'image-previous'),
        tooltip: forward ? 'Sonraki fotoğraf (→)' : 'Önceki fotoğraf (←)',
        icon: forward
            ? Icons.chevron_right_rounded
            : Icons.chevron_left_rounded,
        onPressed: () => widget.onPastEnd?.call(forward),
      ),
    ),
  );

  Widget _counter() => Positioned(
    top: 10,
    left: 0,
    right: 0,
    child: IgnorePointer(
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .52),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
            child: Text(
              '${widget.position} / ${widget.total}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _cropLayer() => LayoutBuilder(
    builder: (context, constraints) => CropOverlay(
      picture: _frameIn(constraints.biggest),
      selection: _crop,
      onChanged: (framed) => setState(() => _crop = framed),
    ),
  );

  /// The two words a crop needs, floating over the picture rather than in
  /// the toolbar, so it reads as something happening to this photograph.
  ///
  /// Stacked rather than in a row: side by side, the sentence and the two
  /// buttons ran 108 pixels past a 600 pixel window, and a phone is
  /// narrower than that.
  Widget _cropBar() => Positioned(
    left: 12,
    right: 12,
    bottom: 18,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Material(
          color: Colors.black.withValues(alpha: .74),
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 9, 9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _crop == null
                      ? 'Saklamak istediğiniz yeri sürükleyin'
                      : 'Aslı olduğu gibi kalır, kırpılan yanına kaydedilir',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : _toggleCrop,
                      child: const Text(
                        'Vazgeç',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      key: const ValueKey('image-crop-save'),
                      onPressed: _crop == null || _saving ? null : _saveCrop,
                      icon: _saving
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Kırp'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _picture() => SwipePages(
    // Panning a zoomed picture must stay panning.
    enabled: () => !_cropping && _transform.value.getMaxScaleOnAxis() <= 1.05,
    onSwipe: (forward) => widget.onPastEnd?.call(forward),
    child: _DoubleTap(
      // Twice on the picture is full screen, the way a gallery has always
      // done it. A single tap is left alone: that is how the keyboard is
      // handed over and how a zoomed picture is taken hold of.
      onDoubleTap: _cropping ? null : widget.onFullScreen,
      // Measured outside the rotation: a quarter turn swaps the box, and
      // reading the width from inside it would decode the picture again
      // every time it is turned.
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: InteractiveViewer(
            transformationController: _transform,
            minScale: .25,
            maxScale: 8,
            // While a frame is being drawn a drag belongs to the frame.
            panEnabled: !_cropping,
            scaleEnabled: !_cropping,
            child: RotatedBox(
              quarterTurns: _turns,
              child: _svg != null
                  ? FutureBuilder<String>(
                      future: _svg,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text('SVG açılamadı: ${snapshot.error}');
                        }
                        if (!snapshot.hasData) {
                          return const CircularProgressIndicator();
                        }
                        return SvgPicture.string(
                          snapshot.data!,
                          fit: BoxFit.contain,
                        );
                      },
                    )
                  : _sourceError != null
                  ? Text(_sourceError!)
                  : _source == null
                  ? const CircularProgressIndicator()
                  : Image.file(
                      File(_source!),
                      fit: BoxFit.contain,
                      // Enough pixels for the screen while the picture is
                      // fitted, all of them once it is zoomed into. Never
                      // upscaled, so nothing is invented.
                      cacheWidth: _detailed
                          ? null
                          : _decodeWidth(context, constraints),
                      // Keeps the picture on screen while the sharper one is
                      // decoded, instead of blinking to nothing.
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, error, stack) =>
                          const Text('Görsel açılamadı.'),
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Two taps in one place, without taking the gesture away from anything.
///
/// A GestureDetector wrapped around the viewer loses the arena to the pan
/// and pinch recognisers inside it — measured, the double tap never
/// arrived at all. The pointers are watched instead, the way a page swipe
/// is watched, so panning, pinching and selecting are all left alone.
class _DoubleTap extends StatefulWidget {
  const _DoubleTap({required this.child, this.onDoubleTap});

  final Widget child;
  final VoidCallback? onDoubleTap;

  @override
  State<_DoubleTap> createState() => _DoubleTapState();
}

class _DoubleTapState extends State<_DoubleTap> {
  /// Long enough for a deliberate second tap, short enough that two
  /// separate looks at the picture are not read as one gesture.
  static const _within = Duration(milliseconds: 320);

  /// How far the second tap may land from the first, and how far a finger
  /// may travel and still have been a tap rather than a drag.
  static const _near = 28.0, _still = 12.0;

  int? _pointer;
  bool _spoiled = false;
  Offset? _from, _where;
  DateTime? _last;

  void _down(PointerDownEvent event) {
    if (_pointer != null) {
      // A second finger is a pinch.
      _spoiled = true;
      return;
    }
    _pointer = event.pointer;
    _spoiled = false;
    _from = event.position;
  }

  void _up(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final press = widget.onDoubleTap;
    if (press == null) return;
    if (_spoiled ||
        event is PointerCancelEvent ||
        (_from != null && (event.position - _from!).distance > _still)) {
      _last = null;
      return;
    }
    final now = DateTime.now();
    if (_last != null &&
        now.difference(_last!) < _within &&
        _where != null &&
        (event.position - _where!).distance < _near) {
      _last = null;
      press();
      return;
    }
    _last = now;
    _where = event.position;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: widget.child,
  );
}

/// A step-along button lying over the picture.
///
/// Dark enough to be seen on a white photograph and on a black one, and
/// quiet until the cursor is near it, so it does not compete with what it
/// is sitting on.
class _EdgeButton extends StatefulWidget {
  const _EdgeButton({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final Key buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_EdgeButton> createState() => _EdgeButtonState();
}

class _EdgeButtonState extends State<_EdgeButton> {
  bool _near = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _near = true),
    onExit: (_) => setState(() => _near = false),
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      opacity: _near ? 1 : .62,
      child: Material(
        color: Colors.black.withValues(alpha: .46),
        shape: const CircleBorder(),
        child: IconButton(
          key: widget.buttonKey,
          tooltip: widget.tooltip,
          icon: Icon(widget.icon, color: Colors.white, size: 26),
          onPressed: widget.onPressed,
        ),
      ),
    ),
  );
}
