import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/office/office_network.dart';
import '../../services/office/office_transfer.dart';
import '../../services/platform/file_actions.dart';
import '../../services/office/office_peer.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../portfolio/portfolio_rows.dart' show clockText, dayText;
import 'office_offer_dialog.dart' show sizeText;
import 'office_pairing_dialog.dart';

/// Büro ağı (docs/buro.md, docs/design/buro-paylasim-taslak.png): the
/// Folios on the office's network under their people. Sending, knowing a
/// new device by its code and the user's own devices come in the next
/// steps; this is the list they will start from.
class OfficeNetworkPage extends StatefulWidget {
  const OfficeNetworkPage({super.key, this.network, this.now});

  final OfficeNetwork? network;
  final DateTime Function()? now;

  @override
  State<OfficeNetworkPage> createState() => _OfficeNetworkPageState();
}

class _OfficeNetworkPageState extends State<OfficeNetworkPage> {
  OfficeNetwork get _net => widget.network ?? OfficeNetwork.instance;

  @override
  void initState() {
    super.initState();
    // A changed profile name is announced at once.
    unawaited(_net.rename());
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: dark ? scheme.surface : AgendaColors.page,
      child: ListenableBuilder(
        listenable: _net,
        builder: (context, _) => LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 900;
            final pad = wide ? 24.0 : 12.0;
            return ListView(
              key: const ValueKey('office-network'),
              padding: EdgeInsets.fromLTRB(pad, wide ? 18 : 10, pad, 24),
              children: [
                _head(context),
                const SizedBox(height: 14),
                if (!_net.joined)
                  _join(context)
                else if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _people(context)),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: Column(
                          children: [_transfers(context), _thisDevice(context)],
                        ),
                      ),
                    ],
                  )
                else ...[
                  _people(context),
                  const SizedBox(height: 12),
                  _transfers(context),
                  _thisDevice(context),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _head(BuildContext context) {
    final people = _net.people;
    final devices = people.fold<int>(0, (n, p) => n + p.devices.length);
    final self = _net.self;
    return Row(
      children: [
        if (Scaffold.maybeOf(context)?.hasDrawer ?? false)
          IconButton(
            tooltip: 'Menü',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu_rounded),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Büro ağı',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                !_net.joined || self == null
                    ? 'Aynı ağdaki Folio’lar birbirini bulur'
                    : 'Aynı ağda ${people.length} kişi, $devices cihaz · bu '
                          'cihaz: ${self.device} (${self.platform.label})',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AgendaColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, {required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  /// Before joining: what joining does and does not do.
  Widget _join(BuildContext context) => _card(
    context,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lan_outlined, size: 30, color: AgendaColors.hearing),
          const SizedBox(height: 10),
          const Text(
            'Büro ağına katılın',
            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Katıldığınızda Folio bu ağdaki diğer Folio’lara avukat '
            'profilinizdeki adla ve bu cihazın adıyla görünür, siz de '
            'onları görürsünüz. Duyuruda hiçbir dosya, evrak ya da müvekkil '
            'bilgisi yer almaz; hiçbir şey internete gitmez.',
            style: TextStyle(fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 6),
          const Text(
            'Kafe ya da otel gibi ortak ağlarda katılmayın. Katıldığınız '
            'ağda Folio her açılışta yeniden görünür; istediğiniz zaman '
            'ayrılabilirsiniz.',
            style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
          ),
          if (_net.error != null) ...[
            const SizedBox(height: 10),
            Text(
              'Ağa katılınamadı: ${_net.error}',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('office-join'),
            onPressed: _net.starting ? null : () => unawaited(_net.join()),
            icon: _net.starting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering_rounded, size: 18),
            label: const Text('Bu ağa katıl'),
          ),
        ],
      ),
    ),
  );

  Widget _people(BuildContext context) {
    final people = _net.people;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 13, 16, 11),
            child: Text(
              'Kişiler ve cihazlar',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ),
          const Divider(height: 1),
          for (final (i, person) in people.indexed) ...[
            if (i > 0) const Divider(height: 1),
            _person(context, person),
          ],
          if (people.length < 2)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Text(
                'Bu ağda henüz başka bir Folio görünmüyor. Diğer cihazda '
                'Folio’nun açık olduğundan, büro ağına katıldığından ve aynı '
                'ağa bağlı olduğundan emin olun.',
                style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _person(BuildContext context, OfficePerson person) {
    final name = person.name.isEmpty ? 'Adı yazılmamış kullanıcı' : person.name;
    final online = person.devices.where((d) => d.online).length;
    final initials = name
        .replaceFirst(RegExp(r'^(Stj\. )?Av\. '), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.substring(0, 1).toUpperCase())
        .join();
    const tones = [
      Color(0xFF2B5EA8),
      Color(0xFF157A52),
      Color(0xFF0E7C86),
      Color(0xFF97600D),
      Color(0xFF4B5465),
    ];
    final tone = person.self
        ? tones[0]
        : tones[1 + name.codeUnits.fold<int>(0, (s, c) => s + c) % 4];
    return Padding(
      key: ValueKey('office-person-${person.devices.first.userId}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: tone,
                child: Text(
                  initials.isEmpty ? '?' : initials,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: name),
                          if (person.self)
                            const TextSpan(
                              text: '  (siz)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: AgendaColors.muted,
                              ),
                            ),
                        ],
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${person.devices.length} cihaz · $online çevrimiçi',
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
          const SizedBox(height: 4),
          for (final d in person.devices) _device(context, d),
        ],
      ),
    );
  }

