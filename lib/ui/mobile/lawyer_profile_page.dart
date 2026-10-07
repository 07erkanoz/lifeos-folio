import 'package:flutter/material.dart';

import '../../services/editor/lawyer_profile.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../widgets/notice.dart';
import 'profile_from_uyap.dart';
import 'settings_parts.dart';

/// The lawyer's profile on a phone, a page of its own (docs/design/mobil-
/// ayarlar-taslak.png): filled from UYAP Mobil in one tap, the office's
/// lawyers, the office; saved with Kaydet.
class LawyerProfilePage extends StatefulWidget {
  const LawyerProfilePage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const LawyerProfilePage()));

  @override
  State<LawyerProfilePage> createState() => _LawyerProfilePageState();
}

class _LawyerFields {
  _LawyerFields(Lawyer l)
    : name = TextEditingController(text: l.name),
      bar = TextEditingController(text: l.bar),
      barNumber = TextEditingController(text: l.barNumber),
      tbbNumber = TextEditingController(text: l.tbbNumber),
      idNumber = TextEditingController(text: l.idNumber);

  final TextEditingController name, bar, barNumber, tbbNumber, idNumber;

  Lawyer get value => Lawyer(
    name: name.text.trim(),
    bar: bar.text.trim(),
    barNumber: barNumber.text.trim(),
    tbbNumber: tbbNumber.text.trim(),
    idNumber: idNumber.text.trim(),
  );

  void dispose() {
    for (final c in [name, bar, barNumber, tbbNumber, idNumber]) {
      c.dispose();
    }
  }
}

class _LawyerProfilePageState extends State<LawyerProfilePage> {
  final _lawyers = <_LawyerFields>[];
  int _main = 0;
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _kep = TextEditingController();
  final _office = TextEditingController();
  final _email = TextEditingController();
  bool _loaded = false;
  bool _filling = false;

  @override
  void initState() {
    super.initState();
    LawyerProfile.load().then((p) {
      if (mounted) setState(() => _show(p));
    });
  }

  void _show(LawyerProfile p) {
    for (final l in _lawyers) {
      l.dispose();
    }
    _lawyers
      ..clear()
      ..addAll([
        for (final l in p.lawyers.isEmpty ? const [Lawyer()] : p.lawyers)
          _LawyerFields(l),
      ]);
    _main = p.main.clamp(0, _lawyers.length - 1);
    _address.text = p.address;
    _phone.text = p.phone;
    _kep.text = p.kep;
    _office.text = p.officeName;
    _email.text = p.email;
    _loaded = true;
  }

  LawyerProfile get _profile => LawyerProfile(
    lawyers: [for (final l in _lawyers) l.value],
    main: _main,
    address: _address.text.trim(),
    phone: _phone.text.trim(),
    email: _email.text.trim(),
    kep: _kep.text.trim(),
    officeName: _office.text.trim(),
  );

  @override
  void dispose() {
    for (final l in _lawyers) {
      l.dispose();
    }
    for (final c in [_address, _phone, _kep, _email, _office]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fill() async {
    setState(() => _filling = true);
    try {
      final filled = await profileFromUyap(context, _profile);
      if (!mounted) return;
      if (filled == null) {
        showNotice(context, 'UYAP Mobil’den bilgi alınamadı');
        return;
      }
      setState(() => _show(filled));
      showNotice(
        context,
        'Bilgiler UYAP Mobil’den alındı',
        detail: 'Kontrol edip Kaydet’e dokunun.',
      );
    } finally {
      if (mounted) setState(() => _filling = false);
    }
  }

  Future<void> _save() async {
    try {
      await _profile.save();
      if (!mounted) return;
      showNotice(
        context,
        'Avukat profili kaydedildi.',
        kind: NoticeKind.success,
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Avukat profili kaydedilemedi',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
    }
  }

  Widget _lawyer(int i) {
    final scheme = Theme.of(context).colorScheme;
    final l = _lawyers[i];
    final main = i == _main;
    return Container(
      key: ValueKey('profile-lawyer-$i'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 2),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: main ? scheme.primary : scheme.outlineVariant,
          width: main ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (main)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF0F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'VARSAYILAN',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                )
              else
                TextButton(
                  onPressed: () => setState(() => _main = i),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Varsayılan yap'),
                ),
              const Spacer(),
              if (_lawyers.length > 1)
                IconButton(
                  tooltip: 'Bu avukatı kaldır',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 19,
                    color: Color(0xFF9AA2B1),
                  ),
                  onPressed: () => setState(() {
                    _lawyers.removeAt(i).dispose();
                    if (_main >= _lawyers.length) _main = _lawyers.length - 1;
                    if (i < _main) _main--;
                  }),
                )
              else
                const SizedBox(height: 36),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(
              children: [
                ProfileField(l.name, 'Ad soyad'),
                fieldPair(
                  ProfileField(l.bar, 'Baro'),
                  ProfileField(l.barNumber, 'Sicil no', digits: true),
                ),
                fieldPair(
                  ProfileField(l.tbbNumber, 'TBB sicil no', digits: true),
                  ProfileField(
                    l.idNumber,
                    'TC kimlik no',
                    digits: true,
                    maxLength: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: settingsPage(context),
      appBar: settingsBar(
        context,
        'Avukat profili',
        action: TextButton(
          key: const ValueKey('profile-save'),
          onPressed: _loaded ? _save : null,
          child: const Text(
            'Kaydet',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: [
                UyapFillCard(
                  title: 'UYAP Mobil’den güncelle',
                  subtitle: 'Ad, baro, sicil, TBB no, iletişim',
                  button: 'Güncelle',
                  busy: _filling,
                  onTap: _fill,
                ),
                const SettingsSection('AVUKATLAR'),
                for (var i = 0; i < _lawyers.length; i++) _lawyer(i),
                Center(
                  child: TextButton.icon(
                    key: const ValueKey('profile-add-lawyer'),
                    onPressed: () => setState(
                      () => _lawyers.add(_LawyerFields(const Lawyer())),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Avukat ekle'),
                  ),
                ),
                const SettingsSection('BÜRO'),
                SettingsGroup(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 2),
                  children: [
                    ProfileField(_office, 'Büro adı'),
                    ProfileField(_address, 'Büro adresi'),
                    fieldPair(
                      ProfileField(
                        _phone,
                        'Telefon',
                        keyboard: TextInputType.phone,
                      ),
                      ProfileField(
                        _kep,
                        'KEP',
                        keyboard: TextInputType.emailAddress,
                      ),
                    ),
                    ProfileField(
                      _email,
                      'E-posta',
                      keyboard: TextInputType.emailAddress,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
                  child: Text(
                    'Kalıplarda [AVUKAT], [BARO], [BARO SİCİL NO] gibi '
                    'boşluklar bu bilgilerle dolar.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: scheme.brightness == Brightness.dark
                          ? scheme.onSurfaceVariant
                          : AgendaColors.muted,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
