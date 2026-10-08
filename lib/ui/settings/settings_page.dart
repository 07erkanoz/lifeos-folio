import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../services/editor/editor_settings.dart';
import '../../services/editor/lawyer_profile.dart';
import '../../services/editor/snippets.dart';
import '../../services/editor/suggestions/phrases.dart';
import '../../services/legal/legal_settings.dart';
import '../../services/platform/context_menu_registration.dart';
import '../../services/platform/platform_capabilities.dart';
import '../../services/platform/system_notices.dart';
import '../../services/desktop/desktop_companion.dart';
import '../../services/portal/background_notices.dart';
import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/portal/uyap_notice.dart';
import '../../services/portal/uyap_notice_alerts.dart';
import '../../services/search/library_controller.dart';
import '../../services/uets/uets_api.dart';
import '../../services/update/update_check.dart';
import '../../services/update/update_manifest.dart';
import '../../services/uyap/uyap_mobile_api.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../agenda/mobile_connect.dart';
import '../agenda/uets_connect.dart';
import '../desktop/quick_search_settings.dart';
import '../mobile/lawyer_profile_page.dart';
import '../mobile/mobile_settings_page.dart'
    show ArchiveFoldersPage, LearningPage;
import '../mobile/settings_parts.dart';
import '../security/security_settings.dart';
import '../theme/theme_controller.dart';
import '../widgets/default_viewer_dialog.dart';
import '../widgets/folio_about_dialog.dart';
import '../widgets/notice.dart';
import '../widgets/signing_dialog.dart';
import '../widgets/snippet_manager.dart';
import '../widgets/update_card.dart';
import '../widgets/update_dialog.dart';
import '../widgets/uyap_connect_view.dart';

/// The settings (docs/design/ayarlar-taslak.png): a page of their own on
/// every system. Wide, the sections on the left and the settings on the
/// right; narrow, one under another. A search finds a setting by its
/// words. Only what the system can do is shown: OCR and reading aloud on
/// a computer, the mobile signature alone on a phone.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.library,
    required this.appearance,
    this.onBack,
  });

  final LibraryController library;
  final ThemeController appearance;

  /// Given where the page sits inside Folio's window (a computer's) rather
  /// than on a route of its own (a phone's): its own way back.
  final VoidCallback? onBack;

  /// The settings on a page of their own, over what is open.
  static Future<void> open(
    BuildContext context, {
    required LibraryController library,
    required ThemeController appearance,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SettingsPage(library: library, appearance: appearance),
    ),
  );

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// "6 gün 22 sa", "1 sa 20 dk", "24 dk".
String _left(DateTime until) {
  final d = until.difference(DateTime.now());
  if (d.isNegative) return 'süresi doldu';
  if (d.inDays > 0) return '${d.inDays} gün ${d.inHours % 24} sa';
  if (d.inHours > 0) return '${d.inHours} sa ${d.inMinutes % 60} dk';
  return '${d.inMinutes} dk';
}

/// One setting: what it shows, and the words it is found by.
class _Entry {
  const _Entry(this.words, this.child);
  final String words;
  final Widget child;
}

class _Section {
  const _Section(
    this.id,
    this.title,
    this.icon,
    this.entries, {
    this.lead,
    this.tag,
  });
  final String id, title;
  final IconData icon;
  final String? lead;

  /// A word beside the section's name in the list on the left ("3/3").
  final String? tag;
  final List<_Entry> entries;
}

class _SettingsPageState extends State<SettingsPage> {
  LawyerProfile? _profile;
  int? _snippets;
  PortalDatabase? _db;
  UyapNoticeAlerts _alerts = const UyapNoticeAlerts();
  String _version = '';
  String? _update;
  UpdateManifest? _newer;
  bool _checking = false;
  bool _registering = false;
  bool _pickingOcr = false;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _content = GlobalKey();
  final _keys = <String, GlobalKey>{};
  String? _current;

  static bool get _desktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  static bool get _phone => Platform.isAndroid || Platform.isIOS;

