import 'dart:async';
import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/clients/client.dart';
import '../../services/clients/client_accounts.dart';
import '../../services/clients/client_documents.dart';
import '../../services/editor/lawyer_profile.dart';
import '../../services/clients/client_files.dart';
import '../../services/clients/client_statement_pdf.dart';
import '../../services/clients/fee_reminders.dart';
import '../../services/portal/portal_database.dart';
import '../../services/platform/document_scan.dart';
import '../../services/speech/speech_models.dart';
import '../../services/speech/speech_session.dart';
import '../widgets/speech_bar.dart';
import '../widgets/speech_download_dialog.dart';
import '../../services/portal/portal_hearing.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../portfolio/portfolio_rows.dart' show titleName;
import '../widgets/notice.dart';
import 'attachment_preview.dart';
import 'client_accounts_view.dart';

/// A scan to keep: from the camera where there is one (Android, iPhone),
/// or a file (a PDF or a picture) chosen; null when backed out.
Future<String?> pickScan(BuildContext context, String title) async {
  if (DocumentScan.available) {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Kameradan tara'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Dosyadan seç (PDF ya da resim)'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (camera == null) return null;
    if (camera) return DocumentScan.toPdf();
  }
  final picked = await FilePicker.pickFiles(
    dialogTitle: title,
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'tif', 'tiff'],
  );
  return picked?.files.single.path;
}

String _two(int v) => v.toString().padLeft(2, '0');
String _day(DateTime t) => '${_two(t.day)}.${_two(t.month)}.${t.year}';
String _time(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// The lawyer's clients (docs/design/muvekkil-taslak): on a wide window the
/// list beside the card, on a phone the card a page of its own.
class ClientsPage extends StatefulWidget {
  const ClientsPage({
    super.key,
    required this.lawyer,
    this.database,
    this.files,
    this.onOpenCase,
    this.person = '',
    this.seesMoney = true,
    this.inOffice = false,
    this.onEdit,
    this.open,
  });

  /// The client to open first (the search found it), by its key.
  final String? open;

  /// A paper made for a client (a fee agreement, a receipt, a release),
  /// opened in the editor to be read over.
  final ValueChanged<String>? onEdit;

  /// "Av. Deniz Kaya": whose clients, and who writes their records.
  final String lawyer;

  /// This person in the office ([ClientRecord.person]); empty for none.
  final String person;

  /// Whether the fees, advances and costs are shown: alone always; in an
  /// office to a manager, or one a manager let.
  final bool seesMoney;
  final bool inOffice;
  final PortalDatabase? database;
  final ClientFiles? files;
  final ValueChanged<String>? onOpenCase;

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  PortalDatabase? _db;
  List<ClientEntry> _entries = const [];
  String _query = '';

  /// The clients whose instalments are late, by card id: how many.
  Map<String, int> _late = const {};
  bool _onlyLate = false;
  String? _selected;

  /// The list beside the card, folded by the lawyer for the card's room;
  /// remembered on this device.
  bool _listOpen = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final db = _db ??= widget.database ?? await PortalDatabase.shared();
    if (!mounted) return;
    final late = <String, int>{};
    if (widget.seesMoney) {
      for (final t in FeeReminders.open(db, DateTime.now())) {
        if (t.daysLeft < 0) late[t.client.id] = (late[t.client.id] ?? 0) + 1;
      }
    }
    final first = _entries.isEmpty ? widget.open : null;
    _listOpen = db.meta(_listKey) != 'kapali';
    setState(() {
      _entries = db.clientEntries(lawyer: widget.lawyer);
      _late = late;
    });
    if (first != null) {
      final e = _entries.where((x) => x.key == first).firstOrNull;
      if (e != null) _open(e);
    }
  }

  static const _listKey = 'muvekkil_listesi';

  void _fold(bool open) {
    _db?.setMeta(_listKey, open ? 'acik' : 'kapali');
    setState(() => _listOpen = open);
  }

  int _lateOf(ClientEntry e) =>
      [for (final id in e.ids) _late[id] ?? 0].fold(0, (a, b) => a + b);

  List<ClientEntry> get _shown {
    final q = UyapWebService.fold(_query.trim());
    final base = _onlyLate
        ? [
            for (final e in _entries)
              if (_lateOf(e) > 0) e,
          ]
        : _entries;
    if (q.isEmpty) return base;
    return [
      for (final e in base)
        if (UyapWebService.fold(
          '${e.name} ${e.client?.idNo ?? ''} '
          '${e.client?.phone ?? ''} ${e.client?.phone2 ?? ''} '
          '${[for (final c in e.cases) _db?.caseOf(c.caseKey)?.number ?? ''].join(' ')}',
        ).contains(q))
          e,
    ];
  }

  void _open(ClientEntry e) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      setState(() => _selected = e.key);
      return;
    }
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Müvekkil')),
                body: _detail(e),
              ),
            ),
          )
          .then((_) => _load()),
    );
  }

  /// The key a card's made under, by the key it had before: a client only
  /// seen in the cases keeps its page (and its tab) when its card is made.
  final _madeFrom = <String, String>{};

  // Keyed by the client, not its name: two of one name are two clients.
  Widget _detail(ClientEntry e) => ClientCard(
    key: ValueKey(_madeFrom[e.key] ?? e.key),
    entry: e,
    database: _db!,
    lawyer: widget.lawyer,
    files: widget.files ?? ClientFiles(),
    person: widget.person,
    seesMoney: widget.seesMoney,
    inOffice: widget.inOffice,
    onEdit: widget.onEdit,
    lookalikes: _db!.clientLookalikes(e, _entries),
    onOpenCase: widget.onOpenCase,
    onChanged: (key) {
      // A card made for a client only seen in the cases: it is the one
      // chosen now, under its id, on the page it had.
      if (key.isNotEmpty && key != e.key && e.client == null) {
        _madeFrom[key] = e.key;
      }
      if (_selected != null) _selected = key.isEmpty ? null : key;
      unawaited(_load());
    },
  );

  @override
  Widget build(BuildContext context) {
    final db = _db;
    if (db == null) return const Center(child: CircularProgressIndicator());
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final shown = _shown;
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(wide ? 6 : 16, 12, 16, 8),
          child: Row(
            children: [
              if (wide)
                IconButton(
                  key: const ValueKey('clients-fold'),
                  tooltip: 'Listeyi kapat',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _fold(false),
                  icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
                ),
              Flexible(
                child: Text(
                  'Müvekkiller',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            key: const ValueKey('clients-search'),
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              hintText: 'Ad, TCKN, telefon ya da dosya no…',
              isDense: true,
            ),
          ),
        ),
        if (_late.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                key: const ValueKey('clients-late'),
                label: Text('Taksiti gecikmiş ${_late.length}'),
                selected: _onlyLate,
                onSelected: (v) => setState(() => _onlyLate = v),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: shown.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Müvekkil yok. Müvekkiller, UYAP dosyalarında vekili '
                    'olduğunuz taraflardan ve "kimi temsil ediyorum" '
                    'kayıtlarından kendiliğinden gelir.',
                    style: TextStyle(color: AgendaColors.muted, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final e = shown[i];
                    return ListTile(
                      key: ValueKey('client-${e.key}'),
                      selected: wide && e.key == _selected,
                      selectedTileColor: AgendaColors.hearingFill,
                      leading: _Avatar(e.name, body: e.client?.body ?? false),
                      title: Text(
                        titleName(e.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        [
                          '${e.cases.length} dosya',
                          if (_lateOf(e) > 0) '${_lateOf(e)} taksit gecikti',
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 12,
                          color: _lateOf(e) > 0
                              ? AgendaColors.deadlineText
                              : null,
                        ),
                      ),
                      onTap: () => _open(e),
                    );
                  },
                ),
        ),
      ],
    );
    if (!wide) return list;
    final selected = shown.where((e) => e.key == _selected).firstOrNull;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_listOpen)
          SizedBox(width: 280, child: Material(child: list))
        else
          Material(
            child: SizedBox(
              width: 40,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  IconButton(
                    key: const ValueKey('clients-unfold'),
                    tooltip: 'Listeyi aç',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _fold(true),
                    icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
                  ),
                  const SizedBox(height: 8),
                  RotatedBox(
                    quarterTurns: 1,
                    child: Text(
                      'Müvekkiller · ${_entries.length}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AgendaColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? Center(
                  child: Text(
                    _listOpen
                        ? 'Soldan bir müvekkil seçin.'
                        : 'Listeyi açıp bir müvekkil seçin.',
                    style: TextStyle(color: AgendaColors.muted),
                  ),
                )
              : _detail(selected),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name, {this.body = false, this.size = 36});
  final String name;
  final bool body;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letters = [
      for (final w in name.trim().split(RegExp(r'\s+')).take(2))
        if (w.isNotEmpty) w.characters.first.toUpperCase(),
    ].join();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: body ? const Color(0xFFF1E6D6) : const Color(0xFFDCE5F4),
      child: Text(
        letters,
        style: TextStyle(
          fontSize: size * .36,
          fontWeight: FontWeight.w700,
          color: body ? const Color(0xFF7A4B12) : AgendaColors.hearingText,
        ),
      ),
    );
  }
}

