import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/clients/client.dart';
import '../../services/clients/client_accounts.dart';
import '../../services/editor/lawyer_profile.dart';
import '../../services/editor/petition_templates.dart'
    show PetitionCase, PetitionTemplate, enforcementRequests, trUpper;
import '../../services/enforcement/enforcement_ledger.dart';
import '../../services/enforcement/ledger_book.dart';
import '../../services/enforcement/ledger_service.dart';
import '../../services/enforcement/enforcement_papers.dart';
import '../../services/udf/udf_writer.dart';
import '../../services/uyap/uyap_case_links.dart';
import '../../services/uyap/uyap_web_service.dart' show UyapWebService;
import '../../models/document_model.dart';
import '../../services/notes/secret_notes.dart';
import '../../services/office/office_network.dart';
import '../../services/pdf/pdf_service.dart';
import '../../services/print/print_job.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/portal/portal_database.dart';
import '../../services/uyap/uyap_case_data.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../../services/uyap/uyap_enforcement.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../tools/interest_page.dart';
import '../widgets/proposals_view.dart';
import '../widgets/secret_note.dart';
import '../widgets/notice.dart';
import '../widgets/folio_dialog.dart';
import 'enforcement_ledger_dialog.dart';
import 'portfolio_rows.dart';
import '../theme/folio_palette.dart';

// Getters, not finals: a final would keep the theme it was first read in.
Color get _green => tone(const Color(0xFF1B6B3A));
Color get _purple => tone(const Color(0xFF5B3B9A));

/// "250.000,00" from lira.
/// Kuruş still held of [r]'s payment: what is held less its set-offs in
/// effect.
int _leftOf(ClientRecord r) {
  final state = LedgerBook.stateOf(r);
  return state.held - state.active.fold<int>(0, (n, s) => n + s.amount);
}

