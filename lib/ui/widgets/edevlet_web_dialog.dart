import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:webview_windows/webview_windows.dart' as edge;

import '../../services/uyap/uyap_web_service.dart';

/// The e-Devlet page inside Folio on Windows, in Microsoft's WebView2. It
/// closes with the code e-Devlet sends the lawyer back with, or with null
/// when it is closed first.
class EdevletWebDialog extends StatefulWidget {
  const EdevletWebDialog({
    super.key,
    required this.page,
    required this.hint,
    this.isReturn,
    this.state,
  });

  final Uri page;
  final String hint;

  /// Whether a page is the return this login waits for; the web portal's
  /// when not given. The mobile API returns elsewhere, and a code for one
  /// is useless to the other.
  final bool Function(Uri url)? isReturn;

  /// The state this login sent, which the return must carry back.
  final String? state;

  static Future<String?> show(
    BuildContext context, {
    required Uri page,
    required String hint,
    bool Function(Uri url)? isReturn,
    String? state,
  }) => showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => EdevletWebDialog(
      page: page,
      hint: hint,
      isReturn: isReturn,
      state: state,
    ),
  );

  /// WebView2 keeps its profile beside the program by default, which an
  /// installation under Program Files cannot write to.
  static Future<void>? _environment;
  static Future<void> _prepare() =>
      _environment ??= edge.WebviewController.initializeEnvironment(
        userDataPath: p.join(Directory.systemTemp.path, 'folio-edevlet'),
      ).catchError((Object _) {});

  /// Whether WebView2 is there to show the page.
  static Future<bool> available() async {
    if (!Platform.isWindows) return false;
    try {
      return await edge.WebviewController.getWebViewVersion() != null;
    } catch (_) {
      return false;
    }
  }

  @override
  State<EdevletWebDialog> createState() => _EdevletWebDialogState();
}

class _EdevletWebDialogState extends State<EdevletWebDialog> {
  final _controller = edge.WebviewController();
  StreamSubscription<String>? _url;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await EdevletWebDialog._prepare();
      await _controller.initialize();
      // No one else's e-Devlet session, on a shared computer.
      await _controller.clearCookies();
      await _controller.clearCache();
      await _controller.setPopupWindowPolicy(
        edge.WebviewPopupWindowPolicy.sameWindow,
      );
      _url = _controller.url.listen(_watch);
      await _controller.loadUrl('${widget.page}');
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = 'e-Devlet sayfası açılamadı: $e');
    }
  }

  void _watch(String url) {
    final uri = Uri.tryParse(url);
    if (_done || uri == null) return;
    final returned =
        widget.isReturn?.call(uri) ??
        url.startsWith(UyapWebService.edevletReturn);
    if (!returned) return;
    if (widget.state != null && uri.queryParameters['state'] != widget.state) {
      return;
    }
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) return;
    _done = true;
    unawaited(_controller.stop());
    if (mounted) Navigator.pop(context, code);
  }

  @override
  void dispose() {
    unawaited(_url?.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 580,
        height: 760,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 6, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'e-Devlet ile UYAP girişi',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Vazgeç',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Text(widget.hint, style: theme.textTheme.bodySmall),
            ),
            const Divider(height: 1),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
                  : _controller.value.isInitialized
                  ? edge.Webview(_controller)
                  : const Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
    );
  }
}