/// One client's card: who they are, their cases, the minutes of meetings
/// with them and their powers of attorney.
class ClientCard extends StatefulWidget {
  const ClientCard({
    super.key,
    required this.entry,
    required this.database,
    required this.lawyer,
    required this.files,
    this.onOpenCase,
    this.onChanged,
    this.person = '',
    this.seesMoney = true,
    this.inOffice = false,
    this.onEdit,
    this.lookalikes = const [],
  });

  final ClientEntry entry;
  final ValueChanged<String>? onEdit;

  /// The clients that may be this one written another way: offered to
  /// be merged, never merged unasked.
  final List<ClientEntry> lookalikes;
  final String person;
  final bool seesMoney, inOffice;
  final PortalDatabase database;
  final String lawyer;
  final ClientFiles files;
  final ValueChanged<String>? onOpenCase;

  /// Told, with the client's key, when its card is made or changed.
  final ValueChanged<String>? onChanged;

  @override
  State<ClientCard> createState() => _ClientCardState();
}

class _ClientCardState extends State<ClientCard> {
  late Client? _client = widget.entry.client;
  PortalDatabase get _db => widget.database;

  /// The card, made the first time something is kept for a client only
  /// seen in the cases so far.
  Client _card() {
    final kept = _client;
    if (kept != null) return kept;
    final made = Client(
      id: Client.newId(),
      name: widget.entry.name,
      updated: DateTime.now(),
      person: widget.person,
    );
    _db.saveClient(made);
    _client = made;
    return made;
  }

  List<ClientRecord> _records([ClientRecordKind? kind]) {
    final c = _client;
    return c == null
        ? const []
        : _db.clientRecords(c.id, kind: kind, also: widget.entry.ids);
  }

  /// [r] written by this person, kept.
  void _keep(ClientRecord r) {
    _db.saveClientRecord(
      r.person.isEmpty && widget.person.isNotEmpty
          ? r.copyWith(person: widget.person)
          : r,
    );
  }

  List<({String key, String title})> get _caseList => [
    for (final c in widget.entry.cases)
      (key: c.caseKey, title: _caseTitle(c.caseKey)),
  ];

  Future<void> _movement(String caseKey) async {
    final card = _card();
    final saved = await showDialog<ClientRecord>(
      context: context,
      builder: (_) => MovementDialog(
        client: card,
        caseKey: caseKey,
        lawyer: widget.lawyer,
        person: widget.person,
        files: widget.files,
      ),
    );
    if (saved == null) return;
    _keep(saved);
    if (mounted) setState(() {});
    widget.onChanged?.call(card.id);
  }

  Future<void> _fee(String caseKey, ClientRecord? kept) async {
    final card = _card();
    final saved = await showDialog<ClientRecord>(
      context: context,
      builder: (_) => FeeDialog(
        client: card,
        caseKey: caseKey,
        lawyer: widget.lawyer,
        person: widget.person,
        kept: kept,
      ),
    );
    if (saved == null) return;
    _keep(saved);
    if (mounted) setState(() {});
    widget.onChanged?.call(card.id);
  }

