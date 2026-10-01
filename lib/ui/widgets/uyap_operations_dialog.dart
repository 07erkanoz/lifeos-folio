import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/pdf/pdf_service.dart';
import '../../services/tiff/tiff_service.dart';
import '../../services/udf/udf_reader.dart';
import '../../services/uyap/uyap_web_service.dart';
import 'notice.dart';
import 'pdf_viewer_widget.dart';
import 'uyap_connect_view.dart';
import 'uyap_session_chip.dart';

/// UYAP "İşlemlerim" view. Opens straight onto live records while the shared
/// web session is up, asks for the PIN otherwise. Documents sent from this app
/// are listed on top and followed until UYAP reports their work complete.
class UyapOperationsDialog extends StatefulWidget {
  const UyapOperationsDialog({super.key, this.focusReceipt});
  final UyapSendReceipt? focusReceipt;

  @override
  State<UyapOperationsDialog> createState() => _UyapOperationsDialogState();
}

class _UyapOperationsDialogState extends State<UyapOperationsDialog> {
  static const _followEvery = Duration(seconds: 30);

  final _web = UyapWebService.instance;
  List<UyapOperation> _rows = const [];
  Map<UyapSendReceipt, UyapOperation> _matches = const {};
  Timer? _follow;
  bool _busy = false;
  bool _pendingOnly = true;
  bool _focusCase = false;
  int _days = 90;
  String? _error;
  DateTime? _checkedAt;
  UyapOperation? _previewing;

  /// Receipts still worth following: not complete, and recent enough for their
  /// record to fall inside a reasonable query.
  List<UyapSendReceipt> get _open => [
    for (final receipt in _web.sent)
      if (!(_matches[receipt]?.completed ?? false) &&
          DateTime.now().difference(receipt.startedAt) <
              const Duration(days: 2))
        receipt,
  ];

