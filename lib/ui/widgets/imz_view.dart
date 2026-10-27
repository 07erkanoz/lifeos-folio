import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../models/evrak_file.dart';
import '../../services/signing/imz_file.dart';
import '../../services/udf/signature_parser.dart';
import '../agenda/agenda_page.dart' show AgendaColors;
import 'file_preview.dart';
import 'notice.dart';

/// An `.imz` opened: whether its signature holds and who signed it, above
/// the document it holds, read as any document is. The document is taken
/// out into a folder of its own while it is shown, and saved elsewhere
/// only when asked.
class ImzView extends StatefulWidget {
  const ImzView({super.key, required this.path});

  final String path;

  @override
  State<ImzView> createState() => _ImzViewState();
}

class _ImzViewState extends State<ImzView> {
  late final Future<ImzContent?> _read = ImzFile.open(widget.path);
  Directory? _folder;
  String? _inside;

  @override
  void initState() {
    super.initState();
    unawaited(
      _read.then((read) async {
        if (read == null) return;
        final folder = await Directory.systemTemp.createTemp('folio-imz-');
        final file = File(p.join(folder.path, read.name));
        await file.writeAsBytes(read.content, flush: true);
        if (!mounted) {
          await folder.delete(recursive: true);
          return;
        }
        setState(() {
          _folder = folder;
          _inside = file.path;
        });
      }),
    );
  }

  @override
  void dispose() {
    final folder = _folder;
    if (folder != null) {
      unawaited(
        folder.delete(recursive: true).catchError((Object _) => folder),
      );
    }
    super.dispose();
  }

  Future<void> _save(ImzContent read) async {
    final target = await FilePicker.saveFile(
      dialogTitle: 'İmzalı belgenin içeriğini kaydet',
      fileName: read.name,
    );
    if (target == null) return;
    await File(target).writeAsBytes(read.content, flush: true);
    if (mounted) {
      showNotice(
        context,
        'Belge kaydedildi',
        detail: target,
        kind: NoticeKind.success,
      );
    }
  }

  /// A TC number shown in part, as on a receipt.
  static String _masked(String? id) {
    final digits = id?.replaceAll(RegExp(r'\D'), '') ?? '';
    if (digits.length != 11) return id ?? '';
    return '${digits.substring(0, 3)}*****${digits.substring(8)}';
  }

  static String _date(DateTime? t) {
    if (t == null) return '';
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  bool _previewable(String name) => EvrakFormat.supportedExtensions.contains(
    p.extension(name).replaceFirst('.', '').toLowerCase(),
  );

  Widget _signer(UdfSignatureInfo s) {
    final lines = [
      if ((s.organization ?? '').isNotEmpty) s.organization!,
      if ((s.subjectIdentifier ?? '').isNotEmpty)
        'T.C. kimlik no: ${_masked(s.subjectIdentifier)}',
      if (s.signedAt != null) 'İmza tarihi: ${_date(s.signedAt)}',
      if ((s.issuerName ?? '').isNotEmpty) 'Sertifikayı veren: ${s.issuerName}',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.signerName ?? 'Adı okunamayan imzacı',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final line in lines)
            Text(
              line,
              style: TextStyle(fontSize: 12.5, color: AgendaColors.muted),
            ),
        ],
      ),
    );
  }

  Widget _panel(ImzContent read) {
    final scheme = Theme.of(context).colorScheme;
    final ok = read.valid;
    final tone = ok ? const Color(0xFF157A52) : scheme.error;
    return Container(
      key: const ValueKey('imz-panel'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .07),
        border: Border.all(color: tone.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.verified_user_outlined : Icons.gpp_bad_outlined,
            color: tone,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ok
                      ? 'E-imza geçerli'
                      : 'E-imza doğrulanamadı: belge imzadan sonra değişmiş '
                            'olabilir',
                  key: const ValueKey('imz-state'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tone,
                  ),
                ),
                for (final s in read.signers) _signer(s),
                const SizedBox(height: 8),
                Text(
                  'İmza, içindeki belgeyle ve imzacının kendi sertifikasıyla '
                  'denetlendi. Sertifikanın yetkili bir kuruluşça verildiği ve '
                  'iptal edilmediği ayrıca denetlenmedi.',
                  style: TextStyle(fontSize: 11.5, color: AgendaColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            key: const ValueKey('imz-save'),
            onPressed: () => unawaited(_save(read)),
            icon: const Icon(Icons.save_alt_rounded, size: 18),
            label: const Text('Belgeyi kaydet…'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ImzContent?>(
    future: _read,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      final read = snapshot.data;
      if (read == null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Bu dosya okunamadı: içinde belge olan bir e-imza dosyası değil '
              'ya da bozuk.',
              key: const ValueKey('imz-unreadable'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AgendaColors.muted),
            ),
          ),
        );
      }
      final inside = _inside;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panel(read),
          Expanded(
            child: inside == null
                ? const Center(child: CircularProgressIndicator())
                : _previewable(read.name)
                ? FilePreview(path: inside)
                : Center(
                    child: Text(
                      'İçindeki belge (${read.name}) burada gösterilemiyor; '
                      'kaydedip açabilirsiniz.',
                      style: TextStyle(color: AgendaColors.muted),
                    ),
                  ),
          ),
        ],
      );
    },
  );
}
