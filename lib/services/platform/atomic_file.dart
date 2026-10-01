import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Never expose a truncated desktop entry or icon to desktop file watchers.
/// Unchanged files are not touched, so repeated registration emits no events.
Future<bool> replaceFileIfChanged(File target, List<int> bytes) async {
  if (await target.exists() && listEquals(await target.readAsBytes(), bytes)) {
    return false;
  }
  await target.parent.create(recursive: true);
  final staging = await target.parent.createTemp('.folio-install-');
  try {
    final pending = File(p.join(staging.path, 'payload'));
    await pending.writeAsBytes(bytes, flush: true);
    await pending.rename(target.path);
    return true;
  } finally {
    await staging.delete(recursive: true);
  }
}