String _tl(double v) {
  final kurus = (v * 100).round();
  final s = lira(kurus.abs()).replaceAll(' TL', '');
  return '${kurus < 0 ? '−' : ''}${s.contains(',') ? s : '$s,00'}';
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// A day as UYAP writes one: "21.09.2026", "2026-09-21", or the web's
/// "Sep 21, 2026 10:50:00 PM".
/// This device's person in the office ([OfficeNetwork.me]); replaced
/// under test.
@visibleForTesting
String Function() ledgerMe = () => OfficeNetwork.instance.me;

/// An office person's name by their id; replaced under test.
@visibleForTesting
String Function(String person) ledgerNameOf = (person) =>
    OfficeNetwork.instance.ledger.member(person)?.name.trim() ?? '';

DateTime? uyapDay(String raw) {
  final en = RegExp(r'([A-Za-z]{3})\w* (\d{1,2}), (\d{4})').firstMatch(raw);
  if (en != null) {
    final m = _months[en.group(1)!.toLowerCase()];
    if (m != null) {
      return DateTime(int.parse(en.group(3)!), m, int.parse(en.group(2)!));
    }
  }
  return parseDay(raw);
}

/// UYAP's balance of an enforcement file, in lira: the account page's, else
/// the particulars' total less what was collected; null when neither says.
double? uyapLeftOf(UyapCaseRecord record) {
  final account = record.enforcement?.account ?? const UyapAccount();
  final facts = {for (final (k, v) in record.details.enforcement) k: v};
  final total = account.total ?? parseLira(facts['Alacak toplamı'] ?? '');
  final paid =
      account.paid ??
      record.money?.collected ??
      parseLira(facts['Yapılmış tahsilat'] ?? '');
  return account.left ?? (total != null && paid != null ? total - paid : null);
}

/// The parts of an enforcement file shown under its summary, one at a time.
enum _Section {
  payments('Ödemeler'),
  account('UYAP hesabı'),
  debtors('Borçlular'),
  course('Dosya seyri');

  const _Section(this.label);
  final String label;
}

/// An enforcement file (icra) as the lawyer follows it: where the debt
/// stands, its items, the money collected and paid out, its debtors and
/// its course, from what UYAP gave (docs: banaozel uyapweb.md §10).
class EnforcementView extends StatefulWidget {
  const EnforcementView({
    super.key,
    required this.record,
    required this.caseKey,
    required this.title,
    required this.database,
    this.lawyer = '',
    this.wide = true,
    this.onOpen,
    this.onLedger,
  });

  /// The file's own account read anew: for the page's heading.
  final ValueChanged<List<LedgerEntry>>? onLedger;

  final UyapCaseRecord? record;
  final String caseKey, title, lawyer;
  final Future<PortalDatabase> Function() database;
  final bool wide;

  /// A paper made here opened in the editor, to be read over, signed and
  /// sent.
  final ValueChanged<File>? onOpen;

  @override
  State<EnforcementView> createState() => _EnforcementViewState();
}

class _EnforcementViewState extends State<EnforcementView> {
  /// The payments out already written to a client's account, by their key.
  Set<String> _booked = const {};
  bool _allCourse = false;

  /// The file's own account in Folio: payments made outside the office and
  /// claims waived.
  List<LedgerEntry> _ledger = const [];

  /// Where each payment's money went, by its id: written to the client's
  /// account or not, and taken as a fee or held.
  Map<String, ({bool booked, MovementKind? target})> _bookings = const {};

  /// The part of the file shown under the summary, one at a time: the
  /// boxes side by side and one under another ran into each other.
  _Section _section = _Section.payments;

  /// What keeps the portals and the office alike: told, the view is read
  /// again (a payment shared changed, or taken off; R8).
  ChangeNotifier? _sync;

  Timer? _soon;

  /// Many changes at once (a sync's) read once, a moment after the last.
  void _changed() {
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 400), () {
      if (mounted) unawaited(_loadBooked());
    });
  }

  @override
  void initState() {
    super.initState();
    _sync = PortalSync.started?..addListener(_changed);
    unawaited(_loadBooked());
  }

  @override
  void dispose() {
    _soon?.cancel();
    _sync?.removeListener(_changed);
    super.dispose();
  }

  @override
  void didUpdateWidget(EnforcementView old) {
    super.didUpdateWidget(old);
    // UYAP read anew: a payment it now shows is official.
    if (old.record != widget.record) unawaited(_loadBooked());
  }

  /// The database, once read: for what was proposed of a colleague's.
  PortalDatabase? _proposalsDb;

  /// The case's accounts shared with this person, by their owner: read
  /// only, in no account of theirs (R8); and who stopped sharing one.
  Map<String, List<LedgerEntry>> _shared = const {};
  String? _sharedRemoved;

  Future<void> _loadBooked() async {
    final db = await widget.database();
    _proposalsDb = db;
    final read = readEnforcementBooks(
      db,
      widget.caseKey,
      widget.record?.money?.collections ?? const [],
    );
    _shared = read.shared;
    _sharedRemoved = read.sharedRemoved;
    if (mounted) {
      setState(() {
        _booked = read.booked;
        _ledger = read.ledger;
        _bookings = read.bookings;
      });
      widget.onLedger?.call(read.ledger);
    }
  }

  /// The file's client: its entry in the list and its card, made when it
  /// has none; null when no client of the lawyer's is in the file.
  Future<(ClientEntry, Client)?> _client(PortalDatabase db) async {
    final entry = db
        .clientEntries(lawyer: widget.lawyer)
        .where((e) => e.cases.any((c) => c.caseKey == widget.caseKey))
        .firstOrNull;
    if (entry == null) return null;
    var card = entry.client;
    if (card == null) {
      card = Client(
        id: Client.newId(),
        name: entry.name,
        updated: DateTime.now(),
        person: OfficeNetwork.instance.me,
      );
      db.saveClient(card);
    }
    return (entry, card);
  }

  /// The debtors by name: UYAP's list of them, else the file's parties
  /// who are debtors.
  List<String> get _debtorNames {
    final listed = [
      for (final d
          in widget.record?.enforcement?.debtors ?? const <UyapDebtor>[])
        if (d.name.isNotEmpty) titleName(d.name),
    ];
    if (listed.isNotEmpty) return listed;
    return [
      for (final p in widget.record?.parties ?? const [])
        if (UyapWebService.fold(p.role).contains('borclu')) titleName(p.name),
    ];
  }

  /// UYAP's balance in kuruş, as the account page or the particulars give
  /// it; null when neither does.
  int? get _uyapLeft {
    final record = widget.record;
    final left = record == null ? null : uyapLeftOf(record);
    return left == null ? null : (left * 100).round();
  }

  /// A payment made outside the office, or a claim waived, written: in
  /// the file's own account, the money in the client's (held, or taken as
  /// a fee), and the papers made.
  Future<void> _add(LedgerKind kind) async {
    final uyap = _uyapLeft;
    final left = folioLeft(uyap == null ? null : uyap / 100, _ledger);
    final input = await showDialog<LedgerInput>(
      context: context,
      builder: (_) => LedgerDialog(
        kind: kind,
        debtors: _debtorNames,
        left: left == null ? null : (left * 100).round(),
      ),
    );
    if (input == null || !mounted) return;
    final db = await widget.database();
    final client = await _client(db);
    // A file with no client of the lawyer's keeps its account with the
    // office's own book; its money goes in no client's account.
    final booked = kind == LedgerKind.external && client != null;
    // The line and its money in the client's account and Kasa, in one
    // transaction (docs/senkron-plan.md R3, R12).
    LedgerService(db).add(
      clientId: client?.$2.id ?? officeCashId,
      caseKey: widget.caseKey,
      kind: input.kind.code,
      amount: input.amount,
      at: input.at,
      by: widget.lawyer,
      person: OfficeNetwork.instance.me,
      debtor: input.debtor,
      way: input.way,
      note: input.note,
      noteSecret: input.noteSecret,
      whole: input.whole,
      uyapLeft: uyap,
      target: booked ? input.target : null,
    );
    await _loadBooked();
    if (!mounted) return;
    // Its papers are printed from its card when wanted ("Yazdır"); nothing
    // opens in the editor of itself.
    setState(() => _section = _Section.payments);
    showNotice(
      context,
      kind == LedgerKind.external
          ? 'Haricen tahsilat Folio hesabına yazıldı.'
          : 'Feragat Folio hesabına yazıldı.',
      detail: [
        if (kind == LedgerKind.external && booked)
          input.target == null
              ? 'Müvekkilin hesabına ve Kasa\'ya emanet olarak işlendi.'
              : 'Kasa\'ya ${input.target == MovementKind.toFee ? 'vekâlet ücreti' : 'karşı vekâlet ücreti'} olarak işlendi.',
        if (kind == LedgerKind.external && !booked)
          'Dosyanın müvekkili bulunamadığı için Kasa\'ya işlenmedi.',
        'Belgeleri ödemenin "Yazdır" düğmesinden yazdırabilirsiniz.',
      ].join(' '),
    );
  }

  /// The movements [e] put in the client's account and Kasa, still
  /// standing: the money held, and what of it was taken as a fee (then or
  /// later, from Kasa).
  ({List<ClientRecord> held, List<ClientRecord> applied}) _movementsOf(
    PortalDatabase db,
    LedgerEntry e,
  ) => _MovementIndex(db).of(e);

  /// Where [e]'s money was written: null for held for the client.
  MovementKind? _targetOf(PortalDatabase db, LedgerEntry e) {
    final applied = _movementsOf(db, e).applied.firstOrNull;
    return applied == null ? null : MovementKind.of(applied.data['hesap']);
  }

  /// A colleague's [e]: what this person would have of it, proposed to
  /// its owner (docs/senkron-plan.md R6); taken off when [remove].
  Future<void> _propose(LedgerEntry e, {bool remove = false}) async {
    final db = await widget.database();
    if (!mounted) return;
    final owner = _ownerOf(e);
    // What it is made seeing: the record as this screen shows it.
    final seen = {
      for (final x in LedgerBook.versionsOf(e.record).entries)
        x.key: '${x.value}',
    };
    final Map<String, Object?> fields;
    var reason = '';
    if (remove) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Silinmesini öner'),
          content: Text(
            'Kaydın sahibi $owner; onaylarsa kayıt Folio hesabından '
            'kaldırılır.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              key: const ValueKey('ledger-propose-remove-ok'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Öneriyi gönder'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      fields = const {};
    } else {
      final input = await showDialog<LedgerInput>(
        context: context,
        builder: (_) => LedgerDialog(
          kind: e.kind,
          debtors: _debtorNames,
          editing: e,
          proposeTo: owner,
        ),
      );
      if (input == null) return;
      reason = input.reason;
      fields = {
        if (input.amount != e.amount) 'tutar': input.amount,
        if (input.at != e.at) 'zaman': input.at.toIso8601String(),
        if (input.debtor != e.debtor) 'borclu': input.debtor,
        if (input.way != e.way) 'odeme': input.way,
        if (input.note != e.note && !e.noteSecret) 'aciklama': input.note,
        if (input.whole != e.whole) 'tamami': input.whole,
      };
      if (fields.isEmpty) {
        if (mounted) showNotice(context, 'Bir değişiklik yazılmadı.');
        return;
      }
    }
    final made = proposalsHere(db).propose(
      kind: 'icra',
      target: e.id,
      fields: fields,
      remove: remove,
      reason: reason,
      seen: seen,
    );
    if (!mounted) return;
    setState(() {});
    showNotice(
      context,
      made == null ? 'Öneri yapılamadı.' : 'Öneri gönderildi.',
      detail: made == null
          ? null
          : 'Kaydın sahibi $owner; onaylarsa kayda işlenir.',
    );
  }

  /// [e] corrected: its sum, day, debtor, way and note. A change of sum,
  /// day or where the money went takes back what it wrote in the client's
  /// account and Kasa, and writes it anew.
  Future<void> _edit(LedgerEntry e) async {
    if (_othersOf(e)) return;
    final db = await widget.database();
    final target = _targetOf(db, e);
    final uyap = _uyapLeft;
    final left = folioLeft(uyap == null ? null : uyap / 100, [
      for (final x in _ledger)
        if (x.id != e.id) x,
    ]);
    if (!mounted) return;
    final input = await showDialog<LedgerInput>(
      context: context,
      builder: (_) => LedgerDialog(
        kind: e.kind,
        debtors: _debtorNames,
        left: left == null ? null : (left * 100).round(),
        editing: e,
        target: target,
      ),
    );
    if (input == null || !mounted) return;
    // Its description made secret after the office had it: asked first (R7).
    if (input.noteSecret &&
        !e.noteSecret &&
        !await confirmSecretNote(context, db, 'aciklama:${e.record.id}')) {
      return;
    }
    if (!mounted) return;
    final money =
        input.amount != e.amount || input.at != e.at || input.target != target;
    // The line and its money, in one transaction; nothing written when it
    // changed meanwhile on another device (R12).
    final done = await _change(
      db,
      (book) => book.edit(
        e.record,
        amount: input.amount,
        at: input.at,
        debtor: input.debtor,
        way: input.way,
        note: input.note,
        noteSecret: input.noteSecret,
        whole: input.whole,
        target: input.target,
        shown: target,
      ),
    );
    if (!done || !mounted) return;
    showNotice(
      context,
      '${e.kind.label} düzeltildi.',
      detail: money && LedgerBook.books(e.record)
          ? 'Müvekkilin hesabı ve Kasa yeni tutara göre güncellendi.'
          : null,
    );
  }

  /// [change] made through the ledger's service, the view read again; a
  /// change refused (made meanwhile elsewhere, or waiting for its repair)
  /// told. Whether it was made.
  Future<bool> _change(
    PortalDatabase db,
    void Function(LedgerService book) change,
  ) async {
    String? refused;
    try {
      change(LedgerService(db));
    } on LedgerConflict catch (e) {
      refused = '$e';
    } on LedgerNeedsRepair catch (e) {
      refused = '$e';
    } on LedgerOverdrawn catch (e) {
      refused = '$e';
    } on LedgerNotYours catch (e) {
      refused = '$e';
    }
    await _loadBooked();
    if (refused != null && mounted) showNotice(context, refused);
    return refused == null;
  }

  /// Who the papers name: the office and the number, our side, the
  /// lawyer, the debtors.
  Future<EnforcementParties> _parties() async {
    final record = widget.record;
    final db = await widget.database();
    final profile = await LawyerProfile.load().catchError(
      (Object _) => const LawyerProfile(),
    );
    final lawyer = profile.lawyer?.titled.isNotEmpty ?? false
        ? profile.lawyer!.titled
        : widget.lawyer;
    final (ours, _) = splitParties(
      record?.parties ?? const [],
      lawyer,
      said: db.representation(widget.caseKey),
    );
    final client = await _client(db);
    return EnforcementParties(
      office: record?.court ?? '',
      number: record?.number ?? '',
      creditor: ours.isNotEmpty
          ? ours.map((p) => titleName(p.name)).join(', ')
          : titleName(client?.$1.name ?? ''),
      lawyer: lawyer,
      lawyerAddress: profile.address,
      debtors: _debtorNames,
    );
  }

  /// [e]'s request to the office, or the debtor's receipt: its name and
  /// its pages, filled from the file and the payment.
  Future<(String, DocModel)> _paperOf(
    LedgerEntry shown, {
    required bool receipt,
  }) async {
    // As it is kept now, whether its description is secret too (R7): what
    // came since the screen read it counts.
    final db = await widget.database();
    final e =
        ledgerOf(
          db,
          widget.caseKey,
        ).where((x) => x.id == shown.id).firstOrNull ??
        shown;
    final parties = await _parties();
    final DocModel model = receipt
        ? debtorReceipt(parties, e)
        : e.kind == LedgerKind.external
        ? externalPaymentRequest(parties, e)
        : waiverRequest(parties, e);
    final d = e.at;
    final day =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final name = receipt
        ? '$day Borçlu makbuzu ve ibraname'
        : e.kind == LedgerKind.external
        ? '$day Haricen tahsil bildirimi'
        : '$day Feragat dilekçesi';
    return (name, model);
  }

  /// [e]'s paper sent to the printer through the system's print screen,
  /// where it can be saved as PDF too; nothing opens in the editor.
  Future<void> _print(LedgerEntry e, {required bool receipt}) async {
    try {
      final (name, model) = await _paperOf(e, receipt: receipt);
      final bytes = await PdfService.modelToPdfBytes(model, title: name);
      await PrintJob.send(bytes, name: name);
    } catch (error) {
      if (mounted) {
        showNotice(
          context,
          'Belge yazdırılamadı: $error',
          kind: NoticeKind.error,
        );
      }
    }
  }

  /// [e]'s request to the office, or the debtor's receipt, written as UDF
  /// in the file's folder, tied to the file and opened in the editor.
  Future<File?> _paper(
    LedgerEntry e, {
    required bool receipt,
    bool open = true,
  }) async {
    final record = widget.record;
    if (record == null) return null;
    try {
      final (name, model) = await _paperOf(e, receipt: receipt);
      return await _write(name, model, link: !receipt, open: open);
    } catch (error) {
      if (mounted) {
        showNotice(
          context,
          'Belge hazırlanamadı: $error',
          kind: NoticeKind.error,
        );
      }
      return null;
    }
  }

  /// [model] written as [name].udf in the file's folder, tied to the file
  /// when it goes to the office ([link]), and opened in the editor.
  Future<File> _write(
    String name,
    DocModel model, {
    bool link = true,
    bool open = true,
  }) async {
    final record = widget.record!;
    await UyapSettings.instance.load();
    final folder = Directory(
      p.join(
        UyapSettings.instance.folder,
        UyapCaseStore.caseFolderName(record),
      ),
    );
    await folder.create(recursive: true);
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
    var file = File(p.join(folder.path, '$safe.udf'));
    for (var i = 2; await file.exists(); i++) {
      file = File(p.join(folder.path, '$safe ($i).udf'));
    }
    await file.writeAsBytes(UdfWriter.writeBytes(model), flush: true);
    if (link) await UyapCaseLinks.instance.link(file.path, record.link);
    if (open && mounted) widget.onOpen?.call(file);
    return file;
  }

  /// One of the ready requests, filled from the file and opened in the
  /// editor.
  Future<void> _request(PetitionTemplate t) async {
    final record = widget.record;
    if (record == null) return;
    try {
      final profile = await LawyerProfile.load().catchError(
        (Object _) => const LawyerProfile(),
      );
      final lawyer = profile.lawyer?.titled.isNotEmpty ?? false
          ? profile.lawyer!.titled
          : widget.lawyer;
      final parties = [
        for (final party in record.parties) (party.role, party.name),
      ];
      // UYAP's debtors list when the parties name none.
      if (!parties.any((x) => UyapWebService.fold(x.$1).contains('borclu'))) {
        for (final d in _debtorNames) {
          parties.add(('Borçlu', d));
        }
      }
      final now = DateTime.now();
      final model = t.build(
        PetitionCase(
          court: record.court,
          number: record.number,
          lawyer: lawyer.isEmpty ? null : lawyer,
          parties: parties,
        ),
        now,
      );
      final day =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final file = await _write('$day ${t.name}', model);
      if (mounted && widget.onOpen == null) {
        showNotice(context, '${t.name} hazırlandı.', detail: file.path);
      }
    } catch (error) {
      if (mounted) {
        showNotice(
          context,
          'Talep hazırlanamadı: $error',
          kind: NoticeKind.error,
        );
      }
    }
  }

  /// The ready requests by what they are for, as the lawyer looks for
  /// one.
  static const _requestGroups = [
    (
      'Tebligat ve kesinleşme',
      Icons.mark_email_read_outlined,
      [
        'Takibin kesinleştirilmesi',
        'Adres araştırması ve MERNİS adresine tebligat',
        'Tebligatın TK m.35’e göre yapılması',
      ],
    ),
    (
      'Haciz',
      Icons.gavel_rounded,
      [
        'Maaş haczi',
        'Araç haczi ve yakalama şerhi',
        'Taşınmaz haczi',
        'Adreste menkul haczi',
      ],
    ),
    (
      'Haciz ihbarnamesi',
      Icons.account_balance_outlined,
      [
        'Bankalara haciz ihbarnamesi (89/1)',
        'Üçüncü kişiye haciz ihbarnamesi (89/1)',
        'İkinci haciz ihbarnamesi (89/2)',
        'Üçüncü haciz ihbarnamesi (89/3)',
      ],
    ),
    (
      'Muhafaza ve satış',
      Icons.inventory_2_outlined,
      ['Muhafaza', 'Kıymet takdiri', 'Satış talebi'],
    ),
    (
      'Para ve dosya',
      Icons.request_quote_outlined,
      [
        'Dosya hesabı',
        'Paranın ödenmesi (reddiyat)',
        'Takibin yenilenmesi',
        'Aciz vesikası',
      ],
    ),
  ];

  /// When each ready request is the one to make, in a few words.
  static const _requestHints = {
    'Takibin kesinleştirilmesi':
        'Ödeme emri tebliğ edildi, süresinde itiraz yok.',
    'Adres araştırması ve MERNİS adresine tebligat':
        'Tebligat bila tebliğ döndü.',
    'Tebligatın TK m.35’e göre yapılması':
        'Borçlu adresini değiştirip bildirmedi.',
    'Maaş haczi': 'Borçlu bir işyerinde çalışıyor (SGK).',
    'Araç haczi ve yakalama şerhi': 'Borçlu adına kayıtlı araç var.',
    'Taşınmaz haczi': 'Borçlu adına kayıtlı taşınmaz var.',
    'Adreste menkul haczi': 'Borçlunun adresinde haczedilecek mal var.',
    'Bankalara haciz ihbarnamesi (89/1)': 'Borçlunun bütün banka hesaplarına.',
    'Üçüncü kişiye haciz ihbarnamesi (89/1)':
        'Borçlunun bir kişide ya da şirkette alacağı var.',
    'İkinci haciz ihbarnamesi (89/2)':
        'Birinci ihbarnameye yedi günde cevap gelmedi.',
    'Üçüncü haciz ihbarnamesi (89/3)': 'İkinci ihbarnameden sonra.',
    'Muhafaza': 'Haczedilen mal yediemine teslim edilsin.',
    'Kıymet takdiri': 'Haczedilen malın değeri belirlensin.',
    'Satış talebi': 'Kıymet takdiri kesinleşti.',
    'Dosya hesabı': 'Güncel borç dökümü istenir.',
    'Paranın ödenmesi (reddiyat)': 'Dosyada tahsil edilen para var.',
    'Takibin yenilenmesi': 'Dosya bir yıldır işlemsiz.',
    'Aciz vesikası': 'Haczi kabil mal bulunamadı.',
  };

  /// The requests the file's state calls for, each with why, at most
  /// three: money waiting in the file, a debtor not reached, a file left
  /// idle; else the ones made most.
  List<(PetitionTemplate, String)> _suggested() {
    final record = widget.record;
    final byName = {for (final t in enforcementRequests) t.name: t};
    final out = <(PetitionTemplate, String)>[];
    void add(String name, String why) {
      final t = byName[name];
      if (t != null && !out.any((x) => x.$1 == t)) out.add((t, why));
    }

    if (record != null) {
      final m = record.money;
      final waiting =
          m?.remaining ??
          (m?.collected != null && m?.paidOut != null
              ? m!.collected! - m.paidOut!
              : null);
      if (waiting != null && waiting >= 1) {
        add(
          'Paranın ödenmesi (reddiyat)',
          'Dosyada ${_tl(waiting)} TL bekliyor.',
        );
      }
      final unreached =
          (record.enforcement?.debtors ?? const <UyapDebtor>[]).any(
            (d) => d.moved,
          ) ||
          record.documents.any((d) {
            final f = UyapWebService.fold('${d.type} ${d.title}');
            return f.contains('bila') || f.contains('teblig edilemedi');
          });
      if (unreached) {
        add(
          'Adres araştırması ve MERNİS adresine tebligat',
          'Borçluya ulaşılamamış ya da adresi değişmiş.',
        );
      }
      final last = [for (final d in record.documents) ?d.date]
          .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
      if (last != null && DateTime.now().difference(last).inDays > 330) {
        add('Takibin yenilenmesi', 'Son işlem bir yıla yakın önce.');
      }
    }
    for (final name in const [
      'Bankalara haciz ihbarnamesi (89/1)',
      'Maaş haczi',
      'Araç haczi ve yakalama şerhi',
    ]) {
      if (out.length >= 3) break;
      add(name, 'Sık kullanılan talep.');
    }
    return out.take(3).toList();
  }

  /// The ready requests in a window of their own: looked for by name or
  /// by what they are for, by group, each with when it is the one.
  Future<void> _pickRequest() async {
    final byName = {for (final t in enforcementRequests) t.name: t};
    final grouped = {for (final (_, _, names) in _requestGroups) ...names};
    final groups = [
      for (final (title, icon, names) in _requestGroups)
        (title, icon, [for (final n in names) ?byName[n]]),
      (
        'Diğer',
        Icons.description_outlined,
        [
          for (final t in enforcementRequests)
            if (!grouped.contains(t.name)) t,
        ],
      ),
    ].where((g) => g.$3.isNotEmpty).toList();
    // The words typed: no controller to outlive the window's closing.
    var typed = '';
    final picked = await showDialog<PetitionTemplate>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final q = UyapWebService.fold(typed.trim());
          bool fits(PetitionTemplate t) =>
              q.isEmpty ||
              UyapWebService.fold('${t.name} ${_requestHints[t.name] ?? ''}')
                  .contains(q);
          final shown = [
            for (final (title, icon, list) in groups)
              if (list.where(fits).isNotEmpty)
                (title, icon, list.where(fits).toList()),
          ];
          return FolioDialog(
            title: 'Talep hazırla',
            subtitle: widget.title,
            icon: Icons.post_add_rounded,
            width: 560,
            onClose: () => Navigator.pop(context),
            footerNote: Text(
              'Daire, esas no, alacaklı, vekil ve borçlular dosyadan dolar; '
              'köşeli parantezli yerleri editörde doldurup e-imzayla '
              'UYAP’a gönderebilirsiniz.',
              style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('request-search'),
                  autofocus: true,
                  onChanged: (v) => setState(() => typed = v),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    hintText: 'Talep ara: maaş, banka, tebligat…',
                  ),
                ),
                const SizedBox(height: 8),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Bu sözcükle bir talep yok.',
                      style: TextStyle(color: AgendaColors.muted),
                    ),
                  ),
                for (final (title, icon, list) in shown) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
                    child: Row(
                      children: [
                        Icon(icon, size: 15, color: AgendaColors.muted),
                        const SizedBox(width: 6),
                        Text(
                          trUpper(title),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .5,
                            color: AgendaColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final t in list)
                    ListTile(
                      key: ValueKey('request-${t.name}'),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      leading: Icon(
                        Icons.description_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(
                        t.name,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: _requestHints[t.name] == null
                          ? null
                          : Text(_requestHints[t.name]!),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                      ),
                      onTap: () => Navigator.pop(context, t),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
    if (picked != null) await _request(picked);
  }

  /// [e] marked as told to the office (icra müdürlüğü) today, or not yet.
  Future<void> _markReported(LedgerEntry e, bool reported) async {
    if (_othersOf(e)) return;
    final db = await widget.database();
    await _change(
      db,
      (book) => book.setReported(e.record, reported ? DateTime.now() : null),
    );
  }

  /// [e] marked as UYAP shows it, or not yet.
  Future<void> _markOfficial(LedgerEntry e, bool official) async {
    if (_othersOf(e)) return;
    final db = await widget.database();
    // The lawyer's word, kept apart from what UYAP is matched to (R4).
    await _change(db, (book) => book.setOfficial(e.record, official));
  }

  /// [e] taken off the file's account, and the money it put in the
  /// client's account and Kasa with it (R3, R5).
  Future<void> _removeEntry(LedgerEntry e) async {
    if (_othersOf(e)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${e.kind.label} kaldırılsın mı?'),
        content: const Text(
          'Folio hesabından çıkar; müvekkil hesabına ve Kasa\'ya yazılan '
          'tutarlar da kalkar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const ValueKey('ledger-remove-ok'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final db = await widget.database();
    if (await _change(db, (book) => book.setRemoved(e.record, true)) &&
        mounted) {
      showNotice(context, '${e.kind.label} kaldırıldı.');
    }
  }

  /// Whether a payment out of [kind] passes the claim on (to the creditor
  /// or their lawyer), not a cost of the file.
  static bool _forTheClaim(String kind) {
    final k = kind
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c');
    if (k.isEmpty || k == 'diger') return false;
    return !RegExp(
      r'posta|masraf|harc|tebligat|bilirki|yediemin|gider|avans|ucret',
    ).hasMatch(k);
  }

  String _keyOf(UyapMoneyItem p) =>
      'uyap-reddiyat:${widget.caseKey}:${p.receipt.isNotEmpty ? p.receipt : '${p.date}|${p.amount}'}';

  /// A payment out of the file written to its client's account: money
  /// held for the client, or the fee the court gave the lawyer.
  Future<void> _book(UyapMoneyItem p) async {
    final db = await widget.database();
    final entry = db
        .clientEntries(lawyer: widget.lawyer)
        .where((e) => e.cases.any((c) => c.caseKey == widget.caseKey))
        .firstOrNull;
    if (!mounted) return;
    if (entry == null) {
      showNotice(
        context,
        'Bu dosyanın müvekkili bulunamadı.',
        detail: 'Müvekkiller sayfasında dosyayı müvekkile ekleyin.',
      );
      return;
    }
    final kind = await showDialog<MovementKind>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('${_tl(p.amount)} TL · ${titleName(entry.name)}'),
        children: [
          SimpleDialogOption(
            key: const ValueKey('book-trust'),
            onPressed: () => Navigator.pop(context, MovementKind.advanceIn),
            child: const ListTile(
              title: Text('Emanet: müvekkile ait'),
              subtitle: Text('Tahsil edilen alacak; müvekkile ödenecek.'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, MovementKind.counterFee),
            child: const ListTile(
              title: Text('Karşı vekâlet ücreti: avukata ait'),
              subtitle: Text('Büronun geliri olarak yazılır.'),
            ),
          ),
        ],
      ),
    );
    if (kind == null) return;
    var card = entry.client;
    if (card == null) {
      card = Client(
        id: Client.newId(),
        name: entry.name,
        updated: DateTime.now(),
        person: OfficeNetwork.instance.me,
      );
      db.saveClient(card);
    }
    final at = uyapDay(p.date) ?? DateTime.now();
    final now = DateTime.now();
    db.saveClientRecord(
      ClientRecord(
        id: Client.newId(),
        clientId: card.id,
        kind: ClientRecordKind.movement,
        data: {
          'dosya': widget.caseKey,
          'hesap': kind.code,
          'tutar': (p.amount * 100).round(),
          'zaman': at.toIso8601String(),
          'aciklama': [
            'UYAP reddiyatı',
            if (p.kind.isNotEmpty) p.kind,
            if (p.receipt.isNotEmpty) 'makbuz ${p.receipt}',
          ].join(' · '),
          'odeme': 'Havale / EFT',
          'kaynak': _keyOf(p),
        },
        created: now,
        by: widget.lawyer,
        updated: now,
        locked: true,
        person: OfficeNetwork.instance.me,
      ),
    );
    await _loadBooked();
    if (mounted) {
      showNotice(
        context,
        kind == MovementKind.advanceIn
            ? 'Emanet olarak müvekkil hesabına yazıldı.'
            : 'Karşı vekâlet ücreti olarak yazıldı.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    if (record == null) {
      // Not read from UYAP yet: what was paid outside or waived is the
      // office's own, written and corrected all the same.
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Dosya henüz UYAP\'tan çekilmedi. "UYAP\'tan tazele" ile borç '
              'hesabı, tahsilatlar ve borçlular gelir.',
              style: TextStyle(color: AgendaColors.muted),
            ),
            const SizedBox(height: 12),
            _payments([
              for (final e in _ledger)
                if (!e.isOfficial) e,
            ], adding: true),
          ],
        ),
      );
    }
    final e = record.enforcement;
    final account = e?.account ?? const UyapAccount();
    final facts = {for (final (k, v) in record.details.enforcement) k: v};
    double? fact(String k) => parseLira(facts[k] ?? '');
    // Without the account page, the particulars' sums.
    final total = account.total ?? fact('Alacak toplamı');
    final paid =
        account.paid ?? record.money?.collected ?? fact('Yapılmış tahsilat');
    final left =
        account.left ?? (total != null && paid != null ? total - paid : null);
    final pending = [
      for (final e in _ledger)
        if (!e.isOfficial) e,
    ];
    final summary = _summary(
      total: total,
      paid: paid,
      left: left,
      pending: pending,
      fromAccount: e?.lines.isNotEmpty ?? false,
      fetchedAt: record.fetchedAt,
    );
    final details = _box('ALACAK HESABI', right: 'UYAP', [
      _columns([
        _lines(
          'ALACAK KALEMLERİ',
          account.items.isNotEmpty
              ? [for (final l in account.items) (l.title, l.amount)]
              : [
                  for (final k in const [
                    'Faiz',
                    'Takip sonrası masraf',
                    'Vekâlet ücreti',
                  ])
                    if (fact(k) != null) (k, fact(k)),
                ],
        ),
        _lines(
          'HARÇ VE VERGİLER',
          account.fees.isNotEmpty
              ? [for (final l in account.fees) (l.title, l.amount)]
              : [
                  if (fact('Tahsil harcı') != null)
                    ('Tahsil harcı', fact('Tahsil harcı')),
                ],
          total: true,
        ),
      ]),
    ]);
    const gap = SizedBox(height: 12, width: 12);
    final debtorList = e?.debtors ?? const <UyapDebtor>[];
    // One part at a time under the summary, chosen by its button; the
    // payments first, which the office writes and follows itself.
    final shown = switch (_section) {
      _Section.payments => _payments(pending),
      _Section.account =>
        widget.wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: details),
                  gap,
                  Expanded(flex: 2, child: _money(record.money)),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [details, gap, _money(record.money)],
              ),
      _Section.debtors => _debtors(debtorList),
      _Section.course => _course(record),
    };
    return Padding(
      padding: EdgeInsets.all(widget.wide ? 14 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          summary,
          gap,
          _sections({
            _Section.payments: _ledger.length,
            _Section.debtors: debtorList.length,
          }),
          gap,
          shown,
        ],
      ),
    );
  }

  /// The buttons the parts are chosen by, each with how many it holds.
  Widget _sections(Map<_Section, int> counts) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('enforcement-sections'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tone(const Color(0xFFF1F3F6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final s in _Section.values)
            Expanded(
              child: Material(
                color: s == _section ? scheme.surface : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: s == _section
                      ? BorderSide(color: AgendaColors.line)
                      : BorderSide.none,
                ),
                child: InkWell(
                  key: ValueKey('enforcement-section-${s.name}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _section = s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Text(
                      [
                        s.label,
                        if ((counts[s] ?? 0) > 0) '${counts[s]}',
                      ].join(' · '),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: s == _section
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: s == _section ? null : AgendaColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Where the debt stands, at the top: what is left as Folio counts it
  /// first, UYAP's figures beside it; how much is collected, and what was
  /// paid outside the office and waits for UYAP; and what is done most.
  Widget _summary({
    required double? total,
    required double? paid,
    required double? left,
    required List<LedgerEntry> pending,
    required bool fromAccount,
    required DateTime fetchedAt,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final waiting = pending.fold<int>(0, (n, e) => n + e.amount) / 100;
    final ours = folioLeft(left, _ledger);
    final whole = total ?? ((paid ?? 0) + (left ?? 0));
    final paidShare = whole > 0 && paid != null
        ? (paid / whole).clamp(0.0, 1.0)
        : null;
    final waitShare = whole > 0
        ? (waiting / whole).clamp(0.0, 1.0 - (paidShare ?? 0))
        : 0.0;
    String pct(double v) =>
        '%${(v * 100).toStringAsFixed(1).replaceAll('.', ',')}';
    final muted = TextStyle(fontSize: 12, color: AgendaColors.muted);

    final hero = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          pending.isEmpty ? 'KALAN BORÇ' : "KALAN BORÇ · FOLIO'YA GÖRE",
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .5,
            color: AgendaColors.muted,
          ),
        ),
        const SizedBox(height: 2),
        KeyedSubtree(
          key: pending.isEmpty
              ? const ValueKey('enforcement-left')
              : const ValueKey('enforcement-folio-left'),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              (pending.isEmpty ? left : ours) == null
                  ? '—'
                  : '${_tl((pending.isEmpty ? left : ours)!)} TL',
              style: TextStyle(
                fontSize: 30,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: AgendaColors.deadlineText,
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          pending.isEmpty
              ? '${fromAccount ? 'UYAP hesap bilgileri' : 'UYAP künyesi'} · '
                    '${dayText(fetchedAt)}'
              : "UYAP'ta ${left == null ? '—' : '${_tl(left)} TL'} · "
                    '${_tl(waiting)} TL UYAP\'a işlenmeyi bekliyor',
          style: muted,
        ),
      ],
    );
    Widget stat(String label, double? v, Color? color) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: muted),
        Text(
          v == null ? '—' : '${_tl(v)} TL',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: v == null ? AgendaColors.muted : color,
          ),
        ),
      ],
    );
    final stats = Wrap(
      spacing: 28,
      runSpacing: 10,
      children: [
        stat('Toplam alacak', total, null),
        stat('Tahsil edilen', paid, _green),
        if (pending.isNotEmpty)
          stat('Haricen (bekliyor)', waiting, AgendaColors.taskText),
      ],
    );
    final bar = paidShare == null
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  height: 10,
                  child: Row(
                    children: [
                      // A share too small for a flex of one is not drawn:
                      // an Expanded of flex 0 is no flex at all.
                      if ((paidShare * 1000).round() > 0)
                        Expanded(
                          flex: (paidShare * 1000).round(),
                          child: ColoredBox(
                            color: tone(const Color(0xFF3E9C6B)),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      if ((waitShare * 1000).round() > 0)
                        Expanded(
                          flex: (waitShare * 1000).round(),
                          child: ColoredBox(
                            color: tone(const Color(0xFFE0A33A)),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      if (((1 - paidShare - waitShare) * 1000).round() > 0)
                        Expanded(
                          flex: ((1 - paidShare - waitShare) * 1000).round(),
                          child: ColoredBox(
                            color: tone(const Color(0xFFEEF0F4)),
                            child: const SizedBox.expand(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  '${pct(paidShare)} tahsil edildi',
                  if (waitShare > 0) '${pct(waitShare)} haricen (bekliyor)',
                ].join(' · '),
                style: muted,
              ),
            ],
          );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          key: const ValueKey('ledger-add-external'),
          onPressed: () => _add(LedgerKind.external),
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: const Text('Haricen tahsilat'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('ledger-add-waiver'),
          onPressed: () => _add(LedgerKind.waiver),
          icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
          label: const Text('Feragat'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('enforcement-interest'),
          onPressed: () {
            final account =
                widget.record?.enforcement?.account ?? const UyapAccount();
            final base = [
              for (final l in account.items)
                if (RegExp(r'asil|kesinles')
                    .hasMatch(l.label.toLowerCase().replaceAll('ı', 'i')))
                  l,
            ].firstOrNull;
            InterestPage.open(
              context,
              title: widget.title,
              principal: base?.amount == null
                  ? null
                  : (base!.amount! * 100).round(),
              from: parseDay(widget.record?.details.openedOn),
            );
          },
          icon: const Icon(Icons.percent_rounded, size: 18),
          label: const Text('Güncel borcu hesapla'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('enforcement-requests'),
          onPressed: _pickRequest,
          icon: const Icon(Icons.post_add_rounded, size: 18),
          label: const Text('Talep hazırla'),
        ),
      ],
    );
    final suggested = _suggested();
    final suggestions = suggested.isEmpty
        ? null
        : Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Önerilen talepler', style: muted),
              const SizedBox(width: 2),
              for (final (t, why) in suggested)
                Tooltip(
                  message: why,
                  child: ActionChip(
                    key: ValueKey('request-suggest-${t.name}'),
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      Icons.auto_awesome_outlined,
                      size: 15,
                      color: scheme.primary,
                    ),
                    label: Text(t.name, style: const TextStyle(fontSize: 12.5)),
                    onPressed: () => _request(t),
                  ),
                ),
            ],
          );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AgendaColors.line),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final roomy = box.maxWidth >= 760;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (roomy)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: hero),
                    const SizedBox(width: 24),
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: stats,
                    ),
                  ],
                )
              else ...[
                hero,
                const SizedBox(height: 12),
                stats,
              ],
              const SizedBox(height: 14),
              bar,
              const SizedBox(height: 14),
              actions,
              if (suggestions != null) ...[
                const SizedBox(height: 10),
                suggestions,
              ],
            ],
          );
        },
      ),
    );
  }

  /// The payments made outside the office and the claims waived, each on a
  /// card of its own: what it was, where it stands (written in Folio, told
  /// to the office, shown by UYAP), and its papers printed, it corrected or
  /// taken off from its own buttons. [adding] puts the buttons that write a
  /// new one here too, for a file with no summary above.
  Widget _payments(List<LedgerEntry> pending, {bool adding = false}) {
    final unreported = [
      for (final e in pending)
        if (!e.isReported) e,
    ];
    int sum(Iterable<LedgerEntry> list) =>
        list.fold<int>(0, (n, e) => n + e.amount);
    Widget total(String label, int kurus, Color ink, Color fill, Key key) =>
        Container(
          key: key,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: TextStyle(fontSize: 13, color: ink)),
              ),
              Text(
                '${_tl(kurus / 100)} TL',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ],
          ),
        );
    return Column(
      key: const ValueKey('enforcement-payments'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Büroya yapılan ödemeler ve feragat',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            if (adding || _ledger.isEmpty) ...[
              OutlinedButton.icon(
                key: const ValueKey('ledger-box-add-external'),
                onPressed: () => _add(LedgerKind.external),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Haricen tahsilat'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const ValueKey('ledger-box-add-waiver'),
                onPressed: () => _add(LedgerKind.waiver),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Feragat'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (_ledger.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AgendaColors.line),
            ),
            child: Text(
              'Borçlunun büroya doğrudan yaptığı ödemeler ve feragatler '
              'burada, her biri kendi kartında durur: icra müdürlüğüne '
              'bildirilip bildirilmediği izlenir, belgeleri yazdırılır, '
              'düzenlenir ya da silinir.',
              style: TextStyle(fontSize: 13, color: AgendaColors.muted),
            ),
          )
        else
          for (final e in _ledger.reversed) ...[
            _paymentCard(e),
            const SizedBox(height: 10),
          ],
        if (unreported.isNotEmpty)
          total(
            "Müdürlüğe bildirilmeyi bekleyen (${unreported.length})",
            sum(unreported),
            AgendaColors.taskText,
            tone(const Color(0xFFFDF4E6)),
            const ValueKey('ledger-unreported'),
          ),
        if (pending.length > unreported.length)
          total(
            "Bildirildi, UYAP'ta görünmeyi bekleyen "
            "(${pending.length - unreported.length})",
            sum(pending) - sum(unreported),
            AgendaColors.muted,
            tone(const Color(0xFFF1F3F6)),
            const ValueKey('ledger-reported-waiting'),
          ),
        const SizedBox(height: 8),
        Text(
          'Ödeme UYAP\'ta aynı tutarda bir tahsilat olarak görününce '
          'kendiliğinden "UYAP\'ta" olur ve Folio\'daki borçtan bir daha '
          'düşülmez.',
          style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
        ),
        // A colleague's account of this case, the case shared with this
        // person who may see the money (R8): apart, read only.
        for (final MapEntry(key: owner, value: entries) in _shared.entries)
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              key: ValueKey('shared-ledger-$owner'),
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: AgendaColors.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Folio hesabı · ${ledgerNameOf(owner)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'salt okunur',
                  style: TextStyle(fontSize: 12, color: AgendaColors.muted),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Text(
                'Kasanıza ve müvekkil hesaplarınıza katılmaz. Bir yanlış '
                'görürseniz önerin.',
                style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
              ),
            ),
            for (final e in entries.reversed) ...[
              _paymentCard(e),
              const SizedBox(height: 10),
            ],
            if (folioLeft(_uyapLeft == null ? null : _uyapLeft! / 100, entries)
                case final left?)
              total(
                "Folio'ya göre kalan",
                (left * 100).round(),
                AgendaColors.hearingText,
                AgendaColors.hearingFill,
                ValueKey('shared-ledger-left-$owner'),
              ),
          ],
        if (_sharedRemoved case final who?)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              '$who bu dosyanın Folio hesabını artık paylaşmıyor; hesap bu '
              'cihazdan silindi.',
              key: const ValueKey('shared-ledger-removed'),
              style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
            ),
          ),
      ],
    );
  }

  /// One payment or waiver: its sum and what it was, where it stands, and
  /// its buttons.
  /// Whether [e] is another person's of the office: shown, and changed
  /// only by them (docs/senkron-plan.md R6).
  static bool _othersOf(LedgerEntry e) {
    final owner = e.record.person, me = ledgerMe();
    return owner.isNotEmpty && me.isNotEmpty && owner != me;
  }

  /// [e]'s owner by name, as the office knows them.
  static String _ownerOf(LedgerEntry e) => ledgerNameOf(e.record.person);

  Widget _paymentCard(LedgerEntry e) {
    final scheme = Theme.of(context).colorScheme;
    final others = _othersOf(e);
    final owner = _ownerOf(e).isEmpty ? 'bir meslektaşınız' : _ownerOf(e);
    final external = e.kind == LedgerKind.external;
    final ink = external ? _green : _purple;
    final fill = external
        ? tone(const Color(0xFFE6F4EC))
        : tone(const Color(0xFFEFE9FA));
    final booking = _bookings[e.id];
    final where = !external || booking == null || !booking.booked
        ? null
        : switch (booking.target) {
            MovementKind.toFee => 'vekâlet ücretine mahsup',
            MovementKind.toCounterFee => 'karşı vekâlet ücretine mahsup',
            _ => 'emanete yazıldı',
          };
    final line = [
      dayText(e.at),
      e.debtor.isNotEmpty ? e.debtor : 'Bütün borçlular',
      if (e.way.isNotEmpty) e.way,
      if (e.whole) 'borcun tamamı',
      ?where,
      if (e.note.isNotEmpty) e.noteSecret ? '${e.note} (gizli not)' : e.note,
    ].join(' · ');
    final reported = e.reported;
    Widget step(String text, Color dot, {Color? color, Key? key}) => Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12.5, color: color)),
      ],
    );
    Widget arrow() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Icon(
        Icons.chevron_right_rounded,
        size: 16,
        color: AgendaColors.muted,
      ),
    );
    Widget small(String text, VoidCallback onPressed, Key key) => TextButton(
      key: key,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 12.5),
      ),
      child: Text(text),
    );
    final print = PopupMenuButton<String>(
      key: ValueKey('ledger-print-${e.id}'),
      tooltip: 'Belgeyi yazdır',
      onSelected: (v) => switch (v) {
        'makbuz' => _print(e, receipt: true),
        'editor' => _paper(e, receipt: false),
        _ => _print(e, receipt: false),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'talep',
          child: Text(
            external ? 'Haricen tahsil bildirimi' : 'Feragat dilekçesi',
          ),
        ),
        if (external)
          const PopupMenuItem(
            value: 'makbuz',
            child: Text('Borçluya makbuz ve ibraname'),
          ),
        if (widget.record != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'editor',
            child: Text(
              external
                  ? 'Bildirimi editörde düzenleyerek aç'
                  : 'Dilekçeyi editörde düzenleyerek aç',
            ),
          ),
        ],
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outline),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.print_outlined, size: 17),
            SizedBox(width: 6),
            Text('Yazdır', style: TextStyle(fontSize: 13)),
            Icon(Icons.arrow_drop_down_rounded, size: 18),
          ],
        ),
      ),
    );
    return Container(
      key: ValueKey('ledger-${e.id}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AgendaColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
                child: Icon(
                  external
                      ? Icons.payments_outlined
                      : Icons.remove_circle_outline_rounded,
                  size: 20,
                  color: ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${_tl(e.amount / 100)} TL',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: fill,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            e.kind.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      line,
                      style: TextStyle(fontSize: 13, color: AgendaColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              print,
              if (others) ...[
                const SizedBox(width: 8),
                Container(
                  key: ValueKey('ledger-owner-${e.id}'),
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F3F7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 14,
                        color: AgendaColors.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Yazan: $owner',
                        style: TextStyle(
                          fontSize: 12,
                          color: AgendaColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                IconButton(
                  key: ValueKey('ledger-edit-${e.id}'),
                  tooltip: 'Düzenle',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => unawaited(_edit(e)),
                ),
                IconButton(
                  key: ValueKey('ledger-remove-${e.id}'),
                  tooltip: 'Sil',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: scheme.error,
                  ),
                  onPressed: () => unawaited(_removeEntry(e)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: AgendaColors.line),
          const SizedBox(height: 6),
          // Where it stands: written here, told to the office, shown by
          // UYAP; the lawyer marks the second, UYAP (or the lawyer, for a
          // waiver UYAP does not list) the third.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              step("Folio'ya yazıldı", _green),
              arrow(),
              if (reported != null) ...[
                step(
                  'Müdürlüğe bildirildi · ${dayText(reported)}',
                  _green,
                  key: ValueKey('ledger-reported-${e.id}'),
                ),
                if (!e.isOfficial && !others)
                  small(
                    'Geri al',
                    () => unawaited(_markReported(e, false)),
                    ValueKey('ledger-unreport-${e.id}'),
                  ),
              ] else ...[
                step(
                  'Müdürlüğe bildirilmedi',
                  AgendaColors.taskText,
                  color: AgendaColors.taskText,
                  key: ValueKey('ledger-not-reported-${e.id}'),
                ),
                if (!others)
                  small(
                    'Bildirildi işaretle',
                    () => unawaited(_markReported(e, true)),
                    ValueKey('ledger-report-${e.id}'),
                  ),
              ],
              arrow(),
              if (e.isOfficial) ...[
                step(
                  e.official == 'elle' ? "UYAP'a işlendi" : "UYAP'ta görüldü",
                  _green,
                ),
                if (e.official == 'elle' && !others)
                  small(
                    'Geri al',
                    () => unawaited(_markOfficial(e, false)),
                    ValueKey('ledger-unofficial-${e.id}'),
                  ),
              ] else ...[
                step(
                  "UYAP'ta görülmedi",
                  tone(const Color(0xFFC4C9D2)),
                  color: AgendaColors.muted,
                ),
                if (!others)
                  small(
                    "İşlendi say",
                    () => unawaited(_markOfficial(e, true)),
                    ValueKey('ledger-official-${e.id}'),
                  ),
              ],
            ],
          ),
          // Set-offs past what is held wait, kept, in no account, till they
          // fit (docs/senkron-plan.md R3).
          for (final w in LedgerBook.stateOf(e.record).waiting)
            Container(
              key: ValueKey('ledger-waiting-${e.id}-${w.id}'),
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              decoration: BoxDecoration(
                color: AgendaColors.taskFill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.pause_circle_outline_rounded,
                    size: 18,
                    color: AgendaColors.taskText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text:
                                'Mahsup askıda: ${_tl(w.amount / 100)} TL '
                                '${w.target == MovementKind.toFee ? 'vekâlet ücretine' : 'karşı vekâlet ücretine'}\n',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text:
                                'Emanette ${_tl(_leftOf(e.record) / 100)} TL '
                                'kaldı; mahsup sığana kadar hesaba işlenmez. '
                                'Tutarı düzeltin ya da mahsubu kaldırın.',
                          ),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: AgendaColors.taskText,
                      ),
                    ),
                  ),
                  if (!others)
                    OutlinedButton(
                      key: ValueKey('ledger-waiting-remove-${w.id}'),
                      onPressed: () async {
                        final db = await widget.database();
                        await _change(
                          db,
                          (book) => book.removeSetOff(
                            e.id,
                            w.id,
                            seen: LedgerBook.tokenOf(e.record),
                          ),
                        );
                      },
                      child: const Text('Mahsubu kaldır'),
                    ),
                ],
              ),
            ),
          if (others) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Bu kaydı yalnız $owner değiştirebilir. Bir yanlış görürseniz '
                'önerin; onaylarsa uygulanır.',
                key: ValueKey('ledger-owner-note-${e.id}'),
                style: TextStyle(fontSize: 12, color: AgendaColors.muted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton(
                    key: ValueKey('ledger-propose-${e.id}'),
                    onPressed: () => unawaited(_propose(e)),
                    child: const Text('Değişiklik öner'),
                  ),
                  OutlinedButton(
                    key: ValueKey('ledger-propose-remove-${e.id}'),
                    onPressed: () => unawaited(_propose(e, remove: true)),
                    child: const Text('Silinmesini öner'),
                  ),
                ],
              ),
            ),
            if (_proposalsDb case final db?)
              ProposalStatus(db: db, target: e.id),
          ],
        ],
      ),
    );
  }

  Widget _box(String title, List<Widget> children, {String? right}) =>
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AgendaColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .5,
                      color: AgendaColors.muted,
                    ),
                  ),
                ),
                if (right != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      right,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AgendaColors.muted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      );

  Widget _columns(List<Widget> parts) => LayoutBuilder(
    builder: (context, box) => box.maxWidth < 460
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, p) in parts.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                p,
              ],
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, p) in parts.indexed) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: p),
              ],
            ],
          ),
  );

  Widget _row(String a, String b, {bool bold = false, Color? color}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: tone(const Color(0xFFF0F1F5))),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                a,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: bold ? FontWeight.w700 : null,
                ),
              ),
            ),
            Text(
              b,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: bold ? FontWeight.w700 : null,
                color: color,
              ),
            ),
          ],
        ),
      );

  Widget _lines(
    String title,
    List<(String, double?)> rows, {
    bool total = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .5,
          color: AgendaColors.muted,
        ),
      ),
      const SizedBox(height: 2),
      if (rows.isEmpty)
        Text(
          'UYAP göstermedi.',
          style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
        ),
      for (final (a, v) in rows) _row(a, v == null ? '—' : _tl(v)),
      if (total && rows.length > 1)
        _row(
          'Toplam',
          _tl(rows.fold<double>(0, (n, r) => n + (r.$2 ?? 0))),
          bold: true,
        ),
    ],
  );

  Widget _money(UyapCaseMoney? m) {
    final items =
        <({UyapMoneyItem item, bool out, DateTime? at})>[
          for (final c in m?.collections ?? const <UyapMoneyItem>[])
            (item: c, out: false, at: uyapDay(c.date)),
          for (final p in m?.payments ?? const <UyapMoneyItem>[])
            (item: p, out: true, at: uyapDay(p.date)),
        ]..sort(
          (a, b) => (b.at ?? DateTime(1900)).compareTo(a.at ?? DateTime(1900)),
        );
    // A payment out for the file's costs (postage, an expert, a
    // custodian) is no one's money to pass on; one of no named kind is
    // booked by hand, from its row.
    final unbooked = [
      for (final i in items)
        if (i.out &&
            !_booked.contains(_keyOf(i.item)) &&
            _forTheClaim(i.item.kind))
          i.item,
    ];
    final collected = m?.collected, out = m?.paidOut;
    return _box('TAHSİLAT VE REDDİYAT', right: '${items.length}', [
      if (items.isEmpty)
        Text(
          'Tahsilat ya da reddiyat yok.',
          style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
        ),
      for (final i in items.take(8))
        InkWell(
          onTap: i.out && !_booked.contains(_keyOf(i.item))
              ? () => _book(i.item)
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: tone(const Color(0xFFF0F1F5))),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 82,
                  child: Text(
                    i.at == null ? i.item.date : dayText(i.at!),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                Container(
                  width: 70,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: i.out
                          ? tone(const Color(0xFFEFE9FA))
                          : tone(const Color(0xFFE6F4EC)),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      i.out ? 'Reddiyat' : 'Tahsilat',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: i.out ? _purple : _green,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    [
                      if (i.item.kind.isNotEmpty) i.item.kind,
                      if (i.item.payer.isNotEmpty) i.item.payer,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                Text(
                  _tl(i.item.amount),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: i.out ? _purple : _green,
                  ),
                ),
              ],
            ),
          ),
        ),
      if (items.length > 8)
        Text(
          've ${items.length - 8} kayıt daha',
          style: TextStyle(fontSize: 12, color: AgendaColors.muted),
        ),
      if (m?.remaining != null || (collected != null && out != null))
        _row(
          'Dosyada kalan',
          _tl(m?.remaining ?? (collected! - out!)),
          bold: true,
        ),
      for (final p in unbooked.take(3))
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.fromLTRB(8, 2, 2, 2),
          decoration: BoxDecoration(
            color: tone(const Color(0xFFFCEBEA)),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${p.date.split(' ').first} reddiyatı (${_tl(p.amount)} TL) '
                  'müvekkil hesabına işlenmedi.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AgendaColors.deadlineText,
                  ),
                ),
              ),
              TextButton(
                key: ValueKey('book-${_keyOf(p)}'),
                onPressed: () => _book(p),
                child: const Text('Hesaba işle'),
              ),
            ],
          ),
        ),
    ]);
  }

  Widget _debtors(
    List<UyapDebtor> debtors,
  ) => _box('BORÇLULAR', right: debtors.isEmpty ? null : '${debtors.length}', [
    if (debtors.isEmpty)
      Text(
        'UYAP borçlu listesi gelmedi; "UYAP\'tan tazele" ile çekilir.',
        style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
      ),
    for (final d in debtors)
      Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: tone(const Color(0xFFF0F1F5))),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: titleName(d.name),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (d.idNo.isNotEmpty)
                    TextSpan(
                      text: '  ${d.body ? 'VKN' : 'TCKN'} ${d.idNo}',
                      style: TextStyle(fontSize: 12, color: AgendaColors.muted),
                    ),
                ],
              ),
              style: const TextStyle(fontSize: 12.5),
            ),
            if (d.dead || d.moved || d.warning)
              Wrap(
                spacing: 6,
                children: [
                  if (d.dead)
                    _flag('Ölüm kaydı var', AgendaColors.deadlineText),
                  if (d.moved)
                    _flag(
                      d.movedWhy.isEmpty
                          ? 'Adresi değişmiş'
                          : 'Adresi değişmiş · ${d.movedWhy}',
                      AgendaColors.taskText,
                    ),
                  if (d.warning) _flag('UYAP uyarısı', AgendaColors.taskText),
                ],
              ),
          ],
        ),
      ),
    const SizedBox(height: 6),
    Text(
      'Borçlu sorguları (araç, tapu, banka, SGK) UYAP\'ta dosya başına '
      'günde 5 ücretsiz, sonrası ücretlidir; burada kendiliğinden '
      'yapılmaz.',
      style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
    ),
  ]);

  Widget _flag(String text, Color color) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );

  /// The file's course from what is kept: its documents and the money in
  /// and out, newest first. UYAP's own course (safahat) is counted and paid
  /// for beyond a number, and is not asked.
  Widget _course(UyapCaseRecord record) {
    final events = <({DateTime at, String text, Color color})>[
      for (final d in record.documents)
        if (uyapDay(d.sentToSystem.isNotEmpty ? d.sentToSystem : d.approved)
            case final at?)
          (at: at, text: d.title, color: AgendaColors.hearing),
      for (final c in record.money?.collections ?? const <UyapMoneyItem>[])
        if (uyapDay(c.date) case final at?)
          (
            at: at,
            text:
                'Tahsilat ${_tl(c.amount)} TL'
                '${c.kind.isEmpty ? '' : ' · ${c.kind}'}',
            color: _green,
          ),
      for (final p in record.money?.payments ?? const <UyapMoneyItem>[])
        if (uyapDay(p.date) case final at?)
          (
            at: at,
            text:
                'Reddiyat ${_tl(p.amount)} TL'
                '${p.kind.isEmpty ? '' : ' · ${p.kind}'}',
            color: _purple,
          ),
    ]..sort((a, b) => b.at.compareTo(a.at));
    final shown = _allCourse ? events : events.take(8).toList();
    return _box('DOSYA SEYRİ', right: 'evraklar ve para hareketleri', [
      if (events.isEmpty)
        Text(
          'Henüz bir şey yok.',
          style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
        ),
      for (final ev in shown)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5, right: 8),
                child: Icon(Icons.circle, size: 8, color: ev.color),
              ),
              SizedBox(
                width: 78,
                child: Text(
                  dayText(ev.at),
                  style: TextStyle(fontSize: 12, color: AgendaColors.muted),
                ),
              ),
              Expanded(
                child: Text(
                  ev.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      if (events.length > 8)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _allCourse = !_allCourse),
            child: Text(_allCourse ? 'Daha az' : 'Tümü ${events.length}'),
          ),
        ),
    ]);
  }
}

