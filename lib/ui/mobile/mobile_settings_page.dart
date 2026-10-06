import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/editor/editor_settings.dart';
import '../../services/editor/lawyer_profile.dart';
import '../../services/editor/snippets.dart';
import '../../services/legal/legal_settings.dart';
import '../../services/platform/document_intents.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/search/library_controller.dart';
import '../../services/uets/uets_api.dart';
import '../../services/uyap/uyap_mobile_api.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../widgets/uyap_connect_view.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import '../agenda/mobile_connect.dart';
import '../agenda/uets_connect.dart';
import '../theme/theme_controller.dart';
import '../widgets/default_viewer_dialog.dart';
import '../widgets/folio_about_dialog.dart';
import '../widgets/learned_phrases_dialog.dart';
import '../widgets/notice.dart';
import '../widgets/snippet_manager.dart';
import 'lawyer_profile_page.dart';
import 'settings_parts.dart';

/// The phone's settings, a page rather than a dialog (docs/design/mobil-
/// ayarlar-taslak.png): the lawyer first, then the connections, the
/// documents and the archive, the editor, the citations, the look.
class MobileSettingsPage extends StatefulWidget {
  const MobileSettingsPage({
    super.key,
    required this.library,
    required this.appearance,
  });

  final LibraryController library;
  final ThemeController appearance;

  static Future<void> open(
    BuildContext context, {
    required LibraryController library,
    required ThemeController appearance,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          MobileSettingsPage(library: library, appearance: appearance),
    ),
  );

  @override
  State<MobileSettingsPage> createState() => _MobileSettingsPageState();
}

/// "6 gün 22 sa", "1 sa 20 dk", "24 dk".
String _left(DateTime until) {
  final d = until.difference(DateTime.now());
  if (d.isNegative) return 'süresi doldu';
  if (d.inDays > 0) return '${d.inDays} gün ${d.inHours % 24} sa';
  if (d.inHours > 0) return '${d.inHours} sa ${d.inMinutes % 60} dk';
  return '${d.inMinutes} dk';
}

class _MobileSettingsPageState extends State<MobileSettingsPage> {
  LawyerProfile? _profile;
  int? _snippets;

