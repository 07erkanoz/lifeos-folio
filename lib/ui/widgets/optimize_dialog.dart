import 'package:flutter/material.dart';

import '../../models/evrak_file.dart';
import '../../services/optimize/optimizer_service.dart';

class OptimizeDialog extends StatefulWidget {
  final EvrakFile file;
  const OptimizeDialog({super.key, required this.file});
  @override
  State<OptimizeDialog> createState() => _OptimizeDialogState();
}

class _OptimizeDialogState extends State<OptimizeDialog> {
  bool _busy = false;
  OptimizeResult? _result;
  String? _error;
  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await OptimizerService.optimize(widget.file.path);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Kayıpsız boyut küçült'),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.file.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Çözünürlük ve görüntü kalitesi korunur. Yalnız daha küçük sonuç elde edilirse kaynak dosyanın yanında yeni bir dosya oluşturulur.',
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_result case final result?) ...[
              const SizedBox(height: 16),
              Text(result.message),
              if (result.reduced) ...[
                Text(
                  '${(result.beforeBytes / 1024).toStringAsFixed(1)} KB → ${(result.afterBytes / 1024).toStringAsFixed(1)} KB  (%${((1 - result.afterBytes / result.beforeBytes) * 100).toStringAsFixed(1)} daha küçük)',
                ),
                const SizedBox(height: 8),
                SelectableText(result.outputPath!),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
        if (_result == null)
          FilledButton(
            onPressed: _busy ? null : _start,
            child: const Text('Boyutu küçült'),
          ),
      ],
    ),
  );
}
