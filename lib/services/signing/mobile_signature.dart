import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../editor/document_history.dart';
import 'signed_data.dart';
import 'udf_signing_service.dart';

/// The operators UYAP's mobile signature service knows, with its own codes —
/// read from the UYAP editor's bytecode, not guessed.
enum MobileOperator {
  turkcell(1, 'Turkcell'),
  turkTelekom(2, 'Türk Telekom'),
  vodafone(3, 'Vodafone');

  const MobileOperator(this.code, this.label);
  final int code;
  final String label;

  static MobileOperator? byCode(int? code) =>
      values.where((o) => o.code == code).firstOrNull;
}

class MobileSignatureException implements Exception {
  final String message;
  const MobileSignatureException(this.message);
  @override
  String toString() => message;
}

/// A signature asked for and not yet given: the code the phone will show,
/// and what is needed to wait for the answer.
class MobileSigningRequest {
  final String path, transaction, code;
  final Uint8List original;
  final bool alreadySigned;
  const MobileSigningRequest({
    required this.path,
    required this.transaction,
    required this.code,
    required this.original,
    required this.alreadySigned,
  });
}

/// UYAP's mobile signature service — the one the UYAP editor itself calls,
/// open to anyone, no account needed.
///
/// ══ It must be spoken to as the editor speaks to it. ══ The service tells
/// its clients apart by `User-Agent`. One it does not know is not refused: it
/// asks the phone, the signer approves, and back comes a well-formed PKCS#7
/// with the signer's real certificate — over data whose first 100 bytes it
/// set to zero. No error, no warning; the UDF opens and looks signed, and
/// UYAP rejects it. With the editor's `Axis/1.3` it happened 0 times in 5,
/// with curl's own header 5 times in 5. [SignedData.sign] refuses such a
/// signature all the same, since nothing else would notice.
class MobileSignatureClient {
  MobileSignatureClient({Uri? endpoint}) : endpoint = endpoint ?? _endpoint;

  /// HTTPS: what is sent is the document's text and the signer's number. The
  /// service answers the same way on it as on plain HTTP.
  static final _endpoint = Uri.parse(
    'https://vatandas.uyap.gov.tr/mimzaclient/services/MImzaSigner',
  );
  static const _namespace = 'http://client.mimza.uyap.gov.tr';

  /// What the phone shows about the request; the editor sends exactly this.
  static const display = 'Evrak Mobil Imza Talebi';

  /// The headers the editor's Axis 1.3 client sends. Do not change the
  /// User-Agent; see the class comment.
  static const headers = {
    'Content-Type': 'text/xml; charset=utf-8',
    'User-Agent': 'Axis/1.3',
    'Accept':
        'application/soap+xml, application/dime, multipart/related, text/*',
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
  };

  final Uri endpoint;
  HttpClient? _client;

  /// The SOAP envelope for [operation], byte for byte the editor's: the
  /// operation in the service's namespace, its fields in none.
  static String envelope(String operation, Map<String, String> fields) {
    final body = fields.entries
        .map((e) => '<${e.key} xmlns="">${_escape(e.value)}</${e.key}>')
        .join();
    return '<?xml version="1.0" encoding="UTF-8"?>'
        '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"'
        ' xmlns:xsd="http://www.w3.org/2001/XMLSchema"'
        ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<soapenv:Body><$operation xmlns="$_namespace">$body</$operation>'
        '</soapenv:Body></soapenv:Envelope>';
  }

  /// Sends the text to be signed. Answers with the transaction to wait on and
  /// the code the signer's phone will show. Nothing reaches the phone yet.
  Future<({String transaction, String code})> requestCode(
    List<int> content,
    String phone,
    MobileOperator operator,
  ) async {
    final answer = await _call('getHash', {
      'dataToBeSigned': base64Encode(content),
      'telNo': phone,
      'gsmOperator': '${operator.code}',
    }, const Duration(seconds: 60));
    _check(answer, 'Doğrulama kodu alınamadı.');
    final transaction = field(answer, 'apTransId');
    if (transaction == null || transaction.isEmpty) {
      throw const MobileSignatureException(
        'Mobil imza servisi işlem numarası vermedi.',
      );
    }
    return (transaction: transaction, code: field(answer, 'fingerPrint') ?? '');
  }

  /// Sends the request to the phone and waits until the signer answers.
  /// The signature, with the content inside it, and the signer's TC number.
  Future<({Uint8List signature, String identity})> awaitSignature(
    String transaction,
  ) async {
    final answer = await _call('getSignature', {
      'dataToBeDisplayed': display,
      'apTransId': transaction,
    }, const Duration(minutes: 5));
    _check(answer, 'İmza tamamlanamadı.');
    final data = field(answer, 'data');
    if (data == null || data.isEmpty) {
      throw const MobileSignatureException(
        'Mobil imza servisi imza verisi göndermedi.',
      );
    }
    return (
      signature: base64Decode(data.replaceAll(RegExp(r'\s'), '')),
      identity: field(answer, 'identityNo') ?? '',
    );
  }

