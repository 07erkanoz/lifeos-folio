import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/editor/lawyer_profile.dart';
import 'notice.dart';

/// The office and its lawyers, typed once for every filing after.
class LawyerProfileDialog extends StatefulWidget {
  const LawyerProfileDialog({super.key, required this.initial});

  final LawyerProfile initial;

  static Future<void> show(BuildContext context) async {
    final profile = await LawyerProfile.load();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => LawyerProfileDialog(initial: profile),
    );
  }

  @override
  State<LawyerProfileDialog> createState() => _LawyerProfileDialogState();
}

class _LawyerFields {
  _LawyerFields(Lawyer lawyer)
    : name = TextEditingController(text: lawyer.name),
      bar = TextEditingController(text: lawyer.bar),
      barNumber = TextEditingController(text: lawyer.barNumber),
      tbbNumber = TextEditingController(text: lawyer.tbbNumber),
      idNumber = TextEditingController(text: lawyer.idNumber);

  final TextEditingController name, bar, barNumber, tbbNumber, idNumber;

  Lawyer get value => Lawyer(
    name: name.text.trim(),
    bar: bar.text.trim(),
    barNumber: barNumber.text.trim(),
    tbbNumber: tbbNumber.text.trim(),
    idNumber: idNumber.text.trim(),
  );

  void dispose() {
    for (final field in [name, bar, barNumber, tbbNumber, idNumber]) {
      field.dispose();
    }
  }
}

class _LawyerProfileDialogState extends State<LawyerProfileDialog> {
  late final _lawyers = [
    for (final one in widget.initial.lawyers) _LawyerFields(one),
    if (widget.initial.lawyers.isEmpty) _LawyerFields(const Lawyer()),
  ];
  late int _main = widget.initial.main < _lawyers.length
      ? widget.initial.main
      : 0;
  late final _address = TextEditingController(text: widget.initial.address);
  late final _phone = TextEditingController(text: widget.initial.phone);
  late final _email = TextEditingController(text: widget.initial.email);
  late final _kep = TextEditingController(text: widget.initial.kep);
  bool _saving = false;

  @override
  void dispose() {
    for (final one in _lawyers) {
      one.dispose();
    }
    for (final field in [_address, _phone, _email, _kep]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final lawyers = [for (final one in _lawyers) one.value];
    final kept = [
      for (final one in lawyers)
        if (!one.isEmpty) one,
    ];
    final chosen = _main < lawyers.length ? lawyers[_main] : null;
    final at = chosen == null ? -1 : kept.indexOf(chosen);
    final profile = LawyerProfile(
      lawyers: kept,
      main: at < 0 ? 0 : at,
      address: _address.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      kep: _kep.text.trim(),
    );
    try {
      await profile.save();
      if (!mounted) return;
      Navigator.pop(context);
      showNotice(
        context,
        'Avukat profili kaydedildi.',
        kind: NoticeKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showNotice(
        context,
        'Avukat profili kaydedilemedi',
        detail: '$e',
        kind: NoticeKind.error,
      );
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    Key? key,
    int maxLines = 1,
    bool digits = false,
    int? maxLength,
  }) => TextField(
    key: key,
    controller: controller,
    maxLines: maxLines,
    maxLength: maxLength,
    keyboardType: digits ? TextInputType.number : null,
    inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
    decoration: InputDecoration(
      isDense: true,
      labelText: label,
      counterText: '',
      border: const OutlineInputBorder(),
    ),
  );

  Widget _lawyer(int index, ColorScheme scheme) {
    final one = _lawyers[index];
    final main = index == _main;
    return Container(
      key: ValueKey('lawyer-$index'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: main ? scheme.primary : scheme.outlineVariant,
          width: main ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                main ? 'Varsayılan avukat' : 'Avukat',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: main ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (!main)
                TextButton(
                  onPressed: () => setState(() => _main = index),
                  child: const Text('Varsayılan yap'),
                ),
              if (_lawyers.length > 1)
                IconButton(
                  tooltip: 'Bu avukatı kaldır',
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  onPressed: () => setState(() {
                    _lawyers.removeAt(index).dispose();
                    if (_main >= _lawyers.length) _main = _lawyers.length - 1;
                    if (index < _main) _main--;
                  }),
                ),
            ],
          ),
          _field(one.name, 'Ad soyad', key: ValueKey('lawyer-name-$index')),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _field(
                  one.bar,
                  'Baro',
                  key: ValueKey('lawyer-bar-$index'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(one.barNumber, 'Baro sicil no', digits: true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _field(one.tbbNumber, 'TBB sicil no', digits: true),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  one.idNumber,
                  'TC kimlik no',
                  digits: true,
                  maxLength: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    TextStyle heading() => TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
    );
    return AlertDialog(
      title: const Text('Avukat profili'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Dilekçelerde her seferinde yazılan bilgiler. Kalıplardaki '
                'boşlukları kendiliğinden doldurur. Yalnızca bu bilgisayarda '
                'saklanır, hiçbir yere gönderilmez.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text('Avukatlar', style: heading()),
              const SizedBox(height: 8),
              for (var i = 0; i < _lawyers.length; i++) _lawyer(i, scheme),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('lawyer-add'),
                  onPressed: () => setState(
                    () => _lawyers.add(_LawyerFields(const Lawyer())),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                  label: const Text('Avukat ekle'),
                ),
              ),
              const SizedBox(height: 12),
              Text('Büro', style: heading()),
              const SizedBox(height: 8),
              _field(_address, 'Adres', maxLines: 2),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _field(_phone, 'Telefon')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_email, 'E-posta')),
                ],
              ),
              const SizedBox(height: 10),
              _field(_kep, 'KEP adresi'),
              const SizedBox(height: 16),
              Text('Kalıplarda kullanılabilecek boşluklar', style: heading()),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in LawyerProfile.known)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SelectableText(
                        '[$name]',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const ValueKey('lawyer-profile-save'),
          onPressed: _saving ? null : _save,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
