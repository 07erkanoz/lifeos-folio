# Windows'ta yapay zekâ: CLI ayarları, kurulum ve giriş

## Denendi (23 Kasım 2026, Windows 11, Flutter 3.47.2)

- `lifeos_folio.exe --mcp` pencereli program olduğu hâlde borularla
  konuşuyor: `initialize` ve `tools/list` ~200 ms. Ayrı `folio-mcp.exe`
  gerekmedi. (Debug derlemesi stdout'a VM satırı yazar; release yazmaz.)
- Claude Code 2.1 (`%USERPROFILE%\.local\bin\claude.exe`): Folio'nun
  araçlarıyla TBK 49, 9 sn. 14.341 karakterlik komut satırı sorunsuz
  (`.exe` doğrudan, `cmd.exe` yok). Folio içinden soru da çalıştı.
- Codex 0.171 (OpenAI'nin kurucusu:
  `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin\codex.exe`): salt-okunur
  kumlama ve `talimat.md` ile TBK 49, 14,5 sn; Folio içinden de çalıştı.
  `-c` değerleri TOML: Windows yolu `jsonEncode` ile verilir (`\` kaçış).
- Program arama: PATH (`;`), `.local\bin`, `%APPDATA%\npm` (`.cmd` yerine
  paketteki `.exe`), WinGet, Bun, Volta, Antigravity, OpenAI Codex.
- Durdur: `taskkill /T /F` (`AiAssistant.stop`).
- Claude girişi: Windows'ta tarayıcıyı Claude kendisi açar.
- Folio Ajan: `lifeos_ajan.exe` derleniyor ve açılıyor; Vosk 0.3.45
  Windows paketi derlemede SHA-256 ile iniyor (`windows/vosk.cmake`).
  Medya: Windows medya tuşları. Eksik: Ajan'ın genel kısayolu (Windows
  yalnız hızlı aramayı kaydediyor).
- Henüz denenmedi: Antigravity, otomatik kurulum (bölüm 2), Codex girişi
  Folio'dan, telefondan sorulan sorunun Windows'ta cevaplanması.

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
