import 'dart:convert';

import 'portal_channel.dart';

/// The long readings the lawyer starts themselves
/// (docs/uyap-hedef-harita.md §6, §11.3): the first setup, which builds the
/// portfolio with its parties and documents' lists; the web's completion,
/// which brings what only the web gives; and the filling of the cases
/// listed but never read one by one, their list not read again.
enum UyapJobKind { setup, webCompletion, fill }

/// Where a job is: the list first, then the cases section by section.
enum UyapJobStage { list, parties, documents, web, done }

/// Why a job stopped before it was done.
enum UyapJobStop {
  /// Its channel's session ended: it goes on when the channel connects.
  session,

  /// The lawyer paused it: it waits for them.
  user,

  /// Cases were left that would not be read: it waits for the lawyer to
  /// try them again.
  incomplete,
}

/// A job the lawyer started, kept so that it goes on where it was: on the
/// channel it was started on and on no other, after the session ends or
/// Folio closes. How far its cases have come is not kept here but in the
/// cases' sections ([PortalDatabase.sections]): a case read is not read
/// again.
class UyapJob {
  const UyapJob({
    required this.kind,
    required this.channel,
    required this.stage,
    required this.started,
    this.stopped,
    this.listGaps = false,
    this.cases,
  });

  final UyapJobKind kind;
  final PortalChannel channel;
  final UyapJobStage stage;
  final DateTime started;
  final UyapJobStop? stopped;

  /// Its list did not come whole: the cases listed were read, and the
  /// lawyer is told to read the portfolio again.
  final bool listGaps;

  /// The cases it reads, by their keys, when not every open one: the fill's
  /// are those never read when it was started, kept so that a case read in
  /// its first stage is still read in its next.
  final Set<String>? cases;

  bool get done => stage == UyapJobStage.done;

  /// [stopped] is what is given: left out, the job runs.
  UyapJob copyWith({
    UyapJobStage? stage,
    UyapJobStop? stopped,
    bool? listGaps,
  }) => UyapJob(
    kind: kind,
    channel: channel,
    stage: stage ?? this.stage,
    started: started,
    stopped: stopped,
    listGaps: listGaps ?? this.listGaps,
    cases: cases,
  );

  String encode() => jsonEncode({
    'tur': kind.name,
    'kanal': channel.name,
    'asama': stage.name,
    'basladi': started.toIso8601String(),
    'durdu': ?stopped?.name,
    if (listGaps) 'listeEksik': true,
    'dosyalar': ?cases?.toList(),
  });

  static UyapJob? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      return UyapJob(
        kind: UyapJobKind.values.byName('${j['tur']}'),
        channel: PortalChannel.values.byName('${j['kanal']}'),
        stage: UyapJobStage.values.byName('${j['asama']}'),
        started: DateTime.parse('${j['basladi']}'),
        stopped: j['durdu'] == null
            ? null
            : UyapJobStop.values.byName('${j['durdu']}'),
        listGaps: j['listeEksik'] == true,
        cases: j['dosyalar'] is List
            ? {for (final k in j['dosyalar'] as List) '$k'}
            : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// How far the running job has come, for the screens.
class UyapJobProgress {
  const UyapJobProgress(this.stage, this.done, this.total);
  final UyapJobStage stage;
  final int done;
  final int total;
}
