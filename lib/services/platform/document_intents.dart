import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Android's content URIs are copied byte-for-byte off the UI thread by the
/// native bridge. Cold and warm launches share one ordered delivery queue.
class DocumentIntents {
  static const channel = MethodChannel('lifeos_evrak/documents');
  final _paths = StreamController<List<String>>.broadcast();
  Stream<List<String>> get paths => _paths.stream;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  /// Android's intents; on iOS the documents another app opens in Folio
  /// (ios/Runner/AppDelegate.swift, FolioDocuments); on a Mac those Finder
  /// opens in it (macos/Runner/AppDelegate.swift, OpenedDocuments).
  Future<void> start() async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'openFiles') {
        _paths.add(List<String>.from(call.arguments as List));
      } else if (call.method == 'foldersChanged') {
        _changes.add(null);
      } else if (call.method == 'openError') {
        _paths.addError(call.arguments.toString());
      }
    });
    await channel.invokeMethod<void>('ready');
  }

  static Future<String?> pickFolder() =>
      channel.invokeMethod<String>('pickFolder');

  /// Asks for a folder the gallery will read where it is, rather than copy.
  /// Falls back to a copied folder when the choice is somewhere the phone
  /// will not let the app read directly, such as a cloud provider.
  static Future<String?> pickPictureFolder() =>
      channel.invokeMethod<String>('pickPictureFolder');

  /// Hands a HEIF photograph to the system decoder, writing a JPEG beside it.
  /// False when this platform has no decoder or the file cannot be read.
  static Future<bool> decodeHeif(String source, String target) async {
    if (!Platform.isAndroid) return false;
    final done = await channel.invokeMethod<bool>('decodeHeif', {
      'source': source,
      'target': target,
    });
    return done ?? false;
  }

  /// The phone's picture folders, after asking for permission to read them.
  /// Empty when the permission is refused, or when there are none.
  static Future<List<String>> pictureFolders() async {
    if (!Platform.isAndroid) return const [];
    final paths = await channel.invokeMethod<List<Object?>>('pictureFolders');
    return [for (final path in paths ?? const []) '$path'];
  }

  static Future<void> syncFolders(List<String> paths) async {
    if (Platform.isAndroid && paths.isNotEmpty) {
      await channel.invokeMethod<void>('syncFolders', paths);
    }
  }

  static Future<void> forgetFolder(String path) async {
    if (Platform.isAndroid) {
      await channel.invokeMethod<void>('forgetFolder', path);
    }
  }

  Future<void> dispose() async {
    if (Platform.isAndroid || Platform.isIOS) {
      channel.setMethodCallHandler(null);
    }
    await _paths.close();
    await _changes.close();
  }
}
