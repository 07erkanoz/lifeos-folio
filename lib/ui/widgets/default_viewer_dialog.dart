import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../services/platform/viewer_file_types.dart';
import '../../services/platform/viewer_registration.dart';

class DefaultViewerDialog extends StatefulWidget {
  final Future<String> Function(List<ViewerFileType>)? register;
  const DefaultViewerDialog({super.key, this.register});
  @override
  State<DefaultViewerDialog> createState() => _DefaultViewerDialogState();
}

class _DefaultViewerDialogState extends State<DefaultViewerDialog> {
  final _selected = <ViewerFileType>{ViewerFileType.supported.first};
  bool _busy = false;
  String? _message;
  bool _failed = false;

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  Future<void> _apply() async {
    if (_busy || _selected.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final types = ViewerFileType.supported.where(_selected.contains).toList();
      final String result;
      if (_android) {
        result = await ViewerRegistration.configureAndroidDefaultViewer();
      } else {
        result =
            await (widget.register?.call(types) ??
                ViewerRegistration.register(types: types));
      }
      if (mounted) {
        setState(() {
          _message = result;
          _failed = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = e.toString();
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Varsayılan önizleyici'),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _android
                      ? 'Belgeleri LifeOS Folio ile açın'
                      : 'LifeOS Folio ile açılacak dosya türlerini seçin.',
                ),
                const SizedBox(height: 8),
                Text(
                  _android
                      ? 'Önce varsayılan yapmak istediğiniz türde gerçek bir belge seçin. Ardından Android’in açma ekranında LifeOS Folio → “Her zaman” seçimini yapın. Her belge türü Android tarafından ayrı yönetilir; PDF, UDF veya DOCX için işlemi ayrı ayrı uygulayabilirsiniz.'
                      : Platform.isWindows
                      ? 'Seçiminiz Windows ayarlarına hazırlanır. Atamayı açılan Windows ekranında onaylayın.'
                      : Platform.isLinux
                      ? 'Yalnızca seçtiğiniz türler atanır. Linux aynı içerik türünü kullanan uzantıları birlikte yönetir; örneğin TXT ve LOG.'
                      : 'Android son seçimi belge açılırken yapar. İstediğiniz türde bir dosyayı açıp Folio → Her zaman seçin.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in ViewerFileType.supported)
                      if (_android)
                        Chip(label: Text(type.label))
                      else
                        FilterChip(
                          label: Text(
                            '${type.label} · ${type.extensions.map((e) => '.$e').join(', ')}',
                          ),
                          selected: _selected.contains(type),
                          onSelected: _busy
                              ? null
                              : (value) => setState(() {
                                  value
                                      ? _selected.add(type)
                                      : _selected.remove(type);
                                  _message = null;
                                }),
                        ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Icon(
                      Icons.fullscreen_rounded,
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Belgeler sol panel kapalı, doğrudan önizlemede açılır.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _message!,
                      style: TextStyle(
                        fontSize: 13,
                        color: _failed ? colors.error : colors.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          FilledButton(
            onPressed: _busy || _selected.isEmpty ? null : _apply,
            child: Text(
              _android
                  ? 'Belge seç ve varsayılanı ayarla'
                  : Platform.isWindows
                  ? 'Windows ayarlarında tamamla'
                  : 'Seçilenleri varsayılan yap',
            ),
          ),
        ],
      ),
    );
  }
}
