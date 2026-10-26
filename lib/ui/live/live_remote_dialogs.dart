import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/editor/lawyer_profile.dart';
import '../../services/live/live_remote.dart';
import '../../services/live/live_share.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../widgets/notice.dart';

/// The digits an invitation shows on both screens, and what they are for.
class _Digits extends StatelessWidget {
  const _Digits(this.digits, {required this.note});

  final String digits, note;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        'DOĞRULAMA',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: .8,
          color: AgendaColors.muted,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        digits,
        key: const ValueKey('remote-digits'),
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 3,
          fontFamily: 'monospace',
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        note,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: AgendaColors.muted),
      ),
    ],
  );
}

/// The sharer's side of an invitation by a code (approved mockup, 26 Ekim
/// 2026): the code to send, then the one who came, asked about.
class RemoteInvitePane extends StatefulWidget {
  const RemoteInvitePane({super.key, required this.host});

  final LiveShareHost host;

  @override
  State<RemoteInvitePane> createState() => _RemoteInvitePaneState();
}

class _RemoteInvitePaneState extends State<RemoteInvitePane> {
  LiveShareHost get _host => widget.host;
  String _me = '';

  @override
  void initState() {
    super.initState();
    if (_host.remoteInvite.value == null) _host.inviteRemote();
    unawaited(() async {
      try {
        final p = await LawyerProfile.load();
        _me = p.lawyer?.titled ?? '';
      } catch (_) {}
    }());
  }

  String _who(RemoteInvite invite) => [
    if (invite.name.isNotEmpty) invite.name else 'Misafir',
    if (invite.office.isNotEmpty) '(${invite.office})',
  ].join(' ');

  Future<void> _let(RemoteInvite invite, LiveRight right) async {
    final id = invite.deviceId;
    final channel = invite.accept();
    if (id == null || channel == null) {
      if (mounted) {
        showNotice(context, 'Gelen kişi ayrıldı.', kind: NoticeKind.error);
      }
      return;
    }
    await _host.showRemote(id, _who(invite), channel, right, from: _me);
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(
      ClipboardData(text: RemoteCode.message(code, _host.title)),
    );
    if (mounted) {
      showNotice(context, 'Davet kopyalandı', kind: NoticeKind.success);
    }
  }

  Future<void> _send(String code, {required bool mail}) async {
    final text = RemoteCode.message(code, _host.title);
    final uri = mail
        ? Uri.parse(
            'mailto:?subject=${Uri.encodeComponent('Canlı belge daveti')}'
            '&body=${Uri.encodeComponent(text)}',
          )
        : Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    await _copy(code);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<RemoteInvite?>(
    valueListenable: _host.remoteInvite,
    builder: (context, invite, _) {
      if (invite == null) return const SizedBox();
      return ListenableBuilder(
        listenable: invite,
        builder: (context, _) => _body(invite),
      );
    },
  );

  Widget _body(RemoteInvite invite) {
    final scheme = Theme.of(context).colorScheme;
    final again = Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const ValueKey('remote-new-code'),
        onPressed: _host.closed ? null : () => _host.inviteRemote(),
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: Text(
          invite.state == RemoteInviteState.accepted
              ? 'Bir kişi daha davet et'
              : 'Yeni kod oluştur',
        ),
      ),
    );
    switch (invite.state) {
      case RemoteInviteState.opening:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Davet kodu hazırlanıyor…'),
            ],
          ),
        );
      case RemoteInviteState.waiting:
        final until = TimeOfDay.fromDateTime(invite.expires).format(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Kodu diğer büroya gönderin. Katılmak isteyen olunca size '
              'sorulur.',
              style: TextStyle(color: AgendaColors.muted),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  SelectableText(
                    RemoteCode.shown(invite.code),
                    key: const ValueKey('remote-code'),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('remote-copy'),
                        onPressed: () => unawaited(_copy(invite.code)),
                        icon: const Icon(Icons.content_copy_rounded, size: 17),
                        label: const Text('Daveti kopyala'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('remote-whatsapp'),
                        onPressed: () =>
                            unawaited(_send(invite.code, mail: false)),
                        icon: const Icon(Icons.chat_outlined, size: 17),
                        label: const Text('WhatsApp'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('remote-mail'),
                        onPressed: () =>
                            unawaited(_send(invite.code, mail: true)),
                        icon: const Icon(Icons.mail_outline_rounded, size: 17),
                        label: const Text('E-posta'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$until’e kadar geçerli, bir kişi içindir. Belge şifreli '
                    'gider; aradaki sunucu içeriği göremez.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AgendaColors.muted),
                  ),
                ],
              ),
            ),
          ],
        );
      case RemoteInviteState.arrived:
        return Container(
          key: const ValueKey('remote-request'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .07),
            border: Border.all(color: scheme.primary, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _who(invite),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'davet koduyla katılmak istiyor',
                style: TextStyle(color: AgendaColors.muted),
              ),
              const SizedBox(height: 10),
              _Digits(
                invite.digits,
                note:
                    'Aynı sayı onun ekranında da görünüyorsa doğru '
                    'kişidir.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('remote-decline'),
                    onPressed: () => unawaited(invite.decline()),
                    child: const Text('Reddet'),
                  ),
                  OutlinedButton(
                    key: const ValueKey('remote-let-view'),
                    onPressed: () => unawaited(_let(invite, LiveRight.view)),
                    child: const Text('Yalnız görsün'),
                  ),
                  if (_host.apply != null)
                    FilledButton(
                      key: const ValueKey('remote-let-edit'),
                      onPressed: () => unawaited(_let(invite, LiveRight.edit)),
                      child: const Text('Sırayla düzenlesin'),
                    ),
                ],
              ),
            ],
          ),
        );
      case RemoteInviteState.accepted:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_who(invite)} katıldı.',
              style: TextStyle(color: AgendaColors.muted),
            ),
            const SizedBox(height: 8),
            again,
          ],
        );
      case RemoteInviteState.declined ||
          RemoteInviteState.expired ||
          RemoteInviteState.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              switch (invite.state) {
                RemoteInviteState.declined => 'Davet geri alındı.',
                RemoteInviteState.expired => 'Davet kodunun süresi doldu.',
                _ => invite.error ?? 'Davet kurulamadı.',
              },
              key: const ValueKey('remote-ended'),
              style: TextStyle(
                color: invite.state == RemoteInviteState.failed
                    ? scheme.error
                    : AgendaColors.muted,
              ),
            ),
            const SizedBox(height: 8),
            again,
          ],
        );
    }
  }
}

