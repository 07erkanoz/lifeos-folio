import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/platform/file_actions.dart';
import '../../services/uyap/uyap_case_panel_controller.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../../services/uyap/uyap_web_service.dart';
import 'uyap_case_picker.dart';
import 'uyap_connect_view.dart';
import 'uyap_session_chip.dart';

/// The UYAP case beside the document being written: its particulars and
/// parties to write from, and its documents to read beside the page — a
/// statement of claim, an expert's report — fetched once and kept.
class UyapCasePanel extends StatefulWidget {
  const UyapCasePanel({
    super.key,
    required this.controller,
    required this.onOpen,
    this.onInsert,
    this.onClose,
    this.onRemoved,
  });

  final UyapCasePanelController controller;

  /// Shows a document, kept on disk, beside the page.
  final void Function(File file, UyapCaseDocument document) onOpen;

  /// Puts [text] where the caret is: a party's name, the case number.
  /// Null on the case's own page, where there is no document to write in.
  final ValueChanged<String>? onInsert;

  /// Null on the case's own page, which is not a panel to close.
  final VoidCallback? onClose;

  /// The case's own page: called once the case was taken off Folio's list.
  /// Its presence is what makes this the page: no document to tie or untie,
  /// the case to remove instead, and what was downloaded listed at the end.
  final VoidCallback? onRemoved;

  bool get page => onRemoved != null;

  @override
  State<UyapCasePanel> createState() => _UyapCasePanelState();
}

class _UyapCasePanelState extends State<UyapCasePanel> {
  UyapCasePanelController get _c => widget.controller;
  UyapWebService get _web => UyapWebService.instance;
  final _search = TextEditingController();

  /// Asked for a session for this: what to do once there is one.
  Future<void> Function()? _afterConnect;

  @override
  void initState() {
    super.initState();
    _web.session.addListener(_changed);
    unawaited(UyapSettings.instance.load());
  }

