import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/office/office_inbox.dart';
import '../../services/office/office_network.dart';
import '../../services/platform/file_actions.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../portfolio/portfolio_rows.dart' show clockText, dayText;
import 'office_offer_dialog.dart' show sizeText;

/// Gelenler (the approved mock): what came to this device, day by day,
/// the newest first; who sent it, when, with what word, and a tap to
/// open it.
class InboxPage extends StatefulWidget {
  const InboxPage({
    super.key,
    this.inbox,
    required this.onOpen,
    this.onSearchable,
  });

  final OfficeInbox? inbox;

  /// Opens a file in Folio.
  final void Function(String path) onOpen;

  /// The inbox's folder into the archive's search, or out of it.
  final Future<void> Function(bool on)? onSearchable;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  OfficeInbox get _inbox => widget.inbox ?? OfficeInbox.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_inbox.reload());
  }

  String _day(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final ago = today.difference(day).inDays;
    return ago == 0
        ? 'BUGÜN'
        : ago == 1
        ? 'DÜN'
        : dayText(d);
  }

  Future<void> _folder() async {
    final dir = await OfficeNetwork.instance.inbox();
    await FileActions.invoke('showFolder', dir.path);
  }

  void _open(InboxItem i) {
    unawaited(_inbox.markRead(i));
    if (i.paths.isNotEmpty) widget.onOpen(i.paths.first);
  }

  Future<void> _remove(InboxItem i) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Silinsin mi?'),
        content: Text(
          '${i.names.length == 1 ? i.names.single : '${i.names.length} dosya'}'
          ' Gelenler’den ve bu bilgisayardan silinecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const ValueKey('inbox-remove-yes'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (go == true) await _inbox.remove(i);
  }

  Future<void> _searchable(bool on) async {
    await _inbox.setSearchable(on);
    await widget.onSearchable?.call(on);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    // A Material ground: the switch's tile paints on it.
    return Material(
      color: dark ? scheme.surface : AgendaColors.page,
      child: ListenableBuilder(
        listenable: _inbox,
        builder: (context, _) => LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 900;
            final pad = wide ? 24.0 : 12.0;
            final items = _inbox.items;
            String? last;
            return ListView(
              key: const ValueKey('inbox-page'),
              padding: EdgeInsets.fromLTRB(pad, wide ? 18 : 10, pad, 24),
              children: [
                Row(
                  children: [
                    if (Scaffold.maybeOf(context)?.hasDrawer ?? false)
                      IconButton(
                        tooltip: 'Menü',
                        onPressed: () => Scaffold.of(context).openDrawer(),
                        icon: const Icon(Icons.menu_rounded),
                      ),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gelenler',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Size gönderilen dosyalar, en yenisi üstte',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AgendaColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('inbox-folder'),
                      onPressed: () => unawaited(_folder()),
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: const Text('Klasörü aç'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: SwitchListTile(
                      key: const ValueKey('inbox-searchable'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: const Text(
                        'Aramada göster',
                        style: TextStyle(fontSize: 13.5),
                      ),
                      subtitle: const Text(
                        'Kapalıyken gelen belgeler genel aramaya girmez; '
                        'yalnız burada görünür.',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _inbox.searchable,
                      onChanged: (on) => unawaited(_searchable(on)),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      'Henüz gelen dosya yok. Telefonunuzdan ya da büronuzdan '
                      'gönderilen dosyalar burada görünür.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AgendaColors.muted),
                    ),
                  ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final i in items) ...[
                          if (_day(i.at) != last) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                              child: Text(
                                last = _day(i.at),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .7,
                                  color: AgendaColors.muted,
                                ),
                              ),
                            ),
                          ],
                          _row(context, i),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(BuildContext context, InboxItem i) {
    final scheme = Theme.of(context).colorScheme;
    final fresh = _inbox.isNew(i);
    final name = i.names.length == 1
        ? i.names.single
        : '${i.names.first} ve ${i.names.length - 1} dosya daha';
    final from = [
      i.from,
      if (i.device.isNotEmpty && i.device != i.from) i.device,
    ].where((s) => s.isNotEmpty).join(' · ');
    final detail = [
      'Gönderen: ${from.isEmpty ? 'bilinmiyor' : from}',
      clockText(i.at),
      if (i.size > 0) sizeText(i.size),
      if (i.withMessage) 'mesajla geldi',
      if (i.task case final t?) 'görevle geldi: $t',
    ].join(' · ');
    return Card(
      key: ValueKey('inbox-${i.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _open(i),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fresh ? scheme.primary : Colors.transparent,
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.description_outlined, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: fresh ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AgendaColors.muted,
                      ),
                    ),
                    if (i.note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '“${i.note}”',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              fresh
                  ? FilledButton(
                      onPressed: () => _open(i),
                      child: const Text('Aç'),
                    )
                  : OutlinedButton(
                      onPressed: () => _open(i),
                      child: const Text('Aç'),
                    ),
              PopupMenuButton<String>(
                key: ValueKey('inbox-menu-${i.id}'),
                tooltip: 'Diğer',
                onSelected: (v) => switch (v) {
                  'okundu' => unawaited(_inbox.markRead(i)),
                  'okunmadi' => unawaited(_inbox.markUnread(i)),
                  'klasor' when i.paths.isNotEmpty => unawaited(
                    FileActions.invoke('showFolder', i.paths.first),
                  ),
                  'sil' => unawaited(_remove(i)),
                  _ => null,
                },
                itemBuilder: (_) => [
                  fresh
                      ? const PopupMenuItem(
                          value: 'okundu',
                          child: Text('Okundu yap'),
                        )
                      : const PopupMenuItem(
                          value: 'okunmadi',
                          child: Text('Okunmadı yap'),
                        ),
                  const PopupMenuItem(
                    value: 'klasor',
                    child: Text('Klasörde göster'),
                  ),
                  const PopupMenuItem(value: 'sil', child: Text('Sil')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
