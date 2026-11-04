import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';

/// [wanted] made small enough to fit the screen's free area, a dock or a
/// panel left uncovered: on a 1280×800 or 1366×768 laptop a window 800 tall
/// hid its bottom buttons behind the dock. Wayland does not tell where the
/// dock is, so a tenth of the height and a twentieth of the width are kept
/// free whatever the screen says. Never below [minimum].
Size fitToScreen(Size wanted, Size screen, {Size minimum = Size.zero}) {
  if (screen.isEmpty) return wanted;
  return Size(
    math.max(minimum.width, math.min(wanted.width, screen.width * 0.95)),
    math.max(minimum.height, math.min(wanted.height, screen.height * 0.9)),
  );
}

/// [fitToScreen] on the primary screen; [wanted] itself when the screen
/// cannot be read.
Future<Size> fitToPrimaryScreen(Size wanted, {Size minimum = Size.zero}) async {
  try {
    final display = await screenRetriever.getPrimaryDisplay();
    return fitToScreen(
      wanted,
      display.visibleSize ?? display.size,
      minimum: minimum,
    );
  } catch (_) {
    return wanted;
  }
}
