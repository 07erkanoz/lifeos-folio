import 'package:flutter/material.dart';

import '../../services/portal/portal_sync.dart';
import '../agenda/agenda_page.dart' show AgendaColors;

/// The phone's menu (docs/design/mobil-anasayfa-taslak.png): the first
/// page; the office with what waits in each place; the documents; the
/// portals and the sync with the computer; the settings at the foot.
class MobileDrawer extends StatelessWidget {
  const MobileDrawer({
    super.key,
    required this.group,
    required this.home,
    required this.onHome,
    required this.onGroup,
    required this.onFolders,
    required this.onSettings,
    required this.onConnectMobile,
    required this.onConnectWeb,
    required this.onConnectUets,
    required this.onSyncComputer,
    this.agendaToday = 0,
    this.uetsUnread = 0,
    this.uyapNotices = 0,
    this.uyapCases = 0,
    this.sync,
  });

  /// The place shown; [home] when the first page is.
  final String group;
  final bool home;
  final VoidCallback onHome, onFolders, onSettings;
  final ValueChanged<String> onGroup;
  final VoidCallback onConnectMobile, onConnectWeb, onConnectUets;
  final VoidCallback onSyncComputer;
  final int agendaToday, uetsUnread, uyapCases, uyapNotices;
  final PortalSync? sync;

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: .8,
        color: AgendaColors.muted,
      ),
    ),
  );

  Widget _item(
    BuildContext context, {
    required Key key,
    required Widget icon,
    required String label,
    bool selected = false,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? const Color(0xFFEAF0F9) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                IconTheme(
                  data: IconThemeData(
                    size: 20,
                    color: selected ? colors.primary : const Color(0xFF5A6273),
                  ),
                  child: SizedBox(width: 22, child: Center(child: icon)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected ? colors.primary : null,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color fill, Color ink) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink),
    ),
  );

  Widget _dot(Color color) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  @override
  Widget build(BuildContext context) {
    final portals = sync ?? PortalSync.started;
    return Drawer(
      width: 300,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            ?portals,
            ?portals?.mobile.session,
            ?portals?.uets.session,
            ?portals?.web.session,
          ]),
          builder: (context, _) {
            final mobile = portals?.mobile.connected ?? false;
            final web = portals?.web.connected ?? false;
            final uets = portals?.uets.connected ?? false;
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(10, 6, 10, 14),
                    child: Text(
                      'LifeOS Folio',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _item(
                          context,
                          key: const ValueKey('drawer-home'),
                          icon: const Icon(Icons.home_outlined),
                          label: 'Anasayfa',
                          selected: home,
                          onTap: onHome,
                        ),
                        _section('BÜRO'),
                        _item(
                          context,
                          key: const ValueKey('drawer-agenda'),
                          icon: const Icon(Icons.event_note_rounded),
                          label: 'Ajanda',
                          selected: !home && group == 'agenda',
                          trailing: agendaToday > 0
                              ? _pill(
                                  'Bugün $agendaToday',
                                  AgendaColors.hearing,
                                  Colors.white,
                                )
                              : null,
                          onTap: () => onGroup('agenda'),
                        ),
                        _item(
                          context,
                          key: const ValueKey('drawer-notices'),
                          icon: const Icon(Icons.notifications_outlined),
                          label: 'UYAP Bildirimleri',
                          selected: !home && group == 'bildirim',
                          trailing: uyapNotices > 0
                              ? _pill(
                                  '$uyapNotices',
                                  AgendaColors.hearing,
                                  Colors.white,
                                )
                              : null,
                          onTap: () => onGroup('bildirim'),
                        ),
                        _item(
                          context,
                          key: const ValueKey('drawer-uets'),
                          icon: const Icon(Icons.mark_email_unread_outlined),
                          label: 'UETS Tebligatlarım',
                          selected: !home && group == 'uets',
                          trailing: uetsUnread > 0
                              ? _pill(
                                  '$uetsUnread',
                                  AgendaColors.deadline,
                                  Colors.white,
                                )
                              : null,
                          onTap: () => onGroup('uets'),
                        ),
                        _item(
                          context,
                          key: const ValueKey('drawer-office'),
                          icon: const Icon(Icons.lan_outlined),
                          label: 'Büro ağı',
                          selected: !home && group == 'buro',
                          onTap: () => onGroup('buro'),
                        ),
                        _item(
                          context,
                          key: const ValueKey('drawer-uyap'),
                          icon: const Icon(Icons.gavel_rounded),
                          label: 'UYAP Dosyalarım',
                          selected:
                              !home &&
                              (group == 'uyap' || group.startsWith('uyap:')),
                          trailing: uyapCases > 0
                              ? _pill(
                                  '$uyapCases',
                                  const Color(0xFFEEF1F6),
                                  const Color(0xFF4B5465),
                                )
                              : null,
                          onTap: () => onGroup('uyap'),
                        ),
                        _section('BELGELER'),
                        _item(
                          context,
                          key: const ValueKey('drawer-all'),
                          icon: const Icon(Icons.grid_view_rounded),
                          label: 'Tüm Evraklar',
                          selected: !home && group == 'all',
                          onTap: () => onGroup('all'),
                        ),
                        _item(
                          context,
                          key: const ValueKey('drawer-gallery'),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: 'Galeri',
                          selected: !home && group == 'images',
                          onTap: () => onGroup('images'),
                        ),
                        _item(
                          context,
                          key: const ValueKey('drawer-folders'),
                          icon: const Icon(Icons.folder_outlined),
                          label: 'Klasörler',
                          onTap: onFolders,
                        ),
                        _section('BAĞLANTILAR'),
                        _item(
                          context,
                          key: const ValueKey('drawer-web'),
                          icon: _dot(
                            web ? AgendaColors.ok : const Color(0xFF9AA2B1),
                          ),
                          label: web ? 'UYAP Web · bağlı' : 'UYAP Web · bağlan',
                          onTap: onConnectWeb,
                        ),
                        _item(
                          context,
                          key: const ValueKey('drawer-mobile'),
                          icon: _dot(
                            mobile ? AgendaColors.ok : const Color(0xFF9AA2B1),
                          ),
                          label: mobile
                              ? 'UYAP Mobil · bağlı'
                              : 'UYAP Mobil · bağlan',
                          onTap: onConnectMobile,
                        ),
                        _item(
                          context,
                          key: const ValueKey('drawer-uets-connect'),
                          icon: _dot(
                            uets ? AgendaColors.ok : const Color(0xFF9AA2B1),
                          ),
                          label: uets ? 'UETS · bağlı' : 'UETS · bağlan',
                          onTap: onConnectUets,
                        ),
                        _item(
                          context,
                          key: const ValueKey('drawer-sync'),
                          icon: const Icon(Icons.sync_alt_rounded),
                          label: 'Bilgisayarla senkronla',
                          onTap: onSyncComputer,
                        ),
                      ],
                    ),
                  ),
                  _item(
                    context,
                    key: const ValueKey('drawer-settings'),
                    icon: const Icon(Icons.settings_outlined),
                    label: 'Ayarlar',
                    onTap: onSettings,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
