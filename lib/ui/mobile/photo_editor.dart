import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/platform/app_directories.dart';
import '../../services/platform/heif_images.dart';
import '../../services/preview/photo_edit.dart';

enum _Tool { corners, crop, rotate, adjust, redact, draw }

/// A photograph edited on a phone (docs/design/mobil-galeri-taslak.png):
/// a photographed page straightened by its corners, cropped, turned, given
/// a document's look and adjusted, what must not be seen covered in black,
/// lines and notes drawn on it. Worked on a small copy, kept as a new file
/// beside the photograph; the photograph is never written over.
class PhotoEditorPage extends StatefulWidget {
  const PhotoEditorPage({super.key, required this.path});

  final String path;

  /// The copy written, or null when nothing was kept.
  static Future<String?> open(BuildContext context, String path) =>
      Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PhotoEditorPage(path: path),
        ),
      );

  @override
  State<PhotoEditorPage> createState() => _PhotoEditorPageState();
}

class _PhotoEditorPageState extends State<PhotoEditorPage> {
  String? _source;
  Uint8List? _work;
  RenderedPhoto? _shown;
  PhotoEdit _edit = const PhotoEdit();
  final _history = <PhotoEdit>[];
  _Tool _tool = _Tool.corners;
  bool _drawText = false;
  bool _saving = false;
  String? _error;
  int _renders = 0;
  Timer? _soon;

  // A box or a line being drawn.
  Offset? _boxFrom, _boxTo;
  List<Offset>? _line;

