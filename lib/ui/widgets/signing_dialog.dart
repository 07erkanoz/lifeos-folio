import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/platform/app_directories.dart';
import '../../services/platform/platform_capabilities.dart';

import '../../services/signing/mobile_signature.dart';
import '../../services/signing/udf_signing_service.dart';

enum _Method { card, mobile }

class SigningDialog extends StatefulWidget {
  final String? filePath;
  final UdfSigningService? service;

  /// For tests: the mobile signature service to ask.
  final MobileSignatureClient Function()? mobileClient;
  const SigningDialog({
    super.key,
    this.filePath,
    this.service,
    this.mobileClient,
  });
  @override
  State<SigningDialog> createState() => _SigningDialogState();
}

class _SigningDialogState extends State<SigningDialog> {
  final _driver = TextEditingController();
  final _pin = TextEditingController();
  final _phone = TextEditingController();
  late final _service = widget.service ?? UdfSigningService();
  List<SigningCard> _cards = [];
  List<SigningCertificate> _certificates = [];
  SigningCard? _card;
  SigningCertificate? _certificate;
  bool _busy = false;
  bool _advanced = false;
  String? _error;
  String _status = 'Takılı kartlar aranıyor…';
  _Method _method = _Method.card;
  MobileOperator _operator = MobileOperator.turkcell;
  bool _remember = true;
  bool _signedAlready = false;

  /// The code the phone will show, while the signer is being waited for.
  String? _code;
  MobileSignatureClient? _waiting;
  bool _cancelled = false;
  bool get _canSign =>
      !_busy &&
      widget.filePath != null &&
      _card != null &&
      _pin.text.isNotEmpty &&
      (_certificates.isEmpty || _certificate != null);
  bool get _canSignMobile =>
      !_busy &&
      widget.filePath != null &&
      MobileUdfSigner.phone(_phone.text) != null;
  bool get _desktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// A phone signs with a mobile signature only: the card needs a PKCS#11
  /// driver, which a phone does not have.
  bool get _mobileOnly =>
      !_desktop && mobileSigningAvailable && widget.filePath != null;
  Future<File> _settings() async =>
      File(p.join((await folioSupportDirectory()).path, 'signing.json'));
  @override
  void initState() {
    super.initState();
    if (_desktop) {
      _initialize();
    } else if (_mobileOnly) {
      _method = _Method.mobile;
      _status = _mobileHint;
      unawaited(_load());
    }
    final path = widget.filePath;
    if (path != null) {
      File(path).readAsBytes().then((bytes) {
        if (mounted) {
          setState(() => _signedAlready = UdfSigningService.isSigned(bytes));
        }
      }, onError: (_) {});
    }
  }

  Future<void> _initialize() => _run(() async {
    await _load();
    if (mounted && _method == _Method.card) await _scanCards();
  });

