import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/editor/lawyer_profile.dart';
import '../../services/editor/profile_autofill.dart';
import '../../services/security/secret_store.dart';
import '../../services/signing/udf_signing_service.dart';
import '../../services/uets/uets_api.dart';
import '../../services/uets/uets_card_login.dart';
import '../../services/uyap/uyap_mobile_api.dart';
import '../../services/uyap/uyap_web_service.dart';
import 'agenda_page.dart' show AgendaColors;
import '../widgets/folio_dialog.dart';
import '../widgets/folio_select.dart';

/// Opens a UETS session (UYGULAMAPLANI P05): with the mobile signature or
/// with the card in the reader. The TC number, the phone and the operator
/// are remembered sealed with Windows' DPAPI; the PIN and UETS's token
/// never are.
Future<bool> connectUets(
  BuildContext context, {
  UetsApi? api,
  SecretStore? secrets,
}) async {
  final done = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UetsConnectDialog(
      api: api ?? UetsApi.instance,
      secrets: secrets ?? SecretStore(),
    ),
  );
  return done == true;
}

enum _Method { mobile, card }

class _UetsConnectDialog extends StatefulWidget {
  final UetsApi api;
  final SecretStore secrets;
  const _UetsConnectDialog({required this.api, required this.secrets});

  @override
  State<_UetsConnectDialog> createState() => _UetsConnectDialogState();
}

class _UetsConnectDialogState extends State<_UetsConnectDialog> {
  static const _remembered = 'uets-login';

  _Method _method = _Method.mobile;
  static bool get _onPhone => Platform.isAndroid || Platform.isIOS;
  final _tckn = TextEditingController();
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  MobileOperator _operator = MobileOperator.turkcell;
  final _service = UdfSigningService();
  List<SigningCard> _cards = const [];
  SigningCard? _card;
  bool _busy = false;
  String? _status;
  String? _error;
  String? _fingerprint;
  Completer<void>? _cancel;

  @override
  void initState() {
    super.initState();
    unawaited(_recall());
  }

  /// The lawyer's own TC number, from a UYAP session: the account UETS
  /// opens is the lawyer's, and a number typed again could be mistyped.
  String get _knownTc {
    final mobile = UyapMobileApi.instance.session.value?.tckn ?? '';
    if (mobile.isNotEmpty) return mobile;
    return UyapWebService.instance.tckn;
  }

  /// Whether the TC field is shown: when no session knows the number, or
  /// the lawyer asks to log into another account.
  bool _askTc = true;