  PortalSync get _sync => PortalSync.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    // A test reads no lawyer's real profile or snippets.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    final profile = await LawyerProfile.load();
    int? snippets;
    try {
      snippets = (await SnippetStore.shared()).all.length;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _profile = profile;
        _snippets = snippets;
      });
    }
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) await _load();
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
    ].join(' · ');
    return SettingsGroup(
      children: [
        InkWell(
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
                            ? 'Ad, baro ve sicil bilgilerinizi ekleyin'
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
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // The sessions are read where they live; the portals are started only
    // when one is used here, so that looking at the settings wakes none.
    final mobile = UyapMobileApi.instance;
    final uets = UetsApi.instance;
    final web = UyapWebService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.library,
        widget.appearance,
        ?PortalSync.started,
        mobile.session,
        uets.session,
        web.session,
      ]),
      builder: (context, _) {
        final library = widget.library;
        final folders = library.sources.where((s) => s.folder).toList();
        final documents = folders.fold<int>(0, (n, f) => n + f.count);
        final desktop =
            Platform.isLinux || Platform.isWindows || Platform.isMacOS;
        const off = Color(0xFF9AA2B1);
        return Scaffold(
          backgroundColor: settingsPage(context),
          appBar: settingsBar(context, 'Ayarlar'),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
            children: [
              _profileCard(context),
              const SettingsSection('BAĞLANTILAR'),
              SettingsGroup(
                children: [
                  SettingsRow(
                    key: const ValueKey('settings-uyap-mobile'),
                    icon: Icons.gavel_rounded,
                    fill: AgendaColors.eHearingFill,
                    tint: AgendaColors.eHearing,
                    title: 'UYAP Mobil',
                    status: mobile.connected ? AgendaColors.ok : off,
                    subtitle: mobile.connected
                        ? 'Bağlı · ${_left(mobile.session.value?.expires ?? DateTime.now())} geçerli'
                        : 'Bağlı değil',
                    onTap: () async {
                      if (mobile.connected) {
                        await _portalMenu(
                          name: 'UYAP Mobil',
                          sync: () => _sync.syncMobile(full: true),
                          disconnect: mobile.logout,
                        );
                      } else if (await connectUyapMobile(
                        context,
                        api: mobile,
                      )) {
                        unawaited(_sync.syncMobile());
                      }
                    },
                  ),
                  SettingsRow(
                    key: const ValueKey('settings-uyap-web'),
                    icon: Icons.account_balance_outlined,
                    title: 'UYAP Web',
                    status: web.connected ? AgendaColors.ok : off,
                    subtitle: web.connected
                        ? 'Bağlı · ${_left(DateTime.now().add(web.session.value?.remaining() ?? Duration.zero))} geçerli'
                        : 'Mobil imza ile, e-Devlet üzerinden',
                    onTap: () async {
                      if (web.connected) {
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
                    onTap: () async {
                      if (uets.connected) {
                        await _portalMenu(
                          name: 'UETS',
                          sync: _sync.syncUets,
                          disconnect: () async => uets.logout(),
                        );
                      } else {
                        await connectUets(
                          context,
                          api: uets,
                          secrets: _sync.secrets,
                        );
                      }
                    },
                  ),
                  SettingsRow(
                    key: const ValueKey('settings-sync'),
                    icon: Icons.sync_alt_rounded,
                    title: 'Bilgisayarla senkronla',
                    subtitle: 'QR ile, aynı ağda',
                    onTap: () => showNotice(
                      context,
                      'Bilgisayarla senkron hazırlanıyor',
                      detail:
                          'Masaüstünde “Telefonla senkronla” deyip QR’ı '
                          'okutarak eşitleyeceksiniz; bu özellik bir sonraki '
                          'sürümde.',
                    ),
                  ),
                ],
              ),
              const SettingsSection('BELGELER VE ARŞİV'),
              SettingsGroup(
                children: [
                  SettingsRow(
                    key: const ValueKey('settings-folders'),
                    icon: Icons.folder_outlined,
                    fill: const Color(0xFFFFF3E0),
                    tint: AgendaColors.task,
                    title: 'Arşiv klasörleri',
                    subtitle: folders.isEmpty
                        ? 'Henüz klasör eklenmedi'
                        : '${folders.length} klasör · $documents evrak',
                    onTap: () => _push(ArchiveFoldersPage(library: library)),
                  ),
                  SettingsRow(
                    icon: Icons.document_scanner_outlined,
                    title: 'Taranmış belgeleri oku (OCR)',
                    subtitle: desktop && library.ocrAvailable
                        ? 'Görsel ve taranmış PDF’lerde arama'
                        : 'Bu cihazda kullanılamıyor',
                    trailing: settingsSwitch(
                      library.ocrEnabled,
                      desktop && library.ocrAvailable
                          ? (v) => unawaited(library.setOcr(v))
                          : null,
                    ),
                  ),
                ],
              ),
              const SettingsSection('EDİTÖR'),
              SettingsGroup(
                children: [
                  SettingsRow(
                    icon: Icons.edit_outlined,
                    title: 'Yazarken öneri',
                    subtitle: 'Kalıplar ve öğrenilen ifadeler',
                    trailing: settingsSwitch(
                      EditorSettings.instance.suggestions,
                      (v) async {
                        await EditorSettings.instance.setSuggestions(v);
                        if (mounted) setState(() {});
                      },
                      key: const ValueKey('setting-suggestions'),
                    ),
                  ),
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
                  SettingsRow(
                    key: const ValueKey('settings-learning'),
                    icon: Icons.auto_awesome_outlined,
                    title: 'Öğrenme',
                    subtitle: 'Belgelerimden · arşivden · ifadeler',
                    onTap: () => _push(const LearningPage()),
                  ),
                ],
              ),
              const SettingsSection('ATIFLAR'),
              SettingsGroup(
                children: [
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
                  SettingsRow(
                    icon: Icons.translate_rounded,
                    title: 'Hukuk sözlüğü',
                    subtitle: 'Terimin anlamı, internetsiz',
                    trailing: settingsSwitch(
                      LegalSettings.instance.dictionary,
                      (v) async {
                        await LegalSettings.instance.setDictionary(v);
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SettingsSection('GÖRÜNÜM'),
              SettingsGroup(
                children: [
                  SettingsRow(
                    icon: Icons.contrast_rounded,
                    title: 'Tema',
                    trailing: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Beyaz'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Siyah'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('Sistem'),
                        ),
                      ],
                      selected: {widget.appearance.mode},
                      onSelectionChanged: (v) =>
                          widget.appearance.setMode(v.first),
                    ),
                  ),
                ],
              ),
              const SettingsSection('HAKKINDA'),
              SettingsGroup(
                children: [
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
                  SettingsRow(
                    icon: Icons.info_outline_rounded,
                    title: 'LifeOS Folio hakkında',
                    onTap: () => showFolioAbout(context),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The archive's folders, on a page: each with its documents, rescanned or
/// left out; a folder added; all brought up to date.
class ArchiveFoldersPage extends StatefulWidget {
  const ArchiveFoldersPage({super.key, required this.library});
  final LibraryController library;

  @override
  State<ArchiveFoldersPage> createState() => _ArchiveFoldersPageState();
}

class _ArchiveFoldersPageState extends State<ArchiveFoldersPage> {
  bool _picking = false;

  Future<void> _add() async {
    setState(() => _picking = true);
    try {
      final path = await DocumentIntents.pickFolder();
      if (path != null && mounted) {
        await widget.library.addPaths([path], recursive: true);
      }
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Klasör eklenemedi',
          detail: '$e',
          kind: NoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.library, widget.library.progress]),
    builder: (context, _) {
      final library = widget.library;
      final folders = library.sources.where((s) => s.folder).toList();
      return Scaffold(
        backgroundColor: settingsPage(context),
        appBar: settingsBar(
          context,
          'Arşiv klasörleri',
          action: library.active
              ? TextButton(
                  onPressed: library.cancel,
                  child: const Text('Durdur'),
                )
              : folders.isEmpty
              ? null
              : TextButton(
                  onPressed: () => library.refresh(),
                  child: const Text('Güncelle'),
                ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            FilledButton.icon(
              key: const ValueKey('folders-add'),
              onPressed: _picking ? null : _add,
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('Klasör ekle'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (library.active) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: library.toProcess == 0
                    ? null
                    : library.processed / library.toProcess,
              ),
              const SizedBox(height: 6),
              Text(
                '${library.phase} · ${library.processed}/${library.toProcess}',
                style: const TextStyle(fontSize: 11, color: AgendaColors.muted),
              ),
            ],
            const SettingsSection('KLASÖRLER'),
            if (folders.isEmpty)
              const SettingsGroup(
                padding: EdgeInsets.all(18),
                children: [
                  Text(
                    'Henüz klasör eklenmedi. Eklediğiniz klasörlerdeki '
                    'belgeler aranabilir olur; belgeler yerinde kalır.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
                  ),
                ],
              )
            else
              SettingsGroup(
                children: [
                  for (final f in folders)
                    SettingsRow(
                      icon: Icons.folder_outlined,
                      fill: const Color(0xFFFFF3E0),
                      tint: AgendaColors.task,
                      title: f.name,
                      subtitle: f.error ?? '${f.count} evrak · ${f.path}',
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) => v == 'refresh'
                            ? library.refresh(ids: [f.id])
                            : library.removeSource(f.id),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'refresh',
                            child: Text('Yeniden tara'),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text('Arşivden çıkar'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 12, 6, 0),
              child: Text(
                'Arşivden çıkarmak dosyaları silmez.',
                style: TextStyle(fontSize: 12, color: AgendaColors.muted),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// What the suggestions learn from, and what they have learned.
class LearningPage extends StatefulWidget {
  const LearningPage({super.key});

  @override
  State<LearningPage> createState() => _LearningPageState();
}

class _LearningPageState extends State<LearningPage> {
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: settingsPage(context),
    appBar: settingsBar(context, 'Öğrenme'),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        SettingsGroup(
          children: [
            SettingsRow(
              icon: Icons.save_outlined,
              title: 'Kaydettiğim belgelerden öğren',
              subtitle: 'Bir belge bir kez sayılır',
              trailing: settingsSwitch(EditorSettings.instance.learnSaved, (
                v,
              ) async {
                await EditorSettings.instance.setLearnSaved(v);
                if (mounted) setState(() {});
              }, key: const ValueKey('setting-learn-saved')),
            ),
            SettingsRow(
              icon: Icons.inventory_2_outlined,
              title: 'Arşivden öğren',
              subtitle: 'En az üç belgede geçen ifadeler, haftada bir',
              trailing: settingsSwitch(EditorSettings.instance.learnArchive, (
                v,
              ) async {
                await EditorSettings.instance.setLearnArchive(v);
                if (mounted) setState(() {});
              }, key: const ValueKey('setting-learn-archive')),
            ),
            SettingsRow(
              icon: Icons.auto_awesome_outlined,
              title: 'Öğrenilen ifadeler',
              subtitle: 'Görün, silin',
              onTap: () => LearnedPhrasesDialog.show(context),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(6, 12, 6, 0),
          child: Text(
            'Kişisel bilgi içeren ifadeler öğrenilmez; hepsi bu cihazda kalır.',
            style: TextStyle(fontSize: 12, color: AgendaColors.muted),
          ),
        ),
      ],
    ),
  );
}
