import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/legal/case_law.dart';
import '../../services/legal/case_law_search.dart';
import '../widgets/article_panel.dart';
import '../widgets/notice.dart';
import 'case_law_results.dart';

/// Searching the official case bank.
///
/// Its own screen rather than a mode of the archive search, because the two
/// answer different questions — what is in my files, and what have the
/// courts held — and because the filters need the room.
///
/// Nothing here is guessed at. Every filter was measured against the bank
/// before it was offered: the bank ignores a field it does not know without
/// complaining, so a filter that quietly does nothing looks exactly like
/// one that works.
class CaseLawSearchScreen extends StatefulWidget {
  const CaseLawSearchScreen({
    super.key,
    required this.bank,
    this.compact = false,
  });

  final CaseLaw bank;

  /// The narrow arrangement, for a phone or a side panel.
  final bool compact;

  @override
  State<CaseLawSearchScreen> createState() => _CaseLawSearchScreenState();
}

class _CaseLawSearchScreenState extends State<CaseLawSearchScreen> {
  final _words = TextEditingController();
  final _chamber = TextEditingController();
  final _esasYear = TextEditingController();
  final _esasNo = TextEditingController();
  final _kararYear = TextEditingController();
  final _kararNo = TextEditingController();

  var _query = const CaseLawQuery();
  var _results = const CaseLawResults.empty();
  var _busy = false;
  var _asked = false;
  var _settling = false;
  var _filtersOpen = false;
  int _run = 0;

  @override
  void dispose() {
    for (final one in [
      _words,
      _chamber,
      _esasYear,
      _esasNo,
      _kararYear,
      _kararNo,
    ]) {
      one.dispose();
    }
    super.dispose();
  }

  static int? _number(TextEditingController field) =>
      int.tryParse(field.text.trim());

  CaseLawQuery get _asSetUp => _query.copyWith(
    words: _words.text,
    chamber: _chamber.text.trim().isEmpty ? null : _chamber.text.trim(),
    clearChamber: _chamber.text.trim().isEmpty,
    esasYear: _number(_esasYear),
    esasNumber: _number(_esasNo),
    kararYear: _number(_kararYear),
    kararNumber: _number(_kararNo),
    clearNumbers:
        _number(_esasYear) == null &&
        _number(_esasNo) == null &&
        _number(_kararYear) == null &&
        _number(_kararNo) == null,
  );

  Future<void> _search({int page = 1}) async {
    final query = _asSetUp.copyWith(page: page);
    if (query.isEmpty || query.kinds.isEmpty) return;
    final run = ++_run;
    setState(() {
      _query = query;
      _busy = true;
      _asked = true;
    });
    final found = await widget.bank.search(query);
    // The reader may have searched again while this was on its way.
    if (!mounted || run != _run) return;
    setState(() {
      _results = found;
      _busy = false;
      _settling = found.hits.isNotEmpty && query.hasWords;
    });

    // Shown in the bank's order at once; the order a reader wants needs
    // each decision read, so the list settles over the next few seconds
    // rather than keeping them waiting for all of it.
    await widget.bank.rank(query, found, (ordered) {
      if (!mounted || run != _run) return;
      setState(() => _results = ordered);
    }, wanted: () => mounted && run == _run);
    if (!mounted || run != _run) return;
    setState(() => _settling = false);
  }

