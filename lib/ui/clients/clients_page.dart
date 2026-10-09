import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../tools/interest_page.dart';
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
import 'client_message_dialog.dart';
import '../../services/clients/client_messages.dart';
import '../../services/clients/client_overview.dart';

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

  /// A case opened from a client's card: the case's key, and the client's.
  final void Function(String caseKey, String clientKey)? onOpenCase;

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  PortalDatabase? _db;
  List<ClientEntry> _entries = const [];
  String _query = '';

  /// The clients whose instalments are late, by card id: how many.
  Map<String, int> _late = const {};
  String? _selected;

  /// Each client at a glance, by key (the list's lines and filters).
  Map<String, ClientGlance> _glance = const {};
  _Filter _filter = _Filter.all;

  /// The lawyer's group the list is narrowed to; null for all.
  String? _group;
  List<String> _groups = const [];

  /// By name alone, not by what is coming first.
  bool _byName = false;

  /// The messages the day asks for (hearings and instalments of clients
  /// who wish to be told).
  List<DueMessage> _due = const [];

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
    final entries = db.clientEntries(lawyer: widget.lawyer);
    final due = dueMessages(db, DateTime.now(), entries);
    final glance = clientGlances(
      db,
      entries,
      DateTime.now(),
      money: widget.seesMoney,
    );
    final groups = clientGroups(db);
    setState(() {
      _entries = entries;
      _late = late;
      _due = due;
      _glance = glance;
      _groups = groups;
      if (_group != null && !groups.contains(_group)) _group = null;
    });
    if (first != null) {
      final e = _entries.where((x) => x.key == first).firstOrNull;
      if (e != null) _open(e);
    }
  }

  static const _listKey = 'muvekkil_listesi';

  /// The day's messages, each opened in turn; the list kept up as they go.
  Future<void> _dueList() async {
    final db = _db!;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, again) {
          final due = dueMessages(db, DateTime.now(), _entries);
          return AlertDialog(
            title: const Text('Bugün gönderilecek mesajlar'),
            content: SizedBox(
              width: 440,
              child: due.isEmpty
                  ? const Text(
                      'Gönderilecek mesaj kalmadı.',
                      style: TextStyle(color: AgendaColors.muted),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final d in due)
                          ListTile(
                            key: ValueKey('due-${d.about}'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(titleName(d.client.name)),
                            subtitle: Text(
                              d.kind == MessageKind.hearing
                                  ? 'Duruşma ${_day(d.at)} ${_time(d.at)}'
                                        ' · ${d.daysLeft == 0 ? 'bugün' : '${d.daysLeft} gün sonra'}'
                                  : 'Taksit ${lira(d.amount)} · '
                                        '${d.daysLeft < 0
                                            ? '${-d.daysLeft} gün gecikti'
                                            : d.daysLeft == 0
                                            ? 'bugün'
                                            : '${d.daysLeft} gün sonra'}',
                            ),
                            trailing: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1FA855),
                              ),
                              onPressed: () async {
                                final e = _entries
                                    .where(
                                      (x) =>
                                          x.client?.id == d.client.id ||
                                          x.ids.contains(d.client.id),
                                    )
                                    .firstOrNull;
                                final sent = await showDialog<ClientRecord>(
                                  context: context,
                                  builder: (_) => ClientMessageDialog(
                                    client: d.client,
                                    cases: e?.cases ?? const [],
                                    ids: e?.ids ?? const [],
                                    database: db,
                                    lawyer: widget.lawyer,
                                    person: widget.person,
                                    seesMoney: widget.seesMoney,
                                    due: d,
                                  ),
                                );
                                if (sent == null) return;
                                db.saveClientRecord(sent);
                                again(() {});
                              },
                              child: const Text('Aç'),
                            ),
                          ),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kapat'),
              ),
            ],
          );
        },
      ),
    );
    await _load();
  }

  void _fold(bool open) {
    _db?.setMeta(_listKey, open ? 'acik' : 'kapali');
    setState(() => _listOpen = open);
  }

  int _lateOf(ClientEntry e) =>
      [for (final id in e.ids) _late[id] ?? 0].fold(0, (a, b) => a + b);

  /// Whether [e] is one the filter [f] keeps.
  bool _keeps(_Filter f, ClientEntry e) {
    final g = _glance[e.key];
    final week = DateTime.now().add(const Duration(days: 7));
    // A hidden client is under "Gizli", and found when searched for by
    // name, TCKN or case; a group narrows them all.
    final hidden = e.client?.hidden ?? false;
    if (f == _Filter.hidden) return hidden;
    if (hidden && (_query.trim().isEmpty || f != _Filter.all)) return false;
    if (_group != null && (e.client?.group ?? '') != _group) return false;
    return switch (f) {
      _Filter.all => true,
      _Filter.open => (g?.open ?? 0) > 0,
      _Filter.week => g?.next != null && g!.next!.at.isBefore(week),
      _Filter.owed => (g?.owed ?? 0) > 0,
      _Filter.late => _lateOf(e) > 0,
      _Filter.unreachable => !(g?.reachable ?? false),
      _Filter.body => e.client?.body ?? false,
      _Filter.hidden => hidden,
    };
  }

  List<ClientEntry> get _shown {
    final q = UyapWebService.fold(_query.trim());
    final base = [
      for (final e in _entries)
        if (_keeps(_filter, e)) e,
    ];
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
              builder: (page) => Scaffold(
                appBar: AppBar(title: const Text('Müvekkil')),
                // A case opened from here comes in front: this page is
                // closed first, not left over it.
                body: _detail(e, closing: () => Navigator.of(page).pop()),
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
  Widget _detail(ClientEntry e, {VoidCallback? closing}) => ClientCard(
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
    onOpenCase: widget.onOpenCase == null
        ? null
        : (caseKey) {
            closing?.call();
            widget.onOpenCase!(caseKey, e.key);
          },
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

  /// A client written in by hand, one with no case in UYAP yet: kept,
  /// listed and opened at once.
  Future<void> _newClient() async {
    final db = _db;
    if (db == null) return;
    final made = await showDialog<Client>(
      context: context,
      builder: (_) => _ContactDialog(
        Client(
          id: Client.newId(),
          name: '',
          updated: DateTime.now(),
          person: widget.person,
          group: _group ?? '',
        ),
        groups: _groups,
        fresh: true,
      ),
    );
    if (made == null || made.name.trim().isEmpty || !mounted) return;
    db.saveClient(made);
    setState(() => _filter = _Filter.all);
    await _load();
    final e = _entries.where((x) => x.client?.id == made.id).firstOrNull;
    if (e != null && mounted) _open(e);
  }

  /// The filters, each with how many it keeps, and the order.
  Widget _filters() {
    final kinds = [
      _Filter.all,
      _Filter.open,
      _Filter.week,
      if (widget.seesMoney) _Filter.owed,
      if (_late.isNotEmpty) _Filter.late,
      _Filter.unreachable,
      _Filter.body,
      if (_entries.any((e) => e.client?.hidden ?? false)) _Filter.hidden,
    ];
    Widget chip(_Filter f) {
      final on = _filter == f;
      final n = _entries.where((e) => _keeps(f, e)).length;
      return InkWell(
        key: ValueKey(
          f == _Filter.late ? 'clients-late' : 'clients-filter-${f.name}',
        ),
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _filter = on ? _Filter.all : f),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: on ? AgendaColors.hearing : null,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: on ? AgendaColors.hearing : AgendaColors.line,
            ),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: f.label),
                TextSpan(
                  text: ' $n',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            style: TextStyle(
              fontSize: 11.5,
              color: on ? Colors.white : const Color(0xFF4A5466),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final f in kinds) chip(f),
              if (_groups.isNotEmpty)
                PopupMenuButton<String>(
                  key: const ValueKey('clients-group'),
                  tooltip: 'Gruba göre',
                  onSelected: (g) =>
                      setState(() => _group = g.isEmpty ? null : g),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: '', child: Text('Tüm gruplar')),
                    for (final g in _groups)
                      PopupMenuItem(value: g, child: Text(g)),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _group == null ? null : AgendaColors.hearingFill,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _group == null
                            ? AgendaColors.line
                            : AgendaColors.hearing,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _group == null ? 'Grup' : 'Grup: $_group',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _group == null
                                ? const Color(0xFF4A5466)
                                : AgendaColors.hearingText,
                            fontWeight: _group == null ? null : FontWeight.w700,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down_rounded, size: 16),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  _byName ? 'Sıra: ada göre' : 'Sıra: yaklaşan işe göre',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AgendaColors.muted,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('clients-order'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => setState(() => _byName = !_byName),
                child: Text(
                  _byName ? 'Yaklaşana göre' : 'Ada göre',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The clients shown, in groups (this week, still worked on, done with)
  /// or by name alone.
  Widget _listOf(List<ClientEntry> shown, bool wide) {
    int byName(ClientEntry a, ClientEntry b) =>
        UyapWebService.fold(a.name).compareTo(UyapWebService.fold(b.name));
    final items = <Object>[];
    if (_byName) {
      items.addAll(List<ClientEntry>.of(shown)..sort(byName));
    } else {
      final week = DateTime.now().add(const Duration(days: 7));
      final soon = <ClientEntry>[], open = <ClientEntry>[];
      final done = <ClientEntry>[];
      for (final e in shown) {
        final g = _glance[e.key];
        if (g?.next != null && g!.next!.at.isBefore(week)) {
          soon.add(e);
        } else if (g?.done ?? false) {
          done.add(e);
        } else {
          open.add(e);
        }
      }
      soon.sort(
        (a, b) => _glance[a.key]!.next!.at.compareTo(_glance[b.key]!.next!.at),
      );
      open.sort(byName);
      done.sort(byName);
      if (soon.isNotEmpty) items.addAll(['BU HAFTA', ...soon]);
      if (open.isNotEmpty) items.addAll(['AÇIK DOSYASI OLAN', ...open]);
      if (done.isNotEmpty) items.addAll(['SONUÇLANMIŞ', ...done]);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 3),
            child: Text(
              item,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
                color: AgendaColors.muted,
              ),
            ),
          );
        }
        final e = item as ClientEntry;
        return _ClientLine(
          entry: e,
          glance: _glance[e.key],
          late: _lateOf(e),
          selected: wide && e.key == _selected,
          onTap: () => _open(e),
        );
      },
    );
  }

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
              Expanded(
                child: Text(
                  'Müvekkiller',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('clients-new'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: _newClient,
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Yeni'),
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
        if (_due.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Material(
              color: const Color(0xFFE7F6EC),
              borderRadius: BorderRadius.circular(10),
              child: ListTile(
                key: const ValueKey('clients-due'),
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                leading: const Icon(
                  Icons.chat_outlined,
                  color: Color(0xFF11663A),
                ),
                title: Text(
                  'Bugün gönderilecek ${_due.length} mesaj',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF11663A),
                  ),
                ),
                onTap: _dueList,
              ),
            ),
          ),
        _filters(),
        Expanded(
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    _entries.isEmpty
                        ? 'Müvekkil yok. Müvekkiller, UYAP dosyalarında vekili '
                              'olduğunuz taraflardan ve "kimi temsil ediyorum" '
                              'kayıtlarından kendiliğinden gelir.'
                        : 'Bu süzgece uyan müvekkil yok.',
                    style: const TextStyle(
                      color: AgendaColors.muted,
                      fontSize: 13,
                    ),
                  ),
                )
              : _listOf(shown, wide),
        ),
      ],
    );
    if (!wide) return list;
    final selected = shown.where((e) => e.key == _selected).firstOrNull;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_listOpen)
          SizedBox(width: 300, child: Material(child: list))
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

