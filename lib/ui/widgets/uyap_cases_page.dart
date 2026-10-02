import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/uyap/uyap_case_links.dart';
import '../../services/uyap/uyap_case_panel_controller.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../../services/uyap/uyap_web_service.dart';
import 'uyap_case_panel.dart';
import 'uyap_case_picker.dart';
import 'uyap_connect_view.dart';
import 'uyap_session_chip.dart';

/// The UYAP cases kept on this computer, where they are looked after on
/// their own rather than beside a petition: each with its particulars,
/// parties and documents, refreshed from UYAP on request, and what was
/// downloaded of it. Cases are added here one by one, never the whole
/// portfolio at once: UYAP answers one request at a time.
class UyapCasesPage extends StatefulWidget {
  const UyapCasesPage({
    super.key,
    required this.caseKey,
    required this.onShowCase,
    required this.onOpen,
    this.onSaved,
    this.onNewPetition,
  });

  /// The case shown, by [UyapCaseRecord.key]; null for the list of cases.
  final String? caseKey;

  /// A case chosen from the list, or null to go back to the list.
  final ValueChanged<String?> onShowCase;

  /// Shows a document in Folio's preview.
  final ValueChanged<File> onOpen;

  /// Told where a document was saved, so that Folio can search the folder.
  final void Function(File file)? onSaved;

  /// Begins a petition for the case shown, tied to it.
  final ValueChanged<UyapCaseLink>? onNewPetition;

  @override
  State<UyapCasesPage> createState() => _UyapCasesPageState();
}

class _UyapCasesPageState extends State<UyapCasesPage> {
  UyapWebService get _web => UyapWebService.instance;
  static bool get _desktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  late final _controller = UyapCasePanelController()..onSaved = widget.onSaved;
  List<(UyapCaseRecord, int)>? _cases;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    UyapCaseStore.changes.addListener(_reload);
    _web.session.addListener(_changed);
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(UyapCasesPage old) {
    super.didUpdateWidget(old);
    if (old.caseKey != widget.caseKey) unawaited(_showCase());
  }

  @override
  void dispose() {
    UyapCaseStore.changes.removeListener(_reload);
    _web.session.removeListener(_changed);
    _controller.dispose();
    _search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    final cases = await UyapCaseStore.instance.cases();
    if (!mounted) return;
    final first = _cases == null;
    setState(() => _cases = cases);
    if (first) await _showCase();
  }

  /// The case of [UyapCasesPage.caseKey], into the panel.
  Future<void> _showCase() async {
    final key = widget.caseKey;
    if (key == null || key == _controller.record?.key) return;
    final record = _cases?.where((c) => c.$1.key == key).firstOrNull?.$1;
    if (record != null) await _controller.show(record);
  }

  Future<void> _connect() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('UYAP’a bağlan'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: UyapConnectView(
            note:
                'Bağlandıktan sonra dosya ekleyebilir, dosyaları yenileyebilir '
                've evrak indirebilirsiniz.',
            onConnected: (_) async {
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    ),
  );

  /// Finds a case in UYAP, fetches it and opens its page.
  Future<void> _add() async {
    final chosen = await UyapCasePicker.show(context);
    final live = chosen?.$2;
    if (chosen == null || live == null || !mounted) return;
    setState(() => _adding = true);
    try {
      await _controller.choose(chosen.$1, live);
      final record = _controller.record;
      if (record != null) widget.onShowCase(record.key);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = widget.caseKey;
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _top(theme),
          const Divider(height: 1),
          Expanded(
            child: key == null
                ? _list(theme)
                : UyapCasePanel(
                    controller: _controller,
                    onOpen: (file, _) => widget.onOpen(file),
                    onOpenFile: widget.onOpen,
                    onRemoved: () => widget.onShowCase(null),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _top(ThemeData theme) {
    final inCase = widget.caseKey != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          if (inCase)
            TextButton.icon(
              key: const ValueKey('uyap-cases-back'),
              onPressed: () => widget.onShowCase(null),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('UYAP Dosyalarım'),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'UYAP Dosyalarım',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          // UYAP is reached from a computer; a phone shows what was kept.
          if (!_desktop)
            const SizedBox.shrink()
          else if (_web.connected)
            const UyapSessionChip()
          else
            OutlinedButton.icon(
              key: const ValueKey('uyap-cases-connect'),
              onPressed: () => unawaited(_connect()),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('UYAP’a bağlan'),
            ),
          if (inCase && widget.onNewPetition != null)
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final link = _controller.link;
                return FilledButton.icon(
                  key: const ValueKey('uyap-case-new-petition'),
                  onPressed: link == null
                      ? null
                      : () => widget.onNewPetition!(link),
                  icon: const Icon(Icons.edit_document, size: 18),
                  label: const Text('Bu dosya için yeni dilekçe'),
                );
              },
            ),
          if (!inCase && _desktop)
            FilledButton.icon(
              key: const ValueKey('uyap-cases-add'),
              onPressed: _adding ? null : () => unawaited(_add()),
              icon: _adding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_rounded, size: 18),
              label: const Text('UYAP’tan dosya ekle'),
            ),
        ],
      ),
    );
  }

