import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/portal/case_import.dart';
import '../../services/portal/observed.dart' show caseKey;
import '../../services/portal/portal_case.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/uyap/uyap_case_links.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../../services/uyap/uyap_mobile_api.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../agenda/mobile_connect.dart';
import 'uyap_connect_view.dart';
import 'uyap_session_chip.dart';
import 'folio_select.dart';

/// Finds the UYAP case a document is written for: the kind of court, the
/// court, then the number. Asks for a session first when there is none.
class UyapCasePicker extends StatefulWidget {
  const UyapCasePicker({super.key, this.offerKept = false, this.number});

  /// "2026/191": the case looked for, its year and number filled in. With
  /// none, both are left empty and a search lists every case of the court.
  final String? number;

  /// Lists the cases kept on this computer first, to take one without
  /// UYAP; a document is tied to a case this way most of the time.
  final bool offerKept;

  /// The case chosen, as it can be found again in any session, and as it
  /// is in this one: null for a case taken from those kept, without UYAP.
  static Future<(UyapCaseLink, UyapCase?)?> show(
    BuildContext context, {
    bool offerKept = false,
    String? number,
  }) => showDialog<(UyapCaseLink, UyapCase?)>(
    context: context,
    builder: (_) => UyapCasePicker(offerKept: offerKept, number: number),
  );

  @override
  State<UyapCasePicker> createState() => _UyapCasePickerState();
}

class _UyapCasePickerState extends State<UyapCasePicker> {
  UyapWebService get _web => UyapWebService.instance;
  late final _wanted = RegExp(r'(\d{4})\s*/\s*(\d+)')
      .firstMatch(widget.number ?? '');
  late final _year = TextEditingController(text: _wanted?.group(1) ?? '');
  late final _number = TextEditingController(text: _wanted?.group(2) ?? '');
  String _jurisdiction = '1';
  bool _closed = false;
  List<UyapOption> _types = const [];
  UyapOption? _type;
  List<UyapOption> _courts = const [];
  UyapOption? _court;
  List<UyapCase>? _cases;
  bool _busy = false;
  String? _error;
  List<UyapCaseRecord> _kept = const [];

  /// The portfolio's cases not kept yet (UYAP Mobil's and the web's).
  List<PortalCase> _portfolio = const [];
  final _filter = TextEditingController();
  PortalSync get _sync => PortalSync.instance;
  UyapMobileApi get _mobile => UyapMobileApi.instance;

  @override
  void initState() {
    super.initState();
    _web.session.addListener(_sessionChanged);
    _mobile.session.addListener(_sessionChanged);
    if (_web.connected) unawaited(_loadTypes());
    if (widget.offerKept) unawaited(_loadKept());
  }

  Future<void> _loadKept() async {
    List<UyapCaseRecord> all;
    try {
      all = [for (final (r, _) in await UyapCaseStore.instance.cases()) r];
    } catch (_) {
      return;
    }
    if (mounted) setState(() => _kept = all);
    final sync = PortalSync.started;
    if (sync == null) return;
    try {
      final have = {for (final r in all) caseKey(r.number, r.court)};
      final portfolio = [
        for (final c in await sync.portfolio())
          if (!have.contains(c.key)) c,
      ]..sort((a, b) => b.number.compareTo(a.number));
      if (mounted) setState(() => _portfolio = portfolio);
    } catch (_) {}
  }

  bool _shows(String number, String court) {
    final words = UyapWebService.fold(_filter.text)
        .split(' ')
        .where((w) => w.isNotEmpty);
    final text = UyapWebService.fold('$number $court');
    return words.every(text.contains);
  }

  /// A case of the portfolio: fetched through whichever portal is connected,
  /// kept, and taken.
  Future<void> _import(PortalCase kase) => _run(() async {
    final import = PortalCaseImport();
    final record = await import.add(kase);
    final link = record.link ?? await import.linkFor(kase);
    if (mounted) Navigator.pop(context, (link, null));
  });

  /// A kept case, taken as it is: where it is in UYAP comes with it, or for
  /// one an earlier Folio kept, from a document tied to it.
  Future<void> _take(UyapCaseRecord record) async {
    final link =
        record.link ??
        await UyapCaseLinks.instance.findFor(record.court, record.number) ??
        UyapCaseLink(
          jurisdiction: '',
          courtType: '',
          courtId: '',
          court: record.court,
          number: record.number,
        );
    if (mounted) Navigator.pop(context, (link, null));
  }

