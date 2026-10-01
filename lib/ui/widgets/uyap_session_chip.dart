import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/uyap/uyap_web_service.dart';

/// Who is logged into UYAP and for how much longer, with the way out. It
/// follows the session wherever it is shown: a session UYAP ends, or one
/// let go of in another window of Folio's, disappears from all of them.
class UyapSessionChip extends StatefulWidget {
  const UyapSessionChip({super.key, this.onDisconnected});

  /// Called after "Bağlantıyı kes", for the caller to clear what it loaded.
  final VoidCallback? onDisconnected;

  @override
  State<UyapSessionChip> createState() => _UyapSessionChipState();
}

class _UyapSessionChipState extends State<UyapSessionChip> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The time left, a minute at a time.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String left(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours == 0) return '$minutes dk';
    return minutes == 0 ? '$hours sa' : '$hours sa $minutes dk';
  }

  static String route(UyapLoginRoute route) => switch (route) {
    UyapLoginRoute.mobile => 'mobil imza',
    UyapLoginRoute.eSignature => 'e-imza, e-Devlet',
    UyapLoginRoute.tray => 'e-imza kartı',
  };

  @override
  Widget build(BuildContext context) {
    final web = UyapWebService.instance;
    return ValueListenableBuilder<UyapSession?>(
      valueListenable: web.session,
      builder: (context, session, _) {
        if (session == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        final remaining = session.remaining();
        final soon = remaining < const Duration(minutes: 10);
        return PopupMenuButton<String>(
          key: const ValueKey('uyap-session'),
          tooltip:
              'UYAP oturumu · ${route(session.route)} · '
              '${TimeOfDay.fromDateTime(session.since).format(context)}’den beri',
          onSelected: (value) async {
            switch (value) {
              case 'check':
                final alive = await web.check();
                if (!alive) widget.onDisconnected?.call();
              case 'disconnect':
                web.disconnect();
                widget.onDisconnected?.call();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'check', child: Text('Oturumu denetle')),
            PopupMenuItem(value: 'disconnect', child: Text('Bağlantıyı kes')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: soon ? scheme.errorContainer : scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 16,
                  color: soon
                      ? scheme.onErrorContainer
                      : scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'UYAP · ${session.user} · ${left(remaining)}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: soon
                          ? scheme.onErrorContainer
                          : scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