  @override
  void dispose() {
    _web.session.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Runs [work] with a session, asking for one first if there is none.
  Future<void> _withSession(Future<void> Function() work) async {
    if (_web.connected) return work();
    setState(() => _afterConnect = work);
  }

  Future<void> _pick() async {
    final chosen = await UyapCasePicker.show(context, offerKept: true);
    if (chosen == null) return;
    final live = chosen.$2;
    // A case kept on this computer is tied without asking UYAP.
    await (live == null ? _c.attach(chosen.$1) : _c.choose(chosen.$1, live));
  }

  Future<void> _remove() async {
    final record = _c.record;
    if (record == null) return;
    final saved = _c.store.savedFiles(record).length;
    var documents = false;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Dosyayı listeden kaldır'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${record.court} ${record.number} Folio’nun listesinden '
                'kaldırılır. UYAP’taki dosyaya dokunulmaz; dosyayı '
                'istediğiniz zaman yeniden ekleyebilirsiniz.',
              ),
              if (saved > 0)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: documents,
                  onChanged: (v) => set(() => documents = v ?? false),
                  title: Text('İndirilen $saved evrakı da sil'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              key: const ValueKey('uyap-case-remove-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kaldır'),
            ),
          ],
        ),
      ),
    );
    if (sure != true) return;
    await _c.store.remove(record, documents: documents);
    widget.onRemoved?.call();
  }

  Future<void> _open(UyapCaseDocument document) async {
    Future<void> go() async {
      final file = await _c.open(document);
      if (file != null && mounted) widget.onOpen(file, document);
    }

    final record = _c.record;
    if (record != null && _c.store.fileOf(record, document.key) != null) {
      return go();
    }
    await _withSession(go);
  }

  Future<void> _settings() async {
    final settings = UyapSettings.instance;
    await settings.load();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('UYAP evrakları'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('İndirilen evrakları kaydet'),
                  subtitle: const Text(
                    'Kayıtlı evraklar Folio’da aranabilir ve bağlantı '
                    'olmadan da açılır. Kapalıyken yalnız Folio’nun kendi '
                    'önbelleğinde tutulur.',
                  ),
                  value: settings.saveDocuments,
                  onChanged: (v) async {
                    await settings.update(saveDocuments: v);
                    set(() {});
                  },
                ),
                const SizedBox(height: 8),
                const Text('Kayıt klasörü'),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        settings.folder,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final folder = await FilePicker.getDirectoryPath(
                          dialogTitle: 'UYAP evraklarının klasörü',
                          initialDirectory: settings.folder,
                        );
                        if (folder != null) {
                          await settings.update(folder: folder);
                          set(() {});
                        }
                      },
                      child: const Text('Değiştir'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Belgeler klasörü yerine ev klasörünüz önerilir: Windows '
                  'Belgeler’i OneDrive’a taşıyabilir.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final theme = Theme.of(context);
        final link = _c.link;
        final record = _c.record;
        return Material(
          color: theme.colorScheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(theme),
              const Divider(height: 1),
              if (_c.busy != null) ...[
                const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                  child: Text(
                    _c.busy!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
              if (_c.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  child: Text(
                    _c.error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              if (_afterConnect != null && !_web.connected)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: UyapConnectView(
                    note: 'Bu iş için UYAP oturumu gerekiyor.',
                    onConnected: (_) async {
                      final then = _afterConnect;
                      setState(() => _afterConnect = null);
                      await then?.call();
                    },
                  ),
                )
              else if (link == null)
                _unlinked(theme)
              else if (record == null)
                _notFetched(theme)
              else
                Expanded(child: _case(theme, record)),
            ],
          ),
        );
      },
    );
  }

  Widget _header(ThemeData theme) {
    final link = _c.link;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      child: Row(
        children: [
          Icon(Icons.gavel_rounded, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  link == null ? 'UYAP dosyası' : link.number,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (link != null)
                  Text(
                    link.court,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (link != null && _c.findable)
            IconButton(
              tooltip: 'UYAP’tan yenile',
              onPressed: _c.busy != null
                  ? null
                  : () => unawaited(_withSession(_c.refresh)),
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          PopupMenuButton<String>(
            tooltip: 'Dosya işlemleri',
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            onSelected: (value) async {
              switch (value) {
                case 'pick':
                  await _pick();
                case 'unlink':
                  await _c.unlink();
                case 'folder':
                  final record = _c.record;
                  if (record != null) {
                    final folder = Directory(
                      '${UyapSettings.instance.folder}'
                      '${Platform.pathSeparator}'
                      '${UyapCaseStore.caseFolderName(record)}',
                    );
                    await folder.create(recursive: true);
                    await FileActions.invoke('openDefault', folder.path);
                  }
                case 'remove':
                  await _remove();
                case 'settings':
                  await _settings();
              }
            },
            itemBuilder: (_) => [
              if (!widget.page)
                PopupMenuItem(
                  value: 'pick',
                  child: Text(
                    link == null ? 'Dosya bağla…' : 'Başka dosya bağla…',
                  ),
                ),
              if (link != null) ...[
                const PopupMenuItem(
                  value: 'folder',
                  child: Text('Evrak klasörünü aç'),
                ),
                if (!widget.page)
                  const PopupMenuItem(
                    value: 'unlink',
                    child: Text('Bağı kaldır'),
                  ),
              ],
              if (widget.page && _c.record != null)
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Listeden kaldır…'),
                ),
              const PopupMenuItem(
                value: 'settings',
                child: Text('Kayıt ayarları…'),
              ),
            ],
          ),
          if (widget.onClose != null)
            IconButton(
              tooltip: 'Paneli kapat',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _unlinked(ThemeData theme) => Padding(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bu belgeyi bir UYAP dosyasına bağlayın. Dosyanın tarafları, '
          'duruşma ve keşif günleri ve evrakları burada görünür; dava '
          'dilekçesini ya da bilirkişi raporunu sayfanın yanında açarak '
          'yazabilirsiniz.',
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const ValueKey('uyap-panel-link'),
          onPressed: () => unawaited(_pick()),
          icon: const Icon(Icons.link_rounded, size: 18),
          label: const Text('Dosya bağla'),
        ),
      ],
    ),
  );

  Widget _notFetched(ThemeData theme) => Padding(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Bu dosyanın bilgileri bu bilgisayarda henüz yok.'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _c.busy != null
              ? null
              : () => unawaited(_withSession(_c.refresh)),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('UYAP’tan çek'),
        ),
      ],
    ),
  );

  static String _clock(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
  }

  Widget _case(ThemeData theme, UyapCaseRecord record) {
    final documents = _c.documents;
    final sources = {for (final d in record.documents) d.source};
    final fresh = record.fresh.length;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                // Side by side when the panel is wide enough, the time
                // under the session otherwise: never squeezed letter by
                // letter beside it.
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    const UyapSessionChip(),
                    Text('Son çekim ${_clock(record.fetchedAt)}', style: muted),
                  ],
                ),
              ),
              _section(theme, 'Dosya bilgileri', [
                _fact('Dava türü', record.details.kind),
                _fact('Durum', record.details.status),
                _fact('Duruşma', record.details.hearing, strong: true),
                _fact('Keşif', record.details.inspection, strong: true),
                _fact('Ön inceleme', record.details.preliminary, strong: true),
                for (final (label, value) in record.details.related)
                  _fact(label, value),
              ]),
              _section(theme, 'Taraflar · ${record.parties.length}', [
                for (final t in record.parties)
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    title: Text(t.name),
                    subtitle: Text(
                      [
                        t.role,
                        if (t.lawyer.isNotEmpty) 'Vekil: ${t.lawyer}',
                      ].join(' · '),
                    ),
                    trailing: widget.onInsert == null
                        ? null
                        : IconButton(
                            tooltip: 'Metne ekle',
                            icon: const Icon(Icons.input_rounded, size: 18),
                            onPressed: () => widget.onInsert!(t.name),
                          ),
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: Row(
                  children: [
                    Text(
                      'Evraklar · ${record.documents.length}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (fresh > 0) ...[
                      const SizedBox(width: 8),
                      _badge(theme, '$fresh yeni'),
                    ],
                  ],
                ),
              ),
              if (record.previousFetchedAt != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                  child: Text(
                    'Yeniler: ${_clock(record.previousFetchedAt!)} çekiminden '
                    'sonra gelenler',
                    style: muted,
                  ),
                ),
              if (record.withheld != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Text(
                    'UYAP evrakları şu an göstermiyor: ${record.withheld}',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: TextField(
                  key: const ValueKey('uyap-panel-search'),
                  controller: _search,
                  onChanged: (v) => _c.query = v,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: 'Evrak ara: tür, gönderen, tarih',
                    border: const OutlineInputBorder(),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _search.clear();
                              _c.query = '';
                            },
                          ),
                  ),
                ),
              ),
              for (final source in sources)
                ...() {
                  final group = [
                    for (final d in documents)
                      if (d.source == source) d,
                  ];
                  if (group.isEmpty) return const <Widget>[];
                  return [
                    if (sources.length > 1)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
                        child: Text(
                          source.isEmpty ? 'Son eklenenler' : source,
                          style: muted?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    for (final d in group) ...[
                      _row(theme, d),
                      for (final a in d.attachments) _row(theme, a, depth: 1),
                    ],
                  ];
                }(),
              if (documents.isEmpty && record.documents.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Aramaya uyan evrak yok.'),
                ),
              if (widget.page) ..._saved(theme, record),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: Row(
            children: [
              if (_c.selected.isNotEmpty)
                TextButton(
                  onPressed: () => setState(_c.selected.clear),
                  child: const Text('Seçimi bırak'),
                ),
              const Spacer(),
              FilledButton.tonalIcon(
                key: const ValueKey('uyap-panel-download'),
                onPressed: _c.busy != null || record.documents.isEmpty
                    ? null
                    : () => unawaited(
                        _withSession(
                          () => _c
                              .download(
                                _c.selected.isEmpty ? null : {..._c.selected},
                              )
                              .then((_) {}),
                        ),
                      ),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(
                  _c.selected.isEmpty
                      ? 'Tümünü indir'
                      : 'Seçilenleri indir (${_c.selected.length})',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// What of the case is on this computer, to open without UYAP.
  List<Widget> _saved(ThemeData theme, UyapCaseRecord record) {
    final files = _c.store.savedFiles(record);
    final byKey = {
      for (final d in record.documents) ...{
        d.key: d,
        for (final a in d.attachments) a.key: a,
      },
    };
    return [
      const Divider(height: 24),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
        child: Text(
          'İndirilen evrak · ${files.length}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      if (files.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
          child: Text(
            'Bu dosyadan henüz evrak indirilmedi. Yukarıdaki listeden '
            'seçerek ya da tümünü indirebilirsiniz.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      for (final MapEntry(key: key, value: file) in files.entries)
        ListTile(
          key: ValueKey('uyap-saved-$key'),
          dense: true,
          leading: const Icon(Icons.description_outlined, size: 20),
          title: Text(byKey[key]?.title ?? file.uri.pathSegments.last),
          subtitle: Text(file.uri.pathSegments.last),
          onTap: () {
            final document = byKey[key];
            if (document != null) widget.onOpen(file, document);
          },
        ),
    ];
  }

  Widget _section(ThemeData theme, String title, List<Widget> children) =>
      Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          dense: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 4),
          children: children,
        ),
      );

  Widget _fact(String label, String? value, {bool strong = false}) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
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

  Widget _row(ThemeData theme, UyapCaseDocument d, {int depth = 0}) {
    final saved = _c.isSaved(d.key);
    final fresh = _c.isNew(d.key);
    final date = d.date;
    final meta = [
      if (date != null)
        '${date.day.toString().padLeft(2, '0')}.'
            '${date.month.toString().padLeft(2, '0')}.${date.year}',
      if (d.sender.isNotEmpty) d.sender,
    ].join(' · ');
    return InkWell(
      key: ValueKey('uyap-doc-${d.key}'),
      onTap: () => unawaited(_open(d)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(4.0 + depth * 22, 2, 10, 2),
        child: Row(
          children: [
            Checkbox(
              value: _c.selected.contains(d.key),
              visualDensity: VisualDensity.compact,
              onChanged: (_) => _c.toggle(d.key),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          d.title.isEmpty ? 'Evrak' : d.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: fresh
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (fresh) ...[
                        const SizedBox(width: 6),
                        _badge(theme, 'Yeni'),
                      ],
                    ],
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Tooltip(
              message: saved ? 'Bu bilgisayarda kayıtlı' : 'Açınca indirilir',
              child: Icon(
                saved ? Icons.download_done_rounded : Icons.cloud_outlined,
                size: 17,
                color: saved
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
