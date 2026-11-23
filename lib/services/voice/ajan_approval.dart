import 'dart:async';

import 'package:flutter/foundation.dart';

/// Something Folio Ajan is about to change, put before the lawyer.
class AjanApprovalAsk {
  AjanApprovalAsk(this.title, this.detail);

  final String title;

  /// What exactly is done: the tool's arguments, one per line.
  final String detail;
  final _done = Completer<bool>();
}

/// The lawyer's yes, on Folio Ajan's screen, before a tool that changes
/// something runs (LifeOS's tools, 23 Kasım 2026): what the voice heard is
/// not enough, the lawyer presses Onayla.
class AjanApprovals extends ChangeNotifier {
  AjanApprovals._();
  static final instance = AjanApprovals._();

  /// How long an unanswered ask waits before it counts as no.
  static const wait = Duration(minutes: 2);

  /// Folio Ajan's screens on, where the ask is shown.
  int shown = 0;
  AjanApprovalAsk? asking;

  /// The lawyer's answer; null when no Folio Ajan screen can show it.
  Future<bool?> request(String title, String detail) async {
    if (shown == 0) return null;
    final open = asking;
    if (open != null && !open._done.isCompleted) open._done.complete(false);
    final ask = asking = AjanApprovalAsk(title, detail);
    notifyListeners();
    try {
      return await ask._done.future.timeout(wait, onTimeout: () => false);
    } finally {
      if (identical(asking, ask)) {
        asking = null;
        notifyListeners();
      }
    }
  }

  void approve() => _end(true);
  void cancel() => _end(false);

  void _end(bool ok) {
    final ask = asking;
    if (ask == null) return;
    asking = null;
    if (!ask._done.isCompleted) ask._done.complete(ok);
    notifyListeners();
  }
}
