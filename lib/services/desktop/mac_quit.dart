import 'dart:io';

import 'package:flutter/services.dart';

/// A Mac's ⌘Q asks Folio first (macos/Runner/AppDelegate.swift): the app
/// ended at once, without its window's close, and unsaved work was lost
/// without a word (21 Ekim 2026). [approve] answers whether it may end;
/// none set, it may.
abstract final class MacQuit {
  static const channel = MethodChannel('com.erkanoz.folio/app');

  static void handle(Future<bool> Function() approve) {
    if (!Platform.isMacOS) return;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'quit') return null;
      try {
        return await approve();
      } catch (_) {
        // Not to be kept from quitting by a failure to ask.
        return true;
      }
    });
  }
}
