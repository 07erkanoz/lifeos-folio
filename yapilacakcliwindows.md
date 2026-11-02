# Windows'ta yapay zekâ: CLI ayarları, kurulum ve giriş

Durum (2 Kasım 2026): Yapay zekâ özellikleri yalnız Linux'ta açık
(`AiAssistant.available`, `lib/services/ai/ai_assistant.dart`). Bu not,
Windows sürümüne getirmek için yapılacakları ve Windows'ta denenecekleri
sıralar. Tahmin: 2–3 gün kod ve 1–2 tur gerçek Windows denemesi.

## Karar

- Python ya da Node kurulum paketine eklenmez. Üç programın hiçbiri Python
  ile kurulmaz; paketi büyütür ve asıl sorunları çözmez.
- Programlar kurulum paketine gömülmez. Claude Code ve Antigravity ticari;
  dağıtma iznimiz yok. Codex Apache 2.0 olsa da gömülürse her Folio
  sürümünde onu bizim güncellememiz gerekir.
- Avukat yapay zekâyı açıp bir program seçtiğinde Folio onu, avukatın
  onayıyla, resmî kaynağından kendi klasörüne indirir. Kurulumda hiçbir şey
  indirilmez; PATH ya da yönetici izni gerekmez.

## 0. Önce denenecek (en büyük belirsizlik)

Folio'nun araç sunucusu `lifeos_folio.exe --mcp` Windows'ta standart girdi
ve çıktıyla konuşabiliyor mu? Flutter'ın Windows uygulaması pencereli
(GUI) bir programdır; üst süreçten gelen borularla JSON-RPC alıp verip
veremediği bilinmiyor.

- Küçük bir Windows derlemesi: yalnız `--mcp` ile başlayıp `initialize` ve
  `tools/list` cevaplıyor mu, bakılır.
- Olmazsa: araç sunucusu için ayrı, konsol türünde küçük bir yardımcı
  program (`folio-mcp.exe`) gerekir.

## 1. Programları bulup çalıştırmak (≈1 gün)

- `AiAssistant.available`: Windows'u da aç (Ofis'te kapalı kalır).
- Program arama (`find`): Folio'nun indirdiği klasör, sonra
  `%LOCALAPPDATA%`, `%APPDATA%\npm`, `%USERPROFILE%\.local\bin` gibi
  kurucuların koyduğu yerler.
- `.cmd` kısayolları `cmd.exe` üzerinden çalışır ve komut satırı 8191
  karakterle sınırlıdır. Folio'nun kural metni (`--system-prompt`) ve
  `--mcp-config` bu sınırı aşar. Çözüm: kısayolu atlayıp asıl programı
  (`claude.exe`, `codex.exe`) doğrudan çalıştırmak; gerekirse uzun ayarları
  dosyayla vermek (Codex'te kural metni zaten `talimat.md` dosyasıyla).
- Durdur: Windows'ta `process.kill()` yalnız ilk süreci kapatır. Süreç
  ağacı `taskkill /T /F /PID` ile kapatılmalı (zaman aşımında da).
- Codex'in salt-okunur kumlaması (`-s read-only`, `sandbox_mode`) ve
  Antigravity'nin `--sandbox` ayarı Windows'ta denenmeli.
- `mcpEnvironment`: Linux'a özgü değişkenler (DISPLAY, XDG_*) yerine
  Windows'ta gerekenler (APPDATA, LOCALAPPDATA, USERPROFILE, TEMP).
- Sohbet sürdürme (`AiThread`): Claude oturumu çalıştığı klasöre bağlı;
  `%TEMP%\folio-yz-<sohbet>` ile aynı yol korunmalı.
- Yazdırma ve pencere düzeltmeleri Linux'a özgüydü; Windows'u etkilemez.

## 2. Otomatik kurulum (≈yarım–1 gün)

Her indirme öncesi avukattan onay: ne indirilecek, nereden, boyutu,
programın kullanım koşulları.

- Claude Code: Anthropic'in resmî Windows kurucusu / tek dosyalık
  `claude.exe`. Kendini güncelleyebiliyor.
- Codex: GitHub sürümlerindeki tek dosyalık Windows `codex.exe` (Node
  istemez). npm yolu kullanılmaz.
- Antigravity: kendi kurucusu.
- İşe başlamadan her birinin güncel dağıtım yolu ve imza/SHA denetimi
  kontrol edilecek; indirilen dosya doğrulanmadan çalıştırılmaz.

## 3. Giriş (≈yarım gün)

- `AiLogin` aynen kullanılır: Claude `auth login --claudeai` (tarayıcı),
  Codex `login --device-auth` (cihaz kodu).
- Windows'ta programın açtığı konsol penceresi gizlenmeli.
- Antigravity'ye Folio'dan giriş yapılmaz (Linux'taki gibi).

## 4. Metinler

- Gizlilik metni, Kullanım Koşulları ve yardım: "şimdilik yalnız Linux'ta"
  ifadeleri; Windows'ta programın Folio tarafından indirildiği.
- Site: `~/projeler/lifeosweb/src/pages/PrivacyPolicyPage.tsx` (TR ve EN).

## 5. Windows'ta deneme listesi

1. `lifeos_folio.exe --mcp`: `initialize`, `tools/list`, bir araç çağrısı.
2. Claude, Codex, Antigravity'nin bulunması; giriş durumu.
3. Uzun kural metniyle soru: komut satırı sınırına takılmıyor mu?
4. Folio'nun araçlarıyla dosya sorusu: evrak listesi, evrak okuma, UYAP'tan
   evrak indirme.
5. Durdur: arkada program kalıyor mu (Görev Yöneticisi)?
6. Sohbeti sürdürme: ikinci soruda ilk sorudaki bilgiyi hatırlıyor mu?
7. Otomatik kurulum: onay, indirme, doğrulama, ilk çalıştırma.
8. Giriş: Claude tarayıcıyla, Codex cihaz koduyla.
9. Telefondan sorulan sorunun Windows bilgisayarda cevaplanması.
