import 'package:flutter/material.dart';

import '../../services/speech/speech_models.dart';

/// Asks before fetching a voice model, then shows it coming. The model is
/// fetched once; after that the feature asks nothing.
class SpeechDownloadDialog extends StatefulWidget {
  const SpeechDownloadDialog({
    super.key,
    required this.model,
    required this.store,
  });

  final SpeechModel model;
  final SpeechModelStore store;

  /// The folder [model] is in: at once when it is already here, after the
  /// question and the download when it is not, null when it was declined.
  static Future<String?> ensure(
    BuildContext context,
    SpeechModel model, {
    SpeechModelStore? store,
  }) async {
    final s = store ?? SpeechModelStore.instance;
    final path = await s.installed(model);
    if (path != null || !context.mounted) return path;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SpeechDownloadDialog(model: model, store: s),
    );
  }

  @override
  State<SpeechDownloadDialog> createState() => _SpeechDownloadDialogState();
}

class _SpeechDownloadDialogState extends State<SpeechDownloadDialog> {
  bool _started = false;
  int _received = 0;
  String? _error;
  DownloadCancel? _cancel;

  Future<void> _download() async {
    final cancel = _cancel = DownloadCancel();
    setState(() {
      _started = true;
      _error = null;
    });
    try {
      final path = await widget.store.download(
        widget.model,
        cancel: cancel,
        progress: (received, _) {
          if (mounted) setState(() => _received = received);
        },
      );
      if (mounted) Navigator.pop(context, path);
    } on DownloadCancelled {
      // Closed by the İptal button already.
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final total = model.size;
    final share = total == 0 ? 0.0 : _received / total;
    final downloading = _started && _error == null;
    return AlertDialog(
      icon: Icon(
        model == SpeechModel.dictation
            ? Icons.mic_none_rounded
            : Icons.record_voice_over_outlined,
      ),
      title: Text(model.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${model.need} (${megabytes(total)}). Model yalnızca bir kez '
              'indirilir ve bilgisayarınızda saklanır. ${model.offline}',
            ),
            const SizedBox(height: 10),
            Text('Model lisansı: ${model.license}', style: muted),
            if (_started) ...[
              const SizedBox(height: 18),
              LinearProgressIndicator(
                key: const ValueKey('speech-download-progress'),
                value: share,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 8),
              Text(
                '${megabytes(_received)} / ${megabytes(total)} · '
                '%${(share * 100).floor()}',
                style: muted,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                'İndirme tamamlanamadı. İndirilen kısım saklandı; yeniden '
                'denediğinizde kaldığı yerden devam eder.\n$_error',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _cancel?.cancel();
            Navigator.pop(context);
          },
          child: Text(downloading ? 'İptal' : 'Vazgeç'),
        ),
        if (!downloading)
          FilledButton.icon(
            key: const ValueKey('speech-download'),
            onPressed: _download,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(
              _error == null ? 'İndir (${megabytes(total)})' : 'Yeniden dene',
            ),
          ),
      ],
    );
  }
}

/// 145 MB, 12,3 MB — as a Turkish reader writes it.
String megabytes(int bytes) {
  final mb = bytes / 1000000;
  return mb >= 100 || mb == mb.roundToDouble()
      ? '${mb.round()} MB'
      : '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
}
