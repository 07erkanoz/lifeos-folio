import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/desktop/desktop_companion.dart';
import '../../services/update/update_check.dart';
import '../../services/update/update_installer.dart';
import '../../services/update/update_manifest.dart';

/// A newer Folio, fetched and installed from inside Folio: its notes, the
/// download as it comes, the check against the signed manifest, and the
/// system's own installer.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.manifest});

  final UpdateManifest manifest;

  static Future<void> show(BuildContext context, UpdateManifest manifest) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => UpdateDialog(manifest: manifest),
      );

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _Step { ready, downloading, downloaded, installing }

class _UpdateDialogState extends State<UpdateDialog> {
  _Step _step = _Step.ready;
  int _done = 0;
  File? _package;
  String? _error;

  UpdateManifest get _m => widget.manifest;

  static String _size(int bytes) => bytes >= 1 << 20
      ? '${(bytes / (1 << 20)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(0)} KB';

  Future<void> _download() async {
    setState(() {
      _step = _Step.downloading;
      _error = null;
      _done = 0;
    });
    try {
      final file = await UpdateInstaller.download(
        _m,
        progress: (done, _) {
          if (mounted) setState(() => _done = done);
        },
      );
      if (!mounted) return;
      setState(() {
        _package = file;
        _step = _Step.downloaded;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e'.replaceFirst('Bad state: ', '');
          _step = _Step.ready;
        });
      }
    }
  }

  Future<void> _install() async {
    final package = _package;
    if (package == null) return;
    final companion = CompanionScope.maybeOf(context);
    setState(() {
      _step = _Step.installing;
      _error = null;
    });
    try {
      await UpdateInstaller.install(
        package,
        restart: () async {
          if (companion != null) {
            await companion.quit();
          } else {
            exit(0);
          }
        },
      );
      if (!mounted) return;
      if (Platform.isWindows) {
        // The setup closes Folio itself, asking first.
        Navigator.of(context).pop();
      } else {
        setState(() => _step = _Step.downloaded);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e'.replaceFirst('Bad state: ', '');
          _step = _Step.downloaded;
        });
      }
    }
  }

  String get _installLabel => Platform.isWindows
      ? 'Kurulumu başlat'
      : Platform.isAndroid
      ? 'Yükle'
      : 'Kur ve yeniden başlat';

  @override
  Widget build(BuildContext context) {
    final notes = _m.notes['tr'] ?? _m.notes['en'] ?? '';
    final scheme = Theme.of(context).colorScheme;
    final busy = _step == _Step.downloading || _step == _Step.installing;
    return AlertDialog(
      title: Text('LifeOS Folio ${_m.version}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (notes.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(
                  child: Text(notes, style: const TextStyle(height: 1.5)),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Paket ${_size(_m.size)} · imzalı sürüm bilgisiyle denetlenir',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            if (_step == _Step.downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                key: const ValueKey('update-progress'),
                value: _m.size == 0 ? null : _done / _m.size,
              ),
              const SizedBox(height: 6),
              Text(
                '${_size(_done)} / ${_size(_m.size)}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (_step == _Step.downloaded && _error == null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    color: Color(0xFF157A52),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      Platform.isLinux
                          ? 'Paket indi ve doğrulandı. Folio kurulumdan sonra '
                                'kapanıp yeni sürümle açılır; açık belgelerinizi '
                                'kaydedin.'
                          : Platform.isWindows
                          ? 'Paket indi ve doğrulandı. Kurulum Folio’yu '
                                'kapatmadan önce sorar.'
                          : 'Paket indi ve doğrulandı.',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ],
            if (_step == _Step.installing) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              const Text('Kuruluyor…', style: TextStyle(fontSize: 12)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const ValueKey('update-error'),
                style: TextStyle(fontSize: 12.5, color: scheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy
              ? null
              : () {
                  UpdateCheck.instance.later();
                  Navigator.of(context).pop();
                },
          child: const Text('Sonra'),
        ),
        if (!UpdateInstaller.canInstall)
          FilledButton.icon(
            onPressed: () {
              unawaited(
                launchUrl(_m.url, mode: LaunchMode.externalApplication),
              );
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('İndirme sayfasını aç'),
          )
        else if (_step == _Step.ready || _step == _Step.downloading)
          FilledButton.icon(
            key: const ValueKey('update-download'),
            onPressed: busy ? null : () => unawaited(_download()),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(_step == _Step.downloading ? 'İniyor…' : 'İndir'),
          )
        else
          FilledButton.icon(
            key: const ValueKey('update-install'),
            onPressed: busy ? null : () => unawaited(_install()),
            icon: const Icon(Icons.system_update_alt_rounded, size: 18),
            label: Text(_installLabel),
          ),
      ],
    );
  }
}
