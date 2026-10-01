import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/uyap/uyap_case_links.dart';
import '../../services/uyap/uyap_web_service.dart';
import 'uyap_connect_view.dart';
import 'uyap_session_chip.dart';

/// Finds the UYAP case a document is written for: the kind of court, the
/// court, then the number. Asks for a session first when there is none.
class UyapCasePicker extends StatefulWidget {
  const UyapCasePicker({super.key});

  /// The case chosen, as it can be found again in any session, and as it
  /// is in this one.
  static Future<(UyapCaseLink, UyapCase)?> show(BuildContext context) =>
      showDialog<(UyapCaseLink, UyapCase)>(
        context: context,
        builder: (_) => const UyapCasePicker(),
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

  @override
  void initState() {
    super.initState();
    _web.session.addListener(_sessionChanged);
    if (_web.connected) unawaited(_loadTypes());
  }

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
        child: !_web.connected
            ? SingleChildScrollView(
                child: UyapConnectView(
                  note: 'Dosyayı bulmak için bağlanın.',
                  onConnected: (_) => _loadTypes(),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                            DropdownMenuItem(value: '1', child: Text('Hukuk')),
                            DropdownMenuItem(value: '0', child: Text('Ceza')),
                            DropdownMenuItem(value: '2', child: Text('İcra')),
                            DropdownMenuItem(value: '6', child: Text('İdari')),
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
                          child: Text(c.label, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => _court = v),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
      ],
    );
  }
}
