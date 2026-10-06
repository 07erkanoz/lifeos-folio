import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../models/evrak_file.dart';
import '../../services/platform/heif_images.dart';

/// A photograph full screen on a phone (docs/design/mobil-galeri-taslak.png):
/// on black, the width of the screen, swiped to the next and the one
/// before, pinched or tapped twice to come closer; one tap hides the bars
/// and a swipe down goes back to the gallery.
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    super.key,
    required this.files,
    required this.initial,
    required this.onShare,
    required this.onPdf,
    required this.onEdit,
    required this.onToCase,
  });

  final List<EvrakFile> files;
  final int initial;
  final ValueChanged<EvrakFile> onShare, onPdf, onToCase;

  /// Edits the photograph; the copy written, or null.
  final Future<String?> Function(EvrakFile file) onEdit;

  static Future<void> open(
    BuildContext context, {
    required List<EvrakFile> files,
    required int initial,
    required ValueChanged<EvrakFile> onShare,
    required ValueChanged<EvrakFile> onPdf,
    required Future<String?> Function(EvrakFile file) onEdit,
    required ValueChanged<EvrakFile> onToCase,
  }) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      pageBuilder: (_, _, _) => PhotoViewerPage(
        files: files,
        initial: initial,
        onShare: onShare,
        onPdf: onPdf,
        onEdit: onEdit,
        onToCase: onToCase,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  bool _bars = true;
  bool _zoomed = false;
  double _drag = 0;

  static const _months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', //
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pages.dispose();
    super.dispose();
  }

  void _toggleBars() {
    setState(() => _bars = !_bars);
    SystemChrome.setEnabledSystemUIMode(
      _bars ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  EvrakFile get _file => widget.files[_index];

  /// "Bugün 09:12 · Kamera".
  String _when(EvrakFile file) {
    try {
      final t = File(file.path).lastModifiedSync();
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final day = DateTime(t.year, t.month, t.day);
      final today = DateTime(now.year, now.month, now.day);
      final date = day == today
          ? 'Bugün'
          : day == today.subtract(const Duration(days: 1))
          ? 'Dün'
          : '${t.day} ${_months[t.month - 1]} ${t.year}';
      return '$date ${two(t.hour)}:${two(t.minute)} · '
          '${p.basename(p.dirname(file.path))}';
    } catch (_) {
      return p.basename(p.dirname(file.path));
    }
  }

  Future<void> _info() {
    final file = _file;
    final stat = File(file.path).statSync();
    String size(int bytes) => bytes > 1 << 20
        ? '${(bytes / (1 << 20)).toStringAsFixed(1)} MB'
        : '${(bytes / 1024).round()} KB';
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.basename(file.path),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text('Tarih: ${_when(file)}'),
              Text('Boyut: ${size(stat.size)}'),
              const SizedBox(height: 4),
              SelectableText(
                p.dirname(file.path),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: Colors.black.withValues(
        alpha: (1 - (_drag.abs() / 400)).clamp(.3, 1),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            // A swipe down, when not come close, goes back to the gallery.
            onVerticalDragUpdate: _zoomed
                ? null
                : (d) => setState(() => _drag += d.delta.dy),
            onVerticalDragEnd: _zoomed
                ? null
                : (d) {
                    if (_drag > 120 || (d.primaryVelocity ?? 0) > 900) {
                      Navigator.pop(context);
                    } else {
                      setState(() => _drag = 0);
                    }
                  },
            child: Transform.translate(
              offset: Offset(0, _drag),
              child: PageView.builder(
                key: const ValueKey('photo-pages'),
                controller: _pages,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: widget.files.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _Photo(
                  file: widget.files[i],
                  onTap: _toggleBars,
                  onZoom: (zoomed) {
                    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
                  },
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: _bars ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: IgnorePointer(
              ignoring: !_bars,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: EdgeInsets.fromLTRB(4, pad.top + 4, 4, 18),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x99000000), Color(0x00000000)],
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            key: const ValueKey('photo-back'),
                            tooltip: 'Galeriye dön',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.basename(file.path),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  _when(file),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFC9CED8),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Bilgi',
                            onPressed: _info,
                            icon: const Icon(
                              Icons.info_outline_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: EdgeInsets.fromLTRB(6, 20, 6, pad.bottom + 10),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0xA6000000)],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_index + 1} / ${widget.files.length}',
                            style: const TextStyle(
                              color: Color(0xFFC9CED8),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _action(
                                const ValueKey('photo-share'),
                                Icons.ios_share_rounded,
                                'Paylaş',
                                () => widget.onShare(file),
                              ),
                              _action(
                                const ValueKey('photo-pdf'),
                                Icons.picture_as_pdf_outlined,
                                'PDF’e çevir',
                                () => widget.onPdf(file),
                              ),
                              _action(
                                const ValueKey('photo-edit'),
                                Icons.tune_rounded,
                                'Düzenle',
                                () => widget.onEdit(file),
                              ),
                              _action(
                                const ValueKey('photo-to-case'),
                                Icons.drive_file_move_outline,
                                'UYAP dosyasına',
                                () => widget.onToCase(file),
                              ),
                            ],
                          ),
                        ],
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

  Widget _action(Key key, IconData icon, String label, VoidCallback onTap) =>
      Expanded(
        child: InkWell(
          key: key,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 21),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ),
      );
}

/// One photograph, as wide as the screen, brought closer by two fingers or
/// two taps.
class _Photo extends StatefulWidget {
  const _Photo({required this.file, required this.onTap, required this.onZoom});

  final EvrakFile file;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoom;

  @override
  State<_Photo> createState() => _PhotoState();
}

class _PhotoState extends State<_Photo> with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  Offset _tapAt = Offset.zero;
  late final Future<String?> _path = HeifImages.isHeif(widget.file.path)
      ? HeifImages.decoded(widget.file.path)
      : Future.value(widget.file.path);

  @override
  void initState() {
    super.initState();
    _transform.addListener(() {
      widget.onZoom(_transform.value.getMaxScaleOnAxis() > 1.01);
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _doubleTap() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed) {
      _transform.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    final x = -_tapAt.dx * (scale - 1);
    final y = -_tapAt.dy * (scale - 1);
    _transform.value = Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap,
    onDoubleTapDown: (d) => _tapAt = d.localPosition,
    onDoubleTap: _doubleTap,
    child: InteractiveViewer(
      transformationController: _transform,
      minScale: 1,
      maxScale: 6,
      child: SizedBox.expand(
        child: FutureBuilder<String?>(
          future: _path,
          builder: (context, s) {
            if (s.data == null) {
              return Center(
                child: s.connectionState == ConnectionState.done
                    ? const Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.white54,
                        size: 40,
                      )
                    : const CircularProgressIndicator(color: Colors.white54),
              );
            }
            return Image.file(
              File(s.data!),
              key: ValueKey('photo-${widget.file.path}'),
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 40,
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