  /// Stops waiting. The request on the phone may still be answered; the
  /// answer is then not used.
  void cancel() {
    _client?.close(force: true);
    _client = null;
  }

  Future<String> _call(
    String operation,
    Map<String, String> fields,
    Duration timeout,
  ) async {
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = headers['User-Agent'];
    try {
      final request = await client.postUrl(endpoint);
      headers.forEach(request.headers.set);
      request.headers.set('SOAPAction', '"$operation"');
      request.add(utf8.encode(envelope(operation, fields)));
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw MobileSignatureException(
          'Mobil imza servisi ${response.statusCode} yanıtı verdi.',
        );
      }
      return text;
    } on TimeoutException {
      throw const MobileSignatureException(
        'Mobil imza servisinden yanıt gelmedi. Onay süresi dolmuş olabilir.',
      );
    } on SocketException catch (e) {
      throw MobileSignatureException(
        'UYAP mobil imza servisine ulaşılamadı: ${e.message}',
      );
    } on HttpException catch (e) {
      throw MobileSignatureException(
        'UYAP mobil imza servisine ulaşılamadı: ${e.message}',
      );
    }
  }

  static void _check(String answer, String fallback) {
    if (field(answer, 'resultCode') != '0') {
      final message = field(answer, 'message');
      throw MobileSignatureException(
        message == null || message.isEmpty ? fallback : message,
      );
    }
  }

  /// The text of the first element called [name], whatever its prefix.
  static String? field(String xml, String name) {
    final match = RegExp(
      '<(?:\\w+:)?$name(?:\\s[^>]*)?>(.*?)</(?:\\w+:)?$name>',
      dotAll: true,
    ).firstMatch(xml);
    return match == null ? null : _unescape(match.group(1)!).trim();
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _unescape(String text) => text
      .replaceAllMapped(
        RegExp(r'&#(x?)([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(
          int.parse(m.group(2)!, radix: m.group(1)!.isEmpty ? 10 : 16),
        ),
      )
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

/// Signs a UDF on disk with a mobile signature, in the two steps the phone
/// needs: [start] gets the code to compare, [finish] waits for the approval
/// and writes the signed file in place.
class MobileUdfSigner {
  MobileUdfSigner({MobileSignatureClient? client})
    : client = client ?? MobileSignatureClient();
  final MobileSignatureClient client;

  /// `05XXXXXXXXX` from however the number was typed, or null.
  static String? phone(String typed) {
    var digits = typed.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('90') && digits.length == 12) {
      digits = digits.substring(2);
    }
    if (digits.length == 10 && digits.startsWith('5')) digits = '0$digits';
    return RegExp(r'^05\d{9}$').hasMatch(digits) ? digits : null;
  }

  Future<MobileSigningRequest> start(
    String path,
    String phone,
    MobileOperator operator,
  ) async {
    final original = await File(path).readAsBytes();
    final content = SignedData.content(original);
    final signed = UdfSigningService.isSigned(original);
    // Checked before the phone is asked: afterwards the signer would have
    // approved for nothing.
    if (signed) {
      final existing = SignedData.signatureOf(original);
      if (existing == null || !SignedData.covers(existing, content)) {
        throw const MobileSignatureException(
          'Belgedeki mevcut imza bu metinle eşleşmiyor; imzanız eklenemez. '
          'Belgenin imzasız bir kopyasını imzalayın.',
        );
      }
    }
    final answer = await client.requestCode(content, phone, operator);
    return MobileSigningRequest(
      path: path,
      transaction: answer.transaction,
      code: answer.code,
      original: original,
      alreadySigned: signed,
    );
  }

  /// Waits for the signer, checks the signature covers the document, and
  /// puts the signed UDF where the unsigned one was — unless the file changed
  /// meanwhile. The document as it was before is kept in its history first.
  Future<String> finish(MobileSigningRequest request) async {
    final answer = await client.awaitSignature(request.transaction);
    final Uint8List output;
    try {
      output = SignedData.sign(request.original, answer.signature);
    } on FormatException catch (e) {
      throw MobileSignatureException(e.message);
    }
    final history = DocumentHistory.instance;
    Future<void> keep(List<int> bytes, String kind) => history.capture(
      document: DocumentHistory.documentKey(request.path),
      name: p.basename(request.path),
      sourcePath: request.path,
      format: 'udf',
      bytes: bytes,
      kind: kind,
    );
    await keep(
      request.original,
      request.alreadySigned ? 'signed' : 'before-sign',
    );
    final path = UdfSigningService.saveSigned(
      request.path,
      request.original,
      output,
    );
    try {
      await keep(output, 'signed');
    } catch (_) {
      // The signature is on disk; the history copy is a convenience.
    }
    return path;
  }
}
