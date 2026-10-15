import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/portal/case_sections.dart';
import '../../services/portal/portal_channel.dart';
import '../../services/portal/portal_database.dart';
import '../../services/portal/portal_sync.dart';
import '../../services/portal/sync_log.dart';
import '../../services/portal/uyap_job.dart';
import '../../services/portal/uyap_status.dart';
import '../../services/uyap/uyap_case_store.dart';
import '../agenda/mobile_connect.dart';
import '../widgets/uyap_connect_view.dart';
import 'portfolio_rows.dart' show dayText;
import 'uyap_setup_dialog.dart';

/// What Folio holds of UYAP and what its readings did, for the lawyer to
/// follow them: the portfolio's list, the cases read one by one and those
/// never read, the sections that would not come, the job running and the
/// log's last lines. The cases never read are filled from here
/// ([PortalSync.startFill]). Nothing is asked of UYAP to show it.
class UyapStatusDialog extends StatefulWidget {
  const UyapStatusDialog({super.key, this.sync, this.database, this.store});

  final PortalSync? sync;
  final PortalDatabase? database;
  final UyapCaseStore? store;

  static Future<void> show(
    BuildContext context, {
    PortalSync? sync,
    PortalDatabase? database,
    UyapCaseStore? store,
  }) => showDialog<void>(
    context: context,
    builder: (_) =>
        UyapStatusDialog(sync: sync, database: database, store: store),
  );

  @override
  State<UyapStatusDialog> createState() => _UyapStatusDialogState();
}

class _UyapStatusDialogState extends State<UyapStatusDialog> {
  PortalSync get _sync => widget.sync ?? PortalSync.instance;
  UyapStatus? _status;
  List<String> _log = const [];
  bool _starting = false;
  Timer? _again;