  static String _clock(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
  }

  /// The search over the list: number, court, parties, kind and state.
  final _search = TextEditingController();

  /// The filters chosen: 'yeni', 'durusma', or a kind of file.
  final _filters = <String>{};
  _Order _order = _Order.fetched;

  /// "05/10/2026 10:35", as UYAP writes a hearing, as a time.
  static DateTime? _hearingAt(String? text) {
    final m = RegExp(
      r'(\d{1,2})[./](\d{1,2})[./](\d{4})(?:\s+(\d{1,2}):(\d{2}))?',
    ).firstMatch(text ?? '');
    if (m == null) return null;
    int n(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    return DateTime(n(3), n(2), n(1), n(4), n(5));
  }

  /// A hearing in the coming 30 days.
  static bool _soon(UyapCaseRecord record, DateTime now) {
    final at = _hearingAt(record.details.hearing);
    return at != null &&
        !at.isBefore(now.subtract(const Duration(hours: 12))) &&
        at.isBefore(now.add(const Duration(days: 30)));
  }

  /// "Davacı: Ali Veli, Ayşe Kaya · Davalı: Mehmet Demir": the parties by
  /// their role, in the order UYAP lists them.
  static String _partiesLine(UyapCaseRecord record) {
    final byRole = <String, List<String>>{};
    for (final t in record.parties) {
      final role = t.role.trim().isEmpty ? 'Taraf' : t.role.trim();
      byRole.putIfAbsent(role, () => []).add(t.name.trim());
    }
    return [
      for (final MapEntry(key: role, value: names) in byRole.entries)
        '$role: ${names.join(', ')}',
    ].join(' · ');
  }

  static String _fold(String v) => UyapCasePanelController.fold(v);

  bool _matches(UyapCaseRecord record, List<String> words) {
    if (words.isEmpty) return true;
    final text = _fold(
      [
        record.number,
        record.court,
        record.details.kind,
        record.details.fileType,
        record.details.state,
        record.details.status,
        for (final t in record.parties) '${t.name} ${t.lawyer}',
      ].join(' '),
    );
    return words.every(text.contains);
  }

  static String _kindOf(UyapCaseRecord record) =>
      record.details.fileType.isNotEmpty ? record.details.fileType : '';

  Widget _list(ThemeData theme) {
    final cases = _cases;
    if (cases == null) return const Center(child: CircularProgressIndicator());
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (cases.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              'Henüz bir UYAP dosyası yok. “UYAP’tan dosya ekle” ile '
              'mahkemeyi ve esas numarasını seçerek dosyayı ekleyin. Folio '
              'dosyanın bilgilerini, taraflarını ve evrak listesini bu '
              'bilgisayara kaydeder; bağlantı olmadan da açarsınız.',
              textAlign: TextAlign.center,
              style: muted,
            ),
          ),
        ),
      );
    }
    final now = DateTime.now();
    final words = _fold(_search.text)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    final kinds = {
      for (final (r, _) in cases)
        if (_kindOf(r).isNotEmpty) _kindOf(r),
    }.toList()..sort();
    final shown = [
      for (final c in cases)
        if (_matches(c.$1, words) &&
            (!_filters.contains('yeni') || c.$1.fresh.isNotEmpty) &&
            (!_filters.contains('durusma') || _soon(c.$1, now)) &&
            (!kinds.any(_filters.contains) || _filters.contains(_kindOf(c.$1))))
          c,
    ];
    switch (_order) {
      case _Order.fetched:
        break; // As kept: the last fetched first.
      case _Order.hearing:
        DateTime key(UyapCaseRecord r) {
          final at = _hearingAt(r.details.hearing);
          return at == null || at.isBefore(now) ? DateTime(9999) : at;
        }
        shown.sort((a, b) => key(a.$1).compareTo(key(b.$1)));
      case _Order.number:
        shown.sort((a, b) => b.$1.number.compareTo(a.$1.number));
    }
    Widget chip(String value, String label, {int? count}) => FilterChip(
      key: ValueKey('uyap-cases-filter-$value'),
      label: Text(count == null ? label : '$label · $count'),
      selected: _filters.contains(value),
      onSelected: (on) =>
          setState(() => on ? _filters.add(value) : _filters.remove(value)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            key: const ValueKey('uyap-cases-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Dosya ara: esas no, mahkeme, taraf, dava türü',
              border: const OutlineInputBorder(),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              chip(
                'yeni',
                'Yeni evrakı olan',
                count: cases.where((c) => c.$1.fresh.isNotEmpty).length,
              ),
              chip(
                'durusma',
                '30 gün içinde duruşma',
                count: cases.where((c) => _soon(c.$1, now)).length,
              ),
              for (final kind in kinds)
                chip(
                  kind,
                  kind,
                  count: cases.where((c) => _kindOf(c.$1) == kind).length,
                ),
              PopupMenuButton<_Order>(
                tooltip: 'Sırala',
                initialValue: _order,
                onSelected: (o) => setState(() => _order = o),
                itemBuilder: (_) => [
                  for (final o in _Order.values)
                    PopupMenuItem(value: o, child: Text(o.label)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort_rounded, size: 18),
                      const SizedBox(width: 4),
                      Text(_order.label, style: muted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(child: Text('Aramaya uyan dosya yok.', style: muted))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _card(theme, shown[i].$1, shown[i].$2, now),
                ),
        ),
      ],
    );
  }

  Widget _card(
    ThemeData theme,
    UyapCaseRecord record,
    int saved,
    DateTime now,
  ) {
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final d = record.details;
    final hearing = d.hearing?.trim() ?? '';
    final parties = _partiesLine(record);
    final kind = [
      if (d.fileType.isNotEmpty) d.fileType,
      if (d.kind.isNotEmpty) d.kind,
    ].join(' · ');
    final state = d.state.isNotEmpty ? d.state : d.status;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey('uyap-cases-${record.key}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onShowCase(record.key),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.gavel_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          record.number,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        Text(record.court, style: muted),
                        if (state.isNotEmpty && state != 'Açık')
                          _badge(theme, state),
                      ],
                    ),
                    if (parties.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        parties,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (kind.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(kind, style: muted),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (hearing.isNotEmpty) 'Duruşma: $hearing',
                        'Son eşitleme ${_clock(record.fetchedAt)}',
                      ].join('  ·  '),
                      style: _soon(record, now)
                          ? muted?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            )
                          : muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (record.fresh.isNotEmpty)
                    _badge(theme, '${record.fresh.length} yeni'),
                  const SizedBox(height: 4),
                  Text(
                    '$saved / ${record.documents.length} evrak',
                    style: muted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(ThemeData theme, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: theme.colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onTertiaryContainer,
      ),
    ),
  );
}

/// How the list of cases is ordered.
enum _Order {
  fetched('Son eşitlenen'),
  hearing('Yaklaşan duruşma'),
  number('Esas numarası');

  const _Order(this.label);
  final String label;
}