  Future<void> _open(CaseLawHit hit) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final found = await widget.bank.byId(hit);
    if (!mounted) return;
    if (found == null) {
      messenger
        ?..clearSnackBars()
        ..showSnackBar(
          noticeBar('Kararın metni getirilemedi.', kind: NoticeKind.error),
        );
      return;
    }
    await showFoundDecision(context, found);
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1960),
      lastDate: DateTime(now.year, 12, 31),
      initialDateRange: _query.hasRange
          ? DateTimeRange(start: _query.from!, end: _query.to!)
          : null,
      helpText: 'Karar tarihi aralığı',
      saveText: 'Seç',
    );
    if (picked == null) return;
    setState(
      () => _query = _query.copyWith(from: picked.start, to: picked.end),
    );
  }

  static String _day(DateTime at) =>
      '${at.day.toString().padLeft(2, '0')}.'
      '${at.month.toString().padLeft(2, '0')}.${at.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _words,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    hintText:
                        'Kavram arayın — kıdem tazminatı giydirilmiş ücret',
                    helperText:
                        'Kelimelerin hepsi aranır. Tam ifade için "tırnak", '
                        'hariç tutmak için -kelime yazabilirsiniz.',
                    helperMaxLines: 2,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _busy ? null : () => _search(),
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Ara'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final kind in CourtKind.values)
                FilterChip(
                  label: Text(kind.label),
                  selected: _query.kinds.contains(kind),
                  onSelected: (on) => setState(() {
                    var kinds = {..._query.kinds};
                    if (on) {
                      // The Constitutional Court's bank is asked on its own,
                      // and each of its two on its own: choosing one lets
                      // go of whatever cannot be asked together with it.
                      kinds = kind.constitutional != null
                          ? {kind}
                          : {
                              for (final one in kinds)
                                if (one.constitutional == null) one,
                              kind,
                            };
                    } else if (kinds.length > 1) {
                      // One bench must stay chosen, or the search would
                      // look through nothing and answer nothing.
                      kinds.remove(kind);
                    }
                    _query = _query.copyWith(kinds: kinds);
                  }),
                ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
                icon: Icon(
                  _filtersOpen ? Icons.expand_less_rounded : Icons.tune_rounded,
                  size: 18,
                ),
                label: Text(_filtersOpen ? 'Süzgeçleri gizle' : 'Süzgeçler'),
              ),
            ],
          ),
        ),
        if (_filtersOpen) _filters(theme),
        const SizedBox(height: 6),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: CaseLawResultList(
            results: _results,
            busy: _busy,
            settling: _settling,
            asked: _asked,
            compact: widget.compact,
            onOpen: _open,
            onPage: (page) => _search(page: page),
          ),
        ),
      ],
    );
  }

  Widget _filters(ThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The Constitutional Court's bank takes words and numbers only; a
        // filter it would quietly ignore is not offered.
        if (_query.constitutional == null) ...[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<WordJoin>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  for (final join in WordJoin.values)
                    ButtonSegment(value: join, label: Text(join.label)),
                ],
                selected: {_query.join},
                onSelectionChanged: (chosen) => setState(
                  () => _query = _query.copyWith(join: chosen.first),
                ),
              ),
              SizedBox(
                width: 210,
                child: TextField(
                  controller: _chamber,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Daire',
                    hintText: '3. Hukuk Dairesi',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: Text(
                  _query.hasRange
                      ? '${_day(_query.from!)} – ${_day(_query.to!)}'
                      : 'Karar tarihi',
                ),
              ),
              if (_query.hasRange)
                IconButton(
                  tooltip: 'Tarih aralığını kaldır',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(
                    () => _query = _query.copyWith(clearRange: true),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Text(
          'KÜNYE İLE ARAMA',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_query.kinds.contains(CourtKind.aymBireysel)) ...[
              // An individual application has one number, and it goes in
              // the esas fields.
              _numberField(_esasYear, 'Başvuru yılı', 96),
              _numberField(_esasNo, 'Başvuru no', 96),
            ] else ...[
              _numberField(_esasYear, 'Esas yılı', 86),
              _numberField(_esasNo, 'Esas no', 86),
              const Text('·'),
              _numberField(_kararYear, 'Karar yılı', 86),
              _numberField(_kararNo, 'Karar no', 86),
            ],
            Text(
              _query.kinds.contains(CourtKind.aymBireysel)
                  ? 'İkisi birden girilince tek başvuru bulunur.'
                  : 'Dördü birden girilince tek karar bulunur.',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _numberField(
    TextEditingController field,
    String label,
    double width,
  ) => SizedBox(
    width: width,
    child: TextField(
      controller: field,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: (_) => _search(),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