/// What the client list is narrowed to.
enum _Filter {
  all('Tümü'),
  open('Açık dosyalı'),
  week('Bu hafta'),
  owed('Alacaklı'),
  late('Taksiti gecikmiş'),
  unreachable('İletişimi eksik'),
  body('Kurum'),
  hidden('Gizli');

  const _Filter(this.label);
  final String label;
}

/// A name as UYAP lists it, its brackets off ("[MUSTAFA KAYA]").
String _bare(String name) => name.replaceAll(RegExp(r'[\[\]]'), '').trim();

/// "14 Eki".
String _shortDay(DateTime d) {
  const months = [
    'Oca',
    'Şub',
    'Mar',
    'Nis',
    'May',
    'Haz',
    'Tem',
    'Ağu',
    'Eyl',
    'Eki',
    'Kas',
    'Ara',
  ];
  return '${d.day} ${months[d.month - 1]}';
}

/// A small coloured label: a hearing (blue), a deadline (red), money
/// (amber), a year done (grey).
class _Pill extends StatelessWidget {
  const _Pill(this.text, this.fill, this.ink);
  final String text;
  final Color fill, ink;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ),
      ],
    ),
  );
}

/// One client in the list: initials, name, cases, and on the right what is
/// nearest for them.
class _ClientLine extends StatelessWidget {
  const _ClientLine({
    required this.entry,
    required this.glance,
    required this.late,
    required this.selected,
    required this.onTap,
  });

