import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/office/office_network.dart';
import '../../services/office/office_pairing.dart';
import '../agenda/agenda_page.dart' show AgendaColors;

/// What two of the person's devices keep alike once they know each other,
/// and what the relay carries when they are on different networks: told
/// before a code is made or typed.
class RemoteSyncNote extends StatelessWidget {
  const RemoteSyncNote({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      fontSize: 12.5,
      height: 1.45,
      color: AgendaColors.muted,
    );
    Widget line(String text) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: muted),
          Expanded(child: Text(text, style: muted)),
        ],
      ),
    );
    return Column(
      key: const ValueKey('remote-sync-note'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Eşleşince cihazlarınız arasında eşitlenenler',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        line('Ajanda, duruşmalar, görevler ve müvekkiller.'),
        line('Dosya bilgileri ve UYAP’tan okunanlar, UYAP oturumu.'),
        line('Profil, kalıplar ve ayarlar.'),
        line('Senkron’da açtıysanız yapay zekâ sohbetleri ve API anahtarları.'),
        line(
          'Diğer cihazlarınızın listesi: bu cihaz telefonunuzu ve tabletinizi '
          'de kendiliğinden tanır.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Belgeler ve boyut',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        line(
          'Belgeler kendiliğinden gitmez. Bir belgeyi “Gönder” ile '
          'gönderirsiniz.',
        ),
        line(
          'Cihazlarınız farklı ağlardayken her şey Folio’nun aktarma '
          'sunucusundan şifreli geçer. Bir gönderim en çok 10 MB olabilir. '
          'Kişi başına günde 50 MB, ayda 500 MB geçer.',
        ),
        line(
          'Sunucu hiçbir şeyi saklamaz ve içeriği göremez. Veri diğer cihaza '
          'ulaşınca sunucuda hiçbir şey kalmaz.',
        ),
        line('Aynı ağdayken sunucu kullanılmaz ve sınır yoktur.'),
      ],
    );
  }
}

/// "Uzaktaki cihazımı ekle": a code for one of the person's devices on
/// another network to type, and word when it has.
class RemoteInviteDialog extends StatefulWidget {
  const RemoteInviteDialog({super.key, required this.network});
  final OfficeNetwork network;

  static Future<void> show(BuildContext context, OfficeNetwork network) =>
      showDialog<void>(
        context: context,
        builder: (_) => RemoteInviteDialog(network: network),
      );

  @override
  State<RemoteInviteDialog> createState() => _RemoteInviteDialogState();
}

class _RemoteInviteDialogState extends State<RemoteInviteDialog> {
  OfficePairing? _pairing;

  OfficeNetwork get _net => widget.network;

  @override
  void initState() {
    super.initState();
    _net.remoteInvite.addListener(_moved);
    _net.remotePairing.addListener(_came);
    final held = _net.remoteInvite.value;
    if (held == null || !held.valid) unawaited(_net.inviteRemote());
  }

  void _came() {
    final p = _net.remotePairing.value;
    if (p == null || p == _pairing) return;
    _pairing?.removeListener(_moved);
    setState(() => _pairing = p..addListener(_moved));
  }

  void _moved() => mounted ? setState(() {}) : null;

  @override
  void dispose() {
    _net.remoteInvite.removeListener(_moved);
    _net.remotePairing.removeListener(_came);
    _pairing?.removeListener(_moved);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _pairing, invite = _net.remoteInvite.value;
    // Known, and the person's key went over: only then theirs.
    final done = p?.state == PairingState.done && p?.keyed == true;
    final failed =
        p?.state == PairingState.failed ||
        (p?.state == PairingState.done && p?.keyed == false);
    final Widget top;
    if (done) {
      top = _Said(
        ok: true,
        text:
            'Cihazınız tanındı: ${p!.other?.device ?? ''}. Eşitleme '
            'kendiliğinden başlar.',
      );
    } else if (failed) {
      top = _Said(
        ok: false,
        text:
            p!.reason ??
            'Eşleşme tamamlanamadı. Yeni bir kodla yeniden deneyin.',
      );
    } else if (p != null) {
      top = const _Said(text: 'Cihazınız bağlandı, tanınıyor…');
    } else if (invite == null) {
      top = const _Said(text: 'Kod hazırlanıyor…');
    } else {
      final until = invite.until;
      top = Column(
        children: [
          SelectableText(
            invite.code!,
            key: const ValueKey('remote-code'),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              fontFamily: 'monospace',
            ),
          ),
          TextButton.icon(
            onPressed: () =>
                unawaited(Clipboard.setData(ClipboardData(text: invite.code!))),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Kopyala'),
          ),
          Text(
            'Diğer cihazınızda Folio’yu açın, Senkron’da “Kod gir”e basın ve '
            'bu kodu yazın. Kod yalnız bir cihaz için, '
            '${until.day}.${until.month} ${until.hour.toString().padLeft(2, '0')}:'
            '${until.minute.toString().padLeft(2, '0')}’e kadar geçerlidir. '
            'O sırada bu cihazda Folio açık olmalı. Kodu kimseyle '
            'paylaşmayın: kodu yazan cihaz bütün verilerinize erişir.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Uzaktaki cihazımı ekle'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [top, const SizedBox(height: 16), const RemoteSyncNote()],
          ),
        ),
      ),
      actions: [
        if (!done && invite != null)
          TextButton(
            key: const ValueKey('remote-code-cancel'),
            onPressed: () {
              _net.cancelRemoteInvite();
              Navigator.pop(context);
            },
            child: const Text('Kodu iptal et'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(done ? 'Tamam' : 'Kapat'),
        ),
      ],
    );
  }
}

