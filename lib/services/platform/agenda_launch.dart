/// `--ajanda-yaz`: no window; LifeOS's agenda file written and its
/// requests kept, then Folio ends (LifeosAgendaWriter.runOnce).
const agendaWriteFlag = '--ajanda-yaz';

/// `--ajanda [uid]`: Folio opened at its agenda, at the record LifeOS's
/// notification centre or a hearing's notification named
/// (LifeosAgenda.uidOf). Without a uid, the agenda alone.
class AgendaLaunch {
  const AgendaLaunch([this.uid]);

  static const flag = '--ajanda';

  final String? uid;

  /// Null when [arguments] do not ask for the agenda. A uid that is not
  /// one (a path, another flag) is not taken for one.
  static AgendaLaunch? parse(List<String> arguments) {
    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      if (argument == '--') return null;
      if (argument.startsWith('$flag=')) {
        return AgendaLaunch(_uid(argument.substring(flag.length + 1)));
      }
      if (argument != flag) continue;
      return AgendaLaunch(
        i + 1 < arguments.length ? _uid(arguments[i + 1]) : null,
      );
    }
    return null;
  }

  static final _plain = RegExp(r'^[A-Za-z0-9._-]+$');

  static String? _uid(String s) =>
      _plain.hasMatch(s) && !s.startsWith('-') ? s : null;

  /// What the open Folio is handed when this one is started again.
  List<String> get arguments => [flag, ?uid];

  /// [arguments] without the agenda's: what is left for the documents.
  static List<String> without(List<String> arguments) {
    final out = <String>[];
    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      if (argument == '--') {
        out.addAll(arguments.sublist(i));
        break;
      }
      if (argument.startsWith('$flag=')) continue;
      if (argument == flag) {
        if (i + 1 < arguments.length && _uid(arguments[i + 1]) != null) i++;
        continue;
      }
      out.add(argument);
    }
    return out;
  }
}
