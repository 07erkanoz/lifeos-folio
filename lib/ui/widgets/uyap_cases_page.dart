import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

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
  });

  /// The case shown, by [UyapCaseRecord.key]; null for the list of cases.
  final String? caseKey;

  /// A case chosen from the list, or null to go back to the list.
  final ValueChanged<String?> onShowCase;

  /// Shows a document in Folio's preview.
  final ValueChanged<File> onOpen;

  /// Told where a document was saved, so that Folio can search the folder.
  final void Function(File file)? onSaved;

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
                : Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: UyapCasePanel(
                        controller: _controller,
                        onOpen: (file, _) => widget.onOpen(file),
                        onRemoved: () => widget.onShowCase(null),
                      ),
                    ),
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: cases.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final (record, saved) = cases[i];
        final hearing = record.details.hearing;
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            key: ValueKey('uyap-cases-${record.key}'),
            leading: Icon(
              Icons.gavel_rounded,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              record.number,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              [
                record.court,
                if (hearing != null && hearing.trim().isNotEmpty)
                  'Duruşma: $hearing',
                'Son eşitleme ${_clock(record.fetchedAt)}',
              ].join('\n'),
            ),
            isThreeLine: true,
            trailing: Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (record.fresh.isNotEmpty)
                  _badge(theme, '${record.fresh.length} yeni'),
                Text('$saved / ${record.documents.length} evrak', style: muted),
              ],
            ),
            onTap: () => widget.onShowCase(record.key),
          ),
        );
      },
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