/// The movements of the client's account and Kasa, read once and indexed:
/// what each enforcement payment put in them, still standing.
class _MovementIndex {
  _MovementIndex(PortalDatabase db) {
    final records = db.recordsOfKind(ClientRecordKind.movement);
    final reversed = {
      for (final r in records)
        if (r.text('ters').isNotEmpty) r.text('ters'),
    };
    for (final r in records) {
      final source = r.text('kaynak');
      if (r.removed || source.isEmpty) continue;
      booked.add(source);
      if (reversed.contains(r.id)) continue;
      (_bySource[source] ??= []).add(r);
    }
  }

  final _bySource = <String, List<ClientRecord>>{};

  /// Every source a movement not taken off names (`kaynak`).
  final booked = <String>{};

  ({List<ClientRecord> held, List<ClientRecord> applied}) of(LedgerEntry e) {
    final held = _bySource['icra:${e.id}'] ?? const <ClientRecord>[];
    return (
      held: held,
      applied: [for (final m in held) ...?_bySource['mahsup:${m.id}']],
    );
  }
}

/// What the enforcement tab shows of [caseKey]: the file's own account
/// with what UYAP shows of it ([collections]), what each payment put in the
/// client's account and Kasa, and the accounts shared with this person
/// (R8). Each kind of record read once, not once a payment.
@visibleForTesting
({
  Set<String> booked,
  List<LedgerEntry> ledger,
  Map<String, ({bool booked, MovementKind? target})> bookings,
  Map<String, List<LedgerEntry>> shared,
  String? sharedRemoved,
})
readEnforcementBooks(
  PortalDatabase db,
  String caseKey,
  List<UyapMoneyItem> collections,
) {
  // Each owner's, with what UYAP shows here: a payment it shows is not
  // taken off the debt twice (R4).
  final shared = {
    for (final e in db.sharedLedgersOf(caseKey).entries)
      e.key: () {
        final entries = [
          for (final r in e.value)
            if (!r.removed)
              LedgerEntry(r, noteHidden: SecretNotes.descriptionHidden(db, r)),
        ]..sort((a, b) => a.at.compareTo(b.at));
        if (collections.isEmpty) return entries;
        final found = officialMatches(entries, collections, uyapDay);
        return [
          for (final x in entries)
            LedgerEntry(
              x.record,
              matched: found[x.id] ?? '',
              noteHidden: x.noteHidden,
            ),
        ];
      }(),
  };
  // What UYAP shows now of the payments made outside: official, worked out
  // from it each time and written nowhere, so that looking at a file
  // changes nothing on any device (docs/senkron-plan.md R4).
  final ledger = ledgerOf(
    db,
    caseKey,
    collections: collections,
    parse: uyapDay,
  );
  final index = _MovementIndex(db);
  return (
    booked: index.booked,
    ledger: ledger,
    bookings: {
      for (final e in ledger)
        if (index.of(e) case (:final held, :final applied))
          e.id: (
            booked: held.isNotEmpty,
            target: applied.isEmpty
                ? null
                : MovementKind.of(applied.first.data['hesap']),
          ),
    },
    shared: shared,
    sharedRemoved: db.sharedLedgerRemoved(caseKey),
  );
}
