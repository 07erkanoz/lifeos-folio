import 'dart:async';
import 'dart:io';

import 'relay.dart';

/// `folio-canli --adres 10.0.0.1 --port 3021`: the relay for live documents
/// shared between offices (see relay.dart), behind Caddy on
/// canli.lifeos.com.tr.
Future<void> main(List<String> args) async {
  String? value(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final relay = await RelayServer.start(
    address: value('--adres') ?? '127.0.0.1',
    port: int.parse(value('--port') ?? '3021'),
    report: const Duration(hours: 1),
  );
  stdout.writeln('folio-canli dinliyor: ${relay.port}');
  final stop = Completer<void>();
  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
    signal.watch().listen((_) {
      if (!stop.isCompleted) stop.complete();
    });
  }
  await stop.future;
  await relay.close();
  exit(0);
}
