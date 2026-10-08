import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/clients/client.dart';
import '../../services/clients/client_accounts.dart';
import '../../services/clients/client_documents.dart';
import '../../services/editor/lawyer_profile.dart';
import '../../services/clients/client_files.dart';
import '../../services/clients/client_statement_pdf.dart';
import '../../services/clients/fee_reminders.dart';
import '../../services/portal/portal_database.dart';
import '../../services/platform/document_scan.dart';
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
  });

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
    setState(() {
      _entries = db.clientEntries(lawyer: widget.lawyer);
      _late = late;
    });
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

  // Keyed by its name, not its key: the card made at its first record
  // is the same client, its tab kept.
  Widget _detail(ClientEntry e) => ClientCard(
    key: ValueKey(UyapWebService.fold(e.name)),
    entry: e,
    database: _db!,
    lawyer: widget.lawyer,
    files: widget.files ?? ClientFiles(),
    person: widget.person,
    seesMoney: widget.seesMoney,
    inOffice: widget.inOffice,
    onEdit: widget.onEdit,
    onOpenCase: widget.onOpenCase,
    onChanged: (key) {
      // A card made for a client only seen in the cases: it is the one
      // chosen now, under its id.
      if (_selected != null) _selected = key;
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Müvekkiller',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            key: const ValueKey('clients-search'),
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              hintText: 'Ad, TCKN/VKN ya da dosya no…',
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
        SizedBox(width: 320, child: Material(child: list)),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const Center(
                  child: Text(
                    'Soldan bir müvekkil seçin.',
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
  });

  final ClientEntry entry;
  final ValueChanged<String>? onEdit;
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

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final c = _client;
    final meetings = _records(ClientRecordKind.meeting);
    final attorneys = _records(ClientRecordKind.attorney);
    final contact = [
      c?.body ?? false ? 'Kurum' : 'Kişi',
      if ((c?.idNo ?? '').isNotEmpty) c!.idNo,
      if ((c?.phone ?? '').isNotEmpty) c!.phone,
      if ((c?.email ?? '').isNotEmpty) c!.email,
    ].join(' · ');
    final money = widget.seesMoney
        ? [
            for (final r in _records())
              if (r.kind.money) r,
          ]
        : const <ClientRecord>[];
    return DefaultTabController(
      length: widget.seesMoney ? 5 : 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Avatar(e.name, body: c?.body ?? false, size: 48),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleName(c?.name ?? e.name),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        contact,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AgendaColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('client-edit'),
                  onPressed: _editContact,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Bilgiler'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('client-meeting'),
                  onPressed: () => _meeting(),
                  icon: const Icon(Icons.record_voice_over_outlined, size: 18),
                  label: const Text('Görüşme tutanağı'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('client-attorney'),
                  onPressed: _attorney,
                  icon: const Icon(Icons.assignment_ind_outlined, size: 18),
                  label: const Text('Vekâletname'),
                ),
                if (widget.seesMoney)
                  OutlinedButton.icon(
                    key: const ValueKey('client-statement'),
                    onPressed: () => _statement(),
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('Hesap dökümü'),
                  ),
                if (widget.inOffice)
                  FilterChip(
                    key: const ValueKey('client-share'),
                    avatar: Icon(
                      c?.office ?? false
                          ? Icons.groups_rounded
                          : Icons.lock_outline_rounded,
                      size: 18,
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
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: 'Özet'),
              Tab(text: 'Dosyalar ${e.cases.length}'),
              if (widget.seesMoney) const Tab(text: 'Hesaplar'),
              Tab(text: 'Görüşmeler ${meetings.length}'),
              Tab(text: 'Vekâletnameler ${attorneys.length}'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _summary(meetings, attorneys, money),
                _cases(),
                if (widget.seesMoney)
                  ClientAccountsView(
                    client:
                        c ??
                        Client(id: '', name: e.name, updated: DateTime(2000)),
                    records: money,
                    cases: _caseList,
                    onMovement: _movement,
                    onFee: _fee,
                    onReverse: _reverse,
                    onOpen: (m) => _preview(m, 'Belge'),
                    onStatement: _statement,
                    onPaper: _paper,
                  ),
                _meetings(meetings),
                _attorneys(attorneys),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) => Card(
    margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: AgendaColors.line),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
                color: AgendaColors.muted,
              ),
            ),
          ),
          ...rows,
        ],
      ),
    ),
  );

  Widget _summary(
    List<ClientRecord> meetings,
    List<ClientRecord> attorneys,
    List<ClientRecord> money,
  ) {
    final hearings = _hearings;
    final accounts = caseAccounts(money).values;
    int sum(int Function(CaseAccount a) f) =>
        accounts.fold(0, (n, a) => n + f(a));
    final owed = sum((a) => a.feeOwed > 0 ? a.feeOwed : 0);
    final lawyer = sum((a) => a.lawyerOwed);
    final advance = sum((a) => a.advanceLeft);
    Widget box(String label, int v, Color color) => Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AgendaColors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
              ),
              const SizedBox(height: 4),
              Text(
                lira(v),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: v == 0 ? AgendaColors.muted : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (widget.seesMoney)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                box('Ücret alacağı', owed, AgendaColors.deadlineText),
                box('Avukatın masrafı', lawyer, AgendaColors.deadlineText),
                box('Avans bakiyesi', advance, const Color(0xFF1B6B3A)),
              ],
            ),
          ),
        if (widget.seesMoney && _client != null)
          ...() {
            final due = [
              for (final t in FeeReminders.open(_db, DateTime.now()))
                if (widget.entry.ids.contains(t.client.id) ||
                    t.client.id == _client!.id)
                  t,
            ];
            return [
              if (due.isNotEmpty)
                _section('TAKSİTLER', [
                  for (final t in due)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        t.daysLeft < 0
                            ? Icons.error_outline_rounded
                            : Icons.schedule_rounded,
                        size: 20,
                        color: t.daysLeft < 0
                            ? AgendaColors.deadline
                            : AgendaColors.task,
                      ),
                      title: Text('${_day(t.due)} · ${lira(t.amount)}'),
                      subtitle: Text(
                        [
                          _caseTitle(t.caseKey),
                          t.daysLeft < 0
                              ? '${-t.daysLeft} gün gecikti'
                              : t.daysLeft == 0
                              ? 'bugün'
                              : '${t.daysLeft} gün kaldı',
                        ].join(' · '),
                      ),
                    ),
                ]),
            ];
          }(),
        _section('YAKLAŞAN DURUŞMALAR', [
          if (hearings.isEmpty)
            const ListTile(dense: true, title: Text('Yaklaşan duruşma yok.')),
          for (final h in hearings.take(3))
            ListTile(
              dense: true,
              leading: const Icon(Icons.gavel_rounded, size: 20),
              title: Text('${_day(h.at)} ${_time(h.at)}'),
              subtitle: Text('${h.number} · ${h.court}'),
              onTap: widget.onOpenCase == null
                  ? null
                  : () => widget.onOpenCase!(h.caseKey),
            ),
        ]),
        if (meetings.isNotEmpty)
          _section('SON GÖRÜŞME', [_meetingTile(meetings.first)]),
        _section('VEKÂLETNAMELER', [
          if (attorneys.isEmpty)
            const ListTile(dense: true, title: Text('Vekâletname eklenmedi.')),
          for (final a in attorneys.take(2)) _attorneyTile(a),
        ]),
        if ((_client?.note ?? '').isNotEmpty)
          _section('NOT', [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(_client!.note),
            ),
          ]),
      ],
    );
  }

  Widget _cases() => ListView(
    children: [
      for (final c in widget.entry.cases)
        ListTile(
          key: ValueKey('client-case-${c.caseKey}'),
          leading: const Icon(Icons.folder_outlined),
          title: Text(_caseTitle(c.caseKey)),
          subtitle: Text(titleName(c.role)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: widget.onOpenCase == null
              ? null
              : () => widget.onOpenCase!(c.caseKey),
        ),
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
  late final _email = TextEditingController(text: widget.client.email);
  late final _address = TextEditingController(text: widget.client.address);
  late final _note = TextEditingController(text: widget.client.note);
  late bool _body = widget.client.body;

  @override
  void dispose() {
    for (final c in [_name, _idNo, _phone, _email, _address, _note]) {
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
            _field(_email, 'E-posta'),
            _field(_address, 'Adres', lines: 2),
            _field(_note, 'Not', lines: 3),
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

  @override
  void dispose() {
    for (final c in [_place, _people, _talked, _decided]) {
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
              decoration: const InputDecoration(labelText: 'Konuşulanlar'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('meeting-decided'),
              controller: _decided,
              minLines: 3,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: 'Kararlar, talimatlar ve verilen yetkiler',
              ),
            ),
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
