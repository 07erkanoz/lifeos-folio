import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Application chrome stays outside the Navigator, including on license pages.
class DesktopFrame extends StatefulWidget {
  final Widget child;
  final bool closeToTray;
  final VoidCallback onAbout;

  /// What the bar says: the app's name, or the standalone editor's.
  final String title;

  /// The icon beside it, the editor's having a pen on it.
  final String icon;

  /// Buttons after the icon: the standalone editor's Yeni and Aç, which
  /// have no other home there.
  final List<Widget> leading;

  /// The icon's tooltip, naming the program now that the bar may not.
  final String iconTooltip;

  /// Shown before and after [title]: the standalone editor's document icon
  /// and its unsaved-changes dot.
  final IconData? titleIcon;
  final Widget? titleTrailing;
  const DesktopFrame({
    super.key,
    required this.child,
    required this.onAbout,
    this.closeToTray = false,
    this.title = 'LifeOS Folio',
    this.icon = 'assets/branding/lifeos_folio.png',
    this.leading = const [],
    this.iconTooltip = 'LifeOS Folio hakkında',
    this.titleIcon,
    this.titleTrailing,
  });
  @override
  State<DesktopFrame> createState() => _DesktopFrameState();
}

class _DesktopFrameState extends State<DesktopFrame> with WindowListener {
  bool _maximized = false;
  bool _fullScreen = false;
  bool _focused = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _sync();
  }

  Future<void> _sync() async {
    final maximized = await windowManager.isMaximized();
    final fullscreen = await windowManager.isFullScreen();
    if (mounted) {
      setState(() {
        _maximized = maximized;
        _fullScreen = fullscreen;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _sync();
    } catch (_) {
      if (mounted) setState(() => _error = 'Pencere işlemi tamamlanamadı');
    }
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    }
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  void _toggleFullScreen() => _run(
    () async =>
        windowManager.setFullScreen(!await windowManager.isFullScreen()),
  );
  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => _sync();
  @override
  void onWindowUnmaximize() => _sync();
  @override
  void onWindowEnterFullScreen() => _sync();
  @override
  void onWindowLeaveFullScreen() => _sync();
  @override
  void onWindowFocus() {
    if (mounted) setState(() => _focused = true);
  }

  @override
  void onWindowBlur() {
    if (mounted) setState(() => _focused = false);
  }

  Widget _control(
    String label,
    IconData icon,
    VoidCallback action, {
    bool close = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 44,
      height: 38,
      child: TextButton(
        key: ValueKey('caption-$label'),
        onPressed: action,
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          minimumSize: const WidgetStatePropertyAll(Size(44, 38)),
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
          splashFactory: NoSplash.splashFactory,
          animationDuration: Duration.zero,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                close &&
                    (states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.pressed))
                ? Colors.white
                : colors.onSurface,
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return close
                  ? const Color(0xFFA83232)
                  : colors.surfaceContainerHighest;
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return close
                  ? const Color(0xFFC34444)
                  : colors.surfaceContainerHighest;
            }
            return colors.surface;
          }),
        ),
        child: Tooltip(
          message: label,
          child: Icon(icon, size: 16, semanticLabel: label),
        ),
      ),
    );
  }

  Widget _resizeEdge(
    ResizeEdge edge,
    MouseCursor cursor, {
    double? left,
    double? top,
    double? right,
    double? bottom,
    double? width,
    double? height,
  }) => Positioned(
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    width: width,
    height: height,
    child: MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _run(() => windowManager.startResizing(edge)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Overlay.wrap(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f11): _toggleFullScreen,
          if (_fullScreen)
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _run(() => windowManager.setFullScreen(false)),
        },
        child: Focus(
          canRequestFocus: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  RepaintBoundary(
                    child: Material(
                      key: const ValueKey('folio-titlebar'),
                      color: colors.surface,
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: colors.outlineVariant),
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            InkWell(
                              onTap: widget.onAbout,
                              borderRadius: BorderRadius.circular(6),
                              child: Tooltip(
                                message: widget.iconTooltip,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: Image.asset(
                                    widget.icon,
                                    width: 23,
                                    height: 23,
                                  ),
                                ),
                              ),
                            ),
                            if (widget.leading.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              ...widget.leading,
                              const SizedBox(width: 6),
                              SizedBox(
                                height: 20,
                                child: VerticalDivider(
                                  width: 1,
                                  thickness: 1,
                                  color: colors.outlineVariant,
                                ),
                              ),
                            ],
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (_) =>
                                    _run(windowManager.startDragging),
                                onDoubleTap: () => _run(_toggleMaximize),
                                child: SizedBox.expand(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (widget.titleIcon != null &&
                                              _error == null) ...[
                                            Icon(
                                              widget.titleIcon,
                                              size: 16,
                                              color: colors.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          Flexible(
                                            child: Text(
                                              _error ?? widget.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: .2,
                                                color: _focused
                                                    ? colors.onSurface
                                                    : colors.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                          if (widget.titleTrailing != null &&
                                              _error == null)
                                            widget.titleTrailing!,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _control(
                              'Hakkında',
                              Icons.info_outline_rounded,
                              widget.onAbout,
                            ),
                            _control(
                              _fullScreen
                                  ? 'Tam ekrandan çık (F11)'
                                  : 'Tam ekran (F11)',
                              _fullScreen
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                              _toggleFullScreen,
                            ),
                            const VerticalDivider(
                              indent: 11,
                              endIndent: 11,
                              width: 1,
                            ),
                            _control(
                              'Simge durumuna küçült',
                              Icons.remove_rounded,
                              () => _run(windowManager.minimize),
                            ),
                            _control(
                              _maximized ? 'Önceki boyut' : 'Ekranı kapla',
                              _maximized
                                  ? Icons.filter_none_rounded
                                  : Icons.crop_square_rounded,
                              () => _run(_toggleMaximize),
                            ),
                            _control(
                              widget.closeToTray
                                  ? 'Tepsiye gizle'
                                  : 'Uygulamayı kapat',
                              Icons.close_rounded,
                              () => _run(windowManager.close),
                              close: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: widget.child),
                ],
              ),
              // Only these narrow edge rectangles participate in hit testing.
              // No full-window overlay sits above the caption or document.
              if (!_maximized && !_fullScreen) ...[
                _resizeEdge(
                  ResizeEdge.top,
                  SystemMouseCursors.resizeUp,
                  left: 6,
                  right: 6,
                  top: 0,
                  height: 4,
                ),
                _resizeEdge(
                  ResizeEdge.bottom,
                  SystemMouseCursors.resizeDown,
                  left: 6,
                  right: 6,
                  bottom: 0,
                  height: 4,
                ),
                _resizeEdge(
                  ResizeEdge.left,
                  SystemMouseCursors.resizeLeft,
                  left: 0,
                  top: 6,
                  bottom: 6,
                  width: 4,
                ),
                _resizeEdge(
                  ResizeEdge.right,
                  SystemMouseCursors.resizeRight,
                  right: 0,
                  top: 6,
                  bottom: 6,
                  width: 4,
                ),
                _resizeEdge(
                  ResizeEdge.topLeft,
                  SystemMouseCursors.resizeUpLeft,
                  top: 0,
                  left: 0,
                  width: 6,
                  height: 6,
                ),
                _resizeEdge(
                  ResizeEdge.topRight,
                  SystemMouseCursors.resizeUpRight,
                  top: 0,
                  right: 0,
                  width: 6,
                  height: 6,
                ),
                _resizeEdge(
                  ResizeEdge.bottomLeft,
                  SystemMouseCursors.resizeDownLeft,
                  bottom: 0,
                  left: 0,
                  width: 6,
                  height: 6,
                ),
                _resizeEdge(
                  ResizeEdge.bottomRight,
                  SystemMouseCursors.resizeDownRight,
                  bottom: 0,
                  right: 0,
                  width: 6,
                  height: 6,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