  Widget _keptList(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      TextField(
        key: const ValueKey('uyap-kept-filter'),
        controller: _filter,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.search, size: 18),
          hintText: 'Dosyalarımda ve portföyde ara: esas no, birim',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 6),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final record in _kept)
              if (_shows(record.number, record.court))
                ListTile(
                  key: ValueKey('uyap-kept-${record.key}'),
                  dense: true,
                  leading: const Icon(Icons.gavel_rounded, size: 18),
                  title: Text(record.number),
                  subtitle: Text(record.court),
                  trailing: const Text(
                    'Dava Dosyalarım',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () => unawaited(_take(record)),
                ),
            for (final kase in _portfolio)
              if (_shows(kase.number, kase.court))
                ListTile(
                  key: ValueKey('uyap-portfolio-${kase.key}'),
                  dense: true,
                  enabled: !_busy && (_web.connected || _mobile.connected),
                  leading: const Icon(Icons.cloud_download_outlined, size: 18),
                  title: Text(kase.number),
                  subtitle: Text(kase.court),
                  trailing: const Text(
                    'Portföy · çekilir',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () => unawaited(_import(kase)),
                ),
          ],
        ),
      ),
      if (_busy) ...[
        const SizedBox(height: 6),
        const LinearProgressIndicator(),
      ],
      if (_error != null && !_web.connected) ...[
        const SizedBox(height: 6),
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const Divider(height: 20),
      Text(
        'UYAP’ta ara',
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
    ],
  );

  @override
  void dispose() {
    _web.session.removeListener(_sessionChanged);
    _mobile.session.removeListener(_sessionChanged);
    _filter.dispose();
    _year.dispose();
    _number.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Yargıtay or Danıştay: chambers in place of kinds of court and courts.
  bool get _high => UyapWebService.isHighCourt(_jurisdiction);

  Future<void> _loadTypes() => _run(() async {
    final types = _high
        ? await _web.chambers(_jurisdiction)
        : await _web.courtTypes(_jurisdiction);
    if (!mounted) return;
    setState(() {
      _types = types;
      _type = null;
      _courts = const [];
      _court = null;
      _cases = null;
    });
  });

  Future<void> _loadCourts() => _run(() async {
    final type = _type;
    if (type == null) return;
    final courts = await _web.courts(_jurisdiction, type.id, closed: _closed);
    if (!mounted) return;
    setState(() {
      _courts = courts;
      _court = courts.length == 1 ? courts.first : null;
      _cases = null;
    });
  });

  Future<void> _search() => _run(() async {
    if (_high) {
      final chamber = _type;
      if (chamber == null) throw StateError('Daireyi seçin.');
      // The chamber comes whole; the year and number narrow it here.
      final year = int.tryParse(_year.text.trim());
      final number = int.tryParse(_number.text.trim());
      final found = [
        for (final c in await _web.chamberCases(_jurisdiction, chamber))
          if ((year == null || c.parsedNumber?.year == year) &&
              (number == null || c.parsedNumber?.sequence == number))
            c,
      ];
      if (mounted) setState(() => _cases = found);
      return;
    }
    final type = _type;
    final court = _court;
    if (type == null || court == null) {
      throw StateError('Mahkeme türünü ve mahkemeyi seçin.');
    }
    final found = await _web.cases(
      jurisdiction: _jurisdiction,
      courtType: type.id,
      court: court,
      year: int.tryParse(_year.text.trim()),
      number: int.tryParse(_number.text.trim()),
      closed: _closed,
    );
    if (mounted) setState(() => _cases = found);
  });

  void _pick(UyapCase found) => Navigator.pop(context, (
    UyapCaseLink(
      jurisdiction: _jurisdiction,
      // A chamber is found again by itself; it has no kind of court.
      courtType: _high ? '' : _type!.id,
      courtId: found.courtId.isEmpty
          ? (_high ? _type!.id : _court!.id)
          : found.courtId,
      court: found.courtName.isEmpty
          ? (_high ? _type!.label : _court!.label)
          : found.courtName,
      number: found.number,
      closed: _closed,
    ),
    found,
  ));

  InputDecoration _field(String label) => InputDecoration(
    labelText: label,
    isDense: true,
    border: const OutlineInputBorder(),
  );

  @override
  Widget build(BuildContext context) {
    final cases = _cases;
    return AlertDialog(
      title: const Text('UYAP dosyası bağla'),
      content: SizedBox(
        width: 560,
        // The kept cases above the search can outgrow a short window.
        child: SingleChildScrollView(
          child: !_web.connected
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_kept.isNotEmpty || _portfolio.isNotEmpty)
                      _keptList(context),
                    if (!_mobile.connected && PortalSync.started != null) ...[
                      OutlinedButton.icon(
                        key: const ValueKey('uyap-picker-mobile'),
                        onPressed: () async {
                          if (await connectUyapMobile(
                            context,
                            api: _sync.mobile,
                          )) {
                            await _sync.syncMobile();
                            await _loadKept();
                          }
                        },
                        icon: const Icon(Icons.phone_iphone, size: 18),
                        label: const Text(
                          'UYAP Mobil ile bağlan (portföyü getirir)',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    UyapConnectView(
                      note: _kept.isEmpty
                          ? 'Dosyayı bulmak için bağlanın.'
                          : 'Başka bir dosyayı UYAP’ta bulmak için bağlanın.',
                      onConnected: (_) => _loadTypes(),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_kept.isNotEmpty || _portfolio.isNotEmpty)
                      _keptList(context),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: UyapSessionChip(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FolioSelect<String>(
                            initialValue: _jurisdiction,
                            decoration: _field('Yargı türü'),
                            items: const [
                              DropdownMenuItem(
                                value: '1',
                                child: Text('Hukuk'),
                              ),
                              DropdownMenuItem(value: '0', child: Text('Ceza')),
                              DropdownMenuItem(value: '2', child: Text('İcra')),
                              DropdownMenuItem(
                                value: '6',
                                child: Text('İdari'),
                              ),
                              DropdownMenuItem(
                                value: 'yargitay',
                                child: Text('Yargıtay'),
                              ),
                              DropdownMenuItem(
                                value: 'danistay',
                                child: Text('Danıştay'),
                              ),
                            ],
                            onChanged: _busy
                                ? null
                                : (v) {
                                    if (v == null) return;
                                    _jurisdiction = v;
                                    unawaited(_loadTypes());
                                  },
                          ),
                        ),
                        // A high court's list has the closed cases with the
                        // open; there is nothing to choose.
                        if (!_high) ...[
                          const SizedBox(width: 10),
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: false, label: Text('Açık')),
                              ButtonSegment(value: true, label: Text('Kapalı')),
                            ],
                            selected: {_closed},
                            onSelectionChanged: _busy
                                ? null
                                : (v) {
                                    setState(() => _closed = v.first);
                                    unawaited(_loadCourts());
                                  },
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    FolioSelect<UyapOption>(
                      key: ValueKey('tur-${_types.length}-$_jurisdiction'),
                      initialValue: _type,
                      isExpanded: true,
                      decoration: _field(_high ? 'Daire' : 'Mahkeme türü'),
                      items: [
                        for (final t in _types)
                          DropdownMenuItem(value: t, child: Text(t.label)),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) {
                              setState(() {
                                _type = v;
                                _cases = null;
                              });
                              if (!_high) unawaited(_loadCourts());
                            },
                    ),
                    if (_high && !_busy && _types.isEmpty) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Bu yargı yerinde dosyanız görünmüyor.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                    if (!_high) ...[
                      const SizedBox(height: 10),
                      FolioSelect<UyapOption>(
                        key: ValueKey('mahkeme-${_courts.length}-${_type?.id}'),
                        initialValue: _court,
                        isExpanded: true,
                        decoration: _field('Mahkeme'),
                        items: [
                          for (final c in _courts)
                            DropdownMenuItem(
                              value: c,
                              child: Text(
                                c.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _court = v),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: _year,
                            decoration: _field('Yıl (boş: tümü)'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _number,
                            decoration: _field('Esas sıra no (boş: tümü)'),
                            keyboardType: TextInputType.number,
                            onSubmitted: (_) => unawaited(_search()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: _busy ? null : () => unawaited(_search()),
                          icon: const Icon(Icons.search, size: 18),
                          label: const Text('Ara'),
                        ),
                      ],
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (cases != null) ...[
                      const SizedBox(height: 12),
                      if (cases.isEmpty)
                        const Text('Bu ölçütlerle dosya bulunamadı.')
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              for (final c in cases)
                                ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.folder_outlined),
                                  title: Text(c.number),
                                  subtitle: Text(c.courtName),
                                  onTap: () => _pick(c),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
      ],
    );
  }
}
