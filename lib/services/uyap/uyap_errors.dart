import 'dart:async';
import 'dart:io';

/// What went wrong talking to UYAP, in words a lawyer can act on: whether
/// the fault is the connection, UYAP's own server or what UYAP said, and
/// what to do. UYAP's own words, when it gave any, are quoted as they came.

/// [error] met reaching [who] ("UYAP Mobil", "UYAP Web").
String uyapFault(String who, Object error) => switch (error) {
  HandshakeException() =>
    '$who ile güvenli bağlantı kurulamadı. Cihazın tarih ve saati yanlışsa '
        'düzeltin; doğruysa sorun UYAP’ta olabilir.',
  SocketException() =>
    '$who’e ulaşılamadı. İnternet bağlantınızı denetleyin; bağlantı '
        'varsa UYAP şu an yanıt vermiyor olabilir.',
  TimeoutException() =>
    '$who zamanında yanıt vermedi. UYAP yoğun ya da arızalı olabilir; bir '
        'süre sonra yeniden deneyin.',
  HttpException() =>
    '$who bağlantıyı yarıda kesti. Bir süre sonra yeniden deneyin.',
  _ => '$error',
};

/// [who] answered with HTTP [status], and [said] if it said anything.
String uyapStatus(String who, int status, [String said = '']) {
  final words = said.trim().isEmpty || said == 'beklenmeyen yanıt'
      ? ''
      : ' UYAP’ın yanıtı: “${said.trim()}”.';
  if (status >= 500) {
    return '$who’de sunucu hatası var (HTTP $status).$words Sorun UYAP’ta; '
        'UYAP’ın kendi uygulamaları da etkilenmiş olabilir. Bir süre sonra '
        'yeniden deneyin.';
  }
  if (status == 429) {
    return '$who çok sık istek gönderildiğini bildirdi (HTTP 429). Folio '
        'kendiliğinden yaptığı istekleri bir süre bekletir; birkaç dakika '
        'sonra yeniden deneyin.';
  }
  if (status == 404) {
    return '$who bu işlemi tanımadı (HTTP 404).$words UYAP hizmetinde bir '
        'değişiklik olmuş olabilir.';
  }
  return '$who isteği kabul etmedi (HTTP $status).$words';
}

/// [who] answered, but refused with [said]: its own words.
String uyapRefused(String who, String said) =>
    '$who isteği reddetti: “${said.trim()}”. Bu ileti UYAP’tan geliyor; '
    'UYAP’ın kendi uygulamasında da görülüyorsa sorun UYAP’tadır.';
