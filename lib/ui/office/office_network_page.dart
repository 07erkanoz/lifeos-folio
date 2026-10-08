import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/office/office_ledger.dart';
import '../../services/office/office_network.dart';
import '../../services/office/office_transfer.dart';
import '../../services/platform/file_actions.dart';
import '../../services/office/office_peer.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../portfolio/portfolio_rows.dart' show clockText, dayText;
import 'office_offer_dialog.dart' show sizeText;
import 'office_pairing_dialog.dart';
import 'qr_pairing.dart';
import 'send_to_office.dart';
import '../widgets/drop_zone.dart';

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
    return DropZoneOverlay(
      title: 'Göndermek için bırakın',
      subtitle: 'Kime gönderileceğini seçeceksiniz',
      onFilesDropped: _dropped,
      child: ColoredBox(
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
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              _office(context),
                              const SizedBox(height: 12),
                              _people(context),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              _transfers(context),
                              _thisDevice(context),
                            ],
                          ),
                        ),
                      ],
                    )
                  else ...[
                    _office(context),
                    const SizedBox(height: 12),
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
      ),
    );
  }

  /// Files dropped on the page: whom they go to is asked.
  void _dropped(List<String> paths) {
    final (:files, :more) = droppedFiles(paths);
    if (files.isEmpty) return;
    if (more) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'Bıraktıklarınızda ${files.length} dosyadan fazlası var; ilk '
            '${files.length} dosya gönderilecek.',
          ),
        ),
      );
    }
    if (_net.sendTargets.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Gönderebileceğiniz kimse yok. Önce bir cihazı tanıyın ya da '
            'büroyu kurun.',
          ),
        ),
      );
      return;
    }
    unawaited(showSendToOffice(context, files, network: _net));
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
        if (_net.joined)
          _phone
              ? FilledButton.tonalIcon(
                  key: const ValueKey('office-qr-scan'),
                  onPressed: () => unawaited(scanAndPair(context, _net)),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: const Text('QR okut'),
                )
              : FilledButton.tonalIcon(
                  key: const ValueKey('office-qr-invite'),
                  onPressed: () =>
                      unawaited(QrInviteDialog.show(context, _net)),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: const Text('Telefonumu ekle'),
                ),
      ],
    );
  }

  /// A phone reads a QR; a computer shows one.
  static bool get _phone =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

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
          // Alone only when no other device is listed, the user's own too.
          if (people.fold<int>(0, (n, p) => n + p.devices.length) < 2)
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
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final self0 = d.deviceId == _net.self?.deviceId;
    final mayAdmit =
        !self0 &&
        _net.isKnown(d.deviceId) &&
        _net.ledger.exists &&
        _net.ledger.member(d.deviceId) == null &&
        _net.ledger.isManager(_net.self?.deviceId ?? '');
    final maySend = !self0 && _net.isTrusted(d.deviceId) && d.online;
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
          // On a phone, what can be done with it in one menu: the
          // name keeps the row.
          if (narrow && (mayAdmit || maySend))
            PopupMenuButton<Object>(
              key: ValueKey('office-device-menu-${d.deviceId}'),
              tooltip: 'İşlemler',
              onSelected: (v) => v is OfficeRole
                  ? unawaited(_say(_net.admit(d.deviceId, v)))
                  : unawaited(_send(d)),
              itemBuilder: (_) => [
                if (maySend)
                  const PopupMenuItem(value: 'gonder', child: Text('Gönder')),
                if (mayAdmit)
                  for (final r in OfficeRole.values)
                    PopupMenuItem(
                      value: r,
                      child: Text(
                        'Büroya ${r.label.toLowerCase()} olarak ekle',
                      ),
                    ),
              ],
            ),
          if (!narrow && mayAdmit)
            PopupMenuButton<OfficeRole>(
              key: ValueKey('office-admit-${d.deviceId}'),
              tooltip: 'Büroya ekle',
              onSelected: (r) => unawaited(_say(_net.admit(d.deviceId, r))),
              itemBuilder: (_) => [
                for (final r in OfficeRole.values)
                  PopupMenuItem(
                    value: r,
                    child: Text('${r.label} olarak ekle'),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  'Büroya ekle ▾',
                  style: TextStyle(fontSize: 12.5, color: AgendaColors.hearing),
                ),
              ),
            ),
          if (!narrow && maySend)
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

  final _officeName = TextEditingController();

  Future<void> _say(Future<String?> action) async {
    final error = await action;
    if (error != null && mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// The office: founding it, or its members and their roles.
  Widget _office(BuildContext context) {
    final l = _net.ledger;
    final me = _net.self?.deviceId;
    final manager = me != null && l.isManager(me);
    if (!l.exists) {
      return _card(
        context,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Büro',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Büro kurduğunuzda büronun ilk yöneticisi siz olursunuz; '
                'tanıdığınız cihazları rolleriyle büroya alırsınız. Başka bir '
                'büroya katılacaksanız o büronun yöneticisinin sizi tanıyıp '
                'büroya eklemesi yeterlidir.',
                style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('office-name'),
                      controller: _officeName,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Büronun adı, ör. Kaya Hukuk Bürosu',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('office-found'),
                    onPressed: () =>
                        unawaited(_say(_net.foundOffice(_officeName.text))),
                    child: const Text('Büro kur'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    // People, each with how many devices they are on.
    final members = l.people;
    final mine = _net.me;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 9),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: l.officeName),
                  TextSpan(
                    text: '  ${members.length} üye',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AgendaColors.muted,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          for (final m in members) ...[
            const Divider(height: 1),
            Padding(
              key: ValueKey('office-member-${m.deviceId}'),
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${m.name.isEmpty ? 'Adsız' : m.name}'
                          '${m.deviceId == mine ? '  (siz)' : ''}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${m.device} · ${m.platform.label}'
                          '${l.devicesOf(m.person).length > 1 ? ' · ${l.devicesOf(m.person).length} cihaz' : ''}'
                          '${m.founder ? ' · kurucu' : ''}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AgendaColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: m.role == OfficeRole.manager
                          ? AgendaColors.hearingFill
                          : const Color(0xFFEEF0F3),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      m.role.label.replaceAll('i', 'İ').toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: m.role == OfficeRole.manager
                            ? AgendaColors.hearing
                            : const Color(0xFF5E6677),
                      ),
                    ),
                  ),
                  if (manager)
                    PopupMenuButton<Object>(
                      key: ValueKey('office-role-${m.deviceId}'),
                      tooltip: 'Rol',
                      onSelected: (v) => unawaited(
                        _say(
                          v is OfficeRole
                              ? _net.setRole(m.deviceId, v)
                              : v == 'ucret'
                              ? _net.setMoney(
                                  m.deviceId,
                                  !l.seesMoney(m.deviceId),
                                )
                              : _net.removeMember(m.deviceId),
                        ),
                      ),
                      itemBuilder: (_) => [
                        for (final r in OfficeRole.values)
                          CheckedPopupMenuItem(
                            value: r,
                            checked: m.role == r,
                            child: Text(r.label),
                          ),
                        if (m.role != OfficeRole.manager) ...[
                          const PopupMenuDivider(),
                          CheckedPopupMenuItem(
                            value: 'ucret',
                            checked: l.seesMoney(m.deviceId),
                            child: const Text('Ücret ve hesapları görebilir'),
                          ),
                        ],
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'cikar',
                          child: Text('Bürodan çıkar'),
                        ),
                      ],
                    )
                  else
                    const SizedBox(width: 12),
                ],
              ),
            ),
          ],
          if (l.member(_net.self?.deviceId ?? '')?.founder ?? false) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('office-recovery-make'),
                  onPressed: () => unawaited(_makeRecovery()),
                  icon: const Icon(Icons.key_rounded, size: 17),
                  label: Text(
                    l.hasRecovery
                        ? 'Yeni kurtarma kodu oluştur'
                        : 'Kurtarma kodu oluştur',
                  ),
                ),
              ),
            ),
          ] else if (l.member(_net.self?.deviceId ?? '') == null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('office-recovery-use'),
                  onPressed: () => unawaited(_useRecovery()),
                  icon: const Icon(Icons.key_rounded, size: 17),
                  label: const Text('Kurucuyum, kurtarma kodum var'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _makeRecovery() async {
    final again = _net.ledger.hasRecovery;
    if (again) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Yeni kurtarma kodu'),
          content: const Text(
            'Yeni kod oluşturulunca eski kod geçersiz olur. Devam edilsin mi?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yeni kod oluştur'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    final code = await _net.makeRecovery();
    if (!mounted || code == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Kurtarma kodunuz'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bu kodu kâğıda yazıp güvenli bir yerde saklayın. Bütün '
                'cihazlarınızı kaybederseniz, yeni cihazda bir meslektaşınızın '
                'cihazıyla tanışıp bu kodu girerek büronun kurucusu olarak '
                'devam edersiniz. Kod bir daha gösterilmez.',
              ),
              const SizedBox(height: 14),
              SelectableText(
                code,
                key: const ValueKey('office-recovery-code'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Yazdım'),
          ),
        ],
      ),
    );
  }

  Future<void> _useRecovery() async {
    final field = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kurtarma kodu'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: field,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('Kurucu olarak devam et'),
          ),
        ],
      ),
    );
    field.dispose();
    if (code == null || code.trim().isEmpty) return;
    await _say(_net.recoverFounder(code));
  }

  Future<void> _send(OfficePeer d) async {
    final picked = await FilePicker.pickFiles(allowMultiple: true);
    final paths = [
      for (final f in picked?.files ?? const <PlatformFile>[])
        if (f.path != null) f.path!,
    ];
    if (paths.isEmpty || !mounted) return;
    final note = await askSendNote(context, paths.length);
    if (note == null) return;
    final t = await _net.send(d, paths, note: note);
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
              Text(
                _phone
                    ? 'Henüz tanınan bir cihaz yok. Bilgisayarınızda Büro ağı’nda '
                          '“Telefonumu ekle”ye basın, çıkan QR’ı burada “QR '
                          'okut” ile okutun.'
                    : 'Henüz tanınan bir cihaz yok. Telefonunuzu “Telefonumu '
                          'ekle” ile QR okutarak ekleyin. Başka bir bilgisayarı '
                          'tanımak için listede yanındaki “Tanı”ya basın; iki '
                          'ekranda aynı kod çıkınca onaylayın.',
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
                      onPressed: () => unawaited(_net.forget(k.deviceId)),
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
                  ],
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