  PortalSync get _sync => PortalSync.instance;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_followScroll);
    unawaited(_load());
  }

  @override
  void dispose() {
    _scroll.removeListener(_followScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // A test reads no lawyer's real profile, snippets or database.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    final profile = await LawyerProfile.load();
    int? snippets;
    try {
      snippets = (await SnippetStore.shared()).all.length;
    } catch (_) {}
    PortalDatabase? db;
    try {
      db = await PortalDatabase.shared();
    } catch (_) {}
    var version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version} (${info.buildNumber})';
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _snippets = snippets;
      _db = db;
      if (db != null) _alerts = UyapNoticeAlerts.of(db);
      _version = version;
    });
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) await _load();
  }

  void _setAlerts(UyapNoticeAlerts next) {
    setState(() => _alerts = next);
    final db = _db;
    if (db != null) next.save(db);
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _update = null;
    });
    try {
      final newer = await UpdateCheck.instance.check();
      if (!mounted) return;
      setState(() {
        _newer = newer;
        _update = newer == null
            ? 'Güncel · son denetim ${_clock(DateTime.now())}'
            : '${newer.version} hazır';
      });
    } catch (e) {
      if (mounted) setState(() => _update = 'Denetlenemedi: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  static String _day(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}';

  /// A word on this device's own notifications, now: leave asked first.
  Future<void> _testNotice() async {
    await SystemNotices.instance.askLeave();
    await SystemNotices.instance.show(
      id: 7,
      title: 'Folio deneme bildirimi',
      body: 'Bu bildirimi görüyorsanız yeni UYAP bildirimleri de gelir.',
      payload: 'notices:',
    );
    if (mounted) {
      showNotice(
        context,
        'Deneme bildirimi gönderildi',
        detail:
            'Gelmediyse Folio’nun bildirim iznini telefonun ayarlarından açın.',
      );
    }
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _registerContext() async {
    setState(() => _registering = true);
    try {
      final message = await ContextMenuRegistration.register();
      if (mounted) showNotice(context, message, kind: NoticeKind.success);
    } catch (e) {
      if (mounted) showNotice(context, '$e', kind: NoticeKind.error);
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  Future<void> _addOcrFolder() async {
    setState(() => _pickingOcr = true);
    try {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: 'OCR uygulanacak klasörü seçin',
      );
      if (path == null || !mounted) return;
      final affected = await widget.library.addOcrFolder(path, recursive: true);
      if (!mounted) return;
      showNotice(
        context,
        widget.library.ocrEnabled
            ? '$affected belge OCR sırasına alındı'
            : 'Bu seçimle $affected belge okunacak',
      );
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Klasör seçilemedi',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _pickingOcr = false);
    }
  }

  /// A connected portal: sync it now, or let it go.
  Future<void> _portalMenu({
    required String name,
    required Future<void> Function() sync,
    required Future<void> Function() disconnect,
  }) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.sync_rounded),
            title: Text('$name · senkronize et'),
            onTap: () {
              Navigator.pop(sheet);
              unawaited(sync());
            },
          ),
          ListTile(
            leading: const Icon(Icons.link_off_rounded),
            title: const Text('Bağlantıyı kes'),
            onTap: () {
              Navigator.pop(sheet);
              unawaited(
                disconnect().then((_) => mounted ? setState(() {}) : null),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  // The sections.

  Widget _profileCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lawyer = _profile?.lawyer;
    final name = lawyer?.titled ?? '';
    final initials = (lawyer?.name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();
    final detail = [
      if ((lawyer?.barName ?? '').isNotEmpty) lawyer!.barName,
      if ((lawyer?.barNumber ?? '').trim().isNotEmpty)
        'Sicil ${lawyer!.barNumber.trim()}',
      if ((lawyer?.idNumber ?? '').trim().length == 11)
        'TC ••••••${lawyer!.idNumber.trim().substring(6)}',
    ].join(' · ');
    return InkWell(
      key: const ValueKey('settings-profile'),
      onTap: () => _push(const LawyerProfilePage()),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: scheme.primary,
              child: initials.isEmpty
                  ? const Icon(Icons.badge_outlined, color: Colors.white)
                  : Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Avukat profili' : name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    detail.isEmpty
                        ? 'Ad, baro, sicil ve TC kimlik no; UYAP’a bağlanınca '
                              'kendiliğinden dolar'
                        : detail,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AgendaColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF9AA2B1)),
          ],
        ),
      ),
    );
  }

  Widget _themes(BuildContext context, bool wide) {
    final mode = widget.appearance.mode;
    if (!wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tema',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            SegmentedButton<ThemeMode>(
              key: const ValueKey('settings-theme'),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Sistem')),
                ButtonSegment(value: ThemeMode.light, label: Text('Açık')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Koyu')),
              ],
              selected: {mode},
              onSelectionChanged: (v) => widget.appearance.setMode(v.first),
            ),
          ],
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    Widget card(ThemeMode m, String label, List<Color> side, List<Color> body) {
      final on = m == mode;
      Widget half(Color a, Color b) => Expanded(
        child: Row(
          children: [
            Container(width: 52, color: a),
            Expanded(
              child: Container(
                color: b,
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final w in [.7, .9, .5])
                      FractionallySizedBox(
                        widthFactor: w,
                        child: Container(
                          height: 5,
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: b.computeLuminance() > .5
                                ? const Color(0xFFD8DDE5)
                                : const Color(0xFF3A404C),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
      return InkWell(
        key: ValueKey('settings-theme-${m.name}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.appearance.setMode(m),
        child: Container(
          width: 180,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            border: Border.all(
              color: on ? scheme.primary : scheme.outlineVariant,
              width: on ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Container(
                foregroundDecoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SizedBox(
                  height: 84,
                  child: Column(
                    children: [
                      for (var i = 0; i < side.length; i++)
                        half(side[i], body[i]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                  color: on ? scheme.primary : null,
                ),
              ),
            ],
          ),
        ),
      );
    }

    const light = Color(0xFFFFFFFF), lightBody = Color(0xFFF4F6F9);
    const dark = Color(0xFF20242D), darkBody = Color(0xFF171A21);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          card(
            ThemeMode.system,
            'Sisteme uy',
            [light, dark],
            [lightBody, darkBody],
          ),
          card(ThemeMode.light, 'Açık', [light], [lightBody]),
          card(ThemeMode.dark, 'Koyu', [dark], [darkBody]),
        ],
      ),
    );
  }

  Widget _kinds(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(56, 0, 14, 14),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final kind in UyapNoticeKind.values)
          FilterChip(
            key: ValueKey('settings-alert-${kind.name}'),
            label: Text(kind.label),
            selected: _alerts.on && !_alerts.quiet.contains(kind),
            showCheckmark: true,
            selectedColor: Theme.of(context).colorScheme.primary
                .withValues(alpha: .12),
            visualDensity: VisualDensity.compact,
            onSelected: !_alerts.on
                ? null
                : (v) => _setAlerts(
                    _alerts.copyWith(
                      quiet: v
                          ? ({..._alerts.quiet}..remove(kind))
                          : {..._alerts.quiet, kind},
                    ),
                  ),
          ),
      ],
    ),
  );

  List<_Section> _sections(BuildContext context, bool wide) {
    final library = widget.library;
    final mobile = UyapMobileApi.instance;
    final uets = UetsApi.instance;
    final web = UyapWebService.instance;
    final folders = library.sources.where((s) => s.folder).toList();
    final documents = folders.fold<int>(0, (n, f) => n + f.count);
    const off = Color(0xFF9AA2B1);
    final connected = [
      mobile.connected,
      web.connected,
      uets.connected,
    ].where((c) => c).length;
    Widget? actions(bool on, Future<void> Function() sync, VoidCallback cut) =>
        !wide || !on
        ? null
        : Wrap(
            spacing: 6,
            children: [
              OutlinedButton(
                onPressed: () => unawaited(sync()),
                child: const Text('Senkronize et'),
              ),
              OutlinedButton(
                onPressed: () {
                  cut();
                  setState(() {});
                },
                child: const Text('Bağlantıyı kes'),
              ),
            ],
          );
    final told = UyapNoticeKind.values.length - _alerts.quiet.length;
    return [
      _Section('profile', 'Profil', Icons.person_outline_rounded, [
        _Entry('profil avukat ad baro sicil tc kimlik', _profileCard(context)),
      ], lead: 'Dilekçelerin ve imzanın kullandığı bilgiler.'),
      _Section(
        'security',
        'Güvenlik',
        Icons.lock_outline_rounded,
        lead: 'Folio’yu açmak için şifre ve kurtarma kodu.',
        [
          const _Entry(
            'güvenlik giriş şifre parola kilit kurtarma kodu ekran koruyucu',
            SecuritySettings(),
          ),
        ],
      ),
      _Section(
        'connections',
        'Bağlantılar',
        Icons.link_rounded,
        lead: 'Oturumlar süreleri bitene kadar bu cihazda saklanır.',
        tag: '$connected/3',
        [
          _Entry(
            'uyap mobil bağlantı e-devlet',
            SettingsRow(
              key: const ValueKey('settings-uyap-mobile'),
              icon: Icons.gavel_rounded,
              fill: AgendaColors.eHearingFill,
              tint: AgendaColors.eHearing,
              title: 'UYAP Mobil',
              status: mobile.connected ? AgendaColors.ok : off,
              subtitle: mobile.connected
                  ? 'Bağlı · ${_left(mobile.session.value?.expires ?? DateTime.now())} geçerli'
                  : 'Bağlı değil · e-Devlet ile',
              trailing: actions(
                mobile.connected,
                () => _sync.syncMobile(full: true),
                () => unawaited(mobile.logout()),
              ),
              onTap: () async {
                if (mobile.connected) {
                  if (wide) return;
                  await _portalMenu(
                    name: 'UYAP Mobil',
                    sync: () => _sync.syncMobile(full: true),
                    disconnect: mobile.logout,
                  );
                } else if (await connectUyapMobile(context, api: mobile)) {
                  unawaited(_sync.syncMobile());
                }
              },
            ),
          ),
          _Entry(
            'uyap web portal avukat bağlantı e-imza',
            SettingsRow(
              key: const ValueKey('settings-uyap-web'),
              icon: Icons.account_balance_outlined,
              title: 'UYAP Web',
              status: web.connected ? AgendaColors.ok : off,
              subtitle: web.connected
                  ? 'Bağlı · ${_left(DateTime.now().add(web.session.value?.remaining() ?? Duration.zero))} geçerli'
                  : _desktop
                  ? 'Bağlı değil · e-imza ya da mobil imza ile'
                  : 'Bağlı değil · mobil imza ile, e-Devlet üzerinden',
              trailing: actions(web.connected, _sync.syncWeb, web.disconnect),
              onTap: () async {
                if (web.connected) {
                  if (wide) return;
                  await _portalMenu(
                    name: 'UYAP Web',
                    sync: _sync.syncWeb,
                    disconnect: () async => web.disconnect(),
                  );
                } else {
                  await connectUyapWeb(
                    context,
                    onConnected: () => unawaited(_sync.syncWeb()),
                  );
                }
              },
            ),
          ),
          _Entry(
            'uets tebligat bağlantı',
            SettingsRow(
              key: const ValueKey('settings-uets'),
              icon: Icons.mark_email_unread_outlined,
              fill: AgendaColors.deadlineFill,
              tint: AgendaColors.deadline,
              title: 'UETS',
              status: uets.connected ? AgendaColors.ok : off,
              subtitle: uets.connected
                  ? 'Bağlı · ${_left(uets.session.value?.expires ?? DateTime.now())} geçerli'
                  : 'Bağlı değil',
              trailing: actions(uets.connected, _sync.syncUets, uets.logout),
              onTap: () async {
                if (uets.connected) {
                  if (wide) return;
                  await _portalMenu(
                    name: 'UETS',
                    sync: _sync.syncUets,
                    disconnect: () async => uets.logout(),
                  );
                } else {
                  await connectUets(context, api: uets, secrets: _sync.secrets);
                }
              },
            ),
          ),
          if (_phone)
            _Entry(
              'bilgisayarla senkron qr',
              SettingsRow(
                key: const ValueKey('settings-sync'),
                icon: Icons.sync_alt_rounded,
                title: 'Bilgisayarla senkronla',
                subtitle: 'QR ile, aynı ağda',
                onTap: () => showNotice(
                  context,
                  'Bilgisayarla senkron hazırlanıyor',
                  detail:
                      'Masaüstünde “Telefonla senkronla” deyip QR’ı okutarak '
                      'eşitleyeceksiniz; bu özellik bir sonraki sürümde.',
                ),
              ),
            ),
        ],
      ),
      _Section(
        'notices',
        'Bildirimler',
        Icons.notifications_none_rounded,
        lead: _phone
            ? 'UYAP Mobil ve UYAP Web’den gelen yeni bildirimler için telefon '
                  'bildirimi.'
            : 'UYAP Mobil ve UYAP Web’den gelen yeni bildirimler için '
                  'masaüstü uyarısı.',
        [
          _Entry(
            'bildirim uyarı masaüstü telefon uyap tür',
            SettingsRow(
              key: const ValueKey('settings-alerts'),
              icon: Icons.notifications_active_outlined,
              title: 'Yeni bildirim gelince uyar',
              subtitle: _alerts.on
                  ? '${UyapNoticeKind.values.length} türden $told tanesi · '
                        'tıklayınca dosya açılır'
                  : 'Kapalı',
              trailing: settingsSwitch(
                _alerts.on,
                (v) => _setAlerts(_alerts.copyWith(on: v)),
              ),
            ),
          ),
          if (_phone)
            _Entry(
              'arka plan kapalıyken denetle pil',
              SettingsRow(
                key: const ValueKey('settings-background'),
                icon: Icons.schedule_rounded,
                title: 'Folio kapalıyken de denetle',
                subtitle: Platform.isIOS
                    ? 'iOS’un izin verdiği aralıklarla, günde birkaç kez'
                    : 'En sık 15 dakikada bir. Bazı telefonlarda Folio’yu pil '
                          'kısıtlamasından çıkarmak gerekir.',
                trailing: settingsSwitch(
                  _alerts.on && _alerts.background,
                  _alerts.on
                      ? (v) {
                          final next = _alerts.copyWith(background: v);
                          _setAlerts(next);
                          unawaited(BackgroundNotices.schedule(next));
                        }
                      : null,
                ),
              ),
            ),
          if (_phone)
            _Entry(
              'arka plan son denetim',
              SettingsRow(
                key: const ValueKey('settings-background-last'),
                icon: Icons.history_rounded,
                title: 'Son arka plan denetimi',
                subtitle: switch (_db == null
                    ? null
                    : BackgroundNotices.last(_db!)) {
                  null =>
                    'Henüz çalışmadı. Android ilk denetimi Folio kapandıktan '
                        'en erken 15 dakika sonra yapar.',
                  final l => '${_day(l.at)} ${_clock(l.at)} · ${l.result}',
                },
              ),
            ),
          _Entry(
            'deneme bildirimi test uyarı',
            SettingsRow(
              key: const ValueKey('settings-test-notice'),
              icon: Icons.notification_add_outlined,
              title: 'Deneme bildirimi gönder',
              subtitle:
                  'Bu cihazın Folio’dan gelen bildirimi gösterip göstermediğini '
                  'denetler',
              onTap: () => unawaited(_testNotice()),
            ),
          ),
          if (_desktop && CompanionScope.maybeOf(context) != null)
            _Entry(
              'tepsi arka plan pencere kapanınca çalış',
              Builder(
                builder: (context) {
                  final companion = CompanionScope.maybeOf(context)!;
                  return SettingsRow(
                    key: const ValueKey('settings-tray'),
                    icon: Icons.inventory_2_outlined,
                    title: 'Pencere kapanınca tepside çalış',
                    subtitle:
                        'Bildirimler ve eşitleme sürer; hızlı arama da açık '
                        'kalır. Tepsideki “Tamamen çık” kapatır.',
                    trailing: settingsSwitch(
                      companion.enabled,
                      companion.busy
                          ? null
                          : (v) => unawaited(companion.configure(v)),
                    ),
                  );
                },
              ),
            ),
          _Entry(
            'bildirim tür karar tahsilat reddiyat bilirkişi rapor kanun yolu '
            'kesinleşme müzekkere tebligat duruşma taraf vekil',
            _kinds(context),
          ),
        ],
      ),
      _Section(
        'documents',
        'Belgeler ve arşiv',
        Icons.folder_open_outlined,
        lead: 'Folio’nun aradığı klasörler ve belgelerin okunması.',
        [
          _Entry(
            'arşiv klasör ekle indeks',
            SettingsRow(
              key: const ValueKey('settings-folders'),
              icon: Icons.folder_outlined,
              fill: const Color(0xFFFFF3E0),
              tint: AgendaColors.task,
              title: 'Arşiv klasörleri',
              subtitle: folders.isEmpty
                  ? 'Henüz klasör eklenmedi'
                  : library.active
                  ? '${library.phase} · ${library.processed}/${library.toProcess}'
                  : '${folders.length} klasör · $documents evrak',
              onTap: () => _push(ArchiveFoldersPage(library: library)),
            ),
          ),
          if (_desktop)
            _Entry(
              'ocr taranmış belge oku metin tanıma',
              SettingsRow(
                icon: Icons.document_scanner_outlined,
                title: 'Taranmış belgeleri oku (OCR)',
                subtitle: library.ocrAvailable
                    ? 'Görsel ve taranmış PDF’lerde arama'
                    : 'Bu bilgisayarda kullanılamıyor',
                trailing: settingsSwitch(
                  library.ocrEnabled,
                  library.ocrAvailable
                      ? (v) => unawaited(library.setOcr(v))
                      : null,
                ),
              ),
            ),
          if (_desktop && library.ocrAvailable)
            _Entry(
              'ocr klasörü seç',
              SettingsRow(
                icon: Icons.create_new_folder_outlined,
                title: 'OCR klasörü',
                subtitle: 'Yalnız seçilen klasördeki taramalar okunur',
                onTap: _pickingOcr ? null : () => unawaited(_addOcrFolder()),
              ),
            ),
          if (!Platform.isIOS)
            _Entry(
              'varsayılan uygulama dosya türleri aç',
              SettingsRow(
                icon: Icons.open_in_browser_rounded,
                title: 'Varsayılan uygulama',
                subtitle: 'Folio’nun açacağı dosya türleri',
                onTap: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const DefaultViewerDialog(),
                ),
              ),
            ),
          if (Platform.isLinux || Platform.isWindows)
            _Entry(
              'sağ tık menü önizle düzenle',
              SettingsRow(
                icon: Icons.ads_click_rounded,
                title: 'Sağ tık menüsü',
                subtitle: _registering
                    ? 'Ekleniyor…'
                    : 'Dosya yöneticisinde “Folio ile önizle ve düzenle”',
                onTap: _registering
                    ? null
                    : () => unawaited(_registerContext()),
              ),
            ),
          if (_desktop)
            const _Entry(
              'hızlı arama kısayol masaüstü',
              Padding(
                padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: QuickSearchSettings(),
              ),
            ),
        ],
      ),
      _Section('editor', 'Editör', Icons.edit_note_rounded, [
        _Entry(
          'yazarken öneri kalıp ifade',
          SettingsRow(
            icon: Icons.edit_outlined,
            title: 'Yazarken öneri',
            subtitle: 'Kalıplar ve öğrenilen ifadeler',
            trailing: settingsSwitch(EditorSettings.instance.suggestions, (
              v,
            ) async {
              await EditorSettings.instance.setSuggestions(v);
              if (mounted) setState(() {});
            }, key: const ValueKey('setting-suggestions')),
          ),
        ),
        _Entry(
          'kalıplarım snippet metin',
          SettingsRow(
            key: const ValueKey('settings-snippets'),
            icon: Icons.bookmark_border_rounded,
            title: 'Kalıplarım',
            subtitle: _snippets == null
                ? 'Sık kullandığınız metinler'
                : '$_snippets kalıp',
            onTap: () async {
              final store = await SnippetStore.shared();
              if (!context.mounted) return;
              await SnippetManager.show(context, store);
              if (mounted) await _load();
            },
          ),
        ),
        _Entry(
          'öğrenme öğrenilen ifadeler arşiv',
          SettingsRow(
            key: const ValueKey('settings-learning'),
            icon: Icons.auto_awesome_outlined,
            title: 'Öğrenme',
            subtitle: 'Belgelerimden · arşivden · ifadeler',
            onTap: () => _push(const LearningPage()),
          ),
        ),
      ], lead: 'Yazarken Folio’nun yardımı.'),
      _Section('citations', 'Atıflar', Icons.menu_book_outlined, [
        _Entry(
          'kanun madde mevzuat atıf',
          SettingsRow(
            icon: Icons.menu_book_outlined,
            title: 'Kanun maddeleri',
            subtitle: 'TMK m.166 tıklanınca resmî metin',
            trailing: settingsSwitch(LegalSettings.instance.articles, (
              v,
            ) async {
              await LegalSettings.instance.setArticles(v);
              if (mounted) setState(() {});
            }),
          ),
        ),
        _Entry(
          'mahkeme kararları içtihat yargıtay danıştay',
          SettingsRow(
            icon: Icons.gavel_outlined,
            title: 'Mahkeme kararları',
            subtitle: 'Yargıtay, BAM, Danıştay · Bedesten',
            trailing: settingsSwitch(LegalSettings.instance.decisions, (
              v,
            ) async {
              await LegalSettings.instance.setDecisions(v);
              if (mounted) setState(() {});
            }),
          ),
        ),
        _Entry(
          'hukuk sözlüğü terim',
          SettingsRow(
            icon: Icons.translate_rounded,
            title: 'Hukuk sözlüğü',
            subtitle: 'Terimin anlamı, internetsiz',
            trailing: settingsSwitch(LegalSettings.instance.dictionary, (
              v,
            ) async {
              await LegalSettings.instance.setDictionary(v);
              if (mounted) setState(() {});
            }),
          ),
        ),
      ], lead: 'Metindeki kanun ve karar atıfları.'),
      _Section('signing', 'E-imza', Icons.verified_outlined, [
        if (_desktop && desktopSigningAvailable)
          _Entry(
            'e-imza kart sürücü pin mobil imza',
            SettingsRow(
              key: const ValueKey('settings-signing'),
              icon: Icons.draw_outlined,
              title: 'E-imza ve mobil imza',
              subtitle: 'Kart sürücüsü, telefon numarası ve operatör',
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => const SigningDialog(),
              ),
            ),
          )
        else
          _Entry(
            'mobil imza telefon',
            SettingsRow(
              icon: Icons.phone_iphone_rounded,
              title: 'Mobil imza',
              subtitle: _phone
                  ? 'Telefonda belgeler mobil imza ile imzalanır; numara '
                        'profilden gelir'
                  : 'Bu bilgisayarda kartlı e-imza kullanılamıyor; mobil '
                        'imza ile imzalanır',
            ),
          ),
      ], lead: 'UYAP’a gönderilen belgelerin imzası.'),
      _Section(
        'look',
        'Görünüm',
        Icons.palette_outlined,
        lead: 'Folio’nun rengi ve düzeni. Değişiklik hemen uygulanır.',
        [
          _Entry(
            'tema açık koyu siyah beyaz sistem renk',
            _themes(context, wide),
          ),
          if (_desktop)
            _Entry(
              'sol panel daralt uyap',
              SettingsRow(
                key: const ValueKey('settings-fold-panel'),
                icon: Icons.view_sidebar_outlined,
                title: 'Sol panel UYAP sayfalarında daralsın',
                subtitle: 'Dosya listesine ve evrak önizlemesine yer açar',
                trailing: settingsSwitch(
                  widget.appearance.foldPanelOnUyap,
                  widget.appearance.setFoldPanelOnUyap,
                ),
              ),
            ),
          if (_desktop)
            _Entry(
              'üzerine gelince hızlı önizleme fare',
              SettingsRow(
                icon: Icons.preview_outlined,
                title: 'Üzerine gelince hızlı önizleme',
                subtitle:
                    'Arşivde bir belgenin üstünde durunca içinden parçalar '
                    'görünür; Esc ile kapanır',
                trailing: settingsSwitch(
                  widget.appearance.hoverPreview,
                  widget.appearance.setHoverPreview,
                ),
              ),
            ),
        ],
      ),
      _Section(
        'update',
        'Güncelleme',
        Icons.system_update_outlined,
        tag: _newer == null ? null : 'yeni',
        [
          _Entry(
            'güncelleme sürüm yeni denetle indir',
            SettingsRow(
              key: const ValueKey('settings-update'),
              icon: Icons.system_update_outlined,
              title: _version.isEmpty ? 'LifeOS Folio' : 'Sürüm $_version',
              subtitle:
                  _update ??
                  (Platform.isIOS
                      ? 'Güncellemeler App Store’dan gelir'
                      : 'Yeni sürüm çıkınca Folio kendisi de haber verir'),
              trailing: Platform.isIOS
                  ? null
                  : _newer != null
                  ? FilledButton(
                      key: const ValueKey('settings-update-install'),
                      onPressed: () =>
                          unawaited(UpdateDialog.show(context, _newer!)),
                      child: const Text('Güncelle'),
                    )
                  : OutlinedButton(
                      key: const ValueKey('settings-update-check'),
                      onPressed: _checking ? null : () => unawaited(_check()),
                      child: Text(_checking ? 'Denetleniyor…' : 'Denetle'),
                    ),
            ),
          ),
        ],
      ),
      _Section('about', 'Hakkında', Icons.info_outline_rounded, [
        _Entry(
          'hakkında lisans sürüm',
          SettingsRow(
            icon: Icons.info_outline_rounded,
            title: 'LifeOS Folio hakkında',
            onTap: () => showFolioAbout(context),
          ),
        ),
      ]),
    ];
  }

  List<_Section> _shown(List<_Section> all) {
    final q = foldPhrase(_search.text.trim());
    if (q.isEmpty) return all;
    return [
      for (final s in all)
        if (foldPhrase(s.title).contains(q))
          s
        else if (s.entries.any((e) => foldPhrase(e.words).contains(q)))
          _Section(
            s.id,
            s.title,
            s.icon,
            [
              for (final e in s.entries)
                if (foldPhrase(e.words).contains(q)) e,
            ],
            lead: s.lead,
            tag: s.tag,
          ),
    ];
  }

  GlobalKey _keyOf(String id) => _keys[id] ??= GlobalKey();

  /// The section at the top of the page, marked on the left.
  void _followScroll() {
    // While a section chosen on the left is scrolled to, and when the page
    // has come to its end with the last sections short of the top, the
    // section chosen stays marked.
    if (_going) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 2 && _chosen != null) {
      if (_current != _chosen) setState(() => _current = _chosen);
      return;
    }
    _chosen = null;
    final viewport = _content.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null) return;
    String? top;
    for (final MapEntry(:key, :value) in _keys.entries) {
      final box = value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final dy = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (dy <= 80) top = key;
    }
    if (top != null && top != _current) setState(() => _current = top);
  }

  bool _going = false;
  String? _chosen;

  Future<void> _goTo(String id) async {
    setState(() => _current = _chosen = id);
    final target = _keys[id]?.currentContext;
    if (target == null) return;
    _going = true;
    try {
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } finally {
      _going = false;
    }
  }

  Widget _searchField() => TextField(
    key: const ValueKey('settings-search'),
    controller: _search,
    onChanged: (_) => setState(() {}),
    decoration: const InputDecoration(
      isDense: true,
      prefixIcon: Icon(Icons.search_rounded, size: 18),
      hintText: 'Ayar ara: tema, OCR, e-imza, UETS',
    ),
  );

  Widget _sectionView(BuildContext context, _Section s, bool wide) {
    final group = SettingsGroup(children: [for (final e in s.entries) e.child]);
    return Column(
      key: _keyOf(s.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide) ...[
          const SizedBox(height: 18),
          Text(
            s.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (s.lead != null)
            Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 10),
              child: Text(
                s.lead!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AgendaColors.muted,
                ),
              ),
            )
          else
            const SizedBox(height: 10),
        ] else
          SettingsSection(s.title.toUpperCase()),
        group,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = UyapMobileApi.instance;
    final uets = UetsApi.instance;
    final web = UyapWebService.instance;
    return ListenableBuilder(
      // The sessions are read where they live; the portals are started only
      // when one is used here, so that looking at the settings wakes none.
      listenable: Listenable.merge([
        widget.library,
        widget.appearance,
        ?PortalSync.started,
        mobile.session,
        uets.session,
        web.session,
      ]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 760;
          final all = _sections(context, wide);
          final shown = _shown(all);
          // Not built lazily: the list on the left goes to a section by
          // scrolling to it, which must be there to be gone to.
          final list = SingleChildScrollView(
            key: _content,
            controller: _scroll,
            padding: wide
                ? const EdgeInsets.fromLTRB(32, 4, 32, 40)
                : const EdgeInsets.fromLTRB(14, 12, 14, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!wide) ...[_searchField(), const SizedBox(height: 4)],
                // A release still to install stands above everything.
                ValueListenableBuilder(
                  valueListenable: UpdateCheck.instance.ready,
                  builder: (context, update, _) => update == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 4),
                          child: UpdateCard(update: update),
                        ),
                ),
                for (final s in shown) _sectionView(context, s, wide),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      'Bu sözcükle bir ayar bulunamadı.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AgendaColors.muted),
                    ),
                  ),
              ],
            ),
          );
          if (!wide) {
            return Scaffold(
              backgroundColor: settingsPage(context),
              appBar: widget.onBack == null
                  ? settingsBar(context, 'Ayarlar')
                  : AppBar(
                      leading: IconButton(
                        tooltip: 'Geri',
                        onPressed: widget.onBack,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      title: const Text('Ayarlar'),
                    ),
              body: list,
            );
          }
          final scheme = Theme.of(context).colorScheme;
          final current = _current ?? all.first.id;
          return Scaffold(
            backgroundColor: settingsPage(context),
            appBar: widget.onBack != null
                ? null
                : settingsBar(context, 'Ayarlar'),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border(
                      bottom: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (widget.onBack != null)
                        IconButton(
                          tooltip: 'Geri',
                          onPressed: widget.onBack,
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      const SizedBox(width: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Ayarlar',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (_version.isNotEmpty)
                            Text(
                              'LifeOS Folio $_version',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AgendaColors.muted,
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      SizedBox(width: 320, child: _searchField()),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 240,
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(color: scheme.outlineVariant),
                          ),
                        ),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                          children: [
                            for (final s in shown)
                              _navItem(context, s, s.id == current),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 920),
                            child: list,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _navItem(BuildContext context, _Section s, bool on) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        key: ValueKey('settings-nav-${s.id}'),
        borderRadius: BorderRadius.circular(9),
        onTap: () => unawaited(_goTo(s.id)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: on ? scheme.primary.withValues(alpha: .09) : null,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Icon(
                s.icon,
                size: 19,
                color: on ? scheme.primary : AgendaColors.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                    color: on ? scheme.primary : null,
                  ),
                ),
              ),
              if (s.tag != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    color: s.tag == 'yeni'
                        ? scheme.primary
                        : const Color(0xFFEAF7F1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s.tag!,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: s.tag == 'yeni'
                          ? Colors.white
                          : const Color(0xFF157A52),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
