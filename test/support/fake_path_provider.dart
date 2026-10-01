import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('plugins.flutter.io/path_provider');

/// Answers path_provider from [root] for the rest of the test.
///
/// The plugin that normally answers is chosen by the host, not by the platform
/// a test says it is running on. A test that declares TargetPlatform.linux
/// sends app code down the Linux path, and on a Windows host nothing is
/// registered to answer it: the call reaches the bare method channel and
/// throws MissingPluginException. Answering here makes the test independent of
/// the machine it runs on, which is the point of declaring a platform at all.
/// The folder is its own, not the one the test is working in: the app writes
/// conversions and history into these paths and still holds them open when the
/// test reaches its teardown. Pointing them at the test's directory made
/// cleaning it up a race the test could lose, and on Windows losing it is a
/// failure rather than a shrug.
void useFakePathProvider([Directory? root]) {
  final base = root ?? Directory.systemTemp.createTempSync('folio-fake-paths-');
  if (root == null) {
    addTearDown(() async {
      for (var attempt = 0; attempt < 40; attempt++) {
        try {
          if (base.existsSync()) base.deleteSync(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    });
  }
  Directory make(String name) =>
      Directory('${base.path}${Platform.pathSeparator}$name')
        ..createSync(recursive: true);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        switch (call.method) {
          case 'getTemporaryDirectory':
            return make('temp').path;
          case 'getApplicationSupportDirectory':
            return make('support').path;
          case 'getApplicationDocumentsDirectory':
            return make('documents').path;
          case 'getApplicationCachePath':
            return make('cache').path;
          case 'getDownloadsDirectory':
            return make('downloads').path;
        }
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
}
