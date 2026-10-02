import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/uyap/uyap_case_links.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../../services/uyap/uyap_web_service.dart';
import 'uyap_connect_view.dart';
import 'uyap_session_chip.dart';

/// Finds the UYAP case a document is written for: the kind of court, the
/// court, then the number. Asks for a session first when there is none.
class UyapCasePicker extends StatefulWidget {
  const UyapCasePicker({super.key, this.offerKept = false});

  /// Lists the cases kept on this computer first, to take one without
  /// UYAP; a document is tied to a case this way most of the time.
  final bool offerKept;

  /// The case chosen, as it can be found again in any session, and as it
  /// is in this one: null for a case taken from those kept, without UYAP.
  static Future<(UyapCaseLink, UyapCase?)?> show(
    BuildContext context, {
    bool offerKept = false,
  }) => showDialog<(UyapCaseLink, UyapCase?)>(
    context: context,
    builder: (_) => UyapCasePicker(offerKept: offerKept),
  );

  @override
  State<UyapCasePicker> createState() => _UyapCasePickerState();
}

class _UyapCasePickerState extends State<UyapCasePicker> {
  UyapWebService get _web => UyapWebService.instance;
  final _year = TextEditingController(text: '${DateTime.now().year}');
  final _number = TextEditingController();
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

  @override
  void initState() {
    super.initState();
    _web.session.addListener(_sessionChanged);
    if (_web.connected) unawaited(_loadTypes());
    if (widget.offerKept) {
      unawaited(
        UyapCaseStore.instance.cases().then((all) {
          if (mounted) setState(() => _kept = [for (final (r, _) in all) r]);
        }, onError: (Object _) {}),
      );
    }
  }

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
      Text(
        'Bu bilgisayardaki dosyalar',
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final record in _kept)
              ListTile(
                key: ValueKey('uyap-kept-${record.key}'),
                dense: true,
                leading: const Icon(Icons.gavel_rounded, size: 18),
                title: Text(record.number),
                subtitle: Text(record.court),
                onTap: () => unawaited(_take(record)),
              ),
          ],
        ),
      ),
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

  Future<void> _loadTypes() => _run(() async {
    final types = await _web.courtTypes(_jurisdiction);
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
      courtType: _type!.id,
      courtId: found.courtId.isEmpty ? _court!.id : found.courtId,
      court: found.courtName.isEmpty ? _court!.label : found.courtName,
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
                    if (_kept.isNotEmpty) _keptList(context),
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
                    if (_kept.isNotEmpty) _keptList(context),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: UyapSessionChip(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
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
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<UyapOption>(
                      key: ValueKey('tur-${_types.length}-$_jurisdiction'),
                      initialValue: _type,
                      isExpanded: true,
                      decoration: _field('Mahkeme türü'),
                      items: [
                        for (final t in _types)
                          DropdownMenuItem(value: t, child: Text(t.label)),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) {
                              setState(() => _type = v);
                              unawaited(_loadCourts());
                            },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<UyapOption>(
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
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: _year,
                            decoration: _field('Yıl'),
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
