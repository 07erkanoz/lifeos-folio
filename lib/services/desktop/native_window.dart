import 'package:flutter/services.dart';

/// The Windows runner's own window calls (windows/runner/flutter_window.cpp).
const _channel = MethodChannel('com.erkanoz.folio/window');

/// Shows the hidden window maximized in one step, without Windows' zoom from
/// the restored size. window_manager's maximize posts SC_MAXIMIZE and its
/// show runs before that is handled, so the window appeared at its restored
/// size, grew, and the page laid itself out again. Windows only.
Future<void> showMaximized() => _channel.invokeMethod<void>('showMaximized');