  /// [m] taken back by a movement that names it: both stay, struck out.
  Future<void> _reverse(ClientRecord m) async {
    final why = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ters kayıtla düzelt'),
        content: TextField(
          controller: why,
          decoration: const InputDecoration(labelText: 'Neden'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Düzelt'),
          ),
        ],
      ),
    );
    final reason = why.text.trim();
    why.dispose();
    if (ok != true) return;
    final now = DateTime.now();
    _keep(
      ClientRecord(
        id: Client.newId(),
        clientId: m.clientId,
        kind: ClientRecordKind.movement,
        data: {
          ...m.data,
          'ters': m.id,
          'zaman': now.toIso8601String(),
          'aciklama': reason.isEmpty ? m.text('aciklama') : reason,
          'ekler': const [],
        },
        created: now,
        by: widget.lawyer,
        updated: now,
        locked: true,
      ),
    );
    if (mounted) setState(() {});
    widget.onChanged?.call(m.clientId);
  }

  /// The client's statement (all cases, or [only]), seen, printed, shared.
  Future<void> _statement([String? only]) async {
    final card = _card();
    final records = [
      for (final r in _records())
        if (r.kind.money) r,
    ];
    final cases = {
      for (final c in widget.entry.cases) c.caseKey: _caseTitle(c.caseKey),
    };
    await showClientAttachment(
      context,
      title: 'Hesap dökümü',
      fileName: 'Hesap dökümü ${titleName(card.name)}.pdf',
      pdf: () => clientStatementPdf(
        client: card,
        records: records,
        cases: cases,
        lawyer: widget.lawyer,
        only: only,
      ),
    );
  }

  /// A paper for [caseKey] made from what is kept, written among the
  /// client's papers and opened in the editor.
  Future<void> _paper(
    String paper,
    String caseKey,
    ClientRecord? movement,
  ) async {
    final card = _card();
    final title = caseKey.isEmpty ? '' : _caseTitle(caseKey);
    final money = [
      for (final r in _records())
        if (r.kind.money) r,
    ];
    final account =
        caseAccounts(money)[caseKey] ?? CaseAccount(caseKey, null, const []);
    final profile = await LawyerProfile.load().catchError(
      (Object _) => const LawyerProfile(),
    );
    final lawyer = profile.lawyer?.titled.isNotEmpty ?? false
        ? profile.lawyer!.titled
        : widget.lawyer;
    final (name, model) = switch (paper) {
      'sozlesme' => (
        'Avukatlık ücret sözleşmesi',
        feeAgreementDocument(
          client: card,
          profile: profile,
          lawyer: lawyer,
          work: title,
          fee: account.fee,
        ),
      ),
      'ibra' => (
        'İbraname',
        releaseDocument(
          client: card,
          account: account,
          lawyer: lawyer,
          caseTitle: title,
        ),
      ),
      _ => (
        'Tahsilat belgesi ${_day(movement!.at)}',
        receiptDocument(
          client: card,
          movement: movement,
          lawyer: lawyer,
          caseTitle: title,
        ),
      ),
    };
    final path = await writeClientDocument(
      await widget.files.root(),
      card.id,
      '$name - ${titleName(card.name)}',
      model,
    );
    if (!mounted) return;
    final edit = widget.onEdit;
    if (edit != null) {
      edit(path);
    } else {
      showNotice(context, '$name hazırlandı.', detail: path);
    }
  }

  /// The client taken off the list, asked first: its records are kept,
  /// and its cases no longer bring it back.
  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Müvekkil listeden kaldırılsın mı?'),
        content: const Text(
          'Kart ve kayıtları silinmez; müvekkil listede görünmez. '
          'Dosyalarından yeniden gelmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const ValueKey('remove-ok'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final card = _card().copyWith(removed: true);
    _db.saveClient(card);
    widget.onChanged?.call('');
    // On a phone the card is a page of its own: back to the list.
    if (mounted && MediaQuery.sizeOf(context).width < 900) {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  /// [other] made this client's, asked first.
  Future<void> _merge(ClientEntry other) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aynı müvekkil mi?'),
        content: Text(
          '"${titleName(other.name)}" bu müvekkille birleştirilsin mi? '
          'Dosyaları ve kayıtları bu kartta görünür.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const ValueKey('merge-ok'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Birleştir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final merged = _db.mergeClients(_card(), other);
    if (mounted) setState(() => _client = merged);
    widget.onChanged?.call(merged.id);
  }

  /// Shared with the office, or no longer (KVKK: a client at a time).
  void _share(bool on) {
    final card = _card().copyWith(office: on);
    _db.saveClient(card);
    setState(() => _client = card);
    widget.onChanged?.call(card.id);
  }

  String _caseTitle(String key) {
    final c = _db.caseOf(key);
    return c == null ? key : '${c.number} · ${c.court}';
  }

  List<PortalHearing> get _hearings {
    final now = DateTime.now();
    return [
      for (final c in widget.entry.cases)
        ..._db.hearings(
          caseKey: c.caseKey,
          from: DateTime(now.year, now.month, now.day),
          to: now.add(const Duration(days: 400)),
        ),
    ]..sort((a, b) => a.at.compareTo(b.at));
  }

  Future<void> _editContact() async {
    final card = _card();
    final saved = await showDialog<Client>(
      context: context,
      builder: (_) => _ContactDialog(card),
    );
    if (saved == null) return;
    _db.saveClient(saved);
    if (mounted) setState(() => _client = saved);
    widget.onChanged?.call(saved.id);
  }

  Future<void> _meeting([ClientRecord? kept]) async {
    final card = _card();
    final saved = await Navigator.of(context).push<ClientRecord>(
      MaterialPageRoute(
        builder: (_) => MeetingForm(
          client: card,
          lawyer: widget.lawyer,
          cases: [
            for (final c in widget.entry.cases)
              (key: c.caseKey, title: _caseTitle(c.caseKey)),
          ],
          kept: kept,
        ),
      ),
    );
    if (saved == null) return;
    _keep(saved);
    // The next step told, put on the agenda once, as a task of the case.
    final step = saved.data['gorev'];
    if (step is Map &&
        step['baslik'] is String &&
        (kept?.data['gorev'] as Map?)?['baslik'] != step['baslik']) {
      _db.saveAgenda(
        AgendaItem(
          id: AgendaItem.newId(),
          kind: 'task',
          title: '${step['baslik']} · ${titleName(card.name)}',
          body: 'Görüşme tutanağından (${_day(saved.created)})',
          at: DateTime.tryParse('${step['tarih']}'),
          allDay: true,
          caseKey: saved.text('dosya').isEmpty ? null : saved.text('dosya'),
          updated: DateTime.now(),
        ),
      );
    }
    if (mounted) setState(() {});
    widget.onChanged?.call(card.id);
  }

  Future<void> _printMinutes(ClientRecord m) async {
    final card = _card();
    try {
      final bytes = await meetingMinutesPdf(
        client: card,
        meeting: m,
        lawyer: m.by.isEmpty ? widget.lawyer : m.by,
        caseTitle: m.text('dosya').isEmpty ? '' : _caseTitle(m.text('dosya')),
      );
      if (!mounted) return;
      await showClientAttachment(
        context,
        title: 'Görüşme tutanağı',
        fileName: 'Görüşme tutanağı ${_day(m.created)}.pdf',
        pdf: () async => bytes,
      );
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Tutanak yazdırılamadı: $e',
          kind: NoticeKind.error,
        );
      }
    }
  }

  /// The minutes signed: their scan kept with them, and they locked.
  Future<void> _signed(ClientRecord m) async {
    final path = await pickScan(context, 'İmzalı tutanağın taranmış hâli');
    if (path == null) return;
    final card = _card();
    final kept = await widget.files.keep(card.id, path);
    final locked = m.copyWith(
      data: {
        ...m.data,
        'ekler': [
          ...clientFilesOf(m).map(clientFileJson),
          clientFileJson(kept),
        ],
        'imzalandi': DateTime.now().toIso8601String(),
      },
      locked: true,
    );
    _db.saveClientRecord(locked);
    if (mounted) setState(() {});
  }

  /// [r]'s first file seen, to be printed or shared.
  Future<void> _preview(ClientRecord r, String title) async {
    final f = clientFilesOf(r).firstOrNull;
    if (f == null) return;
    final file = await widget.files.locate(r.clientId, f);
    if (!mounted) return;
    if (file == null) {
      showNotice(
        context,
        'Bu dosya bu cihazda yok.',
        detail: 'Eklendiği cihaz ağdayken eşitlemeyle gelir.',
      );
      return;
    }
    await showClientAttachment(
      context,
      title: title,
      fileName: '${f.name.replaceAll(RegExp(r'\.[^.]+$'), '')}.pdf',
      pdf: () => attachmentPdf(file),
    );
  }

  Future<void> _attorney() async {
    final card = _card();
    final saved = await Navigator.of(context).push<ClientRecord>(
      MaterialPageRoute(
        builder: (_) => AttorneyForm(
          client: card,
          lawyer: widget.lawyer,
          files: widget.files,
          cases: [
            for (final c in widget.entry.cases)
              (key: c.caseKey, title: _caseTitle(c.caseKey)),
          ],
        ),
      ),
    );
    if (saved == null) return;
    _keep(saved);
    if (mounted) setState(() {});
    widget.onChanged?.call(card.id);
  }

  /// Counted up at every change of the card, for the pages opened from it
  /// (all the minutes, every account) to show it too.
  final _revision = ValueNotifier(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _revision.value++;
  }

  @override
  void dispose() {
    _revision.dispose();
    super.dispose();
  }

  /// [body] on a page of its own, kept up with the card.
  Future<void> _page(String title, Widget Function(BuildContext) body) =>
      Navigator.of(context)
          .push<void>(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text(title)),
                body: ValueListenableBuilder(
                  valueListenable: _revision,
                  builder: (context, _, _) => body(context),
                ),
              ),
            ),
          )
          .then((_) {
            if (mounted) setState(() {});
          });

  /// Every account, or [only] that case's.
  Future<void> _accounts([String? only]) => _page(
    only == null ? 'Hesaplar' : _caseTitle(only),
    (page) => ClientAccountsView(
      client:
          _client ??
          Client(id: '', name: widget.entry.name, updated: DateTime(2000)),
      records: [
        for (final r in _records())
          if (r.kind.money && (only == null || r.text('dosya') == only)) r,
      ],
      cases: only == null ? _caseList : [(key: only, title: _caseTitle(only))],
      onMovement: _movement,
      onFee: _fee,
      onReverse: _reverse,
      onOpen: (m) => _preview(m, 'Belge'),
      onStatement: _statement,
      titleOf: _caseTitle,
      onPaper: (paper, key, m) {
        // The paper opens in the editor: this page out of its way.
        Navigator.of(page).pop();
        unawaited(_paper(paper, key, m));
      },
    ),
  );

  /// The lawyer's word on case [key] for this client: tied by hand,
  /// taken off, or neither; the latest word wins on every device.
  void _link(String key, String state, String role) {
    final card = _card();
    final saved = card.copyWith(
      caseLinks: {
        ...card.caseLinks,
        key: CaseLink(state, DateTime.now(), role: role),
      },
    );
    _db.saveClient(saved);
    setState(() => _client = saved);
    widget.onChanged?.call(saved.id);
  }

  /// Case [c] taken off the client, asked first: the case and its
  /// records stay; it is given back from "Çıkarılan dosyalar".
  Future<void> _takeOff(({String caseKey, String role}) c) async {
    final kept = [
      for (final r in _records())
        if (r.text('dosya') == c.caseKey) r,
    ].length;
    final number = _db.caseOf(c.caseKey)?.number ?? c.caseKey;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$number bu müvekkilden çıkarılsın mı?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dosya yalnız ${titleName(widget.entry.name)} adlı müvekkilin '
              'listesinden çıkar. UYAP\'taki dosyaya ve öteki müvekkillere '
              'dokunulmaz.',
            ),
            const SizedBox(height: 8),
            Text(
              [
                if (kept > 0) 'Bu dosyada $kept kayıt var; silinmez.',
                'Dosyayı "Çıkarılan dosyalar" altından geri alabilirsiniz.',
              ].join(' '),
              style: const TextStyle(color: AgendaColors.muted, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const ValueKey('case-remove-ok'),
            style: FilledButton.styleFrom(
              backgroundColor: AgendaColors.deadlineText,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Çıkar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final before = _client?.caseLinks[c.caseKey];
    final messenger = ScaffoldMessenger.maybeOf(context);
    _link(c.caseKey, CaseLink.removed, c.role);
    messenger?.showSnackBar(
      SnackBar(
        content: Text('$number bu müvekkilden çıkarıldı.'),
        action: SnackBarAction(
          label: 'Geri al',
          onPressed: () {
            if (mounted) {
              _link(c.caseKey, before?.state ?? CaseLink.none, c.role);
            }
          },
        ),
      ),
    );
  }

  /// Cases tied to the client by hand, chosen among the ones kept.
  Future<void> _addCases() async {
    final have = {for (final c in widget.entry.cases) c.caseKey};
    final picked = await showDialog<({List<String> keys, String role})>(
      context: context,
      builder: (_) => _CaseAddDialog(
        database: _db,
        client: titleName(widget.entry.name),
        skip: have,
      ),
    );
    if (picked == null || picked.keys.isEmpty) return;
    final card = _card();
    final now = DateTime.now();
    final saved = card.copyWith(
      caseLinks: {
        ...card.caseLinks,
        for (final k in picked.keys)
          k: CaseLink(CaseLink.added, now, role: picked.role),
      },
    );
    _db.saveClient(saved);
    setState(() => _client = saved);
    widget.onChanged?.call(saved.id);
  }

  /// The deadlines on the agenda for the client's cases, not done.
  List<({DateTime day, String title, String caseKey})> get _deadlines {
    final keys = {for (final c in widget.entry.cases) c.caseKey};
    if (keys.isEmpty) return const [];
    return [
      for (final d in _db.deadlines(decidedOnly: true))
        if (d.onAgenda &&
            !(d.user?.done ?? false) &&
            keys.contains(d.record.caseKey))
          if (DateTime.tryParse(d.day ?? '') case final day?)
            (
              day: day,
              title: d.user?.titleOverride ?? d.record.title,
              caseKey: d.record.caseKey!,
            ),
    ];
  }

  String _number(String key) => _db.caseOf(key)?.number ?? key;

  /// What happened with the client and what is coming: what is coming
  /// first, soonest first; then what happened, latest first.
  List<_Event> _events(
    List<ClientRecord> meetings,
    List<ClientRecord> attorneys,
    List<ClientRecord> money,
    List<PortalHearing> hearings,
    List<({DateTime day, String title, String caseKey})> deadlines,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <_Event>[
      for (final h in hearings)
        _Event(
          h.at,
          'Duruşma ${_time(h.at)}',
          h.number,
          AgendaColors.hearing,
          caseKey: h.caseKey,
        ),
      for (final d in deadlines)
        if (!d.day.isBefore(today.subtract(const Duration(days: 7))))
          _Event(
            d.day,
            'Süre: ${d.title}',
            _number(d.caseKey),
            AgendaColors.task,
            caseKey: d.caseKey,
            day: true,
          ),
      if (widget.seesMoney && _client != null)
        for (final t in FeeReminders.open(_db, now))
          if (widget.entry.ids.contains(t.client.id) ||
              t.client.id == _client!.id)
            _Event(
              t.due,
              'Taksit ${lira(t.amount)}',
              t.daysLeft < 0
                  ? '${_number(t.caseKey)} · ${-t.daysLeft} gün gecikti'
                  : _number(t.caseKey),
              t.daysLeft < 0 ? AgendaColors.deadline : AgendaColors.task,
              day: true,
            ),
      for (final m in meetings)
        _Event(
          DateTime.tryParse(m.text('baslangic')) ?? m.created,
          'Görüşme (${m.locked ? 'imzalı' : 'imza bekliyor'}): '
          '${m.text('kararlar').isEmpty ? m.text('konusulanlar') : m.text('kararlar')}',
          m.text('dosya').isEmpty ? '' : _number(m.text('dosya')),
          AgendaColors.ok,
        ),
      for (final a in attorneys)
        _Event(
          a.created,
          'Vekâletname eklendi',
          a.text('noter'),
          AgendaColors.muted,
        ),
      for (final m in money)
        if (m.kind == ClientRecordKind.movement)
          _Event(
            m.at,
            '${m.movement?.label ?? 'Hareket'} ${lira(m.amount)}',
            [
              if (m.text('dosya').isNotEmpty) _number(m.text('dosya')),
              if (m.reverses.isNotEmpty) 'ters kayıt',
            ].join(' · '),
            AgendaColors.ok,
          ),
    ];
    final coming = [
      for (final e in out)
        if (!e.at.isBefore(e.day ? today : now)) e,
    ]..sort((a, b) => a.at.compareTo(b.at));
    final past = [
      for (final e in out)
        if (e.at.isBefore(e.day ? today : now)) e,
    ]..sort((a, b) => b.at.compareTo(a.at));
    return [...coming, ...past];
  }

  bool _allEvents = false;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, box) => _build(box.maxWidth));

  Widget _build(double width) {
    final e = widget.entry;
    final c = _client;
    final wide = width >= 640;
    final meetings = _records(ClientRecordKind.meeting);
    final attorneys = _records(ClientRecordKind.attorney);
    final money = widget.seesMoney
        ? [
            for (final r in _records())
              if (r.kind.money) r,
          ]
        : const <ClientRecord>[];
    final hearings = _hearings;
    final deadlines = _deadlines;
    final accounts = caseAccounts(money);
    // Each case's next hearing or deadline.
    final next = <String, ({DateTime at, String text})>{};
    void soon(String key, DateTime at, String text) {
      final kept = next[key];
      if (kept == null || at.isBefore(kept.at)) {
        next[key] = (at: at, text: text);
      }
    }

    final today = DateTime.now();
    for (final h in hearings) {
      soon(h.caseKey, h.at, 'Duruşma ${_day(h.at).substring(0, 5)}');
    }
    for (final d in deadlines) {
      if (!d.day.isBefore(DateTime(today.year, today.month, today.day))) {
        soon(d.caseKey, d.day, 'Süre ${_day(d.day).substring(0, 5)}');
      }
    }
    final events = _events(meetings, attorneys, money, hearings, deadlines);
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 16 : 10, 12, wide ? 16 : 10, 24),
      children: [
        _head(c, wide),
        for (final o in widget.lookalikes)
          Card(
            key: ValueKey('lookalike-${o.key}'),
            margin: const EdgeInsets.only(top: 8),
            elevation: 0,
            color: AgendaColors.taskFill,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.merge_type_rounded),
              title: Text(
                'Aynı kişi olabilir: ${titleName(o.name)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('${o.cases.length} dosya'),
              trailing: TextButton(
                onPressed: () => _merge(o),
                child: const Text('Birleştir'),
              ),
            ),
          ),
        if (widget.seesMoney) _moneyStrip(accounts),
        _box(
          'DOSYALAR VE HESAPLARI',
          count: e.cases.length,
          action: TextButton.icon(
            key: const ValueKey('client-add-case'),
            onPressed: _addCases,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Dosya ekle'),
          ),
          children: [
            if (e.cases.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
                child: Text(
                  'Bu müvekkile bağlı dosya yok. "Dosya ekle" ile UYAP '
                  'dosyalarınızdan seçebilirsiniz.',
                  style: TextStyle(color: AgendaColors.muted),
                ),
              ),
            if (wide && e.cases.isNotEmpty) _caseHead(),
            for (final x in e.cases)
              _caseRow(x, accounts[x.caseKey], next[x.caseKey]?.text, wide),
          ],
        ),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _timeline(events)),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Column(
                  children: [_attorneyBox(attorneys), _meetingBox(meetings)],
                ),
              ),
            ],
          )
        else ...[
          _timeline(events),
          _attorneyBox(attorneys),
          _meetingBox(meetings),
        ],
        if (e.removedCases.isNotEmpty)
          _box(
            'ÇIKARILAN DOSYALAR',
            count: e.removedCases.length,
            children: [
              for (final x in e.removedCases)
                ListTile(
                  key: ValueKey('client-removed-${x.caseKey}'),
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(_caseTitle(x.caseKey)),
                  subtitle: x.role.isEmpty ? null : Text(titleName(x.role)),
                  trailing: TextButton(
                    key: ValueKey('case-restore-${x.caseKey}'),
                    onPressed: () => _link(x.caseKey, CaseLink.added, x.role),
                    child: const Text('Geri al'),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// Who the client is and how they are reached, and what is done for
  /// them: the card's head.
  Widget _head(Client? c, bool wide) {
    final e = widget.entry;
    final body = c?.body ?? false;
    Widget pair(String label, String value) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(color: AgendaColors.muted),
          ),
          value.isEmpty
              ? const TextSpan(
                  text: '+ ekle',
                  style: TextStyle(color: AgendaColors.taskText),
                )
              : TextSpan(text: value),
        ],
      ),
      style: const TextStyle(fontSize: 13),
    );
    Widget tap(Widget w, String value) => value.isEmpty
        ? InkWell(onTap: _editContact, child: w)
        : SelectionArea(child: w);
    Future<void> launch(String uri) async {
      try {
        await launchUrl(Uri.parse(uri));
      } catch (_) {}
    }

    return _frame(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!wide) ...[
                _Avatar(e.name, body: body, size: 42),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      titleName(c?.name ?? e.name),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _tag(body ? 'Kurum' : 'Kişi'),
                    if (widget.inOffice)
                      FilterChip(
                        key: const ValueKey('client-share'),
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(
                          c?.office ?? false
                              ? Icons.groups_rounded
                              : Icons.lock_outline_rounded,
                          size: 16,
                        ),
                        label: Text(
                          c?.office ?? false
                              ? 'Büroyla paylaşılıyor'
                              : 'Yalnız bende',
                        ),
                        selected: c?.office ?? false,
                        onSelected: _share,
                        tooltip:
                            'Paylaşılırsa kartı, tutanakları ve vekâletnameleri '
                            'bürodaki avukatlara gider; ücret ve hesaplar '
                            'yalnız yöneticilere ve yetki verilenlere.',
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: const ValueKey('client-more'),
                onSelected: (_) => _remove(),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'kaldir',
                    child: Text('Müvekkili listeden kaldır'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 18,
            runSpacing: 4,
            children: [
              tap(pair('Tel', c?.phone ?? ''), c?.phone ?? ''),
              if ((c?.phone2 ?? '').isNotEmpty) pair('2. tel', c!.phone2),
              tap(pair('E-posta', c?.email ?? ''), c?.email ?? ''),
              tap(pair('Adres', c?.address ?? ''), c?.address ?? ''),
              tap(pair(body ? 'VKN' : 'TCKN', c?.idNo ?? ''), c?.idNo ?? ''),
            ],
          ),
          if ((c?.note ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Not: ${c!.note}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AgendaColors.muted,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (!wide && (c?.phone ?? '').isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => launch('tel:${c!.phone}'),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('Ara'),
                ),
              if (!wide && (c?.email ?? '').isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => launch('mailto:${c!.email}'),
                  icon: const Icon(Icons.mail_outline_rounded, size: 18),
                  label: const Text('E-posta'),
                ),
              FilledButton.icon(
                key: const ValueKey('client-edit'),
                onPressed: _editContact,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Bilgileri düzenle'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('client-meeting'),
                onPressed: () => _meeting(),
                icon: const Icon(Icons.record_voice_over_outlined, size: 18),
                label: const Text('Görüşme tutanağı'),
              ),
              if (widget.seesMoney)
                OutlinedButton.icon(
                  key: const ValueKey('client-statement'),
                  onPressed: () => _statement(),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Hesap dökümü'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, {Color fill = AgendaColors.hearingFill}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      );

  Widget _frame(Widget child, {EdgeInsets? padding}) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: padding ?? const EdgeInsets.fromLTRB(14, 11, 14, 11),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AgendaColors.line),
    ),
    child: child,
  );

  Widget _box(
    String title, {
    int? count,
    Widget? action,
    required List<Widget> children,
  }) => _frame(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 34,
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .5,
                  color: AgendaColors.muted,
                ),
              ),
              if (count != null)
                Text(
                  '  $count',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AgendaColors.muted,
                  ),
                ),
              const Spacer(),
              ?action,
            ],
          ),
        ),
        ...children,
      ],
    ),
    padding: const EdgeInsets.fromLTRB(14, 4, 8, 8),
  );

  /// What is owed and held, all cases together.
  Widget _moneyStrip(Map<String, CaseAccount> accounts) {
    int sum(int Function(CaseAccount a) f) =>
        accounts.values.fold(0, (n, a) => n + f(a));
    final owed = sum((a) => a.feeOwed > 0 ? a.feeOwed : 0);
    final lawyer = sum((a) => a.lawyerOwed);
    final advance = sum((a) => a.advanceLeft);
    Widget chip(String label, int v, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AgendaColors.line),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label  '),
            TextSpan(
              text: lira(v),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: v == 0 ? AgendaColors.muted : color,
              ),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          chip('Ücret alacağı', owed, AgendaColors.deadlineText),
          chip('Avukat masrafı', lawyer, AgendaColors.deadlineText),
          chip('Avans', advance, const Color(0xFF1B6B3A)),
          TextButton(
            key: const ValueKey('client-accounts'),
            onPressed: _accounts,
            child: const Text('Tüm hesaplar'),
          ),
        ],
      ),
    );
  }

  static const _role = 100.0, _next = 120.0, _sum = 92.0, _menu = 40.0;

  Widget _caseHead() {
    Widget h(String t, double w, {bool right = false}) => SizedBox(
      width: w,
      child: Text(
        t,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: const TextStyle(fontSize: 11, color: AgendaColors.muted),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Dosya',
              style: TextStyle(fontSize: 11, color: AgendaColors.muted),
            ),
          ),
          h('Sıfat', _role),
          h('Sıradaki', _next),
          if (widget.seesMoney) ...[
            h('Ücret kalan', _sum, right: true),
            h('Avans', _sum, right: true),
            h('Masraf', _sum, right: true),
          ],
          const SizedBox(width: _menu),
        ],
      ),
    );
  }

  /// The fee still owed as the table shows it: none agreed, a share
  /// only, paid, or what is left.
  ({String text, Color? color}) _feeLeft(CaseAccount? a) {
    if (a == null || a.fee == null) return (text: '—', color: null);
    if (a.feeAgreed == 0) {
      return (text: a.feeShare > 0 ? '%${a.feeShare}' : '—', color: null);
    }
    if (a.feeOwed <= 0) return (text: 'ödendi', color: AgendaColors.ok);
    return (text: _plain(a.feeOwed), color: AgendaColors.deadlineText);
  }

  /// "15.000" from kuruş: TL is the column's.
  static String _plain(int kurus) => lira(kurus).replaceAll(' TL', '');

  Widget _caseRow(
    ({String caseKey, String role}) x,
    CaseAccount? a,
    String? next,
    bool wide,
  ) {
    final kase = _db.caseOf(x.caseKey);
    final hand = widget.entry.addedCases.contains(x.caseKey);
    final fee = _feeLeft(a);
    final advance = a?.advanceLeft ?? 0, cost = a?.lawyerOwed ?? 0;
    final menu = PopupMenuButton<String>(
      key: ValueKey('case-menu-${x.caseKey}'),
      tooltip: 'Dosya işlemleri',
      icon: const Icon(Icons.more_horiz_rounded, size: 20),
      onSelected: (v) => switch (v) {
        'ac' => widget.onOpenCase?.call(x.caseKey),
        'hesap' => _accounts(x.caseKey),
        'hareket' => _movement(x.caseKey),
        'ucret' => _fee(x.caseKey, a?.fee),
        _ => _takeOff(x),
      },
      itemBuilder: (_) => [
        if (widget.onOpenCase != null)
          const PopupMenuItem(value: 'ac', child: Text('Dosyayı aç')),
        if (widget.seesMoney) ...[
          const PopupMenuItem(value: 'hesap', child: Text('Hesabını aç')),
          const PopupMenuItem(value: 'hareket', child: Text('Hareket ekle')),
          const PopupMenuItem(value: 'ucret', child: Text('Ücret anlaşması')),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(
          key: ValueKey('case-remove-${x.caseKey}'),
          value: 'cikar',
          child: const Text(
            'Bu müvekkilden çıkar…',
            style: TextStyle(color: AgendaColors.deadlineText),
          ),
        ),
      ],
    );
    final title = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: kase?.number ?? x.caseKey,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (kase != null) TextSpan(text: ' ${kase.court}'),
          if (hand)
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: EdgeInsets.only(left: 6),
                child: _HandTag(),
              ),
            ),
        ],
      ),
      style: const TextStyle(fontSize: 13),
    );
    Text amount(String t, {Color? color}) => Text(
      t,
      textAlign: TextAlign.right,
      style: TextStyle(fontSize: 13, color: color),
    );
    final open = widget.onOpenCase == null
        ? null
        : () => widget.onOpenCase!(x.caseKey);
    if (wide) {
      return InkWell(
        key: ValueKey('client-case-${x.caseKey}'),
        onTap: open,
        child: Container(
          padding: const EdgeInsets.only(left: 4),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AgendaColors.line)),
          ),
          constraints: const BoxConstraints(minHeight: 38),
          child: Row(
            children: [
              Expanded(child: title),
              SizedBox(
                width: _role,
                child: Text(
                  titleName(x.role),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              SizedBox(
                width: _next,
                child: Text(next ?? '—', style: const TextStyle(fontSize: 13)),
              ),
              if (widget.seesMoney) ...[
                SizedBox(
                  width: _sum,
                  child: amount(fee.text, color: fee.color),
                ),
                SizedBox(
                  width: _sum,
                  child: amount(
                    _plain(advance),
                    color: advance > 0 ? const Color(0xFF1B6B3A) : null,
                  ),
                ),
                SizedBox(
                  width: _sum,
                  child: amount(
                    _plain(cost),
                    color: cost > 0 ? AgendaColors.deadlineText : null,
                  ),
                ),
              ],
              SizedBox(width: _menu, child: menu),
            ],
          ),
        ),
      );
    }
    return InkWell(
      key: ValueKey('client-case-${x.caseKey}'),
      onTap: open,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 6, 0, 6),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AgendaColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  Text(
                    [
                      if (x.role.isNotEmpty) titleName(x.role),
                      ?next,
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AgendaColors.muted,
                    ),
                  ),
                  if (widget.seesMoney)
                    Text(
                      'Ücret ${fee.text} · Avans ${_plain(advance)} · '
                      'Masraf ${_plain(cost)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
            menu,
          ],
        ),
      ),
    );
  }

  Widget _timeline(List<_Event> events) {
    final shown = _allEvents ? events.take(80) : events.take(6);
    return _box(
      'ZAMAN ÇİZELGESİ',
      action: events.length > 6
          ? TextButton(
              key: const ValueKey('client-timeline-all'),
              onPressed: () => setState(() => _allEvents = !_allEvents),
              child: Text(_allEvents ? 'Daha az' : 'Tümü ${events.length}'),
            )
          : null,
      children: [
        if (events.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'Henüz bir şey yok.',
              style: TextStyle(color: AgendaColors.muted),
            ),
          ),
        for (final ev in shown)
          InkWell(
            onTap: ev.caseKey == null || widget.onOpenCase == null
                ? null
                : () => widget.onOpenCase!(ev.caseKey!),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5, right: 8),
                    child: Icon(Icons.circle, size: 8, color: ev.color),
                  ),
                  SizedBox(
                    width: 74,
                    child: Text(
                      _day(ev.at),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AgendaColors.muted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: ev.title),
                          if (ev.detail.isNotEmpty)
                            TextSpan(
                              text: '  ${ev.detail}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AgendaColors.muted,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _attorneyBox(List<ClientRecord> attorneys) => _box(
    'VEKÂLETNAME',
    count: attorneys.length,
    action: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (attorneys.length > 2)
          TextButton(
            onPressed: () => _page(
              'Vekâletnameler',
              (_) => _attorneys(_records(ClientRecordKind.attorney)),
            ),
            child: const Text('Tümü'),
          ),
        TextButton(
          key: const ValueKey('client-attorney'),
          onPressed: _attorney,
          child: const Text('+ Ekle'),
        ),
      ],
    ),
    children: [
      if (attorneys.isEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text(
            'Vekâletname eklenmedi.',
            style: TextStyle(color: AgendaColors.muted),
          ),
        ),
      for (final a in attorneys.take(2)) _attorneyTile(a),
    ],
  );

  Widget _meetingBox(List<ClientRecord> meetings) => _box(
    'GÖRÜŞMELER',
    count: meetings.length,
    action: meetings.length > 2
        ? TextButton(
            onPressed: () => _page(
              'Görüşmeler',
              (_) => _meetings(_records(ClientRecordKind.meeting)),
            ),
            child: const Text('Tümü'),
          )
        : null,
    children: [
      if (meetings.isEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text(
            'Görüşme tutanağı yok.',
            style: TextStyle(color: AgendaColors.muted),
          ),
        ),
      for (final m in meetings.take(2)) _meetingTile(m),
    ],
  );

  Widget _meetingTile(ClientRecord m) {
    final start = DateTime.tryParse(m.text('baslangic')) ?? m.created;
    return ListTile(
      key: ValueKey('meeting-${m.id}'),
      title: Text(
        m.text('kararlar').isEmpty
            ? m.text('konusulanlar')
            : m.text('kararlar'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          '${_day(start)} ${_time(start)}',
          if (m.text('kanal').isNotEmpty) m.text('kanal'),
          m.locked ? 'imzalı' : 'imza bekliyor',
        ].join(' · '),
        style: TextStyle(
          color: m.locked ? AgendaColors.ok : AgendaColors.taskText,
        ),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) => switch (v) {
          'yaz' => _printMinutes(m),
          'imza' => _signed(m),
          'goster' => _preview(m, 'İmzalı tutanak'),
          _ => _meeting(m),
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'yaz',
            child: Text('Tutanağı yazdır / PDF'),
          ),
          if (clientFilesOf(m).isNotEmpty)
            const PopupMenuItem(
              value: 'goster',
              child: Text('İmzalı sureti göster'),
            ),
          if (!m.locked) ...[
            const PopupMenuItem(value: 'duzenle', child: Text('Düzenle')),
            const PopupMenuItem(
              value: 'imza',
              child: Text('İmzalı sureti ekle ve kilitle'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _meetings(List<ClientRecord> meetings) => ListView(
    children: [
      if (meetings.isEmpty)
        const Padding(
          padding: EdgeInsets.all(18),
          child: Text(
            'Görüşme tutanağı yok. Tutanak yazdırılıp müvekkile imzalatılır; '
            'imzalı sureti eklenince kilitlenir ve değiştirilemez.',
            style: TextStyle(color: AgendaColors.muted),
          ),
        ),
      for (final m in meetings) _meetingTile(m),
    ],
  );

  Widget _attorneyTile(ClientRecord a) {
    final powers = a.list('yetkiler');
    return ListTile(
      key: ValueKey('attorney-${a.id}'),
      leading: const Icon(Icons.assignment_ind_outlined),
      title: Text(
        [
          a.text('noter'),
          a.text('tarih'),
          if (a.text('yevmiye').isNotEmpty) 'Yevmiye ${a.text('yevmiye')}',
        ].where((s) => s.isNotEmpty).join(' · '),
      ),
      subtitle: Text(
        [
          if (a.text('kapsam').isNotEmpty) a.text('kapsam'),
          powers.isEmpty
              ? 'özel yetki yok'
              : 'özel yetkiler: ${powers.join(', ')}',
        ].join(' · '),
      ),
      trailing: clientFilesOf(a).isEmpty
          ? null
          : const Icon(Icons.visibility_outlined, size: 18),
      onTap: clientFilesOf(a).isEmpty ? null : () => _preview(a, 'Vekâletname'),
    );
  }

  Widget _attorneys(List<ClientRecord> attorneys) => ListView(
    children: [
      if (attorneys.isEmpty)
        const Padding(
          padding: EdgeInsets.all(18),
          child: Text(
            'Vekâletname eklenmedi.',
            style: TextStyle(color: AgendaColors.muted),
          ),
        ),
      for (final a in attorneys) _attorneyTile(a),
    ],
  );
}

/// One thing on the client's timeline: [day] when only its day counts.
class _Event {
  const _Event(
    this.at,
    this.title,
    this.detail,
    this.color, {
    this.caseKey,
    this.day = false,
  });
  final DateTime at;
  final String title, detail;
  final Color color;
  final String? caseKey;
  final bool day;
}

/// A case tied to the client by the lawyer's hand, not by its names.
class _HandTag extends StatelessWidget {
  const _HandTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: AgendaColors.taskFill,
      borderRadius: BorderRadius.circular(5),
    ),
    child: const Text(
      'elle',
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: AgendaColors.taskText,
      ),
    ),
  );
}

/// The cases kept, to tie some to a client by hand: found by number,
/// court or a party's name; [skip], the client's already.
class _CaseAddDialog extends StatefulWidget {
  const _CaseAddDialog({
    required this.database,
    required this.client,
    required this.skip,
  });
  final PortalDatabase database;
  final String client;
  final Set<String> skip;

  @override
  State<_CaseAddDialog> createState() => _CaseAddDialogState();
}

class _CaseAddDialogState extends State<_CaseAddDialog> {
  late final _all = () {
    final parties = widget.database.caseParties();
    return [
      for (final c in widget.database.cases().values)
        if (!widget.skip.contains(c.key))
          (
            key: c.key,
            number: c.number,
            court: c.court,
            parties: [
              for (final t in parties[c.key] ?? const <UyapParty>[])
                (name: t.name, role: t.role),
            ],
          ),
    ]..sort((a, b) => b.number.compareTo(a.number));
  }();
  final _picked = <String>{};
  final _role = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _role.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = UyapWebService.fold(_query.trim());
    final shown = [
      for (final c in _all)
        if (q.isEmpty ||
            UyapWebService.fold(
              '${c.number} ${c.court} ${c.parties.map((t) => t.name).join(' ')}',
            ).contains(q))
          c,
    ];
    return AlertDialog(
      title: const Text('Dosya ekle'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('case-add-search'),
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                hintText: 'Dosya no, mahkeme ya da taraf adı…',
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: shown.isEmpty
                  ? const Center(
                      child: Text(
                        'Eklenecek dosya bulunamadı.',
                        style: TextStyle(color: AgendaColors.muted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final c = shown[i];
                        return CheckboxListTile(
                          key: ValueKey('case-add-${c.key}'),
                          dense: true,
                          value: _picked.contains(c.key),
                          onChanged: (v) => setState(() {
                            if (v ?? false) {
                              _picked.add(c.key);
                              // The role the client's name has in it.
                              final same = c.parties
                                  .where(
                                    (t) =>
                                        UyapWebService.fold(t.name) ==
                                        UyapWebService.fold(widget.client),
                                  )
                                  .firstOrNull;
                              if (_role.text.isEmpty && same != null) {
                                _role.text = titleName(same.role);
                              }
                            } else {
                              _picked.remove(c.key);
                            }
                          }),
                          title: Text('${c.number} · ${c.court}'),
                          subtitle: c.parties.isEmpty
                              ? null
                              : Text(
                                  [
                                    for (final t in c.parties.take(3))
                                      '${titleName(t.role)}: '
                                          '${titleName(t.name)}',
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey('case-add-role'),
              controller: _role,
              decoration: const InputDecoration(
                labelText: 'Müvekkilin sıfatı',
                hintText: 'Davacı, davalı, alacaklı…',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const ValueKey('case-add-ok'),
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.pop(context, (
                  keys: _picked.toList(),
                  role: _role.text.trim(),
                )),
          child: Text(
            _picked.isEmpty ? 'Ekle' : '${_picked.length} dosyayı ekle',
          ),
        ),
      ],
    );
  }
}

class _ContactDialog extends StatefulWidget {
  const _ContactDialog(this.client);
  final Client client;

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  late final _name = TextEditingController(text: widget.client.name);
  late final _idNo = TextEditingController(text: widget.client.idNo);
  late final _phone = TextEditingController(text: widget.client.phone);
  late final _phone2 = TextEditingController(text: widget.client.phone2);
  late final _email = TextEditingController(text: widget.client.email);
  late final _address = TextEditingController(text: widget.client.address);
  late final _note = TextEditingController(text: widget.client.note);
  late bool _body = widget.client.body;

  @override
  void dispose() {
    for (final c in [_name, _idNo, _phone, _phone2, _email, _address, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(TextEditingController c, String label, {int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          maxLines: lines,
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Müvekkil bilgileri'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Kişi')),
                ButtonSegment(value: true, label: Text('Kurum')),
              ],
              selected: {_body},
              onSelectionChanged: (v) => setState(() => _body = v.first),
            ),
            const SizedBox(height: 12),
            _field(_name, 'Ad'),
            _field(_idNo, _body ? 'VKN' : 'TCKN'),
            _field(_phone, 'Telefon'),
            _field(_phone2, 'İkinci telefon'),
            _field(_email, 'E-posta'),
            _field(_address, 'Adres', lines: 2),
            _field(_note, 'Not', lines: 3),
            const Text(
              'Bilgiler alan alan eşitlenir: bir cihazda telefonu, ötekinde '
              'adresi değiştirirseniz ikisi de korunur.',
              style: TextStyle(fontSize: 12, color: AgendaColors.muted),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        key: const ValueKey('contact-save'),
        onPressed: () {
          final name = _name.text.trim();
          final c = widget.client;
          final names = {
            ...c.names,
            // The name it was found by stays one of its names.
            if (UyapWebService.fold(name) != UyapWebService.fold(c.name))
              UyapWebService.fold(c.name),
          }.toList();
          Navigator.pop(
            context,
            c.copyWith(
              name: name.isEmpty ? c.name : name,
              body: _body,
              idNo: _idNo.text.trim(),
              phone: _phone.text.trim(),
              phone2: _phone2.text.trim(),
              email: _email.text.trim(),
              address: _address.text.trim(),
              note: _note.text.trim(),
              names: names,
            ),
          );
        },
        child: const Text('Kaydet'),
      ),
    ],
  );
}

/// The minutes of a meeting, written; printed and signed afterwards.
class MeetingForm extends StatefulWidget {
  const MeetingForm({
    super.key,
    required this.client,
    required this.lawyer,
    this.cases = const [],
    this.kept,
  });

  final Client client;
  final String lawyer;
  final List<({String key, String title})> cases;
  final ClientRecord? kept;

  @override
  State<MeetingForm> createState() => _MeetingFormState();
}

class _MeetingFormState extends State<MeetingForm> {
  static const _channels = ['Yüz yüze', 'Telefon', 'Görüntülü'];
  late final ClientRecord? _kept = widget.kept;
  late String _channel = _kept?.text('kanal').isNotEmpty ?? false
      ? _kept!.text('kanal')
      : _channels.first;
  late DateTime _start =
      DateTime.tryParse(_kept?.text('baslangic') ?? '') ?? DateTime.now();
  late DateTime? _end = DateTime.tryParse(_kept?.text('bitis') ?? '');
  late String? _case = _kept?.text('dosya').isNotEmpty ?? false
      ? _kept!.text('dosya')
      : null;
  late final _place = TextEditingController(text: _kept?.text('yer') ?? '');
  late final _people = TextEditingController(
    text:
        _kept?.text('katilanlar') ??
        '${titleName(widget.client.name)} (müvekkil), ${widget.lawyer}',
  );
  late final _talked = TextEditingController(
    text: _kept?.text('konusulanlar') ?? '',
  );
  late final _decided = TextEditingController(
    text: _kept?.text('kararlar') ?? '',
  );
  late final _step = TextEditingController(
    text: '${(_kept?.data['gorev'] as Map?)?['baslik'] ?? ''}',
  );
  late DateTime _stepDay =
      DateTime.tryParse('${(_kept?.data['gorev'] as Map?)?['tarih']}') ??
      DateTime.now().add(const Duration(days: 3));

  /// Dictation goes into the field last touched.
  TextEditingController? _hearing;

  /// Dictation on a computer, where Folio has its model (docs: sesli
  /// okuma/yazma).
  bool get _canDictate =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _dictate(TextEditingController into) async {
    final d = Dictation.instance;
    if (d.state != ListenState.idle && d.owner == this) {
      await d.stop();
      return;
    }
    await ReadAloud.instance.stop();
    if (!mounted) return;
    final dir = await SpeechDownloadDialog.ensure(
      context,
      SpeechModel.dictation,
    );
    if (dir == null || !mounted) return;
    _hearing = into;
    await d.start(
      modelDir: dir,
      owner: this,
      onText: (text) {
        final c = _hearing;
        if (c == null || text.trim().isEmpty) return;
        final was = c.text;
        c.text = was.isEmpty || was.endsWith(' ') || was.endsWith('\n')
            ? '$was${text.trim()}'
            : '$was ${text.trim()}';
      },
    );
  }

  Widget? _mic(TextEditingController c) => !_canDictate
      ? null
      : IconButton(
          tooltip: 'Sesle yaz',
          icon: const Icon(Icons.mic_none_rounded),
          onPressed: () => unawaited(_dictate(c)),
        );

  @override
  void dispose() {
    if (Dictation.instance.owner == this) unawaited(Dictation.instance.stop());
    for (final c in [_place, _people, _talked, _decided, _step]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickStart() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (!mounted) return;
    setState(
      () => _start = DateTime(
        day.year,
        day.month,
        day.day,
        time?.hour ?? _start.hour,
        time?.minute ?? _start.minute,
      ),
    );
  }

  Future<void> _pickEnd() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_end ?? DateTime.now()),
    );
    if (time == null || !mounted) return;
    setState(
      () => _end = DateTime(
        _start.year,
        _start.month,
        _start.day,
        time.hour,
        time.minute,
      ),
    );
  }

  void _save() {
    final now = DateTime.now();
    final data = <String, Object?>{
      'kanal': _channel,
      'baslangic': _start.toIso8601String(),
      if (_end != null) 'bitis': _end!.toIso8601String(),
      'yer': _place.text.trim(),
      'katilanlar': _people.text.trim(),
      'konusulanlar': _talked.text.trim(),
      'kararlar': _decided.text.trim(),
      if (_case != null) 'dosya': _case,
      if (_step.text.trim().isNotEmpty)
        'gorev': {
          'baslik': _step.text.trim(),
          'tarih': _stepDay.toIso8601String(),
        },
    };
    final kept = _kept;
    Navigator.pop(
      context,
      kept == null
          ? ClientRecord(
              id: Client.newId(),
              clientId: widget.client.id,
              kind: ClientRecordKind.meeting,
              data: data,
              created: now,
              by: widget.lawyer,
              updated: now,
            )
          : kept.copyWith(data: {...kept.data, ...data}),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Görüşme tutanağı'),
      actions: [
        TextButton(
          key: const ValueKey('meeting-save'),
          onPressed: _save,
          child: const Text('Kaydet'),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<String>(
              segments: [
                for (final c in _channels)
                  ButtonSegment(value: c, label: Text(c)),
              ],
              selected: {_channel},
              onSelectionChanged: (v) => setState(() => _channel = v.first),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickStart,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text('${_day(_start)} ${_time(_start)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickEnd,
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: Text(_end == null ? 'Bitiş saati' : _time(_end!)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.cases.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: _case,
                decoration: const InputDecoration(
                  labelText: 'Dosya (isteğe bağlı)',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Genel')),
                  for (final c in widget.cases)
                    DropdownMenuItem(
                      value: c.key,
                      child: Text(c.title, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _case = v),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _place,
              decoration: const InputDecoration(labelText: 'Yer'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _people,
              decoration: const InputDecoration(labelText: 'Katılanlar'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('meeting-talked'),
              controller: _talked,
              minLines: 4,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: 'Konuşulanlar',
                suffixIcon: _mic(_talked),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('meeting-decided'),
              controller: _decided,
              minLines: 3,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: 'Kararlar, talimatlar ve verilen yetkiler',
                suffixIcon: _mic(_decided),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('meeting-step'),
                    controller: _step,
                    decoration: const InputDecoration(
                      labelText: 'Sonraki adım (görev olarak ajandaya)',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _stepDay,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null && mounted) setState(() => _stepDay = d);
                  },
                  child: Text(_day(_stepDay)),
                ),
              ],
            ),
            Center(child: SpeechBar(owner: this)),
            const SizedBox(height: 12),
            const Text(
              'Kaydedince "Tutanağı yazdır" ile çıkarıp müvekkile '
              'imzalatın; imzalı sureti ekleyince tutanak kilitlenir.',
              style: TextStyle(color: AgendaColors.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A power of attorney: the notary's details, its special powers, its scan.
class AttorneyForm extends StatefulWidget {
  const AttorneyForm({
    super.key,
    required this.client,
    required this.lawyer,
    required this.files,
    this.cases = const [],
  });

  final Client client;
  final String lawyer;
  final ClientFiles files;
  final List<({String key, String title})> cases;

  @override
  State<AttorneyForm> createState() => _AttorneyFormState();
}

class _AttorneyFormState extends State<AttorneyForm> {
  /// The special powers a lawyer is to be given by name (HMK m.74).
  static const _powers = [
    'ahzu kabz',
    'feragat',
    'kabul',
    'sulh',
    'ibra',
    'hakem tayini',
    'davadan vazgeçme',
  ];
  final _notary = TextEditingController();
  final _date = TextEditingController();
  final _journal = TextEditingController();
  final _scope = TextEditingController(text: 'Genel dava vekâletnamesi');
  final _chosen = <String>{};
  final _forCases = <String>{};
  ClientFile? _scan;

  @override
  void dispose() {
    for (final c in [_notary, _date, _journal, _scope]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final path = await pickScan(context, 'Vekâletnamenin taranmış sureti');
    if (path == null) return;
    final kept = await widget.files.keep(widget.client.id, path);
    if (mounted) setState(() => _scan = kept);
  }

  void _save() {
    final now = DateTime.now();
    Navigator.pop(
      context,
      ClientRecord(
        id: Client.newId(),
        clientId: widget.client.id,
        kind: ClientRecordKind.attorney,
        data: {
          'noter': _notary.text.trim(),
          'tarih': _date.text.trim(),
          'yevmiye': _journal.text.trim(),
          'kapsam': _scope.text.trim(),
          'yetkiler': _chosen.toList(),
          'dosyalar': _forCases.toList(),
          if (_scan != null) 'ekler': [clientFileJson(_scan!)],
        },
        created: now,
        by: widget.lawyer,
        updated: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Vekâletname'),
      actions: [
        TextButton(
          key: const ValueKey('attorney-save'),
          onPressed: _save,
          child: const Text('Kaydet'),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(_scan == null ? 'Taranmış sureti seç' : _scan!.name),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('attorney-notary'),
              controller: _notary,
              decoration: const InputDecoration(labelText: 'Noter'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _date,
                    decoration: const InputDecoration(
                      labelText: 'Tarih (gg.aa.yyyy)',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _journal,
                    decoration: const InputDecoration(labelText: 'Yevmiye no'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _scope,
              decoration: const InputDecoration(labelText: 'Kapsam'),
            ),
            const SizedBox(height: 14),
            const Text(
              'Özel yetkiler',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final p in _powers)
                  FilterChip(
                    label: Text(p),
                    selected: _chosen.contains(p),
                    onSelected: (on) =>
                        setState(() => on ? _chosen.add(p) : _chosen.remove(p)),
                  ),
              ],
            ),
            if (widget.cases.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Kullanıldığı dosyalar',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final c in widget.cases)
                CheckboxListTile(
                  dense: true,
                  value: _forCases.contains(c.key),
                  title: Text(c.title),
                  onChanged: (on) => setState(
                    () => on ?? false
                        ? _forCases.add(c.key)
                        : _forCases.remove(c.key),
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}