  final ClientEntry entry;
  final ClientGlance? glance;
  final int late;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = glance;
    final done = g?.done ?? false;
    final next = g?.next;
    final soon =
        next != null &&
        next.at.isBefore(DateTime.now().add(const Duration(days: 30)));
    final hidden = entry.client?.hidden ?? false;
    final Widget? tag = hidden
        ? const _Pill('gizli', Color(0xFFEEF1F5), AgendaColors.muted)
        : late > 0
        ? _Pill(
            '$late taksit gecikti',
            AgendaColors.deadlineFill,
            AgendaColors.deadlineText,
          )
        : soon
        ? _Pill(
            '${next.hearing ? 'Duruşma' : 'Süre'} ${_shortDay(next.at)}',
            next.hearing ? AgendaColors.hearingFill : AgendaColors.deadlineFill,
            next.hearing ? AgendaColors.hearingText : AgendaColors.deadlineText,
          )
        : (g?.owed ?? 0) > 0
        ? _Pill(lira(g!.owed), AgendaColors.taskFill, AgendaColors.taskText)
        : done && g?.closedYear != null
        ? _Pill('${g!.closedYear}', const Color(0xFFEEF1F5), AgendaColors.muted)
        : null;
    return Material(
      color: selected ? AgendaColors.hearingFill : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        key: ValueKey('client-${entry.key}'),
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(
            children: [
              ClientInitials(
                entry.name,
                body: entry.client?.body ?? false,
                faded: done,
                size: 32,
              ),
              const SizedBox(width: 9),
              // The name alone on its line, the whole width: read in full;
              // what is nearest beneath it.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleName(entry.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            [
                              '${entry.cases.length} dosya',
                              if (done)
                                'sonuçlandı'
                              else if ((g?.open ?? 0) > 0)
                                '${g!.open} açık',
                              if ((entry.client?.group ?? '').isNotEmpty)
                                entry.client!.group,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AgendaColors.muted,
                            ),
                          ),
                        ),
                        if (tag != null) ...[const SizedBox(width: 6), tag],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A client's initials on a colour of their own, the same on every
/// device: an office square, a person round; grey once done with.
class ClientInitials extends StatelessWidget {
  const ClientInitials(
    this.name, {
    super.key,
    this.body = false,
    this.faded = false,
    this.size = 36,
  });

  final String name;
  final bool body, faded;
  final double size;

  static const _palette = [
    Color(0xFF2D5AA8),
    Color(0xFF16754F),
    Color(0xFF7A4FC4),
    Color(0xFFB5562C),
    Color(0xFF0C6B5F),
    Color(0xFF9C2550),
    Color(0xFF3B6E8F),
    Color(0xFF8A5A00),
    Color(0xFF4E5BA6),
    Color(0xFF2F7D32),
  ];

  /// [name]'s colour: from its letters, so it never changes.
  static Color colorOf(String name) {
    var h = 0;
    for (final c in UyapWebService.fold(name).codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _palette[h % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final letters = [
      for (final w in name.trim().split(RegExp(r'\s+')).take(2))
        if (w.isNotEmpty) w.characters.first.toUpperCase(),
    ].join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: faded ? const Color(0xFF8A93A3) : colorOf(name),
        borderRadius: BorderRadius.circular(body ? size * .24 : size / 2),
      ),
      child: Text(
        letters,
        style: TextStyle(
          fontSize: size * .36,
          fontWeight: FontWeight.w700,
          color: Colors.white,
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
    final why = await showDialog<String>(
      context: context,
      builder: (_) => const _NoteDialog(
        title: 'Ters kayıtla düzelt',
        label: 'Neden',
        ok: 'Düzelt',
        lines: 1,
      ),
    );
    if (why == null) return;
    final reason = why.trim();
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
      builder: (_) => _ContactDialog(card, groups: clientGroups(_db)),
    );
    if (saved == null) return;
    _db.saveClient(saved);
    if (mounted) setState(() => _client = saved);
    widget.onChanged?.call(saved.id);
  }

  /// The client kept but no more listed, or listed again.
  void _hide(bool hide) {
    final saved = _card().copyWith(hidden: hide);
    _db.saveClient(saved);
    setState(() => _client = saved);
    widget.onChanged?.call(saved.id);
    showNotice(
      context,
      hide
          ? 'Müvekkil listede gizlendi; "Gizli" süzgecinde görünür.'
          : 'Müvekkil yeniden listede.',
    );
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

  /// A message to the client, opened in the lawyer's own WhatsApp, SMS or
  /// e-mail and kept on their timeline once opened.
  Future<void> _message() async {
    final card = _card();
    final sent = await showDialog<ClientRecord>(
      context: context,
      builder: (_) => ClientMessageDialog(
        client: card,
        cases: widget.entry.cases,
        ids: widget.entry.ids,
        database: _db,
        lawyer: widget.lawyer,
        person: widget.person,
        seesMoney: widget.seesMoney,
      ),
    );
    if (sent == null) return;
    _keep(sent);
    if (mounted) setState(() {});
    widget.onChanged?.call(card.id);
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
  ({List<_Event> coming, List<_Event> past}) _events(
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
      for (final m in _records(ClientRecordKind.message))
        _Event(
          m.created,
          'Mesaj (${MessageChannel.values.where((c) => c.name == m.text('kanal')).firstOrNull?.label ?? ''}): '
          '${MessageKind.values.where((k) => k.name == m.text('tur')).firstOrNull?.label ?? ''}',
          m.text('dosya').isEmpty ? '' : _number(m.text('dosya')),
          AgendaColors.hearing,
        ),
      // Notices of the client's cases, and the cases that closed.
      for (final x in widget.entry.cases) ...[
        for (final n in _db.notices(caseKey: x.caseKey).take(5))
          if (n.message.sent case final sent?)
            _Event(
              sent,
              [
                'Tebligat',
                noticeTopic(
                  n.message.subject,
                  _db.caseOf(x.caseKey)?.court ?? '',
                ),
              ].where((s) => s.isNotEmpty).join(': '),
              _number(x.caseKey),
              const Color(0xFF139C8B),
              caseKey: x.caseKey,
            ),
        if (DateTime.tryParse(
              '${_db.caseOf(x.caseKey)?.details?.value['kapanis'] ?? ''}',
            )
            case final closed?)
          _Event(
            closed,
            stageLabel(_db.caseOf(x.caseKey)?.status?.value ?? 'Kapandı'),
            _number(x.caseKey),
            const Color(0xFF7A4FC4),
            caseKey: x.caseKey,
          ),
      ],
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
    return (coming: coming, past: past);
  }

  bool _allEvents = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPapers());
  }

  /// The papers made for the client (fee agreements, releases, receipts),
  /// newest first, as they are kept among the client's files.
  List<({String path, String name, DateTime at})> _papers = const [];

  Future<void> _loadPapers() async {
    final c = _client;
    if (c == null || !ClientFiles.safeId(c.id)) return;
    try {
      final dir = Directory(
        p.join((await widget.files.root()).path, c.id, 'belgeler'),
      );
      if (!await dir.exists()) return;
      final found = <({String path, String name, DateTime at})>[];
      await for (final f in dir.list()) {
        if (f is! File) continue;
        found.add((
          path: f.path,
          name: p.basenameWithoutExtension(f.path),
          at: (await f.stat()).modified,
        ));
      }
      found.sort((a, b) => b.at.compareTo(a.at));
      if (mounted) setState(() => _papers = found);
    } catch (_) {
      // Papers that cannot be listed are not shown; the card stands.
    }
  }

  /// A paper for one of the client's cases, the case asked when more
  /// than one could be meant.
  Future<void> _paperFor(String paper) async {
    final cases = _caseList;
    var key = cases.length == 1 ? cases.single.key : '';
    if (cases.length > 1) {
      final picked = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Hangi dosya için?'),
          children: [
            for (final c in cases)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, c.key),
                child: Text(c.title),
              ),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      key = picked;
    }
    await _paper(paper, key, null);
    await _loadPapers();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, box) => _build(box.maxWidth));