  Future<void> _recall() async {
    // A UYAP session's number first; else the profile's, which every
    // portal that told it, and the lawyer, wrote there.
    var known = _knownTc;
    if (known.isEmpty && !Platform.environment.containsKey('FLUTTER_TEST')) {
      known = await profileTc();
      if (!mounted) return;
    }
    if (known.isNotEmpty) {
      setState(() {
        _tckn.text = known;
        _askTc = false;
      });
    }
    final phones = UyapMobileApi.instance.session.value?.phones ?? const [];
    final mobilePhone = phones
        .map(UetsApi.gsm)
        .where((p) => p.length == 10 && p.startsWith('5'))
        .firstOrNull;
    if (mobilePhone != null) {
      _phone.text = mobilePhone;
    } else if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      final phone = UetsApi.gsm((await LawyerProfile.load()).phone);
      if (phone.length == 10 && phone.startsWith('5') && mounted) {
        _phone.text = phone;
      }
    }
    if (!SecretStore.available) return;
    try {
      final kept = await widget.secrets.read(_remembered);
      if (kept == null || !mounted) return;
      // Asked not to be kept: nothing filled, and the box stays unticked.
      if (kept['keep'] == false) {
        setState(() => _keep = false);
        return;
      }
      setState(() {
        final tc = '${kept['tckn'] ?? ''}';
        if (_askTc && tc.isNotEmpty) {
          _tckn.text = tc;
          _askTc = false;
        }
        final phone = '${kept['phone'] ?? ''}';
        if (phone.isNotEmpty) _phone.text = phone;
        _operator =
            MobileOperator.values.asNameMap()['${kept['operator']}'] ??
            _operator;
        if (kept['method'] == _Method.card.name && !_onPhone) {
          _method = _Method.card;
        }
      });
      if (_method == _Method.card) unawaited(_scan());
    } catch (_) {}
  }

  void _stop() {
    final c = _cancel;
    _cancel = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  void dispose() {
    _stop();
    _pin.clear();
    _tckn.dispose();
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }

  static String _message(Object error) => switch (error) {
    StateError(:final message) => message,
    FormatException(:final message) => message,
    _ => '$error',
  };

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _fingerprint = null;
        });
      }
    }
  }

  Future<void> _scan() => _run(() async {
    setState(() => _status = 'Takılı kartlar aranıyor…');
    final cards = await _service.cards();
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _card = cards.firstOrNull;
      _status = cards.isEmpty
          ? 'Kart bulunamadı. E-imza kartınızı takıp yenileyin.'
          : null;
    });
  });

  /// Whether the TC number and the phone are kept for the next login,
  /// sealed in this computer's keystore; ticked unless the lawyer said no.
  bool _keep = true;

  /// Keeps what was typed as soon as a login is asked for, not only once
  /// it succeeds: a login the phone was too slow for need not be typed
  /// again. Unticked, what was kept is dropped and only that choice stays.
  Future<void> _remember() async {
    if (!SecretStore.available) return;
    try {
      await widget.secrets.write(
        _remembered,
        _keep
            ? {
                'tckn': _tckn.text.trim(),
                'phone': _phone.text.trim(),
                'operator': _operator.name,
                'method': _method.name,
              }
            : {'keep': false, 'method': _method.name},
      );
    } catch (_) {}
  }

  Future<void> _mobile() => _run(() async {
    final tckn = _tckn.text.trim();
    if (!RegExp(r'^\d{11}$').hasMatch(tckn)) {
      throw StateError('TC kimlik numarası 11 haneli olmalı.');
    }
    if (UetsApi.gsm(_phone.text).length != 10) {
      throw StateError('Cep telefonu numarasını 5xx xxx xx xx olarak yazın.');
    }
    await _remember();
    setState(() => _status = 'Mobil imza isteği gönderiliyor…');
    final login = await widget.api.startMobile(
      tckn: tckn,
      phone: _phone.text,
      operator: _operator,
    );
    if (!mounted) return;
    setState(() {
      _fingerprint = login.fingerprint;
      _status = 'Telefonunuza gelen isteği onaylayın.';
    });
    _cancel = Completer<void>();
    await widget.api.finishMobile(login, cancel: _cancel!.future);
    await _remember();
    if (mounted) Navigator.pop(context, true);
  });

  Future<void> _withCard() => _run(() async {
    final card = _card;
    if (card == null) throw StateError('Önce e-imza kartınızı seçin.');
    if (_pin.text.isEmpty) throw StateError('Kartın PIN’ini yazın.');
    setState(() => _status = 'Sertifika okunuyor…');
    final certificates = await _service.certificates(card, _pin.text);
    final valid = certificates.where((c) => c.info.isValid).toList();
    final chosen = valid.firstWhere(
      (c) => _tcOf(c) != null,
      orElse: () => valid.isEmpty
          ? throw StateError('Kartta geçerli bir sertifika bulunamadı.')
          : valid.first,
    );
    final pin = _pin.text;
    await loginWithCard(
      widget.api,
      tckn: _tcOf(chosen),
      sign: (data, {required attached}) =>
          _service.signBytes(data, card, chosen, pin, attached: attached),
      onProgress: (stage) {
        if (mounted) setState(() => _status = '$stage…');
      },
    );
    _pin.clear();
    await _remember();
    if (mounted) Navigator.pop(context, true);
  });

  static String? _tcOf(SigningCertificate c) =>
      RegExp(r'\d{11}').firstMatch(c.info.subjectSerialNumber ?? '')?.group(0);

  /// "123******01": enough to recognise one's own number.
  static String _masked(String tc) =>
      tc.length == 11 ? '${tc.substring(0, 3)}******${tc.substring(9)}' : tc;

  InputDecoration _field(String label, [IconData? icon]) => InputDecoration(
    labelText: label,
    prefixIcon: icon == null ? null : Icon(icon, size: 19),
  );

  void _choose(_Method method) {
    if (_busy || method == _method) return;
    setState(() {
      _method = method;
      _error = null;
      _status = null;
    });
    if (_method == _Method.card && _cards.isEmpty) unawaited(_scan());
  }

  void _close() {
    _stop();
    Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mobile = _method == _Method.mobile;
    return FolioDialog(
      width: 460,
      icon: Icons.mark_email_unread_outlined,
      accent: AgendaColors.hearing,
      title: 'UETS’ye bağlan',
      subtitle: 'Ulusal Elektronik Tebligat Sistemi',
      onClose: _close,
      progress: _busy,
      footerNote: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_rounded, size: 14, color: AgendaColors.muted),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'UETS oturumu yaklaşık 30 dakika açık kalır; bilgisayarda '
              'saklanmaz.',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _close, child: const Text('Vazgeç')),
        FilledButton.icon(
          key: const ValueKey('uets-connect'),
          onPressed: _busy ? null : (mobile ? _mobile : _withCard),
          icon: const Icon(Icons.login_rounded, size: 18),
          label: const Text('Bağlan'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A phone has no card reader: the mobile signature alone.
          if (!_onPhone) ...[
            const FolioSectionLabel('Giriş yöntemi'),
            Row(
              children: [
                Expanded(
                  child: FolioChoiceCard(
                    icon: Icons.smartphone_rounded,
                    title: 'Mobil imza',
                    subtitle: 'Telefondan onay',
                    selected: mobile,
                    onTap: _busy ? null : () => _choose(_Method.mobile),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FolioChoiceCard(
                    icon: Icons.credit_card_rounded,
                    title: 'E-imza kartı',
                    subtitle: 'Takılı kart ve PIN',
                    selected: !mobile,
                    onTap: _busy ? null : () => _choose(_Method.card),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (mobile) ...[
            if (_askTc) ...[
              TextField(
                key: const ValueKey('uets-tckn'),
                controller: _tckn,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: _field('TC kimlik no', Icons.badge_outlined),
              ),
              const SizedBox(height: 12),
            ] else
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.badge_outlined,
                      size: 17,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Hesap: ${_masked(_tckn.text)}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _askTc = true),
                      child: const Text('Başka hesap'),
                    ),
                  ],
                ),
              ),
            TextField(
              key: const ValueKey('uets-phone'),
              controller: _phone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              decoration: _field('Cep telefonu', Icons.phone_android_rounded),
            ),
            const SizedBox(height: 12),
            FolioSelect<MobileOperator>(
              initialValue: _operator,
              isExpanded: true,
              decoration: _field('Operatör', Icons.cell_tower_rounded),
              items: [
                for (final o in MobileOperator.values)
                  DropdownMenuItem(value: o, child: Text(o.label)),
              ],
              onChanged: _busy
                  ? null
                  : (o) => setState(() => _operator = o ?? _operator),
            ),
            if (SecretStore.available) ...[
              const SizedBox(height: 4),
              CheckboxListTile(
                key: const ValueKey('uets-keep'),
                value: _keep,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _keep = v ?? true),
                title: const Text(
                  'TC kimlik ve telefon numaram bu bilgisayarda hatırlansın',
                  style: TextStyle(fontSize: 12.5),
                ),
                subtitle: const Text(
                  'Şifreli saklanır; PIN ve UETS oturumu saklanmaz.',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
            ],
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: FolioSelect<SigningCard>(
                    initialValue: _card,
                    isExpanded: true,
                    decoration: _field('Kart', Icons.credit_card_rounded),
                    items: [
                      for (final c in _cards)
                        DropdownMenuItem(
                          value: c,
                          child: Text(c.label, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _busy ? null : (c) => setState(() => _card = c),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Kartları yeniden ara',
                  onPressed: _busy ? null : _scan,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('uets-pin'),
              controller: _pin,
              enabled: !_busy,
              obscureText: true,
              decoration: _field('E-imza PIN', Icons.lock_outline_rounded),
              onSubmitted: (_) => _withCard(),
            ),
          ],
          if (_fingerprint != null && _fingerprint!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: .25),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Telefonunuzdaki parmak izi bununla aynı olmalı',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: scheme.primary),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    _fingerprint!,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            FolioCallout(tone: CalloutTone.error, child: Text(_error!)),
          ] else if (_status != null) ...[
            const SizedBox(height: 14),
            FolioStatusLine(_status!, busy: _busy),
          ],
        ],
      ),
    );
  }
}
