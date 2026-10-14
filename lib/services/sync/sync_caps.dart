/// What a Folio said of itself in one exchange: its protocol and the
/// capabilities it has.
typedef SyncSaid = ({int protocol, Set<String> caps});

/// What a Folio says it can do when it keeps things alike with another
/// (docs/senkron-plan.md R0, §4.1): its protocol, and the capabilities it
/// knows. A part whose format here needs a capability the other device
/// did not say it has is neither sent to it nor taken from it; the others
/// go on.
abstract final class SyncCaps {
  /// The version of the Senkron and office envelopes. 1: before any
  /// capability was said (a Folio that sends none is taken for it).
  static const protocol = 2;

  static const hlc = 'hlc';
  static const fieldVersions = 'alanSurumu';
  static const ledgerOps = 'defterIslemi';
  static const lifecycle = 'silmeOmru';
  static const proposals = 'oneri';
  static const secretNotes = 'notGizli';
  static const recall = 'geriCekme';
  static const sharedLedger = 'defterPaylasimi';
  static const split = 'paketBolme';

  /// What this Folio knows and says it has: each only once the feature
  /// using it is whole here (§5).
  static const known = {hlc, split, ledgerOps};

  /// The capabilities this Folio's own formats use now: a part needs of
  /// another device only those of its row in [matrix] that are here.
  /// Empty until a part's format changes (§5 steps 3 on).
  static Set<String> active = const {
    // The enforcement ledgers' records keep their groups' versions and
    // set-offs, and their movements are made of them (§5 step 4): an
    // older Folio would write them whole and send the movements back.
    ledgerOps,
  };

  /// What each part and channel needs when its format uses it (§4.1).
  static const matrix = <String, Set<String>>{
    'ajanda': {hlc, fieldVersions, lifecycle, ledgerOps, secretNotes},
    'muvekkil-buro': {
      hlc,
      fieldVersions,
      lifecycle,
      ledgerOps,
      secretNotes,
      recall,
      proposals,
    },
    'paylasilan-dosya': {recall},
    'paylasilan-defter': {
      recall,
      sharedLedger,
      hlc,
      fieldVersions,
      lifecycle,
      ledgerOps,
    },
    'gorev': {secretNotes, recall},
    'oneri': {proposals, hlc},
  };

  /// The capabilities [part] needs now: its row's that are in use here.
  static Set<String> needs(String part) =>
      (matrix[part] ?? const <String>{}).intersection(active);

  /// What [part] needs that [theirs] lacks; empty when it may go.
  static Set<String> missing(String part, Set<String> theirs) =>
      needs(part).difference(theirs);

  /// The envelope's words of this Folio.
  static Map<String, Object?> get said => {
    'surum': protocol,
    'yetenek': known.toList()..sort(),
  };

  /// What one says before the other has said anything.
  static const SyncSaid nothing = (protocol: 1, caps: <String>{});

  /// What [message] says the other Folio has: nothing when it says
  /// nothing, as one before capabilities did.
  static SyncSaid of(Map<Object?, Object?> message) {
    final version = message['surum'];
    final caps = message['yetenek'];
    return (
      protocol: version is num ? version.toInt() : 1,
      caps: {
        if (caps is List)
          for (final c in caps)
            if (c is String) c,
      },
    );
  }
}