  Widget _build(double width) {
    final e = widget.entry;
    final c = _client;
    final wide = width >= 640;
    final twoColumns = width >= 980;
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Each case's next hearing or deadline.
    final next = <String, ({DateTime at, bool hearing})>{};
    void soon(String key, DateTime at, bool hearing) {
      final kept = next[key];
      if (kept == null || at.isBefore(kept.at)) {
        next[key] = (at: at, hearing: hearing);
      }
    }

    for (final h in hearings) {
      soon(h.caseKey, h.at, true);
    }
    final coming = [
      for (final d in deadlines)
        if (!d.day.isBefore(today)) d,
    ]..sort((a, b) => a.day.compareTo(b.day));
    for (final d in coming) {
      soon(d.caseKey, d.day, false);
    }
    final open = <({String caseKey, String role})>[];
    final closed = <({String caseKey, String role})>[];
    for (final x in e.cases) {
      final stage = stageOf(_db.caseOf(x.caseKey)?.status?.value ?? '');
      (stage == CaseStage.closed ? closed : open).add(x);
    }
    final events = _events(meetings, attorneys, money, hearings, deadlines);
    final cases = [
      _section(
        'AÇIK DOSYALAR',
        count: open.length,
        action: TextButton.icon(
          key: const ValueKey('client-add-case'),
          onPressed: _addCases,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Dosya ekle'),
        ),
      ),
      if (e.cases.isEmpty)
        _frame(
          const Text(
            'Bu müvekkile bağlı dosya yok. "Dosya ekle" ile UYAP '
            'dosyalarınızdan seçebilirsiniz.',
            style: TextStyle(color: AgendaColors.muted),
          ),
        )
      else if (open.isEmpty)
        _frame(
          const Text(
            'Açık dosya yok; dosyalarının hepsi sonuçlanmış.',
            style: TextStyle(color: AgendaColors.muted),
          ),
        ),
      for (final x in open)
        _caseCard(x, accounts[x.caseKey], next[x.caseKey], wide),
      if (closed.isNotEmpty) ...[
        _section(
          'SONUÇLANAN DOSYALAR',
          count: closed.length,
          action: closed.length > 3
              ? TextButton(
                  key: const ValueKey('client-closed-all'),
                  onPressed: () => setState(() => _allClosed = !_allClosed),
                  child: Text(_allClosed ? 'daha az' : 'tümünü göster'),
                )
              : null,
        ),
        _frame(
          Column(
            children: [
              for (final x in _allClosed ? closed : closed.take(3))
                _closedLine(x, wide),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
        ),
      ],
      if (e.removedCases.isNotEmpty) ...[
        _section('ÇIKARILAN DOSYALAR', count: e.removedCases.length),
        _frame(
          Column(
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
          padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
        ),
      ],
    ];
    final side = [
      _timeline(events),
      _meetingBox(meetings),
      _paperBox(attorneys),
      _clientNoteBox(c),
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 18 : 10, 8, wide ? 18 : 10, 24),
      children: [
        _head(c, wide, open.length),
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
        _figures(
          width - (wide ? 36 : 20),
          open: open,
          all: e.cases.length,
          hearing: hearings.firstOrNull,
          deadline: coming.firstOrNull,
          accounts: accounts,
        ),
        if (twoColumns)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: cases,
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 360,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: side,
                ),
              ),
            ],
          )
        else ...[
          ...cases,
          ...side,
        ],
      ],
    );
  }

  bool _allClosed = false;

  /// A section's title above its cards.
  Widget _section(String title, {int? count, Widget? action}) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 14, 0, 0),
    child: SizedBox(
      height: 30,
      child: Row(
        children: [
          Flexible(
            child: Text(
              count == null ? title : '$title · $count',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
                color: AgendaColors.muted,
              ),
            ),
          ),
          const Spacer(),
          ?action,
        ],
      ),
    ),
  );

  /// The four figures under the head: cases still worked on, the next
  /// hearing, the nearest deadline, what is owed.
  Widget _figures(
    double width, {
    required List<({String caseKey, String role})> open,
    required int all,
    required PortalHearing? hearing,
    required ({DateTime day, String title, String caseKey})? deadline,
    required Map<String, CaseAccount> accounts,
  }) {
    var stopped = 0, appeal = 0;
    for (final x in open) {
      switch (stageOf(_db.caseOf(x.caseKey)?.status?.value ?? '')) {
        case CaseStage.stopped:
          stopped++;
        case CaseStage.appeal:
          appeal++;
        default:
      }
    }
    int sum(int Function(CaseAccount a) f) =>
        accounts.values.fold(0, (n, a) => n + f(a));
    final owed = sum((a) => a.feeOwed > 0 ? a.feeOwed : 0);
    Widget tile(String label, String value, String sub, {Color? color}) =>
        Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AgendaColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .3,
                  color: AgendaColors.muted,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AgendaColors.muted),
              ),
            ],
          ),
        );
    final tiles = [
      tile(
        'AÇIK DOSYA',
        '${open.length} / $all',
        [
          if (stopped > 0) '$stopped durdurulmuş',
          if (appeal > 0) '$appeal üst mahkemede',
          if (stopped == 0 && appeal == 0) 'hepsi görülüyor',
        ].join(' · '),
      ),
      tile(
        'SIRADAKİ DURUŞMA',
        hearing == null ? '—' : '${_shortDay(hearing.at)} ${_time(hearing.at)}',
        hearing == null ? 'yaklaşan duruşma yok' : _caseTitle(hearing.caseKey),
        color: AgendaColors.hearingText,
      ),
      tile(
        'YAKLAŞAN SÜRE',
        deadline == null ? '—' : _shortDay(deadline.day),
        deadline == null
            ? 'bekleyen süre yok'
            : '${deadline.title} · ${_number(deadline.caseKey)}',
        color: AgendaColors.deadlineText,
      ),
      if (widget.seesMoney)
        InkWell(
          key: const ValueKey('client-accounts'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => _accounts(),
          child: tile(
            'ALACAK',
            lira(owed),
            'Avans ${lira(sum((a) => a.advanceLeft))} · '
                'Masraf ${lira(sum((a) => a.lawyerOwed))}',
          ),
        ),
    ];
    final across = width >= 760 ? tiles.length : 2;
    const gap = 10.0;
    final w = (width - gap * (across - 1)) / across;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final t in tiles) SizedBox(width: w, child: t)],
      ),
    );
  }

  /// A stage's colours: its label's fill and ink, and the card's edge.
  static ({Color fill, Color ink, Color edge}) _stageColors(CaseStage s) =>
      switch (s) {
        CaseStage.open => (
          fill: const Color(0xFFE3F4EC),
          ink: const Color(0xFF16754F),
          edge: AgendaColors.hearing,
        ),
        CaseStage.stopped => (
          fill: AgendaColors.taskFill,
          ink: AgendaColors.taskText,
          edge: AgendaColors.task,
        ),
        CaseStage.appeal => (
          fill: const Color(0xFFEFE8FA),
          ink: const Color(0xFF5B3A9A),
          edge: const Color(0xFF7A4FC4),
        ),
        CaseStage.closed => (
          fill: const Color(0xFFEEF1F5),
          ink: AgendaColors.muted,
          edge: AgendaColors.muted,
        ),
      };

  /// "Sıfat Davacı": a label and its value, the label muted.
  Widget _pair(String label, String value, {Color? color, bool bold = false}) =>
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(color: AgendaColors.muted),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: color,
                fontWeight: bold ? FontWeight.w700 : null,
              ),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 12.5),
      );

  /// The case's menu: open it, its account, its fee, the interest, or
  /// take it off the client.
  Widget _caseMenu(({String caseKey, String role}) x, CaseAccount? a) =>
      PopupMenuButton<String>(
        key: ValueKey('case-menu-${x.caseKey}'),
        tooltip: 'Dosya işlemleri',
        // Small: the case's lines sit close under its title.
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.more_horiz_rounded, size: 20),
        onSelected: (v) => switch (v) {
          'ac' => widget.onOpenCase?.call(x.caseKey),
          'hesap' => _accounts(x.caseKey),
          'hareket' => _movement(x.caseKey),
          'ucret' => _fee(x.caseKey, a?.fee),
          'not' => _editNote(x.caseKey),
          'faiz' => InterestPage.open(
            context,
            title: '${_number(x.caseKey)} · ${titleName(widget.entry.name)}',
          ),
          _ => _takeOff(x),
        },
        itemBuilder: (_) => [
          if (widget.onOpenCase != null)
            const PopupMenuItem(value: 'ac', child: Text('Dosyayı aç')),
          const PopupMenuItem(value: 'not', child: Text('Dosya notu')),
          if (widget.seesMoney) ...[
            const PopupMenuItem(value: 'hesap', child: Text('Hesabını aç')),
            const PopupMenuItem(value: 'hareket', child: Text('Hareket ekle')),
            const PopupMenuItem(value: 'ucret', child: Text('Ücret anlaşması')),
          ],
          PopupMenuItem(
            key: ValueKey('case-interest-${x.caseKey}'),
            value: 'faiz',
            child: const Text('Faiz hesapla'),
          ),
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

  /// One case still worked on, as a card: its court and stage, what is
  /// next in it, the other side, its last notice, its fee and the
  /// lawyer's note on it; opened beneath for its hearings and deadlines.
  Widget _caseCard(
    ({String caseKey, String role}) x,
    CaseAccount? a,
    ({DateTime at, bool hearing})? next,
    bool wide,
  ) {
    final key = x.caseKey;
    final kase = _db.caseOf(key);
    final status = kase?.status?.value ?? '';
    final stage = stageOf(status);
    final colors = _stageColors(stage);
    final details = kase?.details?.value;
    final kind = caseKindOf(details);
    final opened = yearOf(details?['acilis']);
    final mine = {...?_client?.folded, UyapWebService.fold(widget.entry.name)};
    final other = otherSide(
      _db.caseParties(caseKey: key)[key] ?? const <UyapParty>[],
      x.role,
      (p) =>
          mine.contains(UyapWebService.fold(p.name)) || isShortenedName(p.name),
    );
    final notice = _db.notices(caseKey: key).firstOrNull?.message;
    final note = _noteOf(key);
    final hand = widget.entry.addedCases.contains(key);
    final fee = _feeLeft(a);
    final nextPill = next == null
        ? null
        : _Pill(
            next.hearing
                ? 'Duruşma ${_shortDay(next.at)} ${_time(next.at)}'
                : 'Süre ${_shortDay(next.at)}',
            next.hearing ? AgendaColors.hearingFill : AgendaColors.deadlineFill,
            next.hearing ? AgendaColors.hearingText : AgendaColors.deadlineText,
          );
    final head = Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          kase?.number ?? key,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
        if (kase != null)
          Text(
            kase.court,
            style: const TextStyle(fontSize: 13, color: Color(0xFF4A5466)),
          ),
        _Pill(stageLabel(status), colors.fill, colors.ink),
        if (hand) const _HandTag(),
      ],
    );
    final facts = Wrap(
      spacing: 16,
      runSpacing: 3,
      children: [
        if (x.role.isNotEmpty) _pair('Sıfat', titleName(x.role)),
        if (kind.isNotEmpty) _pair('Tür', kind),
        if (other != null)
          _pair(
            titleName(other.role),
            [
              titleName(other.name),
              if (_bare(other.lawyer).isNotEmpty)
                '(Av. ${titleName(_bare(other.lawyer))})',
            ].join(' '),
          ),
        if (opened != null) _pair('Açıldı', '$opened'),
        if (notice != null)
          _pair(
            'Son tebligat',
            [
              if (notice.sent != null) _shortDay(notice.sent!),
              noticeTopic(notice.subject, kase?.court ?? ''),
            ].where((s) => s.isNotEmpty).join(' · '),
          ),
        if (widget.seesMoney)
          a?.fee == null
              ? InkWell(
                  key: ValueKey('case-fee-$key'),
                  onTap: () => _fee(key, null),
                  child: _pair(
                    'Ücret anlaşması',
                    'yok · ekle',
                    color: AgendaColors.taskText,
                    bold: true,
                  ),
                )
              : _pair(
                  'Ücret',
                  [
                    if (a!.feeAgreed > 0) lira(a.feeAgreed),
                    if (a.feeShare > 0) '%${a.feeShare}',
                    'kalan ${fee.text}',
                  ].join(' · '),
                ),
        if (widget.seesMoney && a != null && a.fee != null)
          _pair(
            'Avans',
            _plain(a.advanceLeft),
            color: a.advanceLeft > 0 ? const Color(0xFF1B6B3A) : null,
          ),
        if (widget.seesMoney && (a?.lawyerOwed ?? 0) > 0)
          _pair(
            'Masraf',
            _plain(a!.lawyerOwed),
            color: AgendaColors.deadlineText,
          ),
      ],
    );
    final noteBox = InkWell(
      key: ValueKey('case-note-$key'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => _editNote(key),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: (note?.text ?? '').isEmpty ? null : const Color(0xFFFFFBEA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: (note?.text ?? '').isEmpty
                ? AgendaColors.line
                : const Color(0xFFF1E3B0),
          ),
        ),
        child: (note?.text ?? '').isEmpty
            ? const Text(
                '+ Bu dosyaya not ekle',
                style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.sticky_note_2_outlined,
                    size: 15,
                    color: Color(0xFF8A6A12),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      note!.text,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF5A4A12),
                        height: 1.3,
                      ),
                    ),
                  ),
                  Text(
                    _shortDay(note.at),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AgendaColors.muted,
                    ),
                  ),
                ],
              ),
      ),
    );
    void toggle() => setState(() {
      if (!_opened.remove(key)) _opened.add(key);
    });
    return Container(
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AgendaColors.line),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                key: ValueKey('client-case-$key'),
                onTap: toggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: head),
                          if (wide && nextPill != null) ...[
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: nextPill,
                            ),
                          ],
                          _caseMenu(x, a),
                        ],
                      ),
                      if (!wide && nextPill != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: nextPill,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: facts,
                      ),
                    ],
                  ),
                ),
              ),
              // The note its own place to tap, not the card's.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: noteBox,
              ),
              if (_opened.contains(key)) _caseDetail(x, wide),
            ],
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: ColoredBox(color: colors.edge),
          ),
        ],
      ),
    );
  }

  /// A case done with, on one line: its number, court, how it ended.
  Widget _closedLine(({String caseKey, String role}) x, bool wide) {
    final kase = _db.caseOf(x.caseKey);
    final status = kase?.status?.value ?? '';
    final details = kase?.details?.value;
    final year = yearOf(details?['kapanis']);
    final kind = caseKindOf(details);
    final colors = _stageColors(CaseStage.closed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('client-case-${x.caseKey}'),
          onTap: () => setState(() {
            if (!_opened.remove(x.caseKey)) _opened.add(x.caseKey);
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        kase?.number ?? x.caseKey,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (kase != null)
                        Text(
                          kase.court,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      _Pill(
                        [
                          stageLabel(status),
                          if (year != null) '$year',
                        ].join(' · '),
                        colors.fill,
                        colors.ink,
                      ),
                      if (!wide)
                        Text(
                          [
                            if (x.role.isNotEmpty) titleName(x.role),
                            if (kind.isNotEmpty) kind,
                          ].join(' · '),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AgendaColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                if (wide)
                  Text(
                    [
                      if (x.role.isNotEmpty) titleName(x.role),
                      if (kind.isNotEmpty) kind,
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AgendaColors.muted,
                    ),
                  ),
                _caseMenu(x, null),
              ],
            ),
          ),
        ),
        if (_opened.contains(x.caseKey)) _caseDetail(x, wide),
      ],
    );
  }

  /// Who the client is, how they are reached, and what may be done for
  /// them: the card's head.
  Widget _head(Client? c, bool wide, int open) {
    final e = widget.entry;
    final body = c?.body ?? false;
    final years = [
      for (final x in e.cases)
        ?yearOf(_db.caseOf(x.caseKey)?.details?.value['acilis']),
    ]..sort();
    Future<void> launch(String uri) async {
      try {
        await launchUrl(Uri.parse(uri));
      } catch (_) {}
    }

    final contacts = <(String, String)>[
      if ((c?.phone ?? '').isNotEmpty) ('Tel', c!.phone),
      if ((c?.phone2 ?? '').isNotEmpty) ('2. tel', c!.phone2),
      if ((c?.email ?? '').isNotEmpty) ('E-posta', c!.email),
      if ((c?.address ?? '').isNotEmpty) ('Adres', c!.address),
      if ((c?.idNo ?? '').isNotEmpty) (body ? 'VKN' : 'TCKN', c!.idNo),
    ];
    final missing = [
      if ((c?.phone ?? '').isEmpty) 'telefon',
      if ((c?.email ?? '').isEmpty) 'e-posta',
      if ((c?.idNo ?? '').isEmpty) body ? 'VKN' : 'TCKN',
    ];
    const link = TextStyle(
      fontSize: 12.5,
      color: AgendaColors.hearing,
      fontWeight: FontWeight.w700,
    );
    final papers = PopupMenuButton<String>(
      key: const ValueKey('client-papers'),
      tooltip: 'Belge hazırla',
      onSelected: (v) => v == 'vekalet' ? _attorney() : _paperFor(v),
      itemBuilder: (_) => [
        if (widget.seesMoney) ...[
          const PopupMenuItem(
            value: 'sozlesme',
            child: Text('Avukatlık ücret sözleşmesi'),
          ),
          const PopupMenuItem(value: 'ibra', child: Text('İbraname')),
        ],
        const PopupMenuItem(value: 'vekalet', child: Text('Vekâletname ekle')),
      ],
      child: IgnorePointer(
        child: OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.description_outlined, size: 18),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(wide ? 'Belge hazırla' : 'Belge'),
              const Icon(Icons.arrow_drop_down_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
    final actions = [
      FilledButton.icon(
        key: const ValueKey('client-message'),
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1FA855)),
        onPressed: _message,
        icon: const Icon(Icons.chat_outlined, size: 18),
        label: const Text('Mesaj'),
      ),
      if (!wide && (c?.phone ?? '').isNotEmpty)
        OutlinedButton.icon(
          onPressed: () => launch('tel:${c!.phone}'),
          icon: const Icon(Icons.call_outlined, size: 18),
          label: const Text('Ara'),
        ),
      OutlinedButton.icon(
        key: const ValueKey('client-meeting'),
        onPressed: () => _meeting(),
        icon: const Icon(Icons.record_voice_over_outlined, size: 18),
        label: Text(wide ? 'Görüşme tutanağı' : 'Görüşme'),
      ),
      if (widget.seesMoney)
        OutlinedButton.icon(
          key: const ValueKey('client-statement'),
          onPressed: () => _statement(),
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: Text(wide ? 'Hesap dökümü' : 'Hesap'),
        ),
      papers,
    ];
    final more = PopupMenuButton<String>(
      key: const ValueKey('client-more'),
      onSelected: (v) => switch (v) {
        'duzenle' => _editContact(),
        'gizle' => _hide(!(c?.hidden ?? false)),
        _ => _remove(),
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'duzenle', child: Text('Bilgileri düzenle')),
        PopupMenuItem(
          key: const ValueKey('client-hide'),
          value: 'gizle',
          child: Text(c?.hidden ?? false ? 'Listede göster' : 'Listede gizle'),
        ),
        const PopupMenuItem(
          value: 'kaldir',
          child: Text('Müvekkili listeden kaldır'),
        ),
      ],
    );
    final who = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              titleName(c?.name ?? e.name),
              style: TextStyle(
                fontSize: wide ? 22 : 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            _Pill(
              body ? 'Kurum' : 'Kişi',
              AgendaColors.hearingFill,
              AgendaColors.hearingText,
            ),
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
                  c?.office ?? false ? 'Büroyla paylaşılıyor' : 'Yalnız bende',
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
        const SizedBox(height: 4),
        Wrap(
          spacing: 14,
          runSpacing: 3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              [
                '${e.cases.length} dosya',
                '$open açık',
                if (years.isNotEmpty) 'ilk dosya ${years.first}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12.5, color: AgendaColors.muted),
            ),
            for (final (label, value) in contacts)
              SelectionArea(child: _pair(label, value)),
            InkWell(
              key: const ValueKey('client-edit'),
              onTap: _editContact,
              borderRadius: BorderRadius.circular(4),
              child: Text(
                missing.isEmpty
                    ? 'Düzenle'
                    : '+ ${missing.join(', ').replaceFirst('telefon', 'Telefon')} ekle',
                style: link,
              ),
            ),
          ],
        ),
      ],
    );
    return _frame(
      wide
          ? Row(
              children: [
                ClientInitials(e.name, body: body, size: 56),
                const SizedBox(width: 14),
                Expanded(child: who),
                const SizedBox(width: 10),
                Flexible(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: actions,
                  ),
                ),
                more,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClientInitials(e.name, body: body, size: 46),
                    const SizedBox(width: 10),
                    Expanded(child: who),
                    more,
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: actions),
              ],
            ),
      padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
    );
  }

  /// What is coming, soonest first, then what happened, latest first.
  Widget _timeline(({List<_Event> coming, List<_Event> past}) events) {
    final count = events.coming.length + events.past.length;
    final pastShown = _allEvents
        ? events.past.take(80)
        : events.past.take(events.coming.isEmpty ? 6 : 4);
    Widget label(String t, Color color) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: .5,
          color: color,
        ),
      ),
    );
    Widget line(_Event ev) => InkWell(
      onTap: ev.caseKey == null || widget.onOpenCase == null
          ? null
          : () => widget.onOpenCase!(ev.caseKey!),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 50,
              child: Text(
                _shortDay(ev.at),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AgendaColors.muted,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 9),
              child: Icon(Icons.circle, size: 9, color: ev.color),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ev.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  if (ev.detail.isNotEmpty)
                    Text(
                      ev.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AgendaColors.muted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return _box(
      'ZAMAN ÇİZELGESİ',
      action: events.past.length > pastShown.length || _allEvents
          ? TextButton(
              key: const ValueKey('client-timeline-all'),
              onPressed: () => setState(() => _allEvents = !_allEvents),
              child: Text(_allEvents ? 'Daha az' : 'Tümü $count'),
            )
          : null,
      children: [
        if (count == 0)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'Henüz bir şey yok.',
              style: TextStyle(color: AgendaColors.muted),
            ),
          ),
        if (events.coming.isNotEmpty) ...[
          label('YAKLAŞAN', AgendaColors.deadlineText),
          for (final ev in events.coming.take(_allEvents ? 80 : 5)) line(ev),
        ],
        if (events.past.isNotEmpty) ...[
          label('GEÇMİŞ', AgendaColors.muted),
          for (final ev in pastShown) line(ev),
        ],
      ],
    );
  }

  /// The papers made for the client and the powers of attorney, with a
  /// way to make another.
  Widget _paperBox(List<ClientRecord> attorneys) {
    ({IconData icon, Color fill}) look(String name) => switch (name) {
      _ when name.startsWith('Avukatlık ücret') => (
        icon: Icons.handshake_outlined,
        fill: AgendaColors.hearingFill,
      ),
      _ when name.startsWith('İbraname') => (
        icon: Icons.draw_outlined,
        fill: const Color(0xFFEEF1F5),
      ),
      _ => (icon: Icons.receipt_outlined, fill: const Color(0xFFE3F4EC)),
    };
    Widget tile({
      required Key key,
      required IconData icon,
      required Color fill,
      required String title,
      required String sub,
      VoidCallback? onTap,
    }) => InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, size: 16, color: const Color(0xFF4A5466)),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AgendaColors.muted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final papers = widget.seesMoney ? _papers : const <Never>[];
    final count = papers.length + attorneys.length;
    return _box(
      'BELGELER',
      count: count,
      action: TextButton(
        key: const ValueKey('client-attorney'),
        onPressed: _attorney,
        child: const Text('+ Vekâletname'),
      ),
      children: [
        if (count == 0)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'Belge yok. Ücret sözleşmesi ve ibraname "Belge hazırla"dan '
              'hazırlanır.',
              style: TextStyle(color: AgendaColors.muted),
            ),
          ),
        for (final d in papers.take(_allPapers ? 50 : 4))
          tile(
            key: ValueKey('client-paper-${d.name}'),
            icon: look(d.name).icon,
            fill: look(d.name).fill,
            title: d.name.split(' - ').first,
            sub: _day(d.at),
            onTap: widget.onEdit == null ? null : () => widget.onEdit!(d.path),
          ),
        for (final a in attorneys.take(_allPapers ? 20 : 2))
          tile(
            key: ValueKey('attorney-${a.id}'),
            icon: Icons.assignment_ind_outlined,
            fill: const Color(0xFFEFE8FA),
            title: [
              'Vekâletname',
              if (a.text('noter').isNotEmpty) a.text('noter'),
            ].join(' · '),
            sub: [
              a.text('tarih'),
              if (a.list('yetkiler').isNotEmpty) a.list('yetkiler').join(', '),
            ].where((s) => s.isNotEmpty).join(' · '),
            onTap: clientFilesOf(a).isEmpty
                ? null
                : () => _preview(a, 'Vekâletname'),
          ),
        if (papers.length > 4 || attorneys.length > 2)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _allPapers = !_allPapers),
              child: Text(_allPapers ? 'Daha az' : 'Tümü $count'),
            ),
          ),
      ],
    );
  }

  bool _allPapers = false;

  /// The lawyer's note on the client, apart from the cases' notes.
  Widget _clientNoteBox(Client? c) => _box(
    'MÜVEKKİL NOTU',
    action: TextButton(
      key: const ValueKey('client-note'),
      onPressed: _editContact,
      child: Text((c?.note ?? '').isEmpty ? '+ Not' : 'Düzenle'),
    ),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          (c?.note ?? '').isEmpty ? 'Not yok.' : c!.note,
          style: TextStyle(
            fontSize: 12.5,
            color: (c?.note ?? '').isEmpty ? AgendaColors.muted : null,
          ),
        ),
      ),
    ],
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
              // Narrow: the title gives way, not the action beside it.
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                    color: AgendaColors.muted,
                  ),
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

  /// The cases opened to their detail.
  final _opened = <String>{};

  /// The latest note on case [key], of any of the client's cards.
  CaseNote? _noteOf(String key) {
    CaseNote? best = _client?.caseNotes[key];
    for (final id in widget.entry.ids) {
      final n = _db.clientCard(id)?.caseNotes[key];
      if (n != null && (best == null || n.at.isAfter(best.at))) best = n;
    }
    return best;
  }

  Future<void> _editNote(String key) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(
        title: 'Dosya notu · ${_number(key)}',
        text: _noteOf(key)?.text ?? '',
      ),
    );
    if (note == null || !mounted) return;
    final card = _card();
    final saved = card.copyWith(
      caseNotes: {
        ...card.caseNotes,
        key: CaseNote(note.trim(), DateTime.now(), by: widget.lawyer),
      },
    );
    _db.saveClient(saved);
    setState(() => _client = saved);
    widget.onChanged?.call(saved.id);
  }

  /// A case opened under its row: its hearings, its deadlines and the
  /// other side, and the lawyer's note on it.
  Widget _caseDetail(({String caseKey, String role}) x, bool wide) {
    final key = x.caseKey;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final coming = [
      for (final h in _hearings)
        if (h.caseKey == key) h,
    ];
    final past = _db.hearings(caseKey: key, from: DateTime(2000), to: now)
      ..sort((a, b) => b.at.compareTo(a.at));
    final deadlines = [
      for (final d in _deadlines)
        if (d.caseKey == key && !d.day.isBefore(today)) d,
    ]..sort((a, b) => a.day.compareTo(b.day));
    final mine = {...?_client?.folded, UyapWebService.fold(widget.entry.name)};
    final others = [
      for (final t in _db.caseParties(caseKey: key)[key] ?? const <UyapParty>[])
        if (!mine.contains(UyapWebService.fold(t.name)) &&
            !isShortenedName(t.name))
          t,
    ];
    final status = _db.caseOf(key)?.status?.value ?? '';
    const muted = TextStyle(fontSize: 12.5, color: AgendaColors.muted);
    Widget head(String t, {Widget? action}) => SizedBox(
      height: 26,
      child: Row(
        children: [
          Text(
            t,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
              color: AgendaColors.muted,
            ),
          ),
          const Spacer(),
          ?action,
        ],
      ),
    );
    Widget line(String t, {TextStyle? style}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(t, style: style ?? const TextStyle(fontSize: 12.5)),
    );
    String hearing(PortalHearing h) => [
      '${_day(h.at)} ${_time(h.at)}',
      if ((h.kind?.value ?? '').isNotEmpty) h.kind!.value,
      if ((h.result?.value ?? '').isNotEmpty) h.result!.value,
    ].join(' · ');
    final hearings = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        head('DURUŞMALAR'),
        if (coming.isEmpty && past.isEmpty) line('Duruşma yok.', style: muted),
        for (final h in coming)
          line(
            '${hearing(h)} · ${h.at.difference(today).inDays} gün',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        for (final h in past.take(3)) line(hearing(h), style: muted),
      ],
    );
    final state = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        head('SÜRELER VE DURUM'),
        if (deadlines.isEmpty) line('Bekleyen süre yok.', style: muted),
        for (final d in deadlines)
          line(
            '${_day(d.day).substring(0, 5)} ${d.title} · '
            '${d.day.difference(today).inDays} gün',
            style: const TextStyle(
              fontSize: 12.5,
              color: AgendaColors.taskText,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (status.isNotEmpty) line(titleName(status), style: muted),
        for (final t in others.take(3))
          line(
            [
              '${titleName(t.role)}: ${titleName(t.name)}',
              if (t.lawyer.isNotEmpty) 'vekili ${titleName(t.lawyer)}',
            ].join(' · '),
            style: muted,
          ),
      ],
    );
    return Container(
      key: ValueKey('case-detail-$key'),
      color: const Color(0xFFF7F9FD),
      padding: const EdgeInsets.fromLTRB(16, 4, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: hearings),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: state),
              ],
            )
          else ...[
            hearings,
            const SizedBox(height: 6),
            state,
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (widget.onOpenCase != null)
                OutlinedButton(
                  onPressed: () => widget.onOpenCase!(key),
                  child: const Text('Dosyayı aç'),
                ),
              if (widget.seesMoney) ...[
                OutlinedButton(
                  onPressed: () => _accounts(key),
                  child: const Text('Hesabını aç'),
                ),
                OutlinedButton(
                  onPressed: () => _movement(key),
                  child: const Text('Hareket ekle'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _meetingBox(List<ClientRecord> meetings) => _box(
    'GÖRÜŞMELER',
    count: meetings.length,
    action: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (meetings.length > 2)
          TextButton(
            onPressed: () => _page(
              'Görüşmeler',
              (_) => _meetings(_records(ClientRecordKind.meeting)),
            ),
            child: const Text('Tümü'),
          ),
        TextButton(
          key: const ValueKey('client-meeting-new'),
          onPressed: () => _meeting(),
          child: const Text('+ Yeni'),
        ),
      ],
    ),
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
}

/// A line or a note written: what it says, null when backed out.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.title,
    this.text = '',
    this.label,
    this.ok = 'Kaydet',
    this.lines = 4,
  });
  final String title, text, ok;
  final String? label;
  final int lines;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _text = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: TextField(
        key: const ValueKey('case-note-text'),
        controller: _text,
        autofocus: true,
        minLines: widget.lines,
        maxLines: widget.lines == 1 ? 1 : 10,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.label == null
              ? 'Tanıklar, sulh sınırı, müvekkilin istekleri…'
              : null,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        key: const ValueKey('case-note-save'),
        onPressed: () => Navigator.pop(context, _text.text),
        child: Text(widget.ok),
      ),
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
  const _ContactDialog(
    this.client, {
    this.groups = const [],
    this.fresh = false,
  });
  final Client client;

  /// The groups the lawyer has given clients so far, to pick from.
  final List<String> groups;

  /// A client written in by hand, not yet kept.
  final bool fresh;

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
  late final _group = TextEditingController(text: widget.client.group);
  late bool _body = widget.client.body;
  late bool _messages = widget.client.messages;

  @override
  void dispose() {
    for (final c in [
      _name,
      _idNo,
      _phone,
      _phone2,
      _email,
      _address,
      _note,
      _group,
    ]) {
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
    title: Text(widget.fresh ? 'Yeni müvekkil' : 'Müvekkil bilgileri'),
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
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                key: const ValueKey('contact-name'),
                controller: _name,
                autofocus: widget.fresh,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Ad'),
              ),
            ),
            _field(_idNo, _body ? 'VKN' : 'TCKN'),
            _field(_phone, 'Telefon'),
            _field(_phone2, 'İkinci telefon'),
            _field(_email, 'E-posta'),
            _field(_address, 'Adres', lines: 2),
            _field(_note, 'Not', lines: 3),
            TextField(
              key: const ValueKey('contact-group'),
              controller: _group,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Grup',
                hintText: 'Örn. Bankalar, Sigorta, Kira',
              ),
            ),
            if (widget.groups.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final g in widget.groups)
                        ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(g),
                          selected: _group.text.trim() == g,
                          onSelected: (on) =>
                              setState(() => _group.text = on ? g : ''),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            SwitchListTile(
              key: const ValueKey('contact-messages'),
              contentPadding: EdgeInsets.zero,
              value: _messages,
              onChanged: (v) => setState(() => _messages = v),
              title: const Text('Mesajla bilgilendirilmek istiyor'),
              subtitle: const Text(
                'Duruşma ve taksit hatırlatmaları günün listesine gelir; '
                'WhatsApp, SMS ya da e-postayla siz gönderirsiniz.',
              ),
            ),
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
        onPressed: widget.fresh && _name.text.trim().isEmpty
            ? null
            : () {
                final name = _name.text.trim();
                final c = widget.client;
                final names = {
                  ...c.names,
                  // The name it was found by stays one of its names.
                  if (c.name.isNotEmpty &&
                      UyapWebService.fold(name) != UyapWebService.fold(c.name))
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
                    messages: _messages,
                    names: names,
                    group: _group.text.trim(),
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