  static const _defaultCorners = [
    Offset(.06, .06),
    Offset(.94, .06),
    Offset(.94, .94),
    Offset(.06, .94),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _soon?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final source = HeifImages.isHeif(widget.path)
          ? await HeifImages.decoded(widget.path)
          : widget.path;
      if (source == null) throw const FormatException('Görsel çözülemedi.');
      final bytes = await File(source).readAsBytes();
      // The small copy everything is tried on: quick to redo at each touch.
      final work = await compute(PhotoEditing.render, (
        bytes: bytes,
        edit: const PhotoEdit(),
        stage: PhotoStage.untouched,
        maxSide: 1400,
        jpeg: true,
      ));
      if (!mounted) return;
      _source = source;
      _work = work.bytes;
      _edit = const PhotoEdit(corners: _defaultCorners);
      await _render();
    } catch (e) {
      if (mounted) setState(() => _error = 'Resim açılamadı: $e');
    }
  }

  PhotoStage get _stage => switch (_tool) {
    _Tool.corners => PhotoStage.untouched,
    _Tool.crop => PhotoStage.uncropped,
    _ => PhotoStage.finished,
  };

  Future<void> _render() async {
    final work = _work;
    if (work == null) return;
    final token = ++_renders;
    final made = await compute(PhotoEditing.render, (
      bytes: work,
      edit: _edit,
      stage: _stage,
      maxSide: 0,
      jpeg: false,
    ));
    if (mounted && token == _renders) setState(() => _shown = made);
  }

  void _renderSoon() {
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 90), () => unawaited(_render()));
  }

  /// [next], with the way back to what was.
  void _change(PhotoEdit next, {bool render = true}) {
    setState(() {
      _history.add(_edit);
      _edit = next;
    });
    if (render) _renderSoon();
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() => _edit = _history.removeLast());
    _renderSoon();
  }

  void _choose(_Tool tool) {
    if (tool == _Tool.rotate) {
      _change(_edit.copyWith(turns: (_edit.turns + 1) % 4));
    }
    setState(() {
      _tool = tool;
      _drawText = false;
    });
    _renderSoon();
  }

  Future<void> _save() async {
    final source = _source;
    if (source == null) return;
    setState(() => _saving = true);
    try {
      final file = await PhotoEditing.save(
        source: source,
        original: widget.path,
        edit: _edit,
        fallback: () async => Directory(
          p.join((await folioSupportDirectory()).path, 'Düzenlenen'),
        ),
      );
      if (mounted) Navigator.pop(context, file.path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Kaydedilemedi: $e';
        });
      }
    }
  }

  /// The picture's place on the screen, as large as fits.
  Rect _fit(Size box, RenderedPhoto shown) {
    final scale = [
      box.width / shown.width,
      box.height / shown.height,
    ].reduce((a, b) => a < b ? a : b);
    final w = shown.width * scale, h = shown.height * scale;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  Offset _share(Offset local, Rect r) => Offset(
    ((local.dx - r.left) / r.width).clamp(0, 1),
    ((local.dy - r.top) / r.height).clamp(0, 1),
  );

  Offset _place(Offset share, Rect r) =>
      Offset(r.left + share.dx * r.width, r.top + share.dy * r.height);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Vazgeç',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text(
                      'Düzenle',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('photo-undo'),
                    tooltip: 'Geri al',
                    onPressed: _history.isEmpty ? null : _undo,
                    icon: const Icon(Icons.undo_rounded),
                    color: Colors.white,
                    disabledColor: Colors.white30,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: FilledButton(
                      key: const ValueKey('photo-save'),
                      onPressed: _shown == null || _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Kopya kaydet'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    )
                  : _shown == null
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white54),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                      child: LayoutBuilder(
                        builder: (context, box) =>
                            _canvas(box.biggest, _shown!, scheme),
                      ),
                    ),
            ),
            _panel(scheme),
            _tools(scheme),
          ],
        ),
      ),
    );
  }

  Widget _canvas(Size box, RenderedPhoto shown, ColorScheme scheme) {
    final r = _fit(box, shown);
    final drawn = _tool != _Tool.corners && _tool != _Tool.crop;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fromRect(
          rect: r,
          child: Image.memory(
            shown.bytes,
            gaplessPlayback: true,
            fit: BoxFit.fill,
          ),
        ),
        if (drawn)
          Positioned.fill(
            child: CustomPaint(
              painter: _MarksPainter(
                rect: r,
                edit: _edit,
                box: _boxFrom == null || _boxTo == null
                    ? null
                    : Rect.fromPoints(_boxFrom!, _boxTo!),
                line: _line,
              ),
            ),
          ),
        if (_tool == _Tool.redact || _tool == _Tool.draw)
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('photo-canvas'),
              onTapUp: _tool == _Tool.draw && _drawText
                  ? (d) => unawaited(_text(_share(d.localPosition, r)))
                  : null,
              onPanStart: _tool == _Tool.draw && _drawText
                  ? null
                  : (d) => setState(() {
                      final at = _share(d.localPosition, r);
                      if (_tool == _Tool.redact) {
                        _boxFrom = at;
                        _boxTo = at;
                      } else {
                        _line = [at];
                      }
                    }),
              onPanUpdate: _tool == _Tool.draw && _drawText
                  ? null
                  : (d) => setState(() {
                      final at = _share(d.localPosition, r);
                      if (_tool == _Tool.redact) {
                        _boxTo = at;
                      } else {
                        _line = [...?_line, at];
                      }
                    }),
              onPanEnd: _tool == _Tool.draw && _drawText
                  ? null
                  : (_) {
                      if (_tool == _Tool.redact &&
                          _boxFrom != null &&
                          _boxTo != null) {
                        final box = Rect.fromPoints(_boxFrom!, _boxTo!);
                        if (box.width > .01 && box.height > .005) {
                          _change(
                            _edit.copyWith(
                              redactions: [..._edit.redactions, box],
                            ),
                            render: false,
                          );
                        }
                      } else if (_line != null && _line!.length > 1) {
                        _change(
                          _edit.copyWith(
                            strokes: [..._edit.strokes, PhotoStroke(_line!)],
                          ),
                          render: false,
                        );
                      }
                      setState(() {
                        _boxFrom = _boxTo = null;
                        _line = null;
                      });
                    },
            ),
          ),
        if (_tool == _Tool.corners) ..._cornerHandles(r, scheme),
        if (_tool == _Tool.crop) ..._cropHandles(r, scheme),
      ],
    );
  }

  Future<void> _text(Offset at) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Not'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Yazın'),
          onSubmitted: (v) => Navigator.pop(dialog, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;
    _change(
      _edit.copyWith(texts: [..._edit.texts, PhotoText(at, text.trim())]),
      render: false,
    );
  }

  Widget _handle(Offset centre, ValueChanged<Offset> moved, Key key) =>
      Positioned(
        left: centre.dx - 16,
        top: centre.dy - 16,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => moved(d.delta),
          onPanEnd: (_) => _renderSoon(),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  List<Widget> _cornerHandles(Rect r, ColorScheme scheme) {
    final corners = _edit.corners ?? _defaultCorners;
    return [
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _QuadPainter([
              for (final c in corners) _place(c, r),
            ], scheme.primary),
          ),
        ),
      ),
      for (var i = 0; i < 4; i++)
        _handle(_place(corners[i], r), (delta) {
          final next = [...corners];
          next[i] = Offset(
            (corners[i].dx + delta.dx / r.width).clamp(0, 1),
            (corners[i].dy + delta.dy / r.height).clamp(0, 1),
          );
          // Corners move many times a second: one step back for the drag.
          setState(() => _edit = _edit.copyWith(corners: next));
        }, ValueKey('photo-corner-$i')),
    ];
  }

  List<Widget> _cropHandles(Rect r, ColorScheme scheme) {
    final crop = _edit.crop ?? const Rect.fromLTRB(0, 0, 1, 1);
    Rect moved(int i, Offset d) {
      final dx = d.dx / r.width, dy = d.dy / r.height;
      var c = crop;
      c = switch (i) {
        0 => Rect.fromLTRB(c.left + dx, c.top + dy, c.right, c.bottom),
        1 => Rect.fromLTRB(c.left, c.top + dy, c.right + dx, c.bottom),
        2 => Rect.fromLTRB(c.left, c.top, c.right + dx, c.bottom + dy),
        _ => Rect.fromLTRB(c.left + dx, c.top, c.right, c.bottom + dy),
      };
      return Rect.fromLTRB(
        c.left.clamp(0, c.right - .05),
        c.top.clamp(0, c.bottom - .05),
        c.right.clamp(c.left + .05, 1),
        c.bottom.clamp(c.top + .05, 1),
      );
    }

    final corners = [
      crop.topLeft,
      crop.topRight,
      crop.bottomRight,
      crop.bottomLeft,
    ];
    return [
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _CropPainter(
              Rect.fromPoints(
                _place(crop.topLeft, r),
                _place(crop.bottomRight, r),
              ),
              r,
              scheme.primary,
            ),
          ),
        ),
      ),
      for (var i = 0; i < 4; i++)
        _handle(
          _place(corners[i], r),
          (delta) =>
              setState(() => _edit = _edit.copyWith(crop: moved(i, delta))),
          ValueKey('photo-crop-$i'),
        ),
    ];
  }

  /// Under the picture: the looks, or the adjustments, or what a tool does.
  Widget _panel(ColorScheme scheme) {
    if (_tool == _Tool.adjust) {
      Widget slider(
        String label,
        double value,
        double min,
        PhotoEdit Function(double) set,
      ) => Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: 1,
              onChangeStart: (_) => _history.add(_edit),
              onChanged: (v) {
                setState(() => _edit = set(v));
                _renderSoon();
              },
            ),
          ),
        ],
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            slider(
              'Parlaklık',
              _edit.brightness,
              -1,
              (v) => _edit.copyWith(brightness: v),
            ),
            slider(
              'Kontrast',
              _edit.contrast,
              -1,
              (v) => _edit.copyWith(contrast: v),
            ),
            slider(
              'Netlik',
              _edit.sharpness,
              0,
              (v) => _edit.copyWith(sharpness: v),
            ),
          ],
        ),
      );
    }
    if (_tool == _Tool.redact || _tool == _Tool.draw) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_tool == _Tool.draw)
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  foregroundColor: WidgetStatePropertyAll(Colors.white),
                  visualDensity: VisualDensity.compact,
                ),
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.edit_rounded, size: 16),
                    label: Text('Kalem'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.text_fields_rounded, size: 16),
                    label: Text('Metin'),
                  ),
                ],
                selected: {_drawText},
                onSelectionChanged: (v) => setState(() => _drawText = v.first),
              ),
            const SizedBox(height: 6),
            Text(
              _tool == _Tool.redact
                  ? 'Kapatmak istediğiniz yeri parmağınızla çizin. Kayıtta '
                        'resmin içine işlenir, kaldırılamaz.'
                  : _drawText
                  ? 'Notun yerine dokunun.'
                  : 'Parmağınızla çizin.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      );
    }
    Widget look(PhotoFilter filter, String label, Decoration swatch) {
      final on = _edit.filter == filter;
      return Expanded(
        child: GestureDetector(
          key: ValueKey('photo-filter-${filter.name}'),
          onTap: () => _change(_edit.copyWith(filter: filter)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 54,
                  decoration: swatch is BoxDecoration
                      ? swatch.copyWith(
                          borderRadius: BorderRadius.circular(8),
                          border: on
                              ? Border.all(color: scheme.primary, width: 3)
                              : null,
                        )
                      : swatch,
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: on ? Colors.white : const Color(0xFFC9CED8),
                    fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 0, 9, 10),
      child: Row(
        children: [
          look(
            PhotoFilter.original,
            'Orijinal',
            const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFE8DCC7), Color(0xFFB79E74)],
              ),
            ),
          ),
          look(
            PhotoFilter.document,
            'Belge',
            const BoxDecoration(color: Colors.white),
          ),
          look(
            PhotoFilter.gray,
            'Gri',
            const BoxDecoration(color: Color(0xFFD9D9D9)),
          ),
          look(
            PhotoFilter.colorDocument,
            'Renkli belge',
            const BoxDecoration(color: Color(0xFFFFF6E2)),
          ),
        ],
      ),
    );
  }

  Widget _tools(ColorScheme scheme) {
    Widget tool(_Tool t, IconData icon, String label) {
      final on = _tool == t;
      final ink = on ? const Color(0xFF7FA6E8) : const Color(0xFFAEB4C0);
      return Expanded(
        child: InkWell(
          key: ValueKey('photo-tool-${t.name}'),
          onTap: _shown == null ? null : () => _choose(t),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 21, color: on ? ink : const Color(0xFFE7EAF0)),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: ink,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF14171C),
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
      child: Row(
        children: [
          tool(_Tool.corners, Icons.crop_free_rounded, 'Belge düzelt'),
          tool(_Tool.crop, Icons.crop_rounded, 'Kırp'),
          tool(_Tool.rotate, Icons.rotate_right_rounded, 'Döndür'),
          tool(_Tool.adjust, Icons.tonality_rounded, 'Ayarla'),
          tool(_Tool.redact, Icons.rectangle_rounded, 'Karart'),
          tool(_Tool.draw, Icons.draw_outlined, 'İşaretle'),
        ],
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(this.points, this.color);
  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        path,
      ),
      Paint()..color = Colors.black.withValues(alpha: .45),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_QuadPainter old) => old.points != points;
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.crop, this.picture, this.color);
  final Rect crop, picture;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(picture),
        Path()..addRect(crop),
      ),
      Paint()..color = Colors.black.withValues(alpha: .55),
    );
    canvas.drawRect(
      crop,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.crop != crop || old.picture != picture;
}

