import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/udf/udf_reader.dart';
import '../../services/uyap/uyap_case_links.dart';
import '../../services/uyap/uyap_web_service.dart';
import '../../services/pdf/pdf_service.dart';
import 'pdf_viewer_widget.dart';
import 'uyap_connect_view.dart';
import 'uyap_operations_dialog.dart';
import 'uyap_session_chip.dart';

/// User-driven UYAP submission. Only a verified web session can reach send().
class UyapSendDialog extends StatefulWidget {
  const UyapSendDialog({
    super.key,
    required this.documentName,
    required this.documentBytes,
    required this.stillCurrent,
    this.target,
  });
  final String documentName;
  final Uint8List documentBytes;
  final Future<bool> Function() stillCurrent;

  /// The case the document is tied to, chosen at once when there is one.
  final UyapCaseLink? target;

  @override
  State<UyapSendDialog> createState() => _UyapSendDialogState();
}

class _UyapSendDialogState extends State<UyapSendDialog> {
  final _web = UyapWebService.instance;
  final _year = TextEditingController();
  final _number = TextEditingController();
  final _description = TextEditingController();
  String _jurisdiction = '1';
  bool _closed = false;
  int _casePage = 1;
  bool _hasMoreCases = false;
  List<UyapOption> _types = [];
  List<UyapOption> _courts = [];
  List<UyapCase> _cases = [];
  List<UyapDocumentType> _documentTypes = [];
  UyapOption? _type;
  UyapOption? _court;
  UyapCase? _case;
  List<UyapParty> _parties = [];
  UyapDocumentType? _documentType;
  Uint8List? _previewPdf;
  String? _previewError;
  final _attachments = <UyapUpload>[];
  bool _busy = false;
  bool _uncertain = false;
  UyapSendReceipt? _uncertainReceipt;
  String? _error;
  String? _stage;

  bool _typeHasRoom(UyapDocumentType candidate, {int? excluding}) {
    if (candidate.max < 1) return true;
    var used = _documentType?.code == candidate.code ? 1 : 0;
    for (var i = 0; i < _attachments.length; i++) {
      if (i != excluding &&
          _attachments[i].documentType?.code == candidate.code) {
        used++;
      }
    }
    return used < candidate.max;
  }

  /// One compact look for every box of the dialog: a 13-point label and
  /// text, and the height of a line rather than Material's 56 pixels.
  InputDecoration _field(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    isDense: true,
    labelStyle: const TextStyle(fontSize: 13),
    hintStyle: const TextStyle(fontSize: 13),
    counterStyle: const TextStyle(fontSize: 11),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
  );

