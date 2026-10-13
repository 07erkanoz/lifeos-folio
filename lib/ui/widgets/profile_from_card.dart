import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/editor/lawyer_profile.dart';
import '../../services/editor/profile_autofill.dart';
import '../../services/portal/portal_channel.dart';
import '../../services/signing/udf_signing_service.dart';
import '../../services/uyap/uyap_web_service.dart';
import 'folio_dialog.dart';
import 'uyap_connect_view.dart';

/// Whose e-imza card it is, as its certificate says: the name and the TC
/// number, all a Turkish e-signature certificate carries of the lawyer.
/// The bar and its register number come from UYAP Mobil alone.
typedef CardIdentity = ({String name, String tc});

/// The identity in [certificates]: a valid one with a TC number first.
CardIdentity? identityOf(Iterable<SigningCertificate> certificates) {
  String? tc(SigningCertificate c) =>
      RegExp(r'\d{11}').firstMatch(c.info.subjectSerialNumber ?? '')?.group(0);
  final ordered = [
    ...certificates.where((c) => c.info.isValid),
    ...certificates.where((c) => !c.info.isValid),
  ];
  for (final c in ordered) {
    final number = tc(c);
    final name = c.info.subjectCN.trim();
    if (number != null && name.isNotEmpty) {
      return (name: titleCaseTr(name), tc: number);
    }
  }
  return null;
}

/// [current] with [name] and [tc] as the default lawyer's (added when there
/// is none); the rest as it was.
LawyerProfile fillFromIdentity(
  LawyerProfile current, {
  required String name,
  required String tc,
}) {
  String pick(String fresh, String old) => fresh.trim().isEmpty ? old : fresh;
  final lawyers = [...current.lawyers];
  final at = lawyers.isEmpty
      ? -1
      : current.main >= 0 && current.main < lawyers.length
      ? current.main
      : 0;
  final old = at < 0 ? const Lawyer() : lawyers[at];
  final filled = Lawyer(
    name: pick(name.trim(), old.name),
    bar: old.bar,
    barNumber: old.barNumber,
    tbbNumber: old.tbbNumber,
    idNumber: pick(tc.trim(), old.idNumber),
  );
  if (at < 0) {
    lawyers.add(filled);
  } else {
    lawyers[at] = filled;
  }
  return LawyerProfile(
    lawyers: lawyers,
    main: at < 0 ? 0 : current.main,
    address: current.address,
    phone: current.phone,
    email: current.email,
    kep: current.kep,
    officeName: current.officeName,
  );
}

/// [current] filled from the e-imza card: read without a PIN where the card
/// allows it, else with one. Null when it was given up.
Future<LawyerProfile?> profileFromCard(
  BuildContext context,
  LawyerProfile current, {
  UdfSigningService? service,
}) async {
  final identity = await showDialog<CardIdentity>(
    context: context,
    builder: (_) => _CardIdentityDialog(service ?? UdfSigningService()),
  );
  if (identity == null) return null;
  return fillFromIdentity(current, name: identity.name, tc: identity.tc);
}

/// [current] filled from the UYAP web portal's session, opened with the
/// card (or the mobile signature) when it is not: the name and the TC
/// number, and the portfolio starts filling as it opens. Null when it was
/// given up or gave no one.
Future<LawyerProfile?> profileFromWeb(
  BuildContext context,
  LawyerProfile current, {
  UyapWebService? web,
}) async {
  final w = web ?? UyapWebService.instance;
  if (!w.connected &&
      !await connectUyap(
        context,
        channels: const {PortalChannel.uyapWeb},
        why:
            'Adınız ve TC kimlik numaranız UYAP’tan alınır; portföyünüz de '
            'dolmaya başlar.',
      )) {
    return null;
  }
  final user = w.session.value?.user.trim() ?? '';
  final tc = w.tckn;
  if (user.isEmpty && tc.isEmpty) return null;
  return fillFromIdentity(current, name: titleCaseTr(user), tc: tc);
}

class _CardIdentityDialog extends StatefulWidget {
  const _CardIdentityDialog(this.service);
  final UdfSigningService service;

  @override
  State<_CardIdentityDialog> createState() => _CardIdentityDialogState();
}

class _CardIdentityDialogState extends State<_CardIdentityDialog> {
  final _pin = TextEditingController();
  List<SigningCard>? _cards;
  SigningCard? _card;
  bool _busy = false;
  String? _error;

  /// Asked for once the card would not show its certificate without one.
  bool _needsPin = false;

  @override
  void initState() {
    super.initState();
    unawaited(_find());
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    setState(() {
      _cards = null;
      _error = null;
    });
    try {
      final cards = await widget.service.cards();
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _card = cards.firstOrNull;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cards = const [];
          _error = '$e'.replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  Future<void> _read() async {
    final card = _card;
    if (card == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final certificates = await widget.service.certificates(card, _pin.text);
      final identity = identityOf(certificates);
      if (!mounted) return;
      if (identity != null) {
        Navigator.pop(context, identity);
        return;
      }
      setState(() {
        if (_pin.text.isEmpty) {
          _needsPin = true;
          _error =
              'Kart sertifikasını PIN olmadan göstermedi; PIN’inizi '
              'yazıp yeniden okuyun.';
        } else {
          _error =
              'Kartta adı ve TC kimlik numarası olan bir sertifika '
              'bulunamadı.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('Bad state: ', ''));
      }
    } finally {
      _pin.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards;
    return FolioDialog(
      width: 480,
      icon: Icons.credit_card_rounded,
      title: 'E-imza kartından doldur',
      subtitle: 'Ad soyad ve TC kimlik numarası',
      onClose: () => Navigator.pop(context),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const ValueKey('card-identity-read'),
          onPressed: _busy || _card == null ? null : () => unawaited(_read()),
          child: Text(_busy ? 'Okunuyor…' : 'Kartı oku'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Kartınızdaki sertifikadan adınız ve TC kimlik numaranız alınır. '
            'Baro ve sicil numarası sertifikada yoktur; onları elle ya da '
            'UYAP Mobil ile tamamlayın.',
          ),
          const SizedBox(height: 14),
          if (cards == null)
            const FolioStatusLine('Kart aranıyor…', busy: true)
          else if (cards.isEmpty)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                const Text('Takılı bir e-imza kartı bulunamadı.'),
                TextButton(
                  key: const ValueKey('card-identity-retry'),
                  onPressed: () => unawaited(_find()),
                  child: const Text('Yeniden ara'),
                ),
              ],
            )
          else ...[
            if (cards.length > 1)
              DropdownButtonFormField<SigningCard>(
                initialValue: _card,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kart'),
                items: [
                  for (final c in cards)
                    DropdownMenuItem(
                      value: c,
                      child: Text(c.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (c) => setState(() => _card = c),
              )
            else
              Text(
                cards.single.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('card-identity-pin'),
              controller: _pin,
              obscureText: true,
              enabled: !_busy,
              onSubmitted: (_) => unawaited(_read()),
              decoration: InputDecoration(
                labelText: _needsPin ? 'E-imza PIN' : 'E-imza PIN (gerekirse)',
                helperText: _needsPin
                    ? null
                    : 'Çoğu kart PIN istemeden okunur; boş bırakabilirsiniz.',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            FolioCallout(tone: CalloutTone.error, child: Text(_error!)),
          ],
        ],
      ),
    );
  }
}
