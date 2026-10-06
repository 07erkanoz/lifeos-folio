import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../services/editor/lawyer_profile.dart';
import '../../services/platform/document_intents.dart';
import '../../services/platform/onboarding_store.dart';
import '../../services/search/library_controller.dart';
import 'folio_about_dialog.dart';
import '../theme/theme_controller.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../mobile/profile_from_uyap.dart';
import '../mobile/settings_parts.dart';

class OnboardingGate extends StatefulWidget {
  final Widget child;
  final LibraryController library;
  final ThemeController appearance;
  final bool externalDocument;
  final OnboardingStore store;
  const OnboardingGate({
    super.key,
    required this.child,
    required this.library,
    required this.appearance,
    this.externalDocument = false,
    this.store = const OnboardingStore(),
  });
  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  late final Future<OnboardingStatus> _status = widget.store.load();
  bool _done = false;
  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return FutureBuilder<OnboardingStatus>(
      future: _status,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('Kurulum ayarları okunamadı: ${snapshot.error}'),
            ),
          );
        }
        final status = snapshot.data;
        if (status == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (status.licenseAccepted &&
            (status.completed || widget.externalDocument)) {
          return widget.child;
        }
        return OnboardingScreen(
          library: widget.library,
          appearance: widget.appearance,
          store: widget.store,
          status: status,
          externalDocument: widget.externalDocument,
          onDone: () => setState(() => _done = true),
        );
      },
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  final LibraryController library;
  final ThemeController appearance;
  final OnboardingStore store;
  final OnboardingStatus status;
  final bool externalDocument;
  final VoidCallback onDone;
  final Future<String?> Function()? pickFolder;

  /// Where the lawyer's profile is read from and kept; the profile file
  /// when not given.
  final Future<LawyerProfile> Function()? loadProfile;
  final Future<void> Function(LawyerProfile profile)? saveProfile;
  const OnboardingScreen({
    super.key,
    required this.library,
    required this.appearance,
    required this.store,
    required this.status,
    required this.onDone,
    this.externalDocument = false,
    this.pickFolder,
    this.loadProfile,
    this.saveProfile,
  });
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late int _step = widget.status.licenseAccepted ? 2 : 0;

  // The lawyer's profile (step 3): filled from UYAP Mobil or typed.
  LawyerProfile _profile = const LawyerProfile();
  final _name = TextEditingController();
  final _bar = TextEditingController();
  final _barNumber = TextEditingController();
  final _tbbNumber = TextEditingController();
  final _idNumber = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _fromUyap = false;
  bool _filling = false;

  @override
  void initState() {
    super.initState();
    // A test reads no lawyer's real profile unless it gives one.
    if (widget.loadProfile == null &&
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    (widget.loadProfile ?? LawyerProfile.load)().then((p) {
      if (mounted) setState(() => _showProfile(p));
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _bar,
      _barNumber,
      _tbbNumber,
      _idNumber,
      _phone,
      _email,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _showProfile(LawyerProfile p) {
    _profile = p;
    final l = p.lawyer ?? const Lawyer();
    _name.text = l.name;
    _bar.text = l.barName;
    _barNumber.text = l.barNumber;
    _tbbNumber.text = l.tbbNumber;
    _idNumber.text = l.idNumber;
    _phone.text = p.phone;
    _email.text = p.email;
  }

  LawyerProfile get _typed {
    final lawyer = Lawyer(
      name: _name.text.trim(),
      bar: _bar.text.trim(),
      barNumber: _barNumber.text.trim(),
      tbbNumber: _tbbNumber.text.trim(),
      idNumber: _idNumber.text.trim(),
    );
    final lawyers = [..._profile.lawyers];
    final at = lawyers.isEmpty
        ? -1
        : _profile.main.clamp(0, lawyers.length - 1);
    if (at < 0) {
      lawyers.add(lawyer);
    } else {
      lawyers[at] = lawyer;
    }
    return LawyerProfile(
      lawyers: lawyers,
      main: at < 0 ? 0 : at,
      address: _profile.address,
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      kep: _profile.kep,
    );
  }

  Future<void> _fillFromUyap() async {
    setState(() {
      _filling = true;
      _error = null;
    });
    try {
      final filled = await profileFromUyap(context, _typed);
      if (!mounted) return;
      if (filled == null) {
        setState(() => _error = 'UYAP Mobil’den bilgi alınamadı.');
        return;
      }
      setState(() {
        _showProfile(filled);
        _fromUyap = true;
      });
    } finally {
      if (mounted) setState(() => _filling = false);
    }
  }

  /// The profile kept, when a name was given; on to the folders.
  Future<void> _saveProfile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = _typed;
      if (profile.lawyer != null) {
        await (widget.saveProfile ?? (p) => p.save())(profile);
      }
      if (mounted) setState(() => _step = 3);
    } catch (e) {
      if (mounted) setState(() => _error = 'Profil kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _accepted = false;
  bool _busy = false;
  String? _error;
  final _folders = <String>[];
  bool _licenseReady = false;
  late final _license = _loadLicense();
  Future<String> _loadLicense() async {
    final text = await rootBundle.loadString('assets/legal/LICENSE.txt');
    if (mounted) setState(() => _licenseReady = true);
    return text;
  }

  Future<void> _accept({bool openDocument = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.save(completed: false);
      if (!mounted) return;
      if (openDocument) {
        widget.onDone();
      } else {
        setState(() => _step = 2);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Onay kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _folder() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path =
          await (widget.pickFolder?.call() ??
              (Platform.isAndroid
                  ? DocumentIntents.pickFolder()
                  : FilePicker.getDirectoryPath(
                      dialogTitle: 'İndekslenecek klasörü seçin',
                    )));
      if (path == null || !mounted) return;
      await widget.library.addPaths([path], recursive: true);
      if (!mounted) return;
      if (widget.library.error != null || !widget.library.ready) {
        throw StateError(widget.library.error ?? 'İndeks başlatılamadı');
      }
      setState(() {
        if (!_folders.contains(path)) _folders.add(path);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Klasör eklenemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    try {
      await widget.store.save(completed: true);
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Kurulum kaydedilemedi: $e';
        });
      }
    }
  }

  Future<void> _exit() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.close();
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_busy && _step > 0) setState(() => _step--);
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 20 : 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/branding/lifeos_folio.png',
                              width: 46,
                              height: 46,
                              cacheWidth:
                                  (46 * MediaQuery.devicePixelRatioOf(context))
                                      .ceil(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'LifeOS Folio',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Hakkında',
                            onPressed: () => showFolioAbout(context),
                            icon: const Icon(Icons.info_outline_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          for (var i = 0; i < 4; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: i <= _step
                                        ? colors.primary
                                        : colors.outlineVariant,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        [
                          '01 / HOŞ GELDİNİZ',
                          '02 / KULLANIM LİSANSI',
                          '03 / AVUKAT PROFİLİ',
                          '04 / BELGE KÜTÜPHANENİZ',
                        ][_step],
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: AnimatedSwitcher(
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.topLeft,
                            children: [...previous, ?current],
                          ),
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          child: KeyedSubtree(
                            key: ValueKey(_step),
                            child: _content(colors, compact),
                          ),
                        ),
                      ),
                      if (_busy) const LinearProgressIndicator(),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _error!,
                            style: TextStyle(color: colors.error, fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (_step == 0)
                            FilledButton.icon(
                              onPressed: () => setState(() => _step = 1),
                              icon: const Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                              ),
                              label: const Text('Başlayalım'),
                            ),
                          if (_step == 1) ...[
                            FilledButton(
                              onPressed: !_accepted || !_licenseReady || _busy
                                  ? null
                                  : () => _accept(),
                              child: const Text('Onayla ve devam et'),
                            ),
                            if (widget.externalDocument)
                              OutlinedButton(
                                onPressed: !_accepted || !_licenseReady || _busy
                                    ? null
                                    : () => _accept(openDocument: true),
                                child: const Text('Onayla, belgeye geç'),
                              ),
                            TextButton(
                              onPressed: _busy ? null : _exit,
                              child: const Text('Çıkış'),
                            ),
                          ],
                          if (_step == 2) ...[
                            FilledButton.icon(
                              key: const ValueKey('onboarding-profile-next'),
                              onPressed: _busy || _filling
                                  ? null
                                  : _saveProfile,
                              icon: const Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                              ),
                              label: const Text('Devam et'),
                            ),
                            TextButton(
                              key: const ValueKey('onboarding-profile-later'),
                              onPressed: _busy
                                  ? null
                                  : () => setState(() => _step = 3),
                              child: const Text('Sonra'),
                            ),
                          ],
                          if (_step == 3) ...[
                            FilledButton.icon(
                              onPressed: _busy ? null : _finish,
                              icon: const Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                              ),
                              label: Text(
                                widget.externalDocument
                                    ? 'Belgeyi aç'
                                    : 'Folio’yu aç',
                              ),
                            ),
                            if (_folders.isEmpty)
                              TextButton(
                                onPressed: _busy ? null : _finish,
                                child: const Text('Klasörleri sonra ekle'),
                              ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(ColorScheme colors, bool compact) {
    final titleStyle = TextStyle(
      fontSize: compact ? 26 : 34,
      fontWeight: FontWeight.w700,
      letterSpacing: -.8,
      height: 1.15,
    );
    if (_step == 2) return _profileStep(colors, titleStyle);
    if (_step == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Kullanımı ücretsiz.\nKontrol sizde.', style: titleStyle),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: FutureBuilder<String>(
                future: _license,
                builder: (context, snapshot) => snapshot.hasError
                    ? const Text('Lisans metni yüklenemedi.')
                    : snapshot.hasData
                    ? Scrollbar(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            snapshot.data!,
                            style: const TextStyle(fontSize: 13, height: 1.6),
                          ),
                        ),
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _accepted,
            onChanged: _busy || !_licenseReady
                ? null
                : (value) => setState(() => _accepted = value ?? false),
            title: const Text(
              'Kullanım lisansını okudum ve kabul ediyorum.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _step == 0
                ? 'Belgelerinize\nbiraz alan açın.'
                : 'Aradığınız belge,\nbirkaç kelime uzağınızda.',
            style: titleStyle,
          ),
          const SizedBox(height: 16),
          Text(
            _step == 0
                ? 'Hızlı önizleme, içerikte arama ve gerektiğinde düzenleme.\nFolio’yu bir dakikada tanıyın.'
                : 'İndekslenecek klasörleri seçin. Desteklenen dosyalar ve alt klasörleri taranır; belgeleriniz kendi yerinde kalır.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          if (_step == 0) ...[
            Text(
              'Görünümünüzü seçin',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: widget.appearance,
              builder: (context, _) => Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final choice in [
                    (ThemeMode.light, 'Beyaz', Icons.light_mode_outlined),
                    (ThemeMode.dark, 'Siyah', Icons.dark_mode_outlined),
                    (
                      ThemeMode.system,
                      'Sistem',
                      Icons.brightness_auto_outlined,
                    ),
                  ])
                    ChoiceChip(
                      avatar: Icon(choice.$3, size: 18),
                      label: Text(choice.$2),
                      selected: widget.appearance.mode == choice.$1,
                      onSelected: (_) => widget.appearance.setMode(choice.$1),
                      showCheckmark: false,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _feature(
              Icons.find_in_page_outlined,
              'Önce belgeyi görün',
              'Bir dosya açın veya arama sonucuna tıklayın. Gerçek önizleme hemen karşınızda.',
            ),
            _feature(
              Icons.search_rounded,
              'İçeriğiyle bulun',
              'Belgenin adını hatırlamanız gerekmez. Aradığınız kelimenin geçtiği bölümü sonuçlarda görün.',
            ),
            _feature(
              Icons.edit_note_rounded,
              'İstediğinizde düzenleyin',
              'Düzenle düğmesiyle editöre geçin. Ctrl+S ile kaydedin; Ctrl+tekerlek ile yakınlaşın.',
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: _busy ? null : _folder,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Klasör seç ve ekle'),
            ),
            const SizedBox(height: 16),
            for (final folder in _folders)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.check_circle_outline_rounded,
                  color: colors.primary,
                ),
                title: Text(folder, style: const TextStyle(fontSize: 13)),
              ),
            _feature(
              Icons.sync_rounded,
              'Kütüphane güncel kalır',
              'Uygulama açıkken yeni ve değiştirilen belgeler izlenir. Yeniden açıldığında değişiklikler kontrol edilir.',
            ),
            Text(
              'Klasörleri daha sonra Ayarlar’dan ekleyebilir veya kaldırabilirsiniz. Varsayılan açılacak dosya türleri de Ayarlar’da ayrı ayrı seçilir.',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Step 3: the lawyer, from UYAP Mobil in one tap or typed.
  Widget _profileStep(ColorScheme colors, TextStyle titleStyle) {
    Widget field(
      TextEditingController c,
      String label, {
      bool digits = false,
      int? maxLength,
      TextInputType? keyboard,
    }) => ListenableBuilder(
      listenable: c,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          maxLength: maxLength,
          keyboardType: digits ? TextInputType.number : keyboard,
          inputFormatters: digits
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          decoration: InputDecoration(
            isDense: true,
            labelText: label,
            counterText: '',
            border: const OutlineInputBorder(),
            // What UYAP filled in, in its teal.
            enabledBorder: _fromUyap && c.text.isNotEmpty
                ? const OutlineInputBorder(
                    borderSide: BorderSide(color: AgendaColors.eHearing),
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
      ),
    );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Dilekçeleriniz\nsizi tanısın.', style: titleStyle),
          const SizedBox(height: 10),
          Text(
            'Adınız, baronuz ve sicil numaranız kalıplara ve imza bloğuna '
            'kendiliğinden yazılır. Bilgiler yalnız bu cihazda kalır.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          UyapFillCard(
            title: 'UYAP Mobil ile doldur',
            subtitle: 'e-Devlet ile giriş; bilgiler UYAP’tan gelir',
            button: 'Doldur',
            busy: _filling,
            onTap: _busy ? null : _fillFromUyap,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'ya da elle girin',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ),
          field(_name, 'Ad soyad'),
          fieldPair(
            field(_bar, 'Baro'),
            field(_barNumber, 'Baro sicil no', digits: true),
          ),
          fieldPair(
            field(_tbbNumber, 'TBB sicil no', digits: true),
            field(_idNumber, 'TC kimlik no', digits: true, maxLength: 11),
          ),
          field(_phone, 'Telefon', keyboard: TextInputType.phone),
          field(_email, 'E-posta', keyboard: TextInputType.emailAddress),
        ],
      ),
    );
  }

  Widget _feature(IconData icon, String title, String text) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: colors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