  Future<Map<String, dynamic>> _read() async {
    try {
      final file = await _settings();
      if (await file.exists()) {
        return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  Future<void> _load() async {
    final data = await _read();
    if (!mounted) return;
    String text(String key) => data[key] is String ? data[key] as String : '';
    final operator = data['operator'];
    setState(() {
      if (_driver.text.isEmpty) _driver.text = text('driver');
      if (_phone.text.isEmpty) _phone.text = text('phone');
      _operator =
          MobileOperator.byCode(operator is int ? operator : null) ?? _operator;
      // Only where there is a document: the settings dialog is the card's.
      if (data['method'] == 'mobile' && widget.filePath != null) {
        _method = _Method.mobile;
        _status = _mobileHint;
      }
    });
  }

  String get _mobileHint => _phone.text.isEmpty
      ? 'Numaranızı yazıp operatörünüzü seçin.'
      : 'Numaranızı ve operatörünüzü kontrol edip imzalayın.';

  /// Keeps the settings of this dialog on this device; nothing else leaves it.
  Future<void> _write(Map<String, Object?> changes) async {
    final data = {...await _read(), ...changes};
    data.removeWhere((_, value) => value == null);
    final file = await _settings();
    await file.parent.create(recursive: true);
    // Whole or not at all: a half-written file would be read as no settings.
    final pending = File('${file.path}.tmp');
    await pending.writeAsString(jsonEncode(data), flush: true);
    await pending.rename(file.path);
  }

  Future<void> _saveDriver() => _write({'driver': _driver.text.trim()});

  /// Remembers how the document was signed, for the next one. Not waited
  /// for: the document is signed whether or not this is kept, and it needs
  /// nothing of the dialog, which may be gone by the time it is written.
  Future<void> _keep(Map<String, Object?> changes) async {
    try {
      await _write(changes);
    } catch (_) {}
  }

  Future<void> _signMobile() async {
    final phone = MobileUdfSigner.phone(_phone.text);
    if (phone == null || widget.filePath == null) return;
    _cancelled = false;
    await _run(() async {
      final client = widget.mobileClient?.call() ?? MobileSignatureClient();
      final signer = MobileUdfSigner(client: client);
      try {
        setState(() {
          _waiting = client;
          _status = 'Doğrulama kodu alınıyor…';
        });
        final request = await signer.start(widget.filePath!, phone, _operator);
        if (!mounted || _cancelled) return;
        setState(() {
          _code = request.code;
          _status =
              'Telefonunuza onay isteği gönderildi. Bildirimdeki kodu '
              'kontrol edip onaylayın.';
        });
        final path = await signer.finish(request);
        unawaited(
          _keep({
            'method': 'mobile',
            'phone': _remember ? _phone.text.trim() : null,
            'operator': _operator.code,
          }),
        );
        if (!mounted) return;
        Navigator.pop(context, path);
      } catch (e) {
        if (_cancelled) return;
        if (mounted) setState(() => _status = 'İmzalama tamamlanamadı.');
        rethrow;
      } finally {
        client.cancel();
        _waiting = null;
        if (mounted) setState(() => _code = null);
      }
    });
  }

  void _stopWaiting() {
    _cancelled = true;
    _waiting?.cancel();
    setState(() {
      _code = null;
      _status = 'İmza beklemesi bırakıldı. Belge değişmedi.';
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// What went wrong, without the name of a Dart type in front of it.
  static String _message(Object error) => switch (error) {
    StateError(:final message) => message,
    FormatException(:final message) => message,
    UnsupportedError(:final message?) => message,
    _ => '$error',
  };

  Future<void> _detect() => _run(_scanCards);

  Future<void> _scanCards() async {
    setState(() {
      _cards = [];
      _card = null;
      _certificates = [];
      _certificate = null;
      _pin.clear();
      _status = 'Takılı kartlar aranıyor…';
    });
    late final List<SigningCard> cards;
    try {
      cards = await _service.cards(driver: _driver.text.trim());
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _status = 'Kart araması tamamlanamadı. Yeniden deneyebilirsiniz.',
        );
      }
      rethrow;
    }
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _card = cards.firstOrNull;
      _certificates = [];
      _certificate = null;
      _status = cards.isEmpty
          ? 'Kart bulunamadı. E-imza kartınızı takıp yenileyin.'
          : '${cards.length} kart bulundu.';
    });
  }

  Future<void> _sign() async {
    if (!_canSign) return;
    await _run(() async {
      try {
        if (_certificate == null) {
          setState(() => _status = 'İmzacı sertifikası okunuyor…');
          final values = await _service.certificates(_card!, _pin.text);
          if (!mounted) return;
          final valid = values.where((c) => c.info.isValid).toList();
          setState(() {
            _certificates = values;
            _certificate = valid.length == 1 ? valid.single : null;
            _status = values.isEmpty
                ? 'Kartta okunabilir sertifika bulunamadı.'
                : valid.isEmpty
                ? 'Kartta tarihi geçerli bir imzacı sertifikası bulunamadı.'
                : valid.length > 1
                ? 'İmzalamak için kullanacağınız sertifikayı seçin.'
                : 'Belge imzalanıyor…';
          });
          if (_certificate == null) return;
        }
        setState(() => _status = 'Belge imzalanıyor…');
        final path = await _service.sign(
          widget.filePath!,
          _card!,
          _certificate!,
          _pin.text,
        );
        if (!mounted) return;
        _pin.clear();
        unawaited(_keep({'method': 'card'}));
        Navigator.pop(context, path);
      } catch (_) {
        if (mounted) setState(() => _status = 'İmzalama tamamlanamadı.');
        rethrow;
      }
    });
  }

  @override
  void dispose() {
    _waiting?.cancel();
    _pin.clear();
    _pin.dispose();
    _driver.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _choose(_Method method) {
    if (_busy || method == _method) return;
    setState(() {
      _method = method;
      _error = null;
      _status = method == _Method.mobile
          ? _mobileHint
          : 'Takılı kartlar aranıyor…';
    });
    if (method == _Method.card && _cards.isEmpty) _detect();
  }

  List<Widget> _mobileFields(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return [
      if (_signedAlready) ...[
        Text(
          'Bu belge imzalı. İmzanız mevcut imzaların yanına eklenir; belgenin '
          'metni değişmez.',
          style: TextStyle(fontSize: 12.5, color: colors.primary),
        ),
        const SizedBox(height: 8),
      ],
      const Text(
        'Belgenin metni imza için UYAP’ın mobil imza servisine gönderilir; '
        'onay isteği telefonunuza gelir.',
        style: TextStyle(fontSize: 12.5),
      ),
      const SizedBox(height: 14),
      TextField(
        key: const ValueKey('mobile-phone'),
        controller: _phone,
        enabled: !_busy,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumber],
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _signMobile(),
        decoration: const InputDecoration(
          labelText: 'Cep telefonu',
          hintText: '05XX XXX XX XX',
          prefixIcon: Icon(Icons.phone_android_rounded, size: 20),
        ),
      ),
      const SizedBox(height: 12),
      // Scrolled rather than squeezed on a narrow phone.
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<MobileOperator>(
          showSelectedIcon: false,
          segments: [
            for (final operator in MobileOperator.values)
              ButtonSegment(value: operator, label: Text(operator.label)),
          ],
          selected: {_operator},
          onSelectionChanged: _busy
              ? null
              : (value) => setState(() => _operator = value.single),
        ),
      ),
      CheckboxListTile(
        value: _remember,
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: _busy
            ? null
            : (value) => setState(() => _remember = value ?? true),
        title: const Text(
          'Numaram bu cihazda hatırlansın',
          style: TextStyle(fontSize: 13),
        ),
      ),
      if (_code != null)
        Container(
          key: const ValueKey('mobile-code'),
          width: double.infinity,
          margin: const EdgeInsets.only(top: 4, bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.primary.withValues(alpha: .35)),
          ),
          child: Column(
            children: [
              const Text('Doğrulama kodu', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(
                _code!.isEmpty ? '—' : _code!,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Telefonunuzdaki bildirimde aynı kodu gördüğünüzde onaylayın. '
                'Onay birkaç dakika sürebilir.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      Text(_status, style: const TextStyle(fontSize: 12)),
    ];
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(
        widget.filePath == null ? 'E-imza ayarları' : 'UDF belgesini imzala',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_mobileOnly) ...[
                Text(
                  p.basename(widget.filePath!),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'İmza bu UDF dosyasına kaydedilir. İmza öncesi sürüm belge geçmişinde saklanır. Kartla e-imza masaüstü sürümündedir; telefonda mobil imza kullanılır.',
                ),
                const SizedBox(height: 16),
                ..._mobileFields(context),
              ] else if (!_desktop)
                const Text(
                  'Kartla elektronik imzalama Linux ve Windows’ta PKCS#11 sürücüsüyle kullanılabilir. Telefonda belgeyi mobil imzayla imzalayabilirsiniz.',
                ),
              if (_desktop) ...[
                if (widget.filePath != null) ...[
                  Text(
                    p.basename(widget.filePath!),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'İmza bu UDF dosyasına kaydedilir. İmza öncesi sürüm belge geçmişinde saklanır. Editördeki kaydedilmemiş değişiklikler imzalanmaz.',
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<_Method>(
                    key: const ValueKey('signing-method'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: _Method.card,
                        icon: Icon(Icons.usb_rounded, size: 18),
                        label: Text('E-imza kartı'),
                      ),
                      ButtonSegment(
                        value: _Method.mobile,
                        icon: Icon(Icons.phone_android_rounded, size: 18),
                        label: Text('Mobil imza'),
                      ),
                    ],
                    selected: {_method},
                    onSelectionChanged: _busy
                        ? null
                        : (value) => _choose(value.single),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_method == _Method.mobile && widget.filePath != null)
                  ..._mobileFields(context)
                else ...[
                  Row(
                    children: [
                      const Icon(Icons.usb_rounded, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'E-imza kartı',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        onPressed: _busy ? null : _detect,
                        tooltip: 'Kartları yenile',
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(_status, style: const TextStyle(fontSize: 12)),
                  if (_cards.isNotEmpty)
                    DropdownButton<SigningCard>(
                      isExpanded: true,
                      value: _card,
                      items: [
                        for (final card in _cards)
                          DropdownMenuItem(
                            value: card,
                            child: Text(
                              card.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              _card = value;
                              _certificate = null;
                              _certificates = [];
                              _pin.clear();
                            }),
                    ),
                  if (widget.filePath != null && _card != null) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pin,
                      enabled: !_busy,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _sign(),
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Kart PIN’i',
                        helperText: 'PIN kaydedilmez. Hatalı PIN otomatik tekrar denenmez.',
                      ),
                    ),
                    if (_certificates.isNotEmpty)
                      DropdownButton<SigningCertificate>(
                        isExpanded: true,
                        value: _certificate,
                        hint: const Text('İmzacı sertifikasını seçin'),
                        items: [
                          for (final cert in _certificates)
                            DropdownMenuItem(
                              value: cert,
                              enabled: cert.info.isValid,
                              child: Text(
                                '${cert.info.subjectCN}${cert.info.isValid ? '' : ' · Süresi uygun değil'}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _certificate = value),
                      ),
                    if (_certificate != null)
                      Text(
                        '${_certificate!.info.issuerCN}\nGeçerlilik sonu: ${_certificate!.info.notAfter.toLocal().toString().split(' ').first}',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _advanced = !_advanced),
                    icon: Icon(
                      _advanced ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                    label: const Text('Gelişmiş ayarlar'),
                  ),
                  if (_advanced) ...[
                    const Text(
                      'RSA / SHA-256 · CAdES-BES. Üretilen imzanın belge ve sertifika eşleşmesi kontrol edilir. Sertifika iptal durumu ve güven zinciri doğrulaması yapılmaz.',
                      style: TextStyle(fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Kurulu kart yazılımları otomatik algılanır. Kartınız listelenmiyorsa sağlayıcınızın kart yazılımını kurun veya özel sürücü konumunu belirtin.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _driver,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Özel PKCS#11 sürücüsü',
                        hintText: '.so / .dll yolu (isteğe bağlı)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final files = await FilePicker.pickFiles();
                                  if (mounted &&
                                      files?.files.single.path != null) {
                                    _driver.text = files!.files.single.path!;
                                  }
                                },
                          icon: const Icon(
                            Icons.folder_open_outlined,
                            size: 18,
                          ),
                          label: const Text('Sürücü seç'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  await _saveDriver();
                                  if (mounted) await _scanCards();
                                }),
                          child: const Text('Uygula ve tara'),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        // From the first request on: a service that does not answer is
        // waited for too.
        if (_waiting != null)
          TextButton(
            onPressed: _stopWaiting,
            child: const Text('Beklemeyi bırak'),
          )
        else
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        if (_desktop && widget.filePath == null)
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await _saveDriver();
                    if (context.mounted) Navigator.pop(context);
                  }),
            child: const Text('Ayarları kaydet'),
          ),
        if (_desktop && widget.filePath != null && _method == _Method.card)
          FilledButton.icon(
            onPressed: _canSign ? _sign : null,
            icon: const Icon(Icons.draw_outlined, size: 18),
            label: const Text('İmzala ve kaydet'),
          ),
        if (mobileSigningAvailable &&
            widget.filePath != null &&
            _method == _Method.mobile)
          FilledButton.icon(
            key: const ValueKey('sign-mobile'),
            onPressed: _canSignMobile ? _signMobile : null,
            icon: const Icon(Icons.phone_android_rounded, size: 18),
            label: const Text('Mobil imzayla imzala'),
          ),
      ],
    ),
  );
}
