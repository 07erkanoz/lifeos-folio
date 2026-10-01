import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/document_model.dart';
import '../../services/udf/signature_parser.dart';
import '../theme/app_theme.dart';

class SignatureBanner extends StatelessWidget {
  final DocModel model;
  final bool compact;
  const SignatureBanner({super.key, required this.model, this.compact = false});

  static const saveNotice =
      'Kaydedilen kopya mevcut elektronik imzayı içermeyecek. '
      'İmzalı kaynak dosya korunacak.';

  static String _date(DateTime? date) => date == null
      ? 'Belirtilmemiş'
      : DateFormat('dd.MM.yyyy HH:mm').format(date.toLocal());

  @override
  Widget build(BuildContext context) {
    if (model.metadata['hasSignature'] != true) return const SizedBox.shrink();
    final infos =
        (model.metadata['signatureInfos'] as List?)
            ?.whereType<UdfSignatureInfo>()
            .toList() ??
        const <UdfSignatureInfo>[];
    final names = infos
        .map((s) => s.signerName ?? 'İmzacı bilgisi okunamadı')
        .join(', ');
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Its own colour, strong enough to be seen at a glance: a signed filing
    // and an unsigned copy of it must not look alike.
    final seal = dark ? AppColors.signatureDark : AppColors.signature;
    final onSeal = dark ? const Color(0xFF3B1204) : Colors.white;
    final dates = infos.map((s) => s.signedAt).whereType<DateTime>().toList()
      ..sort();
    final when = dates.isEmpty ? null : _date(dates.last);
    final who = names.isEmpty ? 'İmza ayrıntıları okunamadı' : names;
    final summary = [
      ?when,
      if (infos.length > 1) '${infos.length} imza',
    ].join('  ·  ');
    return Container(
      height: compact ? 32 : 40,
      padding: EdgeInsets.fromLTRB(compact ? 4 : 12, 0, compact ? 2 : 8, 0),
      decoration: BoxDecoration(
        color: seal.withValues(alpha: dark ? .24 : .15),
        borderRadius: compact ? BorderRadius.circular(8) : null,
        border: compact
            ? Border.all(color: seal.withValues(alpha: .55))
            : Border(
                left: BorderSide(color: seal, width: 4),
                bottom: BorderSide(color: seal.withValues(alpha: .40)),
              ),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 22 : 26,
            height: compact ? 22 : 26,
            decoration: BoxDecoration(color: seal, shape: BoxShape.circle),
            child: Icon(
              Icons.draw_rounded,
              size: compact ? 13 : 15,
              color: onSeal,
            ),
          ),
          SizedBox(width: compact ? 6 : 10),
          if (!compact) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: seal,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'E-İMZALI',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .6,
                  color: onSeal,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Tooltip(
              message:
                  'Elektronik imzalı${names.isEmpty ? '' : ': $names'}'
                  '${when == null ? '' : '\nBeyan edilen imza zamanı: $when'}',
              child: Text.rich(
                TextSpan(
                  children: [
                    if (compact)
                      TextSpan(
                        text: 'E-imzalı  ',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: seal,
                        ),
                      ),
                    TextSpan(
                      text: names.isEmpty && compact ? '' : who,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: names.isEmpty
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                    if (!compact && summary.isNotEmpty)
                      TextSpan(
                        text: '  ·  $summary',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: compact ? 12 : 13),
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: seal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: Size(0, compact ? 26 : 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              // The theme's own face: a style given here whole would drop
              // the family, and the button fell back to the system's.
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Elektronik imza bilgileri'),
                content: SizedBox(
                  width: 560,
                  child: SingleChildScrollView(
                    child: SelectionArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'İmza dosyası: sign.sgn\n'
                            'Boyut: ${(model.metadata['signatureBytes'] as List<int>?)?.length ?? 0} bayt',
                          ),
                          if (infos.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'İmza verisi mevcut ancak ayrıntıları okunamadı. '
                                'Bu durum belgenin imzasız olduğu anlamına gelmez.',
                              ),
                            ),
                          for (var i = 0; i < infos.length; i++) ...[
                            const Divider(height: 28),
                            Text(
                              '${i + 1}. ${infos[i].counterSignature ? 'Karşı imza' : 'İmza'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'İmzacı: ${infos[i].signerName ?? 'Okunamadı'}\n'
                              'Sertifika sağlayıcısı: ${infos[i].issuerName ?? 'Belirtilmemiş'}\n'
                              'Kurum: ${infos[i].organization ?? 'Belirtilmemiş'}\n'
                              'Sertifika kimlik alanı: ${infos[i].subjectIdentifier ?? 'Belirtilmemiş'}\n'
                              'Sertifika seri no: ${infos[i].certificateSerial ?? 'Belirtilmemiş'}\n'
                              'Beyan edilen imza zamanı: ${_date(infos[i].signedAt)}\n'
                              'Sertifika başlangıcı: ${_date(infos[i].validFrom)}\n'
                              'Sertifika bitişi: ${_date(infos[i].validUntil)}',
                            ),
                            if (infos[i].issue != null) Text(infos[i].issue!),
                          ],
                          const Divider(height: 28),
                          const Text(
                            'Belgede kayıtlı elektronik imza ve sertifika bilgileri.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Kapat'),
                  ),
                ],
              ),
            ),
            child: compact
                ? const Tooltip(
                    message: 'Elektronik imza ayrıntıları',
                    child: Icon(Icons.info_outline_rounded, size: 17),
                  )
                : const Text('Ayrıntılar'),
          ),
        ],
      ),
    );
  }
}
