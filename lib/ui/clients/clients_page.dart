import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../services/clients/client.dart';
import '../../services/clients/client_files.dart';
import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_hearing.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../portfolio/portfolio_rows.dart' show titleName;
import '../widgets/notice.dart';

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
  });

  /// "Av. Deniz Kaya": whose clients, and who writes their records.
  final String lawyer;
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
  String? _selected;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final db = _db ??= widget.database ?? await PortalDatabase.shared();
    if (!mounted) return;
    setState(() => _entries = db.clientEntries(lawyer: widget.lawyer));
  }

  List<ClientEntry> get _shown {
    final q = UyapWebService.fold(_query.trim());
    if (q.isEmpty) return _entries;
    return [
      for (final e in _entries)
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

  Widget _detail(ClientEntry e) => ClientCard(
    key: ValueKey(e.key),
    entry: e,
    database: _db!,
    lawyer: widget.lawyer,
    files: widget.files ?? ClientFiles(),
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
                        '${e.cases.length} dosya',
                        style: const TextStyle(fontSize: 12),
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
  });

  final ClientEntry entry;
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
    );
    _db.saveClient(made);
    _client = made;
    return made;
  }

  List<ClientRecord> _records(ClientRecordKind kind) {
    final c = _client;
    return c == null ? const [] : _db.clientRecords(c.id, kind: kind);
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
    _db.saveClientRecord(saved);
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
      await Printing.layoutPdf(
        name: 'Görüşme tutanağı ${_day(m.created)}.pdf',
        onLayout: (_) async => bytes,
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
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'İmzalı tutanağın taranmış hâli',
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    final path = picked?.files.single.path;
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
    _db.saveClientRecord(saved);
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
    return DefaultTabController(
      length: 4,
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
              ],
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: 'Özet'),
              Tab(text: 'Dosyalar ${e.cases.length}'),
              Tab(text: 'Görüşmeler ${meetings.length}'),
              Tab(text: 'Vekâletnameler ${attorneys.length}'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _summary(meetings, attorneys),
                _cases(),
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

  Widget _summary(List<ClientRecord> meetings, List<ClientRecord> attorneys) {
    final hearings = _hearings;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
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
          _ => _meeting(m),
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'yaz',
            child: Text('Tutanağı yazdır / PDF'),
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
          : const Icon(Icons.attach_file_rounded, size: 18),
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
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Vekâletnamenin taranmış sureti',
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'tif', 'tiff'],
    );
    final path = picked?.files.single.path;
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