  @override
  void initState() {
    super.initState();
    _web.session.addListener(_sessionChanged);
    if (_web.connected && widget.target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _preselect());
    }
  }

  /// The document's own case, chosen as if it had been looked up: the
  /// kind of court and the court from the tie, the case found again in
  /// this session.
  Future<void> _preselect() async {
    final target = widget.target;
    if (target == null || !_web.connected || !mounted) return;
    setState(() {
      _jurisdiction = target.jurisdiction;
      _closed = target.closed;
    });
    await _run(() async {
      final types = await _web.courtTypes(target.jurisdiction);
      final type = types.where((t) => t.id == target.courtType).firstOrNull;
      if (type == null) return;
      final courts = await _web.courts(
        target.jurisdiction,
        type.id,
        closed: target.closed,
      );
      final court =
          courts.where((c) => c.id == target.courtId).firstOrNull ??
          UyapOption(target.courtId, target.court);
      if (!mounted) return;
      setState(() {
        _types = types;
        _type = type;
        _courts = courts.contains(court) ? courts : [...courts, court];
        _court = court;
      });
    });
    if (mounted && _type != null && _court != null && _case == null) {
      await _chooseCase(
        UyapCase('', target.number, target.courtId, target.court),
      );
    }
  }

  /// A session that ends, here or in another dialog, takes this one back to
  /// the way in.
  void _sessionChanged() {
    if (!mounted) return;
    if (_web.session.value == null) {
      _cleared();
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _web.session.removeListener(_sessionChanged);
    _year.dispose();
    _number.dispose();
    _description.dispose();
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connected(String user) async {
    if (widget.target != null) return _preselect();
    final types = await _web.courtTypes(_jurisdiction);
    if (mounted) setState(() => _types = types);
  }

  void _cleared() => setState(() {
    _types = [];
    _type = null;
    _courts = [];
    _court = null;
    _cases = [];
    _case = null;
    _documentTypes = [];
    _documentType = null;
    _attachments.clear();
  });

  Future<void> _loadTypes() => _run(() async {
    final types = await _web.courtTypes(_jurisdiction);
    if (mounted) {
      setState(() {
        _types = types;
        _type = null;
        _courts = [];
        _court = null;
        _cases = [];
        _case = null;
        _documentTypes = [];
        _documentType = null;
      });
    }
  });

  Future<void> _loadCourts(UyapOption selected) => _run(() async {
    final courts = await _web.courts(
      _jurisdiction,
      selected.id,
      closed: _closed,
    );
    if (mounted) {
      setState(() {
        _type = selected;
        _courts = courts;
        _court = null;
        _cases = [];
        _case = null;
        _documentTypes = [];
        _documentType = null;
      });
    }
  });

  Future<void> _search() => _run(() async {
    final year = int.tryParse(_year.text.trim());
    final number = int.tryParse(_number.text.trim());
    if (_type == null ||
        _court == null ||
        (year != null && (year < 1900 || year > DateTime.now().year)) ||
        (number != null && (number < 1 || year == null))) {
      throw StateError(
        'Mahkemeyi seçin. Esas numarası girerseniz dosya yılını da girin.',
      );
    }
    final cases = await _web.cases(
      jurisdiction: _jurisdiction,
      courtType: _type!.id,
      court: _court!,
      year: year,
      number: number,
      closed: _closed,
    );
    if (cases.isEmpty) {
      throw StateError(
        'Bu ölçütlerde dosya bulunamadı. Açık/kapalı seçimini ve dosya yılını kontrol edin.',
      );
    }
    if (mounted) {
      setState(() {
        _cases = cases;
        _casePage = 1;
        _hasMoreCases = cases.length == 500;
        _case = null;
        _documentTypes = [];
        _documentType = null;
      });
    }
  });

  Future<void> _loadMoreCases() => _run(() async {
    if (_type == null || _court == null || !_hasMoreCases) return;
    final next = await _web.cases(
      jurisdiction: _jurisdiction,
      courtType: _type!.id,
      court: _court!,
      year: int.tryParse(_year.text.trim()),
      number: int.tryParse(_number.text.trim()),
      closed: _closed,
      pageNumber: _casePage + 1,
    );
    if (mounted) {
      setState(() {
        _casePage++;
        _hasMoreCases = next.length == 500;
        final ids = _cases.map((e) => e.id).toSet();
        _cases.addAll(next.where((e) => ids.add(e.id)));
      });
    }
  });

  Future<void> _chooseCase(UyapCase selected) => _run(() async {
    // Re-query through the current web session instead of trusting a cached ID.
    final parsed = selected.parsedNumber;
    if (parsed == null) {
      throw StateError('Dosya numarası doğrulanamadı; bu dosya seçilemez.');
    }
    final fresh = await _web.cases(
      jurisdiction: _jurisdiction,
      courtType: _type!.id,
      court: _court!,
      year: parsed.year,
      number: parsed.sequence,
      closed: _closed,
    );
    final match = fresh.where((c) => c.sameCase(selected)).toList();
    if (match.length != 1) {
      throw StateError('Dosya kimliği değişti; yeniden arayın.');
    }
    final types = await _web.documentTypes(match.single);
    if (types.isEmpty) {
      throw StateError('UYAP bu dosya için evrak türü döndürmedi.');
    }
    final parties = await _web.parties(match.single);
    Uint8List? pdf = _previewPdf;
    String? previewError;
    if (pdf == null) {
      try {
        final model = UdfReader.readBytes(widget.documentBytes);
        if (model == null) throw StateError('UDF önizlemesi okunamadı.');
        pdf = await PdfService.modelToPdfBytes(
          model,
          title: widget.documentName,
        );
      } catch (e) {
        previewError = '$e';
      }
    }
    if (mounted) {
      setState(() {
        _case = match.single;
        _parties = parties;
        _previewPdf = pdf;
        _previewError = previewError;
        _documentTypes = types;
        _documentType = null;
        _attachments.clear();
      });
    }
  });

  Future<void> _addAttachment() => _run(() async {
    final type = _documentType;
    if (type == null) throw StateError('Önce evrak türünü seçin.');
    if (_attachments.length >= type.attachmentMax) {
      throw StateError(
        'Bu evrak türü en fazla ${type.attachmentMax} ek kabul ediyor.',
      );
    }
    final allowed = _documentTypes
        .expand((e) => e.acceptedExtensions)
        .map((e) => e.replaceFirst('.', ''))
        .toSet()
        .toList();
    final picked = await FilePicker.pickFiles(
      type: allowed.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: allowed.isEmpty ? null : allowed,
      withData: false,
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    final name = p.basename(path);
    if (_attachments.any((e) => e.name == name)) {
      throw StateError('Aynı adlı ek zaten seçili.');
    }
    final file = File(path);
    if (await file.length() > 64 * 1024 * 1024) {
      throw StateError('Ek dosya 64 MB sınırını aşıyor.');
    }
    final bytes = Uint8List.fromList(await file.readAsBytes());
    final extension = p.extension(name).toLowerCase();
    final choices = _documentTypes
        .where(
          (t) =>
              (t.acceptedExtensions.isEmpty ||
                  t.acceptedExtensions.contains(extension)) &&
              _typeHasRoom(t),
        )
        .toList();
    if (choices.isEmpty) {
      throw StateError('Bu ek için UYAP evrak türü bulunamadı.');
    }
    if (p.extension(name).toLowerCase() == '.udf') {
      UyapWebService.validateSignedUdf(bytes);
    }
    if (mounted) {
      setState(
        () => _attachments.add(
          UyapUpload(name, bytes, documentType: choices.first),
        ),
      );
    }
  });

  Future<void> _fullPreview(BuildContext dialogContext) async {
    try {
      final pdf = _previewPdf;
      if (pdf == null) throw StateError('UDF önizlemesi açılamadı.');
      if (!dialogContext.mounted) return;
      await showDialog<void>(
        context: dialogContext,
        builder: (context) => Dialog(
          child: SizedBox(
            width: 900,
            height: 700,
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Gönderilecek imzalı UDF önizlemesi'),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Expanded(child: PdfViewerWidget(bytes: pdf)),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (!dialogContext.mounted) return;
      await showDialog<void>(
        context: dialogContext,
        builder: (context) => AlertDialog(
          title: const Text('Önizleme açılamadı'),
          content: Text('$error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _send() => _run(() async {
    final target = _case;
    final type = _documentType;
    if (target == null || type == null) {
      throw StateError('Hedef dosya veya evrak türü eksik.');
    }
    if (!await widget.stillCurrent()) {
      throw StateError(
        'Editördeki belge gönderime hazırlanırken değişti. Yeniden başlatın.',
      );
    }
    if (!mounted) return;
    UyapWebService.validateSignedUdf(widget.documentBytes);
    if (_previewPdf == null || _parties.isEmpty) {
      throw StateError(
        'Dosya tarafları ve belge önizlemesi olmadan gönderilemez.',
      );
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Son kontrol · UYAP’a gönder'),
        content: SizedBox(
          width: 700,
          height: 500,
          child: Row(
            children: [
              SizedBox(
                width: 245,
                child: ListView(
                  children: [
                    const Text(
                      'HEDEF DOSYA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      target.number,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(target.courtName),
                    const Divider(height: 24),
                    const Text(
                      'TARAFLAR',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    for (final party in _parties)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(
                          '${party.role}: ${party.name}'
                          '${party.lawyer.isEmpty ? '' : '\nVekil: ${party.lawyer}'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    const Divider(height: 24),
                    const Text(
                      'GÖNDERİLECEK EVRAK',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      type.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      widget.documentName,
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (_description.text.trim().isNotEmpty)
                      Text(
                        _description.text.trim(),
                        style: const TextStyle(fontSize: 12),
                      ),
                    for (final attachment in _attachments)
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Text(
                          'Ek: ${attachment.name}\n'
                          '${attachment.documentType?.label ?? type.label}'
                          '${attachment.description.isEmpty ? '' : '\n${attachment.description}'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'İMZALI UDF ÖNİZLEMESİ',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(child: PdfViewerWidget(bytes: _previewPdf!)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dosyayı ve belgeyi kontrol ettim · Gönder'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!await widget.stillCurrent()) {
      throw StateError('Belge onay sırasında değişti. Gönderilmedi.');
    }
    // Refresh the web-only ID at the final gate; never use a cached/mobile ID.
    final parsed = target.parsedNumber;
    if (parsed == null) {
      throw StateError('Hedef dosya numarası doğrulanamadı. Gönderilmedi.');
    }
    final fresh = await _web.cases(
      jurisdiction: _jurisdiction,
      courtType: _type!.id,
      court: _court!,
      year: parsed.year,
      number: parsed.sequence,
      closed: _closed,
    );
    final matches = fresh.where((c) => c.sameCase(target)).toList();
    if (matches.length != 1) {
      throw StateError('Hedef dosya yeniden doğrulanamadı. Gönderilmedi.');
    }
    final refreshedParties = await _web.parties(matches.single);
    final previous = _parties.map((e) => e.identity).toList()..sort();
    final current = refreshedParties.map((e) => e.identity).toList()..sort();
    if (previous.join('\n') != current.join('\n')) {
      throw StateError('Dosya tarafları değişti. Yeniden seçip inceleyin.');
    }
    final currentTypes = await _web.documentTypes(matches.single);
    final currentByCode = {for (final t in currentTypes) t.code: t};
    final currentMainType = currentByCode[type.code];
    if (currentMainType == null) {
      throw StateError('Evrak türü artık kullanılamıyor. Gönderilmedi.');
    }
    final currentAttachments = <UyapUpload>[];
    for (final attachment in _attachments) {
      final current = currentByCode[attachment.documentType?.code];
      if (current == null) {
        throw StateError(
          '${attachment.name} için evrak türü artık kullanılamıyor.',
        );
      }
      currentAttachments.add(
        UyapUpload(
          attachment.name,
          attachment.bytes,
          description: attachment.description,
          documentType: current,
        ),
      );
    }
    if (!await widget.stillCurrent()) {
      throw StateError('Belge gönderimden önce değişti. Gönderilmedi.');
    }
    final startedAt = DateTime.now();
    var dispatched = false;
    UyapSendReceipt receipt({required bool confirmed}) => UyapSendReceipt(
      target: matches.single,
      documentName: widget.documentName,
      documentType: currentMainType.label,
      startedAt: startedAt,
      confirmed: confirmed,
    );
    try {
      await _web.send(
        target: matches.single,
        type: currentMainType,
        files: [
          UyapUpload(
            widget.documentName,
            widget.documentBytes,
            description: _description.text.trim(),
          ),
          ...currentAttachments,
        ],
        onDispatched: () => dispatched = true,
      );
    } catch (e) {
      // Before dispatch nothing left this computer: a plain, retryable error.
      if (!dispatched) rethrow;
      // A server error or unreadable response may also follow a committed send.
      final uncertain = receipt(confirmed: false);
      _web.track(uncertain);
      _uncertain = true;
      _uncertainReceipt = uncertain;
      if (e is TimeoutException) {
        throw StateError(
          'UYAP yanıtı zaman aşımına uğradı. Evrak gönderilmiş '
          'olabilir; tekrar denemeden önce Devam Eden İşlemler’de kontrol edin.',
        );
      }
      if (e is SocketException) {
        throw StateError(
          'UYAP bağlantısı gönderim sırasında kesildi. Evrak '
          'gönderilmiş olabilir; tekrar denemeden önce Devam Eden '
          'İşlemler’de kontrol edin.',
        );
      }
      rethrow;
    }
    final sent = receipt(confirmed: true);
    _web.track(sent);
    if (!mounted) return;
    Navigator.pop(context, sent);
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
      contentPadding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        children: [
          Icon(Icons.upload_file_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          const Expanded(child: Text('UYAP’a evrak gönder')),
        ],
      ),
      content: SizedBox(
        width: _case == null ? 620 : 720,
        height: _web.connected
            ? (_case != null ? 590 : (_cases.isEmpty ? 450 : 590))
            : 480,
        child: ListView(
          children: [
            if (_busy) ...[
              LinearProgressIndicator(borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 12),
              Text(
                _stage ?? 'İşlem sürüyor',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.45,
                  ),
                  border: Border.all(
                    color: theme.colorScheme.error.withValues(alpha: 0.35),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: theme.colorScheme.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_uncertain) ...[
              const Text(
                'Gönderim sonucu belirsiz. UYAP dosyasındaki evrak '
                've işlem kayıtlarını kontrol edin.',
              ),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) => UyapOperationsDialog(
                          focusReceipt: _uncertainReceipt,
                        ),
                      ),
                icon: const Icon(Icons.pending_actions),
                label: const Text('Devam Eden İşlemler’de kontrol et'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _uncertain = false;
                        _uncertainReceipt = null;
                        _error = null;
                      }),
                child: const Text('Kayıtları kontrol ettim'),
              ),
            ],
            if (!_web.connected) ...[
              UyapConnectView(onConnected: _connected),
            ] else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: UyapSessionChip(onDisconnected: _cleared),
              ),
              const Divider(),
              // Room for the first box's floating label.
              const SizedBox(height: 10),
              if (_case == null) ...[
                DropdownButtonFormField<String>(
                  initialValue: _jurisdiction,
                  decoration: _field('Yargı türü'),
                  style: TextStyle(
                    fontFamily: 'LiberationSans',
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                  ),
                  isExpanded: true,
                  iconSize: 20,
                  items: const [
                    DropdownMenuItem(value: '1', child: Text('Hukuk')),
                    DropdownMenuItem(value: '0', child: Text('Ceza')),
                    DropdownMenuItem(value: '2', child: Text('İcra')),
                    DropdownMenuItem(value: '6', child: Text('İdari')),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) {
                          if (v == null) return;
                          _jurisdiction = v;
                          _loadTypes();
                        },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Dosya durumu', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 12),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        textStyle: WidgetStatePropertyAll(
                          TextStyle(fontFamily: 'LiberationSans', fontSize: 12),
                        ),
                      ),
                      segments: const [
                        ButtonSegment(value: false, label: Text('Açık')),
                        ButtonSegment(value: true, label: Text('Kapalı')),
                      ],
                      selected: {_closed},
                      onSelectionChanged: _busy
                          ? null
                          : (values) {
                              setState(() {
                                _closed = values.first;
                                _courts = [];
                                _court = null;
                                _cases = [];
                                _case = null;
                                _documentTypes = [];
                                _documentType = null;
                              });
                              if (_type != null) _loadCourts(_type!);
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_types.isEmpty)
                  OutlinedButton(
                    onPressed: _busy ? null : _loadTypes,
                    child: const Text('Yargı birimlerini yükle'),
                  ),
                if (_types.isNotEmpty)
                  DropdownButtonFormField<UyapOption>(
                    key: ValueKey('uyap-types-$_jurisdiction'),
                    initialValue: _type,
                    decoration: _field('Mahkeme türü'),
                    style: TextStyle(
                      fontFamily: 'LiberationSans',
                      fontSize: 13,
                      color: theme.colorScheme.onSurface,
                    ),
                    isExpanded: true,
                    iconSize: 20,
                    menuMaxHeight: 320,
                    items: [
                      for (final t in _types)
                        DropdownMenuItem(
                          value: t,
                          child: Text(
                            t.label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) {
                            if (v != null) _loadCourts(v);
                          },
                  ),
                if (_courts.isNotEmpty) const SizedBox(height: 12),
                if (_courts.isNotEmpty)
                  DropdownButtonFormField<UyapOption>(
                    key: ValueKey('uyap-courts-${_type?.id}-$_closed'),
                    initialValue: _court,
                    decoration: _field('Mahkeme'),
                    style: TextStyle(
                      fontFamily: 'LiberationSans',
                      fontSize: 13,
                      color: theme.colorScheme.onSurface,
                    ),
                    isExpanded: true,
                    iconSize: 20,
                    menuMaxHeight: 320,
                    items: [
                      for (final c in _courts)
                        DropdownMenuItem(
                          value: c,
                          child: Text(
                            c.label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            _court = v;
                            _cases = [];
                            _case = null;
                            _documentTypes = [];
                            _documentType = null;
                          }),
                  ),
                if (_court != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _year,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 13),
                          decoration: _field('Yıl', hint: 'İsteğe bağlı'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _number,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 13),
                          decoration: _field('Esas no', hint: 'İsteğe bağlı'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : _search,
                    child: const Text('Dosyaları getir'),
                  ),
                ],
                if (_cases.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Dosyalar · ${_cases.length}${_hasMoreCases ? '+' : ''}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    height: 210,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListView.builder(
                      itemCount: _cases.length,
                      itemBuilder: (context, index) {
                        final item = _cases[index];
                        return ListTile(
                          dense: true,
                          selected: _case?.sameCase(item) ?? false,
                          title: Text(
                            item.number,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            item.courtName,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: _busy ? null : () => _chooseCase(item),
                        );
                      },
                    ),
                  ),
                  if (_hasMoreCases)
                    TextButton(
                      onPressed: _busy ? null : _loadMoreCases,
                      child: const Text('Sonraki dosyaları yükle'),
                    ),
                ],
              ],
              if (_case != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    // A tint of the app's blue: the theme's primaryContainer
                    // is lilac, which nothing else in Folio uses.
                    color: theme.colorScheme.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.folder_open, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SEÇİLİ HEDEF DOSYA',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _case!.number,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              _case!.courtName,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _case = null;
                                _parties = [];
                                _documentTypes = [];
                                _documentType = null;
                                _attachments.clear();
                              }),
                        icon: const Icon(Icons.swap_horiz, size: 16),
                        label: const Text('Değiştir'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'DOSYA TARAFLARI · ${_parties.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                for (final party in _parties)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 95,
                          child: Text(
                            party.role,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            party.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (party.lawyer.isNotEmpty)
                          Flexible(
                            child: Text(
                              'Vekil: ${party.lawyer}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'GÖNDERİLECEK BELGE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _previewPdf == null
                          ? null
                          : () => _fullPreview(context),
                      icon: const Icon(Icons.open_in_full, size: 16),
                      label: const Text('Tam sayfa'),
                    ),
                  ],
                ),
                Text(
                  widget.documentName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                if (_previewPdf != null)
                  Container(
                    height: 270,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: PdfViewerWidget(bytes: _previewPdf!, chrome: false),
                  )
                else
                  Text(
                    'Önizleme oluşturulamadı: ${_previewError ?? 'Bilinmeyen hata'}',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                const SizedBox(height: 16),
              ],
              if (_documentTypes.isNotEmpty)
                DropdownButtonFormField<UyapDocumentType>(
                  key: ValueKey('uyap-doc-types-${_case?.id}'),
                  initialValue: _documentType,
                  decoration: _field('Evrak türü'),
                  style: TextStyle(
                    fontFamily: 'LiberationSans',
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                  ),
                  isExpanded: true,
                  iconSize: 20,
                  menuMaxHeight: 320,
                  items: [
                    for (final t in _documentTypes)
                      DropdownMenuItem(
                        value: t,
                        child: Text(
                          t.label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _documentType = v;
                          _attachments.clear();
                        }),
                ),
              if (_documentType != null) ...[
                TextField(
                  controller: _description,
                  maxLength: 350,
                  decoration: _field('Evrak açıklaması'),
                  style: const TextStyle(fontSize: 13),
                ),
                const Divider(),
                for (var i = 0; i < _attachments.length; i++)
                  Card(
                    key: ValueKey('attachment-${_attachments[i].name}'),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          ListTile(
                            title: Text(_attachments[i].name),
                            subtitle: Text(
                              '${_attachments[i].bytes.length} bayt',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: _busy
                                  ? null
                                  : () => setState(
                                      () => _attachments.removeAt(i),
                                    ),
                            ),
                          ),
                          DropdownButtonFormField<UyapDocumentType>(
                            initialValue: _attachments[i].documentType,
                            decoration: _field('Ek evrak türü'),
                            style: const TextStyle(fontSize: 13),
                            isExpanded: true,
                            iconSize: 20,
                            items: [
                              for (final t in _documentTypes)
                                if ((t.acceptedExtensions.isEmpty ||
                                        t.acceptedExtensions.contains(
                                          p
                                              .extension(_attachments[i].name)
                                              .toLowerCase(),
                                        )) &&
                                    _typeHasRoom(t, excluding: i))
                                  DropdownMenuItem(
                                    value: t,
                                    child: Text(t.label),
                                  ),
                            ],
                            onChanged: _busy
                                ? null
                                : (selected) {
                                    if (selected == null) return;
                                    final old = _attachments[i];
                                    setState(
                                      () => _attachments[i] = UyapUpload(
                                        old.name,
                                        old.bytes,
                                        description: old.description,
                                        documentType: selected,
                                      ),
                                    );
                                  },
                          ),
                          TextFormField(
                            key: ValueKey(
                              'description-${_attachments[i].name}',
                            ),
                            initialValue: _attachments[i].description,
                            maxLength: 350,
                            decoration: _field('Ek açıklaması'),
                            style: const TextStyle(fontSize: 13),
                            onChanged: (value) {
                              final old = _attachments[i];
                              _attachments[i] = UyapUpload(
                                old.name,
                                old.bytes,
                                description: value.trim(),
                                documentType: old.documentType,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_documentType!.attachmentMax > 0)
                  OutlinedButton.icon(
                    onPressed:
                        _busy ||
                            _attachments.length >= _documentType!.attachmentMax
                        ? null
                        : _addAttachment,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      'Ek evrak ekle '
                      '(${_attachments.length}/${_documentType!.attachmentMax})',
                    ),
                  ),
                if (_documentType!.attachmentMax == 0)
                  const Text('Bu evrak türü için UYAP ek evrak kabul etmiyor.'),
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
        if (_case != null && _documentType != null)
          FilledButton(
            onPressed: _busy || _uncertain || _previewPdf == null
                ? null
                : _send,
            child: const Text('Gönderimi incele'),
          ),
      ],
    );
  }
}