  Widget _device(BuildContext context, OfficePeer d) {
    final self = d.deviceId == _net.self?.deviceId;
    final now = (widget.now ?? DateTime.now)();
    final seen = d.lastSeen;
    String when(DateTime at) {
      final today = DateTime(now.year, now.month, now.day);
      final day = DateTime(at.year, at.month, at.day);
      if (day == today) return clockText(at);
      if (today.difference(day).inDays == 1) return 'dün ${clockText(at)}';
      return dayText(at);
    }

    return Padding(
      key: ValueKey('office-device-${d.deviceId}'),
      padding: const EdgeInsets.only(left: 44, top: 5),
      child: Row(
        children: [
          Icon(
            d.platform.phone
                ? Icons.smartphone_rounded
                : Icons.computer_rounded,
            size: 17,
            color: const Color(0xFF4B5465),
          ),
          const SizedBox(width: 8),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: d.online ? AgendaColors.ok : const Color(0xFFB8BFCC),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${d.device} · ${d.platform.label}'),
                  if (self)
                    const TextSpan(
                      text: '  bu cihaz',
                      style: TextStyle(fontSize: 11, color: AgendaColors.muted),
                    )
                  else if (!d.online)
                    TextSpan(
                      text: seen == null
                          ? '  kapalı'
                          : '  kapalı · ${when(seen)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AgendaColors.muted,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (!self && _net.isKnown(d.deviceId) && d.online)
            TextButton.icon(
              key: ValueKey('office-send-${d.deviceId}'),
              onPressed: () => unawaited(_send(d)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.send_rounded, size: 15),
              label: const Text('Gönder'),
            ),
          if (!self && _net.isKnown(d.deviceId))
            const Tooltip(
              message: 'Tanınan cihaz',
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.verified_rounded,
                  size: 17,
                  color: AgendaColors.ok,
                ),
              ),
            )
          else if (!self && d.online)
            TextButton(
              key: ValueKey('office-pair-${d.deviceId}'),
              onPressed: () => _pair(d),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Tanı'),
            ),
        ],
      ),
    );
  }

  Future<void> _send(OfficePeer d) async {
    final picked = await FilePicker.pickFiles(allowMultiple: true);
    final paths = [
      for (final f in picked?.files ?? const <PlatformFile>[])
        if (f.path != null) f.path!,
    ];
    if (paths.isEmpty) return;
    final t = await _net.send(d, paths);
    if (t == null && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Cihaz şu anda ağda görünmüyor.')),
      );
    }
  }

  /// Today's transfers: what went and came, how far, and what to do next.
  Widget _transfers(BuildContext context) {
    final list = _net.transfers;
    if (list.isEmpty) return const SizedBox.shrink();
    Widget tag(String text, Color ink, Color fill) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: ink),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _card(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 13, 16, 9),
              child: Text(
                'Aktarımlar',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ),
            for (final t in list.take(12)) ...[
              const Divider(height: 1),
              Padding(
                key: ValueKey('office-transfer-${t.id}'),
                padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        switch (t.state) {
                          TransferState.done =>
                            t.outgoing
                                ? tag(
                                    'GÖNDERİLDİ',
                                    AgendaColors.ok,
                                    const Color(0xFFE3F5EF),
                                  )
                                : tag(
                                    'ALINDI',
                                    AgendaColors.ok,
                                    const Color(0xFFE3F5EF),
                                  ),
                          TransferState.declined => tag(
                            'REDDEDİLDİ',
                            AgendaColors.muted,
                            const Color(0xFFEEF0F3),
                          ),
                          TransferState.failed => tag(
                            'KESİLDİ',
                            AgendaColors.deadline,
                            AgendaColors.deadlineFill,
                          ),
                          _ =>
                            t.outgoing
                                ? tag(
                                    'GİDİYOR',
                                    AgendaColors.taskText,
                                    AgendaColors.taskFill,
                                  )
                                : tag(
                                    'GELEN',
                                    AgendaColors.hearing,
                                    AgendaColors.hearingFill,
                                  ),
                        },
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${t.outgoing ? 'Alıcı' : 'Gönderen'}: '
                            '${t.peer.name.isEmpty ? t.peer.device : t.peer.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          clockText(t.at),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AgendaColors.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        t.files.length == 1
                            ? t.files.single.name
                            : '${t.files.length} dosya',
                        sizeText(t.total),
                        if (t.reason != null) t.reason!,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AgendaColors.muted,
                      ),
                    ),
                    if (t.state == TransferState.sending) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: t.total == 0 ? null : t.moved / t.total,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                    if (!t.outgoing && t.saved.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        children: [
                          TextButton(
                            onPressed: () => unawaited(
                              FileActions.invoke('openDefault', t.saved.first),
                            ),
                            child: const Text('Aç'),
                          ),
                          TextButton(
                            onPressed: () => unawaited(
                              FileActions.invoke('showFolder', t.saved.first),
                            ),
                            child: const Text('Klasörde göster'),
                          ),
                        ],
                      ),
                    if (t.outgoing && t.state == TransferState.failed)
                      TextButton(
                        key: ValueKey('office-retry-${t.id}'),
                        onPressed: () => unawaited(_net.retry(t)),
                        child: const Text('Sürdür'),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _pair(OfficePeer d) {
    final pairing = _net.pair(d);
    if (pairing == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Şu anda başka bir cihaz tanınıyor; bitince deneyin.'),
        ),
      );
      return;
    }
    unawaited(OfficePairingDialog.show(context, pairing));
  }

  /// This device: how it is seen, what comes next, and leaving.
  Widget _thisDevice(BuildContext context) {
    final self = _net.self;
    return _card(
      context,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bu cihaz',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              self == null
                  ? ''
                  : '${self.name.isEmpty ? 'Adı yazılmamış kullanıcı' : self.name}'
                        ' · ${self.device} · ${self.platform.label}',
              style: const TextStyle(fontSize: 13),
            ),
            if (self != null && self.name.isEmpty) ...[
              const SizedBox(height: 6),
              const Text(
                'Diğerleri sizi adınızla görsün diye Ayarlar’daki avukat '
                'profilinize adınızı yazın.',
                style: TextStyle(fontSize: 12.5, color: AgendaColors.taskText),
              ),
            ],
            if (!_net.kept) ...[
              const SizedBox(height: 6),
              const Text(
                'Bu cihazda güvenli anahtar deposu bulunamadı; Folio her '
                'açılışta ağa yeni bir cihaz olarak görünür.',
                style: TextStyle(fontSize: 12.5, color: AgendaColors.taskText),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              'Tanınan cihazlar',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            if (_net.known.isEmpty)
              const Text(
                'Henüz tanınan bir cihaz yok. Listedeki bir cihazın yanındaki '
                '“Tanı”ya basın; iki ekranda aynı kod çıkınca onaylayın.',
                style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
              )
            else
              for (final k in _net.known)
                Row(
                  key: ValueKey('office-known-${k.deviceId}'),
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      size: 15,
                      color: AgendaColors.ok,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${k.name.isEmpty ? 'Adsız' : k.name} · ${k.device}'
                        '${k.code.isEmpty ? '' : ' · kod ${k.code}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('office-forget-${k.deviceId}'),
                      tooltip: 'Tanımayı kaldır',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => unawaited(_net.forget(k.deviceId)),
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
                  ],
                ),
            const SizedBox(height: 10),
            const Text(
              'Sıradaki adımlarda: UYAP dosyasından evrak ve UETS evrakı '
              'göndermek; kendi cihazlarınız arasında Senkron sayfasından '
              'klasör, ajanda ve oturum eşitlemek.',
              style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('office-leave'),
              onPressed: () => unawaited(_net.leave()),
              icon: const Icon(Icons.wifi_tethering_off_rounded, size: 17),
              label: const Text('Ağdan ayrıl'),
            ),
          ],
        ),
      ),
    );
  }
}
