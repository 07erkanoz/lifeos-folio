import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../portal/portal_database.dart';
import 'client.dart';
import 'client_files.dart';

/// The files kept with the clients' records (a power of attorney's scan,
/// signed minutes, a receipt), brought from the device that has them to
/// the one whose records name them: in pieces, for a channel's line holds
/// a megabyte at most; checked by their digest before they are kept.
class ClientFileSync {
  ClientFileSync({required this.db, ClientFiles? files})
    : files = files ?? ClientFiles();

  final PortalDatabase db;
  final ClientFiles files;

  static const kind = 'muvekkil-ek';
  static const piece = 512 * 1024;

  /// A piece of the file of digest asked, when [may] lets the asker have
  /// the record it is kept with.
  Future<Map<String, Object?>?> answer(
    Map<String, Object?> asked, {
    required bool Function(ClientRecord record) may,
  }) async {
    final sha = '${asked['sha256']}';
    final from = asked['bas'] is int ? asked['bas'] as int : 0;
    for (final r in db.allClientRecords()) {
      if (r.removed || !may(r)) continue;
      for (final f in clientFilesOf(r)) {
        if (f.sha256 != sha) continue;
        // Its content checked against its digest before it goes.
        final file = await files.locate(r.clientId, f);
        if (file == null) continue;
        final size = await file.length();
        final raf = await file.open();
        try {
          await raf.setPosition(from);
          final bytes = await raf.read(piece);
          return {
            'parca': base64Encode(bytes),
            'boy': size,
            'son': from + bytes.length >= size,
          };
        } finally {
          await raf.close();
        }
      }
    }
    return null;
  }

  /// The files the records name and this device has not, asked of [ask]:
  /// how many were brought.
  Future<int> fetchMissing(
    Future<Map<String, Object?>?> Function(Map<String, Object?> body) ask, {
    bool Function(ClientRecord record)? may,
  }) async {
    var brought = 0;
    final seen = <String>{};
    for (final r in db.allClientRecords()) {
      if (r.removed) continue;
      if (may != null && !may(r)) continue;
      if (!ClientFiles.safeId(r.clientId)) continue;
      for (final f in clientFilesOf(r)) {
        if (!seen.add('${r.clientId}|${f.sha256}|${f.name}')) continue;
        if (await files.locate(r.clientId, f) != null) continue;
        final bytes = BytesBuilder(copy: false);
        var ok = false;
        for (var guard = 0; guard < 400; guard++) {
          final a = await ask({'sha256': f.sha256, 'bas': bytes.length});
          if (a == null || a['parca'] is! String) break;
          bytes.add(base64Decode(a['parca'] as String));
          if (a['son'] == true) {
            ok = true;
            break;
          }
        }
        if (!ok) continue;
        final all = bytes.takeBytes();
        if (sha256.convert(all).toString() != f.sha256) continue;
        // Still kept, and still to be had, when it came.
        final still = db.clientRecord(r.id);
        if (still == null || still.removed || (may != null && !may(still))) {
          continue;
        }
        final target = await files.placeFor(r.clientId, f);
        await target.parent.create(recursive: true);
        await File(target.path).writeAsBytes(all, flush: true);
        // Taken off, or no longer to be had, while it was written: gone.
        final after = db.clientRecord(r.id);
        if (after == null || after.removed || (may != null && !may(after))) {
          await files.forget(r.clientId, f);
          continue;
        }
        brought++;
      }
    }
    return brought;
  }
}
