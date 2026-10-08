import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/office/office_network.dart';
import '../../services/office/office_pairing.dart';
import '../agenda/agenda_page.dart' show AgendaColors;

/// "Telefonumu ekle" on a computer: a QR the phone reads, and word when
/// it has. No code to compare; the phone becomes one of this person's
/// devices.
class QrInviteDialog extends StatefulWidget {
  const QrInviteDialog({super.key, required this.network});
  final OfficeNetwork network;

  static Future<void> show(BuildContext context, OfficeNetwork network) =>
      showDialog<void>(
        context: context,
        builder: (_) => QrInviteDialog(network: network),
      );

  @override
  State<QrInviteDialog> createState() => _QrInviteDialogState();
}

class _QrInviteDialogState extends State<QrInviteDialog> {
  QrInvite? _invite;
  bool _loading = true;
  Timer? _expiry;
  OfficePairing? _pairing;

  OfficeNetwork get _net => widget.network;

  @override
  void initState() {
    super.initState();
    _net.qrPairing.addListener(_came);
    unawaited(_renew());
  }

  Future<void> _renew() async {
    setState(() => _loading = true);
    final invite = await _net.inviteByQr();
    if (!mounted) return;
    _expiry?.cancel();
    if (invite != null) {
      _expiry = Timer(
        invite.until.difference(DateTime.now()),
        () => mounted ? setState(() {}) : null,
      );
    }
    setState(() {
      _invite = invite;
      _loading = false;
      _pairing = null;
    });
  }

  void _came() {
    final p = _net.qrPairing.value;
    if (p == null || p == _pairing) return;
    _pairing?.removeListener(_moved);
    setState(() => _pairing = p..addListener(_moved));
  }

  void _moved() => mounted ? setState(() {}) : null;

  @override
  void dispose() {
    _expiry?.cancel();
    _net.qrPairing.removeListener(_came);
    _pairing?.removeListener(_moved);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _pairing, invite = _invite;
    final done = p?.state == PairingState.done;
    final failed = p?.state == PairingState.failed;
    final expired = invite != null && !invite.valid && p == null;
    final Widget body;
    if (done) {
      body = _Result(
        ok: true,
        text:
            'Telefonunuz tanındı: ${p!.other?.device ?? ''}. Artık '
            'birbirinize kodsuz gönderebilirsiniz.',
      );
    } else if (failed) {
      body = _Result(ok: false, text: p!.reason ?? 'Tanıma tamamlanamadı.');
    } else if (p != null) {
      body = const _Busy('Telefon bağlandı, tanınıyor…');
    } else if (_loading) {
      body = const _Busy('QR hazırlanıyor…');
    } else if (invite == null) {
      body = const _Result(
        ok: false,
        text:
            'Bu bilgisayar bir ağa bağlı görünmüyor. Wi‑Fi’ya ya da '
            'kabloya bağlanıp yeniden deneyin.',
      );
    } else if (expired) {
      body = const _Result(
        ok: false,
        text: 'QR’ın süresi doldu. Yeni bir QR alın.',
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(10),
            child: QrImageView(
              key: const ValueKey('office-qr'),
              data: invite.text,
              size: 220,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Telefonunuzda Folio’yu açın, Büro ağı’nda “QR okut”a dokunun ve '
            'bu kodu okutun. Telefon bu bilgisayarla aynı ağda olmalı.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 6),
          const Text(
            'Kod beş dakika geçerlidir ve yalnız bir telefon için kullanılır.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AgendaColors.muted),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Telefonumu ekle'),
      content: SizedBox(width: 360, child: body),
      actions: [
        if (!done && (failed || expired || invite == null) && !_loading)
          TextButton(
            key: const ValueKey('office-qr-renew'),
            onPressed: () => unawaited(_renew()),
            child: const Text('Yeni QR'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(done ? 'Tamam' : 'Kapat'),
        ),
      ],
    );
  }
}

/// "QR okut" on a phone: reads a computer's QR and knows it.
Future<void> scanAndPair(BuildContext context, OfficeNetwork net) async {
  final invite = await Navigator.of(context)
      .push<QrInvite>(MaterialPageRoute(builder: (_) => const _QrScanPage()));
  if (invite == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ScanPairingDialog(network: net, invite: invite),
  );
}

class _QrScanPage extends StatefulWidget {
  const _QrScanPage();

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  final _scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _taken = false;
  String? _wrong;

  @override
  void dispose() {
    unawaited(_scanner.dispose());
    super.dispose();
  }

  void _seen(BarcodeCapture capture) {
    if (_taken) return;
    for (final b in capture.barcodes) {
      final invite = QrInvite.parse(b.rawValue ?? '');
      if (invite != null) {
        _taken = true;
        Navigator.pop(context, invite);
        return;
      }
    }
    setState(() => _wrong = 'Bu bir Folio QR’ı değil.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: const Text('Bilgisayardaki QR’ı okutun'),
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    body: Stack(
      children: [
        MobileScanner(controller: _scanner, onDetect: _seen),
        Positioned(
          left: 16,
          right: 16,
          bottom: 32,
          child: Text(
            _wrong ??
                'Bilgisayarda Büro ağı → “Telefonumu ekle”ye basınca çıkan '
                    'kodu çerçeveye alın.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ],
    ),
  );
}

class _ScanPairingDialog extends StatefulWidget {
  const _ScanPairingDialog({required this.network, required this.invite});
  final OfficeNetwork network;
  final QrInvite invite;

  @override
  State<_ScanPairingDialog> createState() => _ScanPairingDialogState();
}

class _ScanPairingDialogState extends State<_ScanPairingDialog> {
  OfficePairing? _pairing;
  bool _unreached = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.network.pairByQr(widget.invite).then((p) {
        if (!mounted) return;
        setState(() {
          _pairing = p?..addListener(_moved);
          _unreached = p == null;
        });
      }),
    );
  }

  void _moved() => mounted ? setState(() {}) : null;

  @override
  void dispose() {
    _pairing?.removeListener(_moved);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _pairing;
    final Widget body;
    var finished = true;
    if (_unreached) {
      body = const _Result(
        ok: false,
        text:
            'Bilgisayara ulaşılamadı. Telefon ile bilgisayar aynı Wi‑Fi '
            'ağında mı? Bilgisayarda Folio açık kalmalı.',
      );
    } else if (p?.state == PairingState.done) {
      body = _Result(
        ok: true,
        text:
            'Bilgisayarınız tanındı: ${p!.other?.device ?? ''}. Artık '
            'birbirinize kodsuz gönderebilirsiniz.',
      );
    } else if (p != null && p.finished) {
      body = _Result(ok: false, text: p.reason ?? 'Tanıma tamamlanamadı.');
    } else {
      finished = false;
      body = const _Busy('Bilgisayara bağlanılıyor…');
    }
    return AlertDialog(
      title: const Text('QR ile tanıma'),
      content: body,
      actions: [
        if (finished)
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
      ],
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      ),
      const SizedBox(width: 14),
      Expanded(child: Text(text)),
    ],
  );
}

class _Result extends StatelessWidget {
  const _Result({required this.ok, required this.text});
  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
        color: ok ? AgendaColors.ok : Theme.of(context).colorScheme.error,
      ),
      const SizedBox(width: 12),
      Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
    ],
  );
}
