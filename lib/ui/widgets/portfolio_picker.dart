import 'package:flutter/material.dart';

import '../../services/portal/portal_case.dart';
import '../../services/uyap/uyap_web_service.dart';

/// The portfolio the portals gave (UYAP Mobil's every case, the web's
/// hearings' cases), grouped by unit: a whole unit or cases one by one are
/// chosen to be added to UYAP Dosyalarım. Cases already there are left out.
class PortfolioPicker extends StatefulWidget {
  const PortfolioPicker({super.key, required this.cases});

  final List<PortalCase> cases;

  /// A page of its own on a phone, a dialog on a computer.
  static Future<List<PortalCase>?> show(
    BuildContext context,
    List<PortalCase> cases,
  ) => MediaQuery.sizeOf(context).width < 700
      ? Navigator.of(context).push<List<PortalCase>>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => PortfolioPicker(cases: cases),
          ),
        )
      : showDialog<List<PortalCase>>(
          context: context,
          builder: (_) => PortfolioPicker(cases: cases),
        );

  @override
  State<PortfolioPicker> createState() => _PortfolioPickerState();
}

class _PortfolioPickerState extends State<PortfolioPicker> {
  final _query = TextEditingController();
  final _chosen = <String>{};
  final _open = <String>{};
  bool _closed = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  static bool _isClosed(PortalCase c) {
    final s = UyapWebService.fold(c.status?.value ?? '');
    return s.contains('kapal') || s.contains('kapan');
  }

  /// The cases shown, by unit, the units in alphabetical order.
  Map<String, List<PortalCase>> get _groups {
    final words = UyapWebService.fold(_query.text)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    final out = <String, List<PortalCase>>{};
    for (final c in widget.cases) {
      if (!_closed && _isClosed(c)) continue;
      final text = UyapWebService.fold('${c.number} ${c.court}');
      if (!words.every(text.contains)) continue;
      (out[c.court] ??= []).add(c);
    }
    for (final list in out.values) {
      list.sort((a, b) => b.number.compareTo(a.number));
    }
    return Map.fromEntries(
      out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  List<PortalCase> get _picked => [
    for (final c in widget.cases)
      if (_chosen.contains(c.key)) c,
  ];

  Widget _search() => TextField(
    key: const ValueKey('portfolio-search'),
    controller: _query,
    onChanged: (_) => setState(() {}),
    decoration: const InputDecoration(
      isDense: true,
      prefixIcon: Icon(Icons.search, size: 18),
      hintText: 'Birim ya da esas no',
      border: OutlineInputBorder(),
    ),
  );

  Widget _closedChip() => FilterChip(
    label: const Text('Kapalılar da'),
    selected: _closed,
    onSelected: (v) => setState(() => _closed = v),
  );

  Widget _listOf(Map<String, List<PortalCase>> groups, bool searching) {
    final scheme = Theme.of(context).colorScheme;
    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.cases.isEmpty
                ? 'Eklenecek dosya yok: portföyünüzdeki dosyaların '
                      'hepsi UYAP Dosyalarım’da.'
                : 'Aramaya uyan dosya yok.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final MapEntry(key: unit, value: list) in groups.entries)
          ..._group(context, unit, list, searching),
      ],
    );
  }

  /// A phone: the whole screen, the button the width of it at the foot.
  Widget _page(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = _groups;
    final searching = _query.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text(
          'Portföyden dosya ekle',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_chosen.isNotEmpty)
            TextButton(
              onPressed: () => setState(_chosen.clear),
              child: const Text('Temizle'),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Text(
              'Birimin kutusu tüm dosyalarını seçer; birimi açıp tek tek de '
              'seçebilirsiniz.',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: _search(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: Align(alignment: Alignment.centerLeft, child: _closedChip()),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _listOf(groups, searching),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: FilledButton.icon(
            key: const ValueKey('portfolio-add'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _chosen.isEmpty
                ? null
                : () => Navigator.pop(context, _picked),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(
              _chosen.isEmpty
                  ? 'Dosya seçin'
                  : '${_chosen.length} dosyayı ekle',
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 700) return _page(context);
    final scheme = Theme.of(context).colorScheme;
    final groups = _groups;
    final searching = _query.text.trim().isNotEmpty;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      title: const Text(
        'Portföyden dosya ekle',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      contentPadding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Bir birimin tüm dosyalarını ya da dosyaları tek tek seçin. '
              'Seçilenler UYAP’tan çekilip UYAP Dosyalarım’a eklenir.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('portfolio-search'),
                    controller: _query,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Birim ya da esas no',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('Kapalılar da'),
                  selected: _closed,
                  onSelected: (v) => setState(() => _closed = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: groups.isEmpty
                  ? Center(
                      child: Text(
                        widget.cases.isEmpty
                            ? 'Eklenecek dosya yok: portföyünüzdeki dosyaların '
                                  'hepsi UYAP Dosyalarım’da.'
                            : 'Aramaya uyan dosya yok.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final MapEntry(key: unit, value: list)
                            in groups.entries)
                          ..._group(context, unit, list, searching),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
      actions: [
        if (_chosen.isNotEmpty)
          TextButton(
            onPressed: () => setState(_chosen.clear),
            child: const Text('Seçimi temizle'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton.icon(
          key: const ValueKey('portfolio-add'),
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.pop(context, [
                  for (final c in widget.cases)
                    if (_chosen.contains(c.key)) c,
                ]),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(
            _chosen.isEmpty ? 'Ekle' : '${_chosen.length} dosyayı ekle',
          ),
        ),
      ],
    );
  }

  List<Widget> _group(
    BuildContext context,
    String unit,
    List<PortalCase> list,
    bool searching,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final chosen = list.where((c) => _chosen.contains(c.key)).length;
    final open = searching || _open.contains(unit);
    return [
      Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: ValueKey('portfolio-unit-$unit'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(
            () => _open.contains(unit) ? _open.remove(unit) : _open.add(unit),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                Checkbox(
                  key: ValueKey('portfolio-unit-check-$unit'),
                  tristate: true,
                  value: chosen == 0
                      ? false
                      : chosen == list.length
                      ? true
                      : null,
                  onChanged: (_) => setState(() {
                    if (chosen == list.length) {
                      _chosen.removeAll(list.map((c) => c.key));
                    } else {
                      _chosen.addAll(list.map((c) => c.key));
                    }
                  }),
                ),
                Expanded(
                  child: Text(
                    unit,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  chosen == 0
                      ? '${list.length} dosya'
                      : '$chosen / ${list.length} seçili',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
      if (open)
        for (final c in list)
          InkWell(
            key: ValueKey('portfolio-case-${c.key}'),
            onTap: () => setState(
              () => _chosen.contains(c.key)
                  ? _chosen.remove(c.key)
                  : _chosen.add(c.key),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Row(
                children: [
                  Checkbox(
                    value: _chosen.contains(c.key),
                    onChanged: (v) => setState(
                      () => v == true
                          ? _chosen.add(c.key)
                          : _chosen.remove(c.key),
                    ),
                  ),
                  Text(
                    c.number,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      [
                        '${c.details?.value['tur'] ?? ''}',
                        c.status?.value ?? '',
                      ].where((s) => s.trim().isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      const SizedBox(height: 6),
    ];
  }
}