/// "Kod gir": the code another of the person's devices shows, typed here.
class RemoteCodeDialog extends StatefulWidget {
  const RemoteCodeDialog({super.key, required this.network});
  final OfficeNetwork network;

  static Future<void> show(BuildContext context, OfficeNetwork network) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RemoteCodeDialog(network: network),
      );

  @override
  State<RemoteCodeDialog> createState() => _RemoteCodeDialogState();
}

class _RemoteCodeDialogState extends State<RemoteCodeDialog> {
  final _code = TextEditingController();
  OfficePairing? _pairing;
  bool _busy = false;
  String? _wrong;

  @override
  void dispose() {
    _pairing?.removeListener(_moved);
    _code.dispose();
    super.dispose();
  }

  void _moved() => mounted ? setState(() {}) : null;

  Future<void> _go() async {
    if (QrInvite.normalCode(_code.text) == null) {
      setState(() => _wrong = 'Kod 12 harf ve rakamdan oluşur.');
      return;
    }
    setState(() {
      _busy = true;
      _wrong = null;
    });
    final p = await widget.network.pairByCode(_code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (p == null) {
        _wrong =
            'Bu kodu bekleyen bir cihaz bulunamadı. Kodu doğru yazdığınızdan '
            've diğer cihazda Folio’nun açık olduğundan emin olun.';
      } else {
        _pairing = p..addListener(_moved);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _pairing;
    // Known, and the person's key went over: only then theirs.
    final done = p?.state == PairingState.done && p?.keyed == true;
    final failed =
        p?.state == PairingState.failed ||
        (p?.state == PairingState.done && p?.keyed == false);
    final Widget top;
    if (done) {
      top = _Said(
        ok: true,
        text:
            'Cihazınız tanındı: ${p!.other?.device ?? ''}. Eşitleme '
            'kendiliğinden başlar.',
      );
    } else if (failed) {
      top = _Said(
        ok: false,
        text:
            p!.reason ??
            'Eşleşme tamamlanamadı. Yeni bir kodla yeniden deneyin.',
      );
    } else if (p != null || _busy) {
      top = const _Said(text: 'Cihazınıza bağlanılıyor…');
    } else {
      top = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Diğer cihazınızda Senkron’da “Uzaktaki cihazımı ekle”ye basınca '
            'çıkan kodu yazın.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('remote-code-field'),
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: '7K3M-XQ2P-HT4D',
              errorText: _wrong,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => unawaited(_go()),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Kod gir'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [top, const SizedBox(height: 16), const RemoteSyncNote()],
          ),
        ),
      ),
      actions: [
        if (p == null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
        if (p == null)
          FilledButton(
            key: const ValueKey('remote-code-go'),
            onPressed: _busy ? null : () => unawaited(_go()),
            child: const Text('Eşleş'),
          )
        else
          FilledButton(
            onPressed: p.finished ? () => Navigator.pop(context) : null,
            child: Text(done ? 'Tamam' : 'Kapat'),
          ),
      ],
    );
  }
}

class _Said extends StatelessWidget {
  const _Said({required this.text, this.ok});
  final String text;
  final bool? ok;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (ok == null)
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      else
        Icon(
          ok! ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          color: ok! ? Colors.green : Colors.redAccent,
        ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.4)),
      ),
    ],
  );
}