  /// "Son haber" told again as time goes: another own device's job.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sync.addListener(_changed);
    _sync.job.addListener(_changed);
    _sync.jobClaim.addListener(_changed);
    _sync.jobProgress.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _sync.jobElsewhere) setState(() {});
    });
    unawaited(_read());
  }

  @override
  void dispose() {
    _again?.cancel();
    _tick?.cancel();
    _sync.removeListener(_changed);
    _sync.job.removeListener(_changed);
    _sync.jobClaim.removeListener(_changed);
    _sync.jobProgress.removeListener(_changed);
    super.dispose();
  }

  /// Drawn again at once; counted again a little after, not at every case.
  void _changed() {
    if (!mounted) return;
    setState(() {});
    _again ??= Timer(const Duration(seconds: 3), () {
      _again = null;
      unawaited(_read());
    });
  }

  Future<void> _read() async {
    try {
      final status = await readUyapStatus(
        database: widget.database,
        store: widget.store,
      );
      final log = await SyncLog.tail(14);
      if (mounted) {
        setState(() {
          _status = status;
          _log = log;
        });
      }
    } catch (_) {}
  }

  Future<void> _fill({required bool web}) async {
    setState(() => _starting = true);
    try {
      if (web && !_sync.web.connected) {
        await connectUyapWeb(context);
      } else if (!web && !_sync.mobile.connected) {
        await connectUyapMobile(context, api: _sync.mobile);
      }
      // The job runs on; the dialog follows it.
      unawaited(
        _sync.startFill(
          channel: web ? PortalChannel.uyapWeb : PortalChannel.uyapMobile,
        ),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  static String _at(DateTime at) {
    final l = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dayText(l)} ${two(l.hour)}:${two(l.minute)}';
  }

  static String _name(PortalChannel c) => switch (c) {
    PortalChannel.uyapWeb => 'UYAP Web',
    PortalChannel.uyapMobile => 'UYAP Mobil',
    PortalChannel.uets => 'UETS',
  };

  static String _section(CaseSection s) => switch (s) {
    CaseSection.particulars => 'künye',
    CaseSection.parties => 'taraflar',
    CaseSection.documents => 'evrak listesi',
    CaseSection.money => 'para',
    CaseSection.account => 'icra hesabı',
    CaseSection.debtors => 'borçlular',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _status;
    final job = _sync.job.value;
    final muted = TextStyle(fontSize: 13, color: scheme.onSurfaceVariant);
    final warn = TextStyle(fontSize: 13, color: scheme.error);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    );
    Widget line(String text, {TextStyle? style, Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(text, key: key, style: style),
    );

    final List<Widget> body;
    if (s == null) {
      body = const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else {
      final running = [
        for (final c in [PortalChannel.uyapMobile, PortalChannel.uyapWeb])
          if (_sync.state(c).running) c,
      ];
      final fillRuns = job != null && !job.done && job.stopped == null;
      final mobileCount = s.documentsMissing.length - s.documentsMissingWebOnly;
      body = [
        heading('Portföy listesi'),
        line(
          s.listWhole == null
              ? 'Liste hiç eksiksiz okunmadı.'
              : 'Son eksiksiz okuma: ${_at(s.listWhole!)}',
          key: const ValueKey('uyap-status-list'),
        ),
        if (s.listTried != null)
          line(
            'Son deneme eksik kaldı: ${_at(s.listTried!)} (bazı listeler '
            'alınamadı).',
            style: warn,
          ),
        for (final MapEntry(key: c, value: at) in s.listStarted.entries)
          if (!running.contains(c))
            line(
              '${_name(c)} ile ${_at(at)}’de başlayan okuma bitmedi: Folio '
              'kapandı ya da okuma kesildi. “Portföyü yenile” baştan dener.',
              key: ValueKey('uyap-status-unfinished-${c.name}'),
              style: warn,
            ),
        for (final c in running)
          line(
            'Şimdi ${_name(c)} okuyor'
            '${_sync.state(c).progress == null ? '' : ': ${_sync.state(c).progress}'}',
            style: muted,
          ),
        heading('Dosyalar · ${s.open} açık'),
        line(
          'Evrak listesi gelen: ${s.open - s.documentsMissing.length}',
          key: const ValueKey('uyap-status-read'),
        ),
        if (s.read - (s.open - s.documentsMissing.length) case final n
            when n > 0)
          line(
            'Yalnız tarafları okunan: $n (evrak listesi henüz gelmedi)',
            key: const ValueKey('uyap-status-parties-only'),
            style: warn,
          ),
        if (s.unread.isNotEmpty)
          line(
            'Hiç okunmamış: ${s.unread.length} (künye ve listeden gelen '
            'taraflar var)',
            key: const ValueKey('uyap-status-unread'),
            style: warn,
          ),
        line(
          s.documentsMissing.isEmpty
              ? 'Evrak listesi gelmemiş dosya yok.'
              : 'Evrak listesi gelmemiş toplam: '
                    '${s.documentsMissing.length}',
          key: const ValueKey('uyap-status-documents-missing'),
          style: s.documentsMissing.isEmpty ? null : warn,
        ),
        line(
          'Para UYAP Web’den gelen: ${s.open - s.webMissing.length}',
          style: muted,
        ),
        line(
          s.webMissing.isEmpty
              ? 'Parası UYAP Web’den gelmemiş dosya yok.'
              : 'Parası UYAP Web’den gelmemiş: ${s.webMissing.length}',
          key: const ValueKey('uyap-status-web-missing'),
          style: s.webMissing.isEmpty ? null : warn,
        ),
        if ((mobileCount > 0 || s.webMissing.isNotEmpty) && !fillRuns) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (mobileCount > 0)
                FilledButton.icon(
                  key: const ValueKey('uyap-status-fill'),
                  // Pressed while the list is read, it waits for the list.
                  onPressed: _starting
                      ? null
                      : () => unawaited(_fill(web: false)),
                  icon: const Icon(Icons.phone_iphone_rounded, size: 18),
                  label: Text('UYAP Mobil ile tamamla ($mobileCount)'),
                ),
              if (s.webMissing.isNotEmpty)
                OutlinedButton.icon(
                  key: const ValueKey('uyap-status-fill-web'),
                  onPressed: _starting
                      ? null
                      : () => unawaited(_fill(web: true)),
                  icon: const Icon(Icons.public_rounded, size: 18),
                  label: Text('UYAP Web ile tamamla (${s.webMissing.length})'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (running.isNotEmpty)
            line(
              'Portföy listesi okunuyor: tamamlama başlatılırsa liste '
              'bitince kendiliğinden başlar.',
              style: muted,
            ),
          if (mobileCount > 0)
            line(
              'UYAP Mobil: evrak listesi gelmemiş dosyaların evrak listeleri '
              've okunmamış tarafları; hızlı. Para gelmez.'
              '${s.documentsMissingWebOnly > 0 ? ' ${s.documentsMissingWebOnly} Yargıtay/savcılık dosyası UYAP Web’i bekler.' : ''}',
              style: muted,
            ),
          if (s.webMissing.isNotEmpty)
            line(
              'UYAP Web: yalnız parası gelmemiş dosyalar; künye, vekilleriyle '
              'taraflar, para, icra hesabı ve borçlular (mobilden tam gelen '
              'evrak listesi yeniden istenmez). Dosya başına ~10 sn.',
              style: muted,
            ),
          line(
            'Liste yeniden okunmaz; kesilirse kaldığı yerden sürer. Web '
            'bağlıyken bir dosyayı açmak da o dosyanın eskiyen bilgilerini '
            'tazeler.',
            style: muted,
          ),
        ],
        if (s.failed.isNotEmpty) ...[
          heading('Okunamayanlar · ${s.failed.length} bölüm'),
          for (final f in s.failed.take(8))
            line(
              '${f.number} ${f.court} · ${_section(f.section)} '
              '(${_name(f.channel)}, ${f.tries} deneme)',
              style: muted,
            ),
          if (s.failed.length > 8)
            line('ve ${s.failed.length - 8} bölüm daha', style: muted),
        ],
        if (job != null) ...[
          heading('Süren iş · ${PortalSync.jobName(job.kind)}'),
          line(_jobLine(job), style: muted),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('uyap-status-job'),
              onPressed: () => unawaited(
                UyapSetupDialog.show(
                  context,
                  sync: widget.sync,
                  database: widget.database,
                ),
              ),
              child: Text(
                _sync.jobElsewhere
                    ? 'Ayrıntı ya da bu bilgisayarda devral'
                    : 'Ayrıntı, duraklat ya da sürdür',
              ),
            ),
          ),
          // Its cases read there come here with the own devices' sync.
          if (_sync.jobElsewhere)
            line(
              'Yukarıdaki sayılar bu bilgisayarın bildikleri; öbür '
              'bilgisayarın okudukları eşitlemeyle gelir.',
              style: muted,
            ),
        ],
        heading('Son kayıtlar'),
        if (_log.isEmpty)
          line('Kayıt yok.', style: muted)
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              _log.reversed.join('\n'),
              style: const TextStyle(fontSize: 11.5, height: 1.4),
            ),
          ),
      ];
    }
    return AlertDialog(
      key: const ValueKey('uyap-status'),
      title: const Text('UYAP durumu'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: body,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => unawaited(_read()),
          child: const Text('Yenile'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    );
  }

  String _jobLine(UyapJob job) {
    final progress = _sync.jobProgressShown;
    final elsewhere = _sync.jobElsewhere;
    final stage = switch (job.stage) {
      UyapJobStage.list => 'portföy listesi',
      UyapJobStage.parties => 'taraflar',
      UyapJobStage.documents => 'evrak listeleri',
      UyapJobStage.web => 'web bilgileri',
      UyapJobStage.done => 'bitti',
    };
    final count = progress != null && progress.total > 0
        ? ' ${progress.done}/${progress.total}'
        : '';
    final why = switch (job.stopped) {
      null when job.done => '',
      null when elsewhere && !_sync.jobRunningElsewhere() =>
        ' · haber gelmiyor',
      null when elsewhere => ' · sürüyor',
      // Its own reading not begun, the channel's list reading still is.
      null when progress == null && _sync.state(job.channel).running =>
        ' · liste okuması bitince başlar',
      null => ' · sürüyor',
      UyapJobStop.user => ' · duraklatıldı',
      UyapJobStop.session => ' · ${_name(job.channel)} oturumu bekleniyor',
      UyapJobStop.incomplete => ' · bazı dosyalar okunamadı',
    };
    final word = _sync.jobLastWord;
    final owner = _sync.jobClaim.value?.ownerName ?? '';
    return elsewhere
        ? '${owner.isEmpty ? 'Öbür bilgisayarınız' : owner} · '
              '${_name(job.channel)} · $stage$count$why'
              '${word == null ? '' : ' · son haber ${lastWordText(word)}'}'
        : '${_name(job.channel)} · $stage$count$why';
  }
}