  @override
  void initState() {
    super.initState();
    _focusCase = widget.focusReceipt != null;
    _pendingOnly = widget.focusReceipt == null;
    _days = widget.focusReceipt == null ? 90 : 7;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _web.connected) _refresh();
    });
    _web.session.addListener(_sessionChanged);
  }

  /// A session that ends stops the following and shows the way back in.
  void _sessionChanged() {
    if (!mounted) return;
    if (_web.session.value == null) _follow?.cancel();
    setState(() {});
  }

  @override
  void dispose() {
    _follow?.cancel();
    _web.session.removeListener(_sessionChanged);
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) {
        _scheduleFollow();
        setState(() => _busy = false);
      }
    }
  }

  /// Re-query while a sent document is unfinished. An error stops following:
  /// a failing or expired session must not be hammered.
  void _scheduleFollow() {
    _follow?.cancel();
    _follow = null;
    if (!mounted || _error != null || !_web.connected || _open.isEmpty) return;
    _follow = Timer(_followEvery, () {
      if (mounted && !_busy) _refresh();
    });
  }

  Future<void> _refresh() => _run(_fetch);

  Future<void> _fetch() async {
    if (!_web.connected) {
      throw StateError('UYAP web oturumu sona erdi. Yeniden bağlanın.');
    }
    final now = DateTime.now();
    var from = now.subtract(Duration(days: _days));
    for (final receipt in _web.sent) {
      final day = receipt.startedAt.subtract(UyapSendReceipt.matchBefore);
      if (day.isBefore(from)) from = day;
    }
    final rows = await _web.operations(from: from, to: now);
    // Newest first; a record without a readable date goes last.
    final epoch = DateTime(0);
    rows.sort((a, b) => (b.time ?? epoch).compareTo(a.time ?? epoch));
    if (mounted) {
      setState(() {
        _rows = rows;
        _matches = UyapSendReceipt.match(_web.sent, rows);
        _checkedAt = now;
      });
    }
  }

  /// UYAP serves PDF, UDF or TIFF; all are shown through the PDF viewer.
  static Future<Uint8List> _asPdf(Uint8List bytes, String title) async {
    bool starts(List<int> magic) =>
        bytes.length >= magic.length &&
        [for (var i = 0; i < magic.length; i++) bytes[i]].join(',') ==
            magic.join(',');
    if (starts([0x25, 0x50, 0x44, 0x46])) return bytes;
    if (starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A])) {
      return TiffService.tiffToPdf(bytes);
    }
    if (starts([0x50, 0x4B])) {
      final model = UdfReader.readBytes(bytes);
      if (model == null) throw StateError('UYAP’tan gelen UDF okunamadı.');
      return PdfService.modelToPdfBytes(model, title: title);
    }
    throw StateError('UYAP evrakı tanınmayan bir biçimde geldi.');
  }

  /// Opens the document of [op] from UYAP. An expired handle is renewed once
  /// by re-querying İşlemlerim and finding the same work order again.
  Future<void> _preview(UyapOperation op) async {
    if (_previewing != null) return;
    setState(() => _previewing = op);
    try {
      Uint8List bytes;
      try {
        bytes = await _web.documentBytes(op);
      } on UyapStaleDocument {
        if (op.orderNumber.isEmpty) rethrow;
        await _fetch();
        final fresh = _rows.where((e) => e.orderNumber == op.orderNumber);
        if (fresh.isEmpty) {
          throw StateError('İşlem kaydı yenilenen listede bulunamadı.');
        }
        bytes = await _web.documentBytes(fresh.first);
      }
      final title = op.name.isEmpty ? 'UYAP evrakı' : op.name;
      final pdf = await _asPdf(bytes, title);
      if (!mounted) return;
      setState(() => _previewing = null);
      await showDialog<void>(
        context: context,
        builder: (context) {
          final size = MediaQuery.sizeOf(context);
          return Dialog(
            insetPadding: const EdgeInsets.all(20),
            child: SizedBox(
              width: size.width < 960 ? size.width - 40 : 920,
              height: size.height < 800 ? size.height - 40 : 760,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${op.caseNumber} · ${op.court}'
                                '${op.status.isEmpty ? '' : ' · ${op.status}'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Kapat',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: PdfViewerWidget(bytes: pdf)),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          'Evrak önizlemesi açılamadı',
          detail: e.toString().replaceFirst('Bad state: ', ''),
          kind: NoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _previewing = null);
    }
  }

  Widget _previewButton(UyapOperation op) {
    final current = _previewing;
    final loading =
        current != null &&
        (identical(current, op) ||
            (op.orderNumber.isNotEmpty &&
                current.orderNumber == op.orderNumber));
    return TextButton.icon(
      onPressed: _previewing != null || _busy || !_web.connected
          ? null
          : () => _preview(op),
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.visibility_outlined, size: 18),
      label: const Text('Önizle'),
    );
  }

  String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _receiptCard(ThemeData theme, UyapSendReceipt receipt) {
    final op = _matches[receipt];
    final scheme = theme.colorScheme;
    final focused = identical(receipt, widget.focusReceipt);
    late final IconData icon;
    late final Color color;
    late final String title;
    late final String detail;
    if (op != null && op.completed) {
      icon = Icons.check_circle;
      color = Colors.green.shade700;
      title = 'Gönderildi · UYAP işlemi tamamlandı';
      detail = [
        if (op.documentNumber.isNotEmpty) 'Evrak no: ${op.documentNumber}',
        if (op.date.isNotEmpty) 'İşlem: ${op.date}',
      ].join(' · ');
    } else if (op != null) {
      icon = Icons.schedule;
      color = scheme.tertiary;
      title = op.pending
          ? 'UYAP’ta işleniyor'
          : 'UYAP durumu: ${op.status.isEmpty ? 'Bilinmiyor' : op.status}';
      detail = [
        if (op.owner.isNotEmpty) 'Görevli: ${op.owner}',
        if (op.orderNumber.isNotEmpty) 'İş no: ${op.orderNumber}',
      ].join(' · ');
    } else if (_checkedAt == null) {
      icon = Icons.hourglass_empty;
      color = scheme.outline;
      title = _web.connected
          ? 'UYAP işlem kaydı sorgulanıyor'
          : 'Durumu görmek için UYAP’a bağlanın';
      detail = '';
    } else if (receipt.confirmed) {
      icon = Icons.hourglass_top;
      color = scheme.outline;
      title = 'Gönderim yanıtı alındı; UYAP işlem kaydı henüz görünmüyor';
      detail = 'Kayıt çıkana kadar kendiliğinden yeniden sorgulanır.';
    } else {
      icon = Icons.help_outline;
      color = scheme.error;
      title = 'Gönderim sonucu belirsiz; UYAP’ta kaydı görünmüyor';
      detail =
          'Tekrar göndermeden önce UYAP’ta dosyanın evraklarını kontrol edin.';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: focused
            ? scheme.primary.withValues(alpha: .07)
            : scheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w800, color: color),
                ),
                Text(
                  '${receipt.documentName} · ${receipt.documentType}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${receipt.target.number} · ${receipt.target.courtName}'
                  ' · Gönderim ${_clock(receipt.startedAt)}',
                  style: const TextStyle(fontSize: 12),
                ),
                if (detail.isNotEmpty)
                  Text(detail, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          if (op != null && op.documentId.isNotEmpty) _previewButton(op),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final receipt = widget.focusReceipt;
    final receipts = _web.sent;
    final displayed = _rows.where((row) {
      if (_pendingOnly && !row.pending) return false;
      if (_focusCase && receipt != null && !row.isFor(receipt.target)) {
        return false;
      }
      return true;
    }).toList();
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: size.width < 900 ? size.width - 40 : 860,
        height: size.height < 760 ? size.height - 40 : 700,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.pending_actions, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Devam Eden İşlemler',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                children: [
                  if (_error != null)
                    Card(
                      color: theme.colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  if (receipts.isNotEmpty) ...[
                    const Text(
                      'Gönderdiğim evraklar',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    for (final r in receipts) _receiptCard(theme, r),
                    const SizedBox(height: 8),
                  ],
                  if (!_web.connected) ...[
                    UyapConnectView(
                      note: 'Gönderdiğiniz evrakların UYAP’taki durumu için.',
                      onConnected: (_) => _run(_fetch),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        const UyapSessionChip(),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _follow != null
                                ? 'Gönderilen evrak tamamlanana kadar 30 sn’de '
                                      'bir sorgulanıyor'
                                : 'Canlı kayıtlar',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (_checkedAt != null)
                          Text(
                            'Son sorgu ${_clock(_checkedAt!)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: true,
                              label: Text('Devam eden'),
                            ),
                            ButtonSegment(
                              value: false,
                              label: Text('Tüm işlemler'),
                            ),
                          ],
                          selected: {_pendingOnly},
                          onSelectionChanged: (value) =>
                              setState(() => _pendingOnly = value.first),
                        ),
                        DropdownButton<int>(
                          value: _days,
                          items: const [
                            DropdownMenuItem(
                              value: 7,
                              child: Text('Son 7 gün'),
                            ),
                            DropdownMenuItem(
                              value: 30,
                              child: Text('Son 30 gün'),
                            ),
                            DropdownMenuItem(
                              value: 90,
                              child: Text('Son 90 gün'),
                            ),
                            DropdownMenuItem(
                              value: 365,
                              child: Text('Son 1 yıl'),
                            ),
                          ],
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() => _days = value);
                                  _refresh();
                                },
                        ),
                        if (receipt != null)
                          FilterChip(
                            label: const Text('Bu dosya'),
                            selected: _focusCase,
                            onSelected: (value) =>
                                setState(() => _focusCase = value),
                          ),
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : _refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('UYAP’tan yenile'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_checkedAt == null && !_busy)
                      const Text('Henüz işlem sorgulanmadı.'),
                    if (_checkedAt != null && displayed.isEmpty)
                      const Text(
                        'Sorgu başarılı; seçilen filtrelerde işlem kaydı görünmüyor.',
                      ),
                    for (final row in displayed)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                row.pending ? Icons.schedule : Icons.task_alt,
                                color: row.pending
                                    ? theme.colorScheme.tertiary
                                    : theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      row.name.isEmpty
                                          ? 'UYAP işlemi'
                                          : row.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '${row.caseNumber} · ${row.court}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      'Durum: ${row.status.isEmpty ? 'Bilinmiyor' : row.status}'
                                      '${row.owner.isEmpty ? '' : ' · Görevli: ${row.owner}'}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      'İş no: ${row.orderNumber.isEmpty ? '—' : row.orderNumber}'
                                      ' · Tarih: ${row.date.isEmpty ? '—' : row.date}'
                                      '${row.documentNumber.isEmpty ? '' : ' · Evrak no: ${row.documentNumber}'}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              if (row.documentId.isNotEmpty)
                                _previewButton(row),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
