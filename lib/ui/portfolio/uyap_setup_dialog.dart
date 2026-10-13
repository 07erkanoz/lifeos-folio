import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/portal/portal_channel.dart';
import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/portal/uyap_job.dart';
import '../agenda/mobile_connect.dart';
import '../widgets/uyap_connect_view.dart';

/// The first setup and the web's completion, as the lawyer starts and
/// follows them (docs/uyap-hedef-harita.md §6): UYAP Mobil recommended,
/// the web after it for what only the web has. Closed, the job goes on;
/// opened again, it shows how far it has come.
class UyapSetupDialog extends StatefulWidget {
  const UyapSetupDialog({super.key, this.sync, this.database});

  final PortalSync? sync;
  final PortalDatabase? database;

  static bool _showing = false;

  /// Shown unless it already is.
  static Future<void> show(
    BuildContext context, {
    PortalSync? sync,
    PortalDatabase? database,
  }) async {
    if (_showing) return;
    _showing = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => UyapSetupDialog(sync: sync, database: database),
      );
    } finally {
      _showing = false;
    }
  }

  @override
  State<UyapSetupDialog> createState() => _UyapSetupDialogState();
}

class _UyapSetupDialogState extends State<UyapSetupDialog> {
  PortalSync get _sync => widget.sync ?? PortalSync.instance;
  int? _cases;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _sync.job.addListener(_changed);
    _sync.jobProgress.addListener(_changed);
    _sync.addListener(_changed);
    unawaited(_count());
  }

  @override
  void dispose() {
    _sync.job.removeListener(_changed);
    _sync.jobProgress.removeListener(_changed);
    _sync.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_sync.job.value?.done ?? false) unawaited(_count());
  }

  Future<void> _count() async {
    try {
      final db = widget.database ?? await PortalDatabase.shared();
      final open = db.cases().values.where(
        (c) => !isClosedStatus(c.status?.value),
      );
      if (mounted) setState(() => _cases = open.length);
    } catch (_) {}
  }

  Future<void> _start(PortalChannel channel) async {
    setState(() => _connecting = true);
    try {
      final web = channel == PortalChannel.uyapWeb;
      if (web && !_sync.web.connected) {
        await connectUyapWeb(context);
      } else if (!web && !_sync.mobile.connected) {
        await connectUyapMobile(context, api: _sync.mobile);
      }
      final connected = web ? _sync.web.connected : _sync.mobile.connected;
      if (!connected) return;
      unawaited(_sync.startSetup(channel));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _completeOnWeb() async {
    setState(() => _connecting = true);
    try {
      if (!_sync.web.connected) await connectUyapWeb(context);
      if (!_sync.web.connected) return;
      unawaited(_sync.startWebCompletion());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _sync.job.value;
    final (title, body, actions) = switch (job) {
      null => _welcome(context),
      UyapJob(kind: UyapJobKind.setup, done: true) => _setupDone(context),
      UyapJob(kind: UyapJobKind.webCompletion, done: true) => (
        'Web bilgileri tamamlandı',
        const Text(
          'Para, icra hesabı, borçlular ve Yargıtay dosyaları UYAP Web’den '
          'geldi. Bundan sonra bir dosyayı açtığınızda eskiyen bilgileri '
          'tazelenir.',
        ),
        [
          FilledButton(
            onPressed: () {
              unawaited(_sync.dropJob());
              Navigator.pop(context);
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
      final UyapJob running => _running(context, running),
    };
    return AlertDialog(
      key: const ValueKey('uyap-setup'),
      title: Text(title),
      content: SizedBox(width: 520, child: body),
      actions: actions,
    );
  }

  (String, Widget, List<Widget>) _welcome(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget choice({
      required Key key,
      required IconData icon,
      required String title,
      required String note,
      required PortalChannel channel,
      bool recommended = false,
    }) => Expanded(
      child: OutlinedButton(
        key: key,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.all(14),
          side: BorderSide(
            color: recommended ? scheme.primary : scheme.outlineVariant,
            width: recommended ? 2 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.topLeft,
        ),
        onPressed: _connecting ? null : () => unawaited(_start(channel)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (recommended)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Önerilen',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              note,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
    return (
      'Dosyalarınızı UYAP’tan getirelim',
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'UYAP Mobil ile başlamanızı öneririz: dosya listeniz, '
            'müvekkilleriniz ve evrak listeleri gelir. UYAP Web daha sonra '
            'Yargıtay dosyalarını ekler; tahsilat, reddiyat, icra hesabı ve '
            'borçluları tamamlar.',
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              choice(
                key: const ValueKey('uyap-setup-mobile'),
                icon: Icons.phone_iphone_rounded,
                title: 'UYAP Mobil ile başla',
                note: 'Hızlı · 500 dosyada yaklaşık 40 dk',
                channel: PortalChannel.uyapMobile,
                recommended: true,
              ),
              const SizedBox(width: 12),
              choice(
                key: const ValueKey('uyap-setup-web'),
                icon: Icons.public_rounded,
                title: 'UYAP Web ile başla',
                note: 'Daha yavaş, aynı sonuç',
                channel: PortalChannel.uyapWeb,
              ),
            ],
          ),
        ],
      ),
      [
        TextButton(
          key: const ValueKey('uyap-setup-later'),
          onPressed: () {
            PortalSync.setupOffer.value = false;
            Navigator.pop(context);
          },
          child: const Text('Şimdilik geç'),
        ),
      ],
    );
  }

  (String, Widget, List<Widget>) _running(BuildContext context, UyapJob job) {
    final scheme = Theme.of(context).colorScheme;
    final progress = _sync.jobProgress.value;
    final setup = job.kind == UyapJobKind.setup;
    final stages = setup
        ? const [
            (UyapJobStage.list, 'Portföy listesi ve duruşmalar'),
            (UyapJobStage.parties, 'Taraflar ve müvekkiller'),
            (UyapJobStage.documents, 'Evrak listeleri'),
          ]
        : const [
            (UyapJobStage.list, 'Yargıtay dosyaları'),
            (UyapJobStage.web, 'Para, icra hesabı, borçlular, vekiller'),
          ];
    final at = stages.indexWhere((s) => s.$1 == job.stage);
    final channelName = job.channel == PortalChannel.uyapWeb
        ? 'UYAP Web'
        : 'UYAP Mobil';
    final listProgress = _sync.state(job.channel).progress;
    Widget row(int i, UyapJobStage stage, String name) {
      final done = i < at;
      final now = i == at;
      final counted = now && progress != null && progress.stage == stage;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  done
                      ? Icons.check_circle_rounded
                      : now
                      ? Icons.autorenew_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: done
                      ? Colors.green.shade600
                      : now
                      ? scheme.primary
                      : scheme.outline,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(name)),
                Text(
                  counted && progress.total > 0
                      ? '${progress.done} / ${progress.total}'
                      : now && stage == UyapJobStage.list
                      ? listProgress ?? ''
                      : done
                      ? 'tamam'
                      : 'sırada',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            if (counted && progress.total > 0)
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 6),
                child: LinearProgressIndicator(
                  value: progress.done / progress.total,
                ),
              ),
          ],
        ),
      );
    }

    final left = progress == null || progress.total == 0
        ? null
        : progress.total - progress.done;
    final perCase = setup ? 4 : 10;
    final note = switch (job.stopped) {
      UyapJobStop.user => 'Duraklatıldı. Okunan dosyalar kayıtlı.',
      UyapJobStop.session =>
        '$channelName oturumu kapandı. Yeniden bağlandığınızda kaldığı '
            'yerden sürer.',
      null =>
        '${left == null ? '' : 'Kalan yaklaşık ${_minutes(left * perCase)} · '}'
            'Folio’yu kullanmaya devam edebilirsiniz; kesilirse kaldığı '
            'yerden sürer.',
    };
    final paused = job.stopped != null;
    return (
      setup ? '$channelName’den getiriliyor' : 'UYAP Web ile tamamlanıyor',
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, (stage, name)) in stages.indexed) row(i, stage, name),
          const SizedBox(height: 10),
          Text(
            note,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
        if (paused)
          FilledButton(
            key: const ValueKey('uyap-setup-resume'),
            onPressed:
                job.stopped == UyapJobStop.session &&
                    !(job.channel == PortalChannel.uyapWeb
                        ? _sync.web.connected
                        : _sync.mobile.connected)
                ? null
                : () => unawaited(_sync.resumeJob()),
            child: const Text('Sürdür'),
          )
        else
          OutlinedButton(
            key: const ValueKey('uyap-setup-pause'),
            onPressed: () => unawaited(_sync.pauseJob()),
            child: const Text('Duraklat'),
          ),
      ],
    );
  }

  (String, Widget, List<Widget>) _setupDone(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = _cases;
    final perCase = 10;
    return (
      '${n == null ? 'Dosyalarınız' : '$n dosya'} ve evrak listeleri geldi',
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Para, icra hesabı, borçlular ve Yargıtay dosyaları UYAP Web’den '
            'gelir. Siz başlatınca sırayla okunur: önce duruşması yakın ve '
            'icra dosyaları.',
          ),
          if (n != null && n > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Tahmini süre: ${_minutes(n * perCase)}. Web oturumu kapanırsa '
              'sonraki girişte kaldığı yerden sürer.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
      [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Sonra'),
        ),
        FilledButton.icon(
          key: const ValueKey('uyap-setup-web-complete'),
          onPressed: _connecting ? null : () => unawaited(_completeOnWeb()),
          icon: const Icon(Icons.public_rounded, size: 18),
          label: const Text('UYAP Web ile tamamla'),
        ),
      ],
    );
  }

  static String _minutes(int seconds) {
    final m = (seconds / 60).ceil();
    if (m < 60) return '$m dk';
    final h = m ~/ 60, rest = m % 60;
    return rest == 0 ? '$h sa' : '$h sa $rest dk';
  }
}