/// Joining a document shared live from another office, by the code its
/// sharer sent (approved mockup, 26 Ekim 2026). The session, once the
/// sharer lets this side in.
class RemoteJoinDialog extends StatefulWidget {
  const RemoteJoinDialog({super.key, this.code});

  /// A code already in hand, as a pasted link carries it.
  final String? code;

  static Future<LiveSession?> show(BuildContext context, {String? code}) =>
      showDialog<LiveSession>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RemoteJoinDialog(code: code),
      );

  @override
  State<RemoteJoinDialog> createState() => _RemoteJoinDialogState();
}

class _RemoteJoinDialogState extends State<RemoteJoinDialog> {
  late final _code = TextEditingController(text: widget.code ?? '');
  final _name = TextEditingController();
  String _office = '';
  RemoteJoin? _join;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
    unawaited(() async {
      try {
        final p = await LawyerProfile.load();
        if (!mounted) return;
        if (_name.text.isEmpty) _name.text = p.lawyer?.titled ?? '';
        _office = p.officeName.trim();
      } catch (_) {}
    }());
  }

  @override
  void dispose() {
    final join = _join;
    if (join != null) {
      join.removeListener(_changed);
      unawaited(join.cancel());
    }
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  void _start() {
    final code = RemoteCode.read(_code.text);
    if (code == null) return;
    final join = RemoteJoin.start(
      code,
      name: _name.text.trim(),
      office: _office,
    )..addListener(_changed);
    setState(() => _join = join);
  }

  void _changed() {
    final join = _join;
    if (join == null || !mounted) return;
    if (join.state == RemoteJoinState.joined) {
      join.removeListener(_changed);
      _join = null;
      Navigator.of(context).pop(join.session);
      return;
    }
    setState(() {});
  }

  void _again() {
    _join?.removeListener(_changed);
    setState(() => _join = null);
  }

  @override
  Widget build(BuildContext context) {
    final join = _join;
    final ready = RemoteCode.read(_code.text) != null;
    final scheme = Theme.of(context).colorScheme;
    final Widget body;
    final actions = <Widget>[
      TextButton(
        key: const ValueKey('remote-join-cancel'),
        onPressed: () => Navigator.of(context).pop(),
        child: Text(join == null ? 'Vazgeç' : 'Kapat'),
      ),
    ];
    if (join == null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Size gönderilen kodu yazın ya da davet bağlantısını '
            'yapıştırın.',
            style: TextStyle(color: AgendaColors.muted),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('remote-join-code'),
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              fontFamily: 'monospace',
            ),
            decoration: const InputDecoration(
              hintText: 'K7Q-4MP-2XD',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _start(),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('remote-join-name'),
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Adınız (paylaşana böyle görünür)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      );
      actions.add(
        FilledButton(
          key: const ValueKey('remote-join-go'),
          onPressed: ready ? _start : null,
          child: const Text('Katıl'),
        ),
      );
    } else {
      body = switch (join.state) {
        RemoteJoinState.connecting || RemoteJoinState.joined => const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Bağlanılıyor…'),
            ],
          ),
        ),
        RemoteJoinState.asking => Column(
          key: const ValueKey('remote-join-asking'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top_rounded, size: 30, color: scheme.primary),
            const SizedBox(height: 6),
            const Text(
              'Onay bekleniyor',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              'Paylaşan onaylayınca belge açılır.',
              style: TextStyle(color: AgendaColors.muted),
            ),
            const SizedBox(height: 14),
            _Digits(
              join.digits,
              note: 'Paylaşanın ekranında da bu sayı görünür.',
            ),
          ],
        ),
        RemoteJoinState.declined || RemoteJoinState.failed => Text(
          join.state == RemoteJoinState.declined
              ? 'Paylaşan katılmanızı kabul etmedi.'
              : join.error ?? 'Katılınamadı.',
          key: const ValueKey('remote-join-error'),
          style: TextStyle(color: scheme.error),
        ),
      };
      if (join.state == RemoteJoinState.failed ||
          join.state == RemoteJoinState.declined) {
        actions.add(
          FilledButton(
            key: const ValueKey('remote-join-again'),
            onPressed: _again,
            child: const Text('Yeniden dene'),
          ),
        );
      }
    }
    return AlertDialog(
      title: const Text('Canlı belgeye katıl'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: body)),
      actions: actions,
    );
  }
}