/// The black boxes, lines and notes over the picture on the screen, as the
/// copy saved will have them burnt in.
class _MarksPainter extends CustomPainter {
  _MarksPainter({required this.rect, required this.edit, this.box, this.line});
  final Rect rect;
  final PhotoEdit edit;
  final Rect? box;
  final List<Offset>? line;

  Offset _at(Offset s) =>
      Offset(rect.left + s.dx * rect.width, rect.top + s.dy * rect.height);

  @override
  void paint(Canvas canvas, Size size) {
    final black = Paint()..color = Colors.black;
    for (final r in [...edit.redactions, ?box]) {
      canvas.drawRect(
        Rect.fromPoints(_at(r.topLeft), _at(r.bottomRight)),
        black,
      );
    }
    final pen = Paint()
      ..color = const Color(0xFFDC2626)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in [...edit.strokes.map((s) => s.points), ?line]) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(_at(s.first).dx, _at(s.first).dy);
      for (final pt in s.skip(1)) {
        path.lineTo(_at(pt).dx, _at(pt).dy);
      }
      canvas.drawPath(path, pen);
    }
    for (final t in edit.texts) {
      final painter = TextPainter(
        text: TextSpan(
          text: t.text,
          style: const TextStyle(
            color: Color(0xFFDC2626),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width);
      painter.paint(canvas, _at(t.at));
    }
  }

  @override
  bool shouldRepaint(_MarksPainter old) => true;
}
