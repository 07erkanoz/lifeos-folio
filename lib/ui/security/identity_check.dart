import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/signing/udf_signing_service.dart';
import '../agenda/mobile_connect.dart' show edevletIdentity;

/// Whose Folio it is, for a forgotten lock password: on a computer with an
/// e-imza card in, the card proves it, its PIN asked; else, and on a phone,
/// e-Devlet (mobil imza). The TC number, or null when given up.
Future<String?> lockIdentity(BuildContext context) async {
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    final service = UdfSigningService();
    var cards = const <SigningCard>[];
    try {
      cards = await service.cards();
    } catch (_) {}
    if (cards.isNotEmpty && context.mounted) {
      final got = await showDialog<_Proof>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CardDialog(service: service, cards: cards),
      );
      if (got == null) return null;
      if (got.tckn != null) return got.tckn;
      // "e-Devlet ile" chosen instead.
    }
  }
  if (!context.mounted) return null;
  return edevletIdentity(context);
}

class _Proof {
  const _Proof(this.tckn);
  final String? tckn;
}

class _CardDialog extends StatefulWidget {
  const _CardDialog({required this.service, required this.cards});
  final UdfSigningService service;
  final List<SigningCard> cards;

  @override
  State<_CardDialog> createState() => _CardDialogState();
}

class _CardDialogState extends State<_CardDialog> {
  final _pin = TextEditingController();
  late SigningCard _card = widget.cards.first;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy || _pin.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tc = await widget.service.provenTckn(_card, _pin.text);
      if (!mounted) return;
      if (tc == null) {
        setState(() {
          _busy = false;
          _error =
              'Karttaki sertifika TC numarası taşımıyor ya da imza '
              'doğrulanamadı.';
        });
        return;
      }
      Navigator.pop(context, _Proof(tc));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pin.clear();
        _error = e is StateError ? e.message : 'Kart okunamadı: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('E-imza ile doğrula'),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Kartınız rastgele bir veriyi imzalar; sertifikadaki TC '
            'numarası bu Folio’nun avukatınınkiyle tutarsa yeni şifreniz '
            'konur.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (widget.cards.length > 1)
            DropdownButton<SigningCard>(
              isExpanded: true,
              value: _card,
              onChanged: _busy
                  ? null
                  : (c) => setState(() => _card = c ?? _card),
              items: [
                for (final c in widget.cards)
                  DropdownMenuItem(
                    value: c,
                    child: Text(c.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
            )
          else
            Text(_card.label, style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('lock-card-pin'),
            controller: _pin,
            autofocus: true,
            obscureText: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Kart PIN’i'),
            onSubmitted: (_) => unawaited(_check()),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      TextButton(
        key: const ValueKey('lock-card-edevlet'),
        onPressed: _busy
            ? null
            : () => Navigator.pop(context, const _Proof(null)),
        child: const Text('e-Devlet ile'),
      ),
      FilledButton(
        key: const ValueKey('lock-card-go'),
        onPressed: _busy ? null : () => unawaited(_check()),
        child: _busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Doğrula'),
      ),
    ],
  );
}
