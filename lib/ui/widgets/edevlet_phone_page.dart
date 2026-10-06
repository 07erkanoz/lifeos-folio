import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/uyap/uyap_web_service.dart';

/// The e-Devlet page on a phone, full screen in the phone's own web view
/// (Android WebView, iOS WKWebView) (UYGULAMAPLANI §13). The lawyer signs
/// in there with e-Devlet's own means (mobil imza, e-Devlet şifresi);
/// the return is caught before it loads and the page closes with its
/// code, never with a password, which Folio does not see.
class EdevletPhonePage extends StatefulWidget {
  const EdevletPhonePage({
    super.key,
    required this.page,
    required this.hint,
    this.isReturn,
    this.state,
  });

  final Uri page;
  final String hint;
  final bool Function(Uri url)? isReturn;
  final String? state;

  static Future<String?> show(
    BuildContext context, {
    required Uri page,
    required String hint,
    bool Function(Uri url)? isReturn,
    String? state,
  }) => Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => EdevletPhonePage(
        page: page,
        hint: hint,
        isReturn: isReturn,
        state: state,
      ),
    ),
  );

  /// The code in [url] when it is the return this login waits for, with
  /// the state it sent; null otherwise.
  static String? codeOf(
    Uri url, {
    bool Function(Uri url)? isReturn,
    String? state,
  }) {
    final returned =
        isReturn?.call(url) ?? '$url'.startsWith(UyapWebService.edevletReturn);
    if (!returned) return null;
    if (state != null && url.queryParameters['state'] != state) return null;
    final code = url.queryParameters['code'];
    return code == null || code.isEmpty ? null : code;
  }

  @override
  State<EdevletPhonePage> createState() => _EdevletPhonePageState();
}

class _EdevletPhonePageState extends State<EdevletPhonePage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && _finish(uri)) return NavigationDecision.prevent;
            return NavigationDecision.navigate;
          },
          onUrlChange: (change) {
            final uri = Uri.tryParse(change.url ?? '');
            if (uri != null) _finish(uri);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      );
    _start();
  }

  Future<void> _start() async {
    // No one else's e-Devlet session.
    await WebViewCookieManager().clearCookies();
    await _controller.clearCache();
    await _controller.loadRequest(widget.page);
  }

  bool _finish(Uri uri) {
    if (_done) return true;
    final code = EdevletPhonePage.codeOf(
      uri,
      isReturn: widget.isReturn,
      state: widget.state,
    );
    if (code == null) return false;
    _done = true;
    if (mounted) Navigator.pop(context, code);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('e-Devlet ile giriş', style: TextStyle(fontSize: 16)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(34),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  widget.hint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
            ],
          ),
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
