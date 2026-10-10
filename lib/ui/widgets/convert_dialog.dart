import 'dart:io';

import '../../services/platform/phone_document_save.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/evrak_file.dart';
import '../../services/convert/converter_service.dart';
import '../theme/app_theme.dart';

class ConvertDialog extends StatefulWidget {
  final List<EvrakFile> files;

  const ConvertDialog({super.key, required this.files});

  @override
  State<ConvertDialog> createState() => _ConvertDialogState();
}

class _ConvertDialogState extends State<ConvertDialog> {
  late EvrakFormat _targetFormat;
  String? _targetDirectory;
  bool _isConverting = false;
  double _progress = 0.0;
  final List<String> _results = [];
  int _failureCount = 0;
  int _skippedCount = 0;

  bool _alreadyTarget(EvrakFile file, EvrakFormat target) =>
      file.name.split('.').last.toLowerCase() == target.defaultExtension;

  List<EvrakFormat> get _targets =>
      [
            EvrakFormat.pdf,
            EvrakFormat.udf,
            EvrakFormat.docx,
            EvrakFormat.text,
            EvrakFormat.image,
            EvrakFormat.tif,
          ]
          .where(
            (target) =>
                widget.files.any(
                  (file) => file.conversionTargets.contains(target),
                ) &&
                widget.files.every(
                  (file) =>
                      _alreadyTarget(file, target) ||
                      file.conversionTargets.contains(target),
                ),
          )
          .toList();

  @override
  void initState() {
    super.initState();
    if (_targets.isNotEmpty) {
      _targetFormat = _targets.first;
      return;
    }
    // İlk dosyaya göre uygun bir hedef format seç
    final first = widget.files.firstOrNull;
    if (first != null && first.format.availableConversions.isNotEmpty) {
      _targetFormat = first.format.availableConversions.first;
    } else {
      _targetFormat = EvrakFormat.pdf;
    }
  }

  Future<void> _selectDirectory() async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: 'Hedef Klasörü Seçin',
    );
    if (mounted && selected != null) {
      setState(() => _targetDirectory = selected);
    }
  }

  Future<void> _startConversion() async {
    setState(() {
      _isConverting = true;
      _progress = 0.0;
      _results.clear();
      _failureCount = 0;
      _skippedCount = 0;
    });

    final mobileDirectory = PhoneDocumentSave.here
        ? p.join((await getTemporaryDirectory()).path, 'conversions')
        : null;
    int count = 0;
    for (final file in widget.files) {
      if (_alreadyTarget(file, _targetFormat)) {
        _skippedCount++;
        _results.add('${file.name}: zaten hedef biçimde, atlandı.');
        count++;
        setState(() => _progress = count / widget.files.length);
        continue;
      }
      final res = await ConverterService.convertFile(
        sourcePath: file.path,
        targetFormat: _targetFormat,
        targetDirectory: mobileDirectory ?? _targetDirectory,
      );

      if (!mounted) return;
      if (res.success && res.outputPath != null) {
        if (PhoneDocumentSave.here) {
          try {
            final saved = await PhoneDocumentSave.save(
              fileName: p.basename(res.outputPath!),
              bytes:
                  res.outputBytes ?? await File(res.outputPath!).readAsBytes(),
            );
            if (saved == null) {
              _skippedCount++;
              _results.add('${file.name}: dışa aktarma iptal edildi.');
            } else {
              _results.add('${file.name}: seçtiğiniz konuma kaydedildi.');
            }
          } catch (e) {
            _failureCount++;
            _results.add('${file.name}: Kaydetme hatası ($e)');
          }
        } else {
          _results.add(res.outputPath!);
        }
      } else {
        _failureCount++;
        _results.add(
          '${file.name}: Hata (${res.errorMessage ?? "Bilinmeyen hata"})',
        );
      }

      count++;
      setState(() {
        _progress = count / widget.files.length;
      });
    }

    setState(() {
      _isConverting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDone =
        _results.length == widget.files.length && _results.isNotEmpty;

    final visual = widget.files.every((f) => f.format.isVisual);
    return PopScope(
      canPop: !_isConverting,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.transform_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              widget.files.length > 1
                  ? '${widget.files.length} Evrakı Dönüştür'
                  : 'Evrakı Dönüştür',
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dosyalar Listesi Özeti
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      visual ? 'Görsel dönüşümü' : 'Belge dönüşümü',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 100),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: widget.files.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '• ${widget.files[i].name} (${widget.files[i].format.label})',
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Hedef Format Seçimi
              const Text(
                'Desteklenen hedefler:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _targets.map((fmt) {
                  final isSelected = _targetFormat == fmt;
                  return ChoiceChip(
                    label: Text(fmt == EvrakFormat.image ? 'PNG' : fmt.label),
                    selected: isSelected,
                    onSelected: _isConverting
                        ? null
                        : (selected) {
                            if (selected) setState(() => _targetFormat = fmt);
                          },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Kaydedilecek Klasör
              Row(
                children: [
                  Expanded(
                    child: Text(
                      PhoneDocumentSave.here
                          ? 'Konum: Kaydederken seçilecek'
                          : _targetDirectory != null
                          ? 'Konum: $_targetDirectory'
                          : 'Konum: Kaynak dosyaların bulunduğu klasör',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.darkTextMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isConverting || PhoneDocumentSave.here
                        ? null
                        : _selectDirectory,
                    icon: const Icon(Icons.folder_open_rounded, size: 16),
                    label: const Text('Değiştir'),
                  ),
                ],
              ),

              // İlerleme ve Sonuçlar
              if (_isConverting) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text(
                  'Dönüştürülüyor... (${(_progress * 100).toInt()}%)',
                  style: const TextStyle(fontSize: 12),
                ),
              ],

              if (isDone) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.success),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _failureCount == 0
                                ? Icons.check_circle_rounded
                                : Icons.error_outline,
                            color: _failureCount == 0
                                ? AppColors.success
                                : AppColors.error,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '${widget.files.length - _failureCount - _skippedCount} başarılı, $_skippedCount atlandı, $_failureCount başarısız',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (final res in _results)
                        Text(
                          res,
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],

              if (_targets.isEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Seçili dosyalar için ortak bir hedef format yok.',
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isConverting ? null : () => Navigator.of(context).pop(),
            child: Text(isDone ? 'Kapat' : 'İptal'),
          ),
          if (!isDone)
            FilledButton.icon(
              onPressed: _isConverting || _targets.isEmpty
                  ? null
                  : _startConversion,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Başlat'),
            ),
        ],
      ),
    );
  }
}
