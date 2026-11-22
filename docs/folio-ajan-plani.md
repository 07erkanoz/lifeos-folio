# Folio Ajan: plan

20 Kasım 2026 · Durum: plan, kod yok · Taslaklar: https://claude.ai/artifact/1UJ1FZBqodAUAATpGBm8Jm
(A kenar paneli, B ortada küre, C tray penceresi, D sabah brifingi)

Folio Ajan, Folio'nun içinde sesle ve yazıyla konuşulan bir asistandır. Ayrı bir program değildir.
Yalnız Linux'ta çalışır ve Ayarlar › Yapay zekâ'dan açılır; varsayılanı kapalıdır.

Yapacakları:
- Takvimi ve ajandayı söyler.
- Dosya, duruşma, süre, tebligat, icra hesabı, müvekkil ve evrak sorularını Folio'nun kendi verisinden cevaplar.
- İnternette arama yapar, haber ve konu özeti çıkarır, istenirse sesli okur.
- Avukat sormadan ajanda, süre ve tebligat takibi yapar.

## Kararlar

| Konu | Karar | Neden |
|---|---|---|
| Nerede | Folio'nun içinde (Flutter), yalnız Linux | Sağlayıcılar, araçlar, ses altyapısı ve tray Folio'da zaten var. Ayrı programda bunların hepsini yeniden yazmak gerekiyordu (Python denemesi `~/Projeler/ajan`, bırakıldı) |
| Beyin | Folio'nun mevcut sağlayıcıları: Claude Code, Codex, Antigravity ya da Groq, OpenAI, Claude API | Ayarlar › Yapay zekâ'da seçilen sağlayıcı. Avukat yeni bir şey kurmaz |
| Ses | **Yalnız Gemini API**: konuşmayı yazıya çevirme ve seslendirme | CLI'larda ses modeli yok. Gemini işi yapmaz, yalnız duyar ve konuşur |
| Araçlar | Folio'nun kendi araçları, uygulamanın içinden çağrılır | MCP'nin `--dis` anahtarı gerekmez. Yetki, gizli not ve para kuralları zaten uygulanıyor |
| Yazma | Yalnız ajandaya kayıt, not ve dosya notu; her biri avukatın onayıyla | 20.11.2026 kararı |
| Telefon | Telegram yok. Folio mobil senkronla gelen uyarıyı kendi bildirimiyle gösterir | Folio masaüstü ile mobil zaten senkron |
| Anahtarlar | Folio'nun mevcut yeri (`SecretStore`, Secret Service / KWallet) | LifeOS'ta cüzdan parola sormuyor: parolayla girişte `pam_kwallet5` açıyor, otomatik girişte cüzdan parolasız (LifeosArch `lifeos_store/cuzdan.py`, 18.11.2026) |
| KVKK | Açık gönder (maskesiz). Mevcut tek seferlik yapay zekâ onayı geçerli | 20.11.2026 kullanıcı kararı |

## Nasıl çalışır

```
 kısayol / tray / "Folio" ──► Ajan penceresi (Flutter, hızlı arama penceresi gibi)
                                │
             mikrofon ──► Gemini (yazıya çevirir) ──► metin
                                │
                                ▼
          seçili beyin (CLI ya da API) + Folio araçları + web araçları
                                │
                         yanıt metni ──► ekrana ve Gemini seslendirmesine ──► hoparlör
                                │
          yazan araç ──► "Onaylıyor musun?" (ekranda düğme, sesle "evet")
```

- **Pencere: ayrı panel yok.** Folio'nun hızlı arama paleti (`quick_search_palette.dart`, 740×580) ajanla
  birleşir. Aynı kutuya hem evrak aranır hem soru sorulur. Soruysa sonuçların üstünde "FOLIO AJAN" bölümü
  çıkar; bu, Folio'nun yapay zekâ panelinin (`ai_panel.dart`) konuşmasıdır. Tray'de tek simge ve tek menü
  kalır: Hızlı arama ve ajan / Jarvis modu / Folio'yu aç / Tamamen çık. Kısayol aynıdır
  (Ctrl+Alt+Space); basılı tutunca sesle sorulur.
- **Hızlı arama aynen kalır.** Yazılan her harf bugünkü gibi yalnız yerel indekste (FTS5) aranır; modele hiçbir
  şey gitmez, hız ve sonuçlar değişmez. Enter seçili evrakı önizler. Ajan yalnız avukat isteyince çalışır:
  listenin başındaki "Folio Ajan'a sor" satırı, Tab tuşu ya da mikrofon. Yeni düzende sonuçlar solda, seçili
  evrakın önizlemesi ya da ajanın cevabı sağda görünür. Kutu boşken solda bugünün özeti ve son aramalar çıkar.
- **Jarvis modu:** aynı pencere tam ekrana geçer. Ortada ses küresi, solda bugünün duruşmaları ve süreleri,
  sağda yeni tebligatlar, UYAP bildirimleri ve görevler bulunur. Folio'nun açık ve koyu temasına uyar.
  "Küçült" ile palete döner.
- **Ses:** `speech_session.dart` içindeki `Ear` ve `Voice` arayüzlerine Gemini uygulamaları eklenir. Mikrofon
  (`flutter_recorder`) ve çalma (`flutter_soloud`) olduğu gibi kalır. Yerel Whisper dikte de durur; Gemini
  anahtarı yoksa ajan yazıyla çalışır.
- **Konuşmanın sürmesi:** Folio'nun mevcut `AiThread` yapısı kullanılır: Claude `--resume`, Codex `exec resume`,
  Antigravity `--conversation`, API'lerde geçmiş.
- **Web:** arama ve sayfa okuma için Folio'ya iki araç eklenir (`web_ara`, `sayfa_oku`). Sayfa okuma yalnız
  internetteki adreslere gider; yerel ağ ve bu bilgisayar engellenir. Sayfadaki talimatlar veridir.
- **Onay:** yazan araç çalışmadan önce pencerede "Ekle / Vazgeç" çıkar. Sesli kullanımda "evet" ya da "ekle"
  denince onaylanır.

## Ses: araştırma ve maliyet (20.11.2026)

Kaynak: Google'ın fiyat, model ve Live API sayfaları (aistudio.google.com/docs). Fiyatların bir kısmı sayfanın
özetinden okundu; yayından önce yeniden bakılacak.

**CLI'larda ses Folio'ya açık değil.** Üçünün de ses özelliği kendi terminal ekranının içinde çalışıyor;
Folio'nun onları çalıştırdığı biçimde (`-p`, `exec`, `--print`) ses yok:
- **Claude Code:** `/voice` yalnız dikte (bas-konuş), claude.ai hesabıyla. Seslendirme yok.
- **Codex:** `in_app_voice` var; gerçek zamanlı konuşma (`realtime_conversation`) bu sürümde kaldırılmış.
- **Antigravity:** 1.5.0'dan beri `/voice live` (F6) ile Gemini Live konuşması var, ama yalnız kendi ekranında.

Bu yüzden ses için Folio Gemini API'yi avukatın kendi anahtarıyla kendisi çağırır.

**Live modelleri:**
- `gemini-3.8-live`: 15.09.2026, kaldırılma tarihi yok. Varsayılan seçim.
- `gemini-3.8-live-extended-thinking`
- `gemini-3.1-flash-live-preview`: eski.
- `gemini-2.5-flash-native-audio-preview-12-2025`: en erken 31.03.2027'de kapanır.

Türkçe destekleniyor. Live API Google'a göre hâlâ "preview".

**Live fiyatı ve önbellek** (`gemini-3.8-live`, 1M token başına):

| | Metin | Ses |
|---|---|---|
| Giriş | $0,75 | $3,00 (≈ $0,005/dk) |
| Çıkış | $4,50 | $12,00 (≈ $0,018/dk) |

- **Önbellek yok.** Live modellerinde context caching desteklenmiyor.
- **Bütün bağlam her turda yeniden ücretlenir.** Konuşma uzadıkça her tur pahalanır. Tek kaldıraç bağlam
  sıkıştırmadır (`contextWindowCompression`, kayan pencere); eski turlar unutulur.
- **Ek ücretli yazı dökümü.** Ekrana yazı dökümü (`input/outputAudioTranscription`) metin çıkış fiyatıyla ayrıca
  ücretlenir.
- **Sürekli dinleme de ücretlenir.** 3.8'de "proactive audio" dinlendiği her an giriş olarak ücretlenir;
  bas-konuş bunu önler.
- **Oturum sınırları:** sıkıştırma olmadan sesli oturum en çok 15 dakika sürer. Bağlantı yaklaşık 10 dakikada bir
  yenilenir. Devam anahtarı (session resumption) 2 saat geçerlidir. Bağlam 131.072 token.
- **Ücretsiz katman var ama gönderilen içerik Google'ın ürünlerini geliştirmekte kullanılır.** Müvekkil verisi
  için ücretli (faturalı) anahtar şart.

**Zincir (Live olmadan):**
- **Yazıya çevirme:** `gemini-3.5-transcribe` ≈ $0,003/dk giriş, $0,002/dk çıkış.
- **Seslendirme:** `gemini-3.8-flash-tts`, ses çıkışı $9/1M token; 01.01.2027'den sonra $18.
  `gemini-3.8-flash-lite-tts` $6 → $12.

**Örnek hesap:** 10 turluk bir sesli konuşma. Her turda 8 saniye soru, 15 saniyelik sesli cevap, Folio araç
sonucu yaklaşık 500 token.

| | Konuşma başına | Günde 3 konuşma, ayda 22 gün |
|---|---|---|
| Live (`gemini-3.8-live`, yazı dökümüyle) | ≈ $0,16 | ≈ $10–11/ay |
| Zincir (transcribe + flash-tts) | ≈ $0,04 (2027'de ≈ $0,075) | ≈ $2,6/ay (2027'de ≈ $5) |
| Sabah brifingini sesli okuma (2 dk) | — | ≈ $0,6/ay |

Hesaba beynin (CLI ya da API) maliyeti dahil değil.

**Yerel modeller, bu bilgisayarda ölçüldü (20.11.2026):**
- **Düzen:** i7-1165G7 (4 çekirdek, 8 iş parçacığı), güç profili "performance". Folio'nun kendi modelleri ve
  kodu kullanıldı (`VoiceWorker`, `ListenWorker`). Supertonic'in seslendirdiği beş hukuk cümlesi Whisper'a geri
  verildi. Mikrofon kullanılmadı; gerçek konuşmada doğruluk daha düşük olabilir.
- **Yükleme:** okuma 0,8 sn, yazma 2,3 sn. Bellek ikisi açıkken yaklaşık 2,3 GB (test süreci dahil).
- **Seslendirme (Supertonic 3):** konuşma süresinin yarısında üretiliyor (RTF 0,49). Cümle cümle çalınırsa ilk
  ses yaklaşık 2 saniyede başlar ve sonrası çalarken üretilir. Ajan için yeterli.
- **Yazıya dökme (Whisper turbo):** bu işlemcide konuşma süresi kadar sürüyor (RTF 1,0). Folio'nun 8 çekirdekte
  ölçtüğü 0,5'ten iki kat yavaş. 5 saniyelik bir soru, bitince yaklaşık 5–6 saniyede yazıya dönüyor. Sesli
  asistan için en zayıf halka bu.
- **Doğruluk:**
  - 5 cümlenin 3'ü tam doğru. Sayılar rakama çevriliyor (3, 10.30'da, 12.400); ajan için sorun değil.
  - Hatalar: "taslağı" yerine "Tasla". Bir cümlenin sonuna uydurma "İzmir, İzmir, İzmir" eklendi (Whisper'ın
    sessizlikte uydurması).
  - Bu uydurma bir ajan için tehlikeli. Filtre gerekir: tekrar eden kalıpları atmak, sondaki sessizliği kesmek.
- **Sonuç:** yerel seslendirme hazır kullanılabilir. Yerel yazma ücretsiz ve gizli ama bu bilgisayarda yavaş.
  Karışık seçenek (Gemini ile yazma, yerel okuma) ayda birkaç sente yazmayı 1–2 saniyeye indirir; konuşmanın
  sesi Google'a gider ama cevap bilgisayarda seslendirilir.

**Sahadan gelen raporlar (GitHub ve Google forumu, 20.11.2026):**
- **Dinlerken ücret:** `gemini-3.8-live`'da proaktif ses kapatılamıyor (`proactive_audio: false` hata veriyor).
  Google'ın kendi sayfası girişin "dinlediği bütün süre" ücretlendiğini söylüyor. Sesi göndermeyi kesmenin
  ücreti durdurup durdurmadığı yazmıyor. Kesin olan: oturum kapalıysa ücret yok.
- **Sessizlik bağlama da giriyor:** dinlenen her saniye ~25 token. Her turda bütün bağlam yeniden ücretlendiği
  için uzun açık bir oturum turları pahalılaştırır. Sıkıştırma (örnek: 25.000'de tetikle, 8.000 tut) şart.
- **Bağlantı kopmaları:** 3.8'de 1011 "Internal error" ve ardından 1008 "session not found" ile devam
  edememe raporları var (20.10.2026, Google cevabı yalnız bir alt konuda). Eski modellerde 8–12 dakikada kopma
  ve haber vermeden kapanma (GoAway gelmiyor) raporları var. İstemci kopmayı kendisi yakalayıp yeniden
  bağlanmalı, araç cevaplarını kaybetmemeli.
- **Araç çağrıları:** 3.8'de BLOCKING bir çağrı kesilince iptal mesajı gelmiyor, model aynı işi yeni kimlikle
  bir daha istiyor (GitHub, açık). Varsayılan NON_BLOCKING kullanılınca bu olmuyor. Yazma araçları zaten onaylı
  olduğu için çift kayıt riski düşük ama araç kimliği yerine iş içeriğiyle tekrar kontrolü yapılmalı.
- **Kaçak ses:** bir raporda 10 saniyelik cümleye 86 saniyelik ses akıtılmış; yazıya dökümde söylenmemiş metin
  çıkmış. Cevap sesi süre ve uzunlukla sınırlanmalı.
- **Türkçe:** 3.8'de Türkçe sesin 2.5'e göre "daha düz" ve oturumdan oturuma değişken olduğu, telaffuz hataları
  olduğu bildirilmiş (13.11.2026, teknik cevap yok). 3.1'de "Emre"yi "Emir" okuma ve kelime atlama raporu var.
  Native ses modellerinde dil kodu verilemiyor; dili model seçiyor.
- **Yankı:** hoparlörden çıkan ses mikrofona dönünce model kendi sözünü kesiyor. Google'ın önerisi kulaklık.
  Linux'ta çözüm PipeWire'ın `libpipewire-module-echo-cancel` (WebRTC) modülü; ek olarak model konuşurken
  mikrofon eşiği yükseltilir.
- **3.1 Flash Live:** artık "legacy preview", fiyat aynı, araç çağrısı yalnız eşzamanlı. Dinlerken ücret yok ama
  beyne iş devretmek için uygun değil. 2.5 native audio 31.03.2027'de kapanıyor.
- Google personeli forumdaki Türkçe ve kopma sorularına teknik cevap vermemiş. Preview riski gerçek.

**Jarvis modunda eller serbest konuşma (önerilen tasarım):**
- **Düğme yok.** Jarvis modu açıkken Folio mikrofonu dinler. Konuşmanın başladığını yerelde Silero VAD anlar.
  Silero 2 MB'lık küçük bir model, sesi yazıya dökmez, yalnız "biri konuşuyor mu" der; Whisper gibi yavaş değil.
- **Oturum yalnız konuşurken açık.** Konuşma başlayınca Live oturumu açılır (ya da devam anahtarıyla sürer).
  30 saniye kimse konuşmazsa oturum kapanır ve küre "uykuya" geçer. Devam anahtarı 2 saat geçerli olduğu için
  bağlam kaybolmaz. Böylece sessizlik ücretlenmez ve bağlama girmez.
- **Kesme:** model konuşurken kullanıcı konuşursa ses durur (barge-in). Yankı için PipeWire yankı giderme açılır.
  Ayarda "kulaklık takılı" seçilirse eşik düşer.
- **Uyandırma kelimesi (isteğe bağlı):** odada başkaları konuşuyorsa VAD yetmez. sherpa_onnx'in anahtar kelime
  algılayıcısı ("Folio") yerelde çalışır; Folio bu kütüphaneyi zaten kullanıyor.
- **İş bölümü:** Live yalnız konuşur ve kısa cevapları verir. Folio işi NON_BLOCKING araçla beyne (Claude Code,
  Codex, Antigravity ya da API) devreder. Beyin çalışırken Live "bakıyorum" der, sonuç gelince özetler.
- **Hızlı arama paleti** bas-konuş olarak kalır ve zinciri kullanır (transcribe + beyin + seslendirme). Orada
  sürekli dinlemeye gerek yok.

**AvukatOS Asistan'dan taşındı (20.11.2026):** `lib/services/voice/`. Sahada denenmiş kurallar aynen
korundu: her soru yeni küçük oturum (son 8 satır, 300 karakter bağlam), cevap okunurken sonraki oturum
açılır, üç tur yenilenemezse konuşma kapanır, asistan sustuktan 20 sn sonra oturum kapanır, kulaklık
yoksa asistan konuşurken mikrofon gönderilmez, konuşma başlangıcı düşük hassasiyette.
- `live_session.dart`: Live WebSocket. Anahtar avukatın kendi Gemini anahtarı, adreste değil başlıkta.
  `languageCode` gönderilmez (native ses dikkate almıyor).
- `live_audio.dart`: mikrofon (flutter_recorder, 16 kHz) ve hoparlör (SoLoud akışı, 24 kHz).
- `live_usage.dart`: tur başına jeton → dolar; Gemini anahtarının aylık sınırına sayılır (`AiUsage`).
- `speech_gate.dart`: Jarvis'te düğmesiz başlatma. Vosk uyandırma kelimesi yerine Silero (0,6 MB,
  `assets/ses/`) konuşmanın başladığını anlar, öncesindeki 1,5 sn sesle birlikte Live'a geçer.
- `live_conversation.dart`: döngü. Live yalnız konuşur; iş tek araçla (`folio_ajan_sor`) beyne gider.
- `voice_settings.dart`: varsayılan kapalı, yalnız bu bilgisayarda. Beyin, yapay zekâ kapalıysa ya da
  onay yoksa hiçbir şey sormaz.
- Alınmayanlar: AvukatOS sunucusu, geçici anahtar, `arac_bul`, Flash özeti, uyandırma kelimesi (Vosk;
  derlemede kitaplık indirir, pencere gizliyken dinlemek için sonra), telefonla arama.
- Testler: `test/live_voice_test.dart` (13). Arayüz henüz bağlı değil; gerçek Live ile denenmedi.

**Karar önerisi:**
- **Jarvis modu: Live (3.8) ve yukarıdaki eller serbest tasarım.** Yerel yazıya dökme kullanılmaz. Yerel
  kalan tek şey küçük VAD ve isteğe bağlı uyandırma kelimesi.
- **Hızlı arama: zincir ve bas-konuş.** Ucuz, bağlam yeniden ücretlenmez.
- **Önce ölçüm:** ücretli bir Gemini anahtarıyla 10 dakikalık deneme. Turları ve sessizlikte usage sayaçlarını
  kaydeder; sesi kesince ücretin durup durmadığını ve Türkçe sesi gerçek olarak gösterir. Tahminler ondan sonra
  kesinleşir.

### Abonelik sesleri: Codex ve Antigravity (21.11.2026)

Soru: ses, Gemini API anahtarı yerine avukatın Codex ya da Antigravity aboneliğiyle çalışabilir mi?
Bu makinede (Codex 0.171.0, agy 1.5.13) denendi.

**Codex** (GitHub araştırmasıyla düzeltildi)
- Sesli konuşma var: TUI'de `/voice`, `in_app_voice` özelliği "stable".
- `codex app-server` (deneysel, resmî protokol) ses için şu yöntemleri sunuyor: `thread/realtime/start`,
  `appendAudio`, `appendText`, `outputAudio/delta`, `listVoices`.
- Websocket aktarımında "realtime conversation requires API key auth" hatası alındı.
- **WebRTC + `version: "v3"` ile ChatGPT girişi çalışıyor** (21.11.2026'da bu makinede denendi):
  - `thread/realtime/started` ve SDP cevabı geldi.
  - Bağlantı kuruldu, olay kanalı açıldı.
  - 45 saniyede 2123 ses çerçevesi alındı. Yalnız sessizlik gönderildi.
  - SDP cevabı 25 saniyeden geç gelebiliyor; 45–60 saniye beklemek gerekiyor.
- Araçlar: `thread/start`'ta `dynamicTools` (ad, açıklama, şema, `deferLoading`) ile tanımlanıyor. Codex
  aracı çağırınca Folio'ya `item/tool/call` isteği geliyor ve cevabı Folio veriyor. Gizli not süzgeci ve yazma
  onayı Folio'da kalır.
- Mimari: önde ses modeli (`gpt-live-1-codex`), arkada Codex ajanı; aradaki devir `codexResponseHandoffMode`
  ile yönetiliyor.
- WebRTC'nin kendi yankı giderme özelliği var; hoparlörde kendi sesini duyma sorununa da çare olabilir.
- Aynı yolu kullanan açık kaynak örnekler:
  - `xiaotianfotos/homerail` (1015★, MIT): `codex-live-voice-runtime.ts`.
  - `steerlabs/opensteer` (260★, MIT): `harness-codex/src/voice.ts`.
- Riskler:
  - Protokol deneysel.
  - 15–18 Eylül 2026'da tüm hesaplarda 403 "Voice session access denied" kesintisi yaşanmış (openai/codex#45752).
  - Varsayılan ses modeli bir sürümde değişmiş (homerail modeli açıkça yazıyor).
  - Ses kotası normal Codex kotasından ayrı ölçülüyor.
  - Veri: ChatGPT veri denetimleri geçerli; Business ve Enterprise'da eğitim yok.
- Henüz bilinmeyenler: Türkçe kalitesi, gecikme, kota, araç çağrısıyla uçtan uca davranış.

**Antigravity (agy)**
- `/voice live` Gemini Live ile çalışıyor. `/voice duplex on` sözünü kesmeye izin veriyor.
- Belgeye göre ses print modunda ve uzak ajanlarda yok; yalnız etkileşimli TUI'de var.
- `agy acp` (resmî entegrasyon yolu) şunu ilan ediyor: `promptCapabilities.audio: false`. Ses içerikli istem
  kabul etmiyor, ses oturumu yeteneği de ilan etmiyor.
- `agy mic-serve` düz TCP'den ham PCM veriyor (ölçüldü: ≈30 kB/s, yani 16 kHz / 16 bit / mono).
  `ANTIGRAVITY_MIC` ile CLI mikrofonu oradan okuyor.
- İkili dosyadaki yapıya göre `mic-serve` iki yönlü: ayrı bir "speaker" bağlantısı ve el sıkışma
  (`serveSpeaker`, `handshakeSpeaker`) var. Biçimi belgelenmemiş; tersine mühendislikle açılmadı.
- Metin TUI ekranında görünüyor. Dışarıya veren kararlı bir protokol yok.
- GitHub:
  - `NomekoGenkah/argos-board` (MIT) gizli PTY + sahte `mic-serve` yöntemini yalnız **dikte** (F5) için
    uygulamış: 16 kHz / 16 bit / mono, başlıksız, 10 ms'lik parçalar.
  - Live ses ya da hoparlör kanalı köprüsü yapan bir proje bulunamadı.
  - Linux'ta Live ses `pw-cat --playback --raw --rate 16000 --channels 1 --format s16` ile çalınıyor.
    Eski PipeWire `--raw`'ı tanımıyor (#1445, #1063); buradaki 1.6.11 tanıyor.
  - Resmî depoda ses için ACP ya da SDK isteği yok.
- Kullanım şartları:
  - Ek Şartlar 6. madde, hizmete üçüncü taraf yazılımla erişimi ihlal sayıyor.
  - Forumda (16.09.2026) yerel, değiştirilmemiş `agy`'yi tek kullanıcılı sarmalamanın uygun olduğu söylenmiş.
    Yazanın yetkisi doğrulanamadı; bağlayıcı değil.
- Veri: 5. maddeye göre etkileşimler ürün geliştirmede kullanılabilir; ayarlardan kapatılabiliyor. Müvekkil
  verisi için bu tek başına yeterli bir KVKK değerlendirmesi değil (aktarım, saklama, erişim, sözleşme).

**Karar:**
- Üretimde ses **Gemini Live API (ücretli anahtar)** olarak kalır.
- **Codex sesi ikinci bir seçenek olarak denenmeye değer.** Resmî protokolden geçiyor, abonelikle çalışıyor ve
  araçları Folio verebiliyor. Önce Türkçe kalitesi ve gecikme denenmeli; Flutter'da `flutter_webrtc`
  (Linux masaüstü) gerekir.
- Abonelikler yazılı işlerde beyin seçeneği olarak kullanılır (Codex, Antigravity, Claude).
- AGY sesi yalnız kişisel deney ve kalite karşılaştırması için kullanılır.
- Mimari ancak şu iki koşul birlikte sağlanırsa yeniden düşünülür:
  - Google'dan yazılı onay.
  - Belgelenmiş bir programatik ses arayüzü (ACP'de ses ya da SDK'da Live oturumu).

**Codex ses denemesi (21.11.2026):** ayrı bir pencere (`~/Projeler/ajan/codex_ses_deneme`), Folio'ya dokunmadan.
- Kurulum:
  - `codex app-server`, WebRTC + `v3`, ChatGPT girişi.
  - Ajan `environments: []` ile kabuksuz ve dosyasız açılır.
  - Folio araçları `lifeos_folio --mcp` alt sürecinden gelir: 34 araçtan yazan ve dışarıda bir şey
    başlatan 4'ü çıkarıldı, 30 okuma aracı `dynamicTools` olarak verildi.
- Sonuç: **çalışıyor.** Sesli soruda ses modeli işi Codex ajanına devrediyor (`delegation.created`), ajan
  Folio aracını çağırıyor ve cevap Türkçe, doğru geliyor.
  - TMK 1. madde: `mevzuat_madde` 27 ms.
  - "Bu hafta duruşmam var mı?": `ajanda` 37 ms, iki duruşma doğru tarih, saat ve mahkemeyle.
- Gecikme: söz bittikten sonra ilk ses 0,9–1,7 sn. İlk cümle bir dolgu ("Bakıyorum hemen"), asıl cevap araçtan
  sonra geliyor.
- Kullanım ses süresi olarak sayılıyor (`audio_duration_ms`); arka ajanın ayrıca sayılıp sayılmadığı belli değil.
- Dikkat:
  - Yazıyla eklenen satır (`thread/realtime/appendText`) devretmiyor, bağlam sayılıyor. Yazılı soru gerekirse
    ayrı yoldan gitmeli.
  - Deferred araçlar bir ad alanı (namespace) istiyor; araçlar doğrudan verildi.
  - `flutter_webrtc` 1.6.3 yeni clang'de `-Wno-unused-but-set-global` ister.
  - Ajan geçmiş günlerdeki duruşmaları "bu hafta var" diye okudu, geçtiğini söylemedi. Talimatta bugünün
    tarihi ve "geçmişse belirt" olmalı.
- Sırada:
  - Araçlar `dynamicTools` köprüsü yerine Codex'e doğrudan MCP olarak verilebilir: daha az kod. Bunun için
    yazan araçlar sunucu ayarında kapatılmalı ve araçlar yalnız sesli oturuma verilmeli.
  - Folio'ya almak, Gemini Live'ın yanında ayar arkasında ikinci bir ses seçeneği olarak düşünülebilir.

## Kendiliğinden takip

Folio açıkken (tray'de de olur) arka planda çalışır. Model çağırmaz: kurallar Folio'nun verisinden hesaplanır,
ajan yalnız özetlerken ve okurken modele gider.

- **Sabah brifingi** (varsayılan 08:30): günün duruşmaları, yaklaşan süreler, yeni tebligat ve UYAP bildirimleri,
  açık görevler. Masaüstü bildirimi gelir; avukat isterse sesli okunur.
- **Duruşma:** 1 gün önce ve 1 saat önce.
- **Süre:** 3 gün, 1 gün ve aynı gün.
- **Yeni tebligat ve UYAP bildirimi:** kısa özetle.
- **Sessiz saatler** (22:00–08:00): yalnız aynı gün dolan süre bildirilir.
- **Telefon:** uyarı senkronla gider, Folio mobil `system_notices` ile gösterir. *Açık soru:* mobil bunu
  uygulama kapalıyken de gösterebiliyor mu, yoksa yalnız açılınca mı (`workmanager` ile kontrol edilecek).

## Aşamalar

1. **Yazıyla ajan.**
   - Ajan penceresi, kısayol ve tray girişi.
   - Seçili beyinle sohbet, Folio araçları, web araçları, yazmada onay.
   - *Bitti sayılır:* "Bu haftaki duruşmalarım ne?", "Erkan'a ait dosyalar", "Şu icra dosyasının borcu ne?" ve
     "X hakkında son haberleri özetle" doğru cevaplanıyor.
2. **Ses.**
   - Gemini ile konuşmayı yazıya çevirme ve seslendirme, bas-konuş (kısayolu basılı tutmak ya da düğme).
   - Panelde ses halkası, cevabı durdurma.
3. **Kendiliğinden takip.** Brifing, duruşma, süre ve tebligat uyarıları, sessiz saatler, telefona senkron.
4. **Uyandırma kelimesi** ("Folio"). Yerel ve küçük bir modelle, isteğe bağlı. Kapalıyken mikrofon dinlenmez.
5. **Cila.** Gemini Live ile kesintisiz konuşma, sözü kesebilme, sesli "oku" komutu.

## Sınırlar ve riskler

- **Wayland pencere konumu:** uygulama kendi penceresini ekranda istediği yere koyamaz. Tray'in yanında
  açılan küçük pencere (taslak C) için KWin pencere kuralı gerekir; olmazsa pencere ortada açılır.
- **Yayın:** Folio'daki her değişiklik tag ile bütün avukatlara yayınlanır. Bu yüzden her şey ayar arkasında ve
  varsayılan kapalı olur; tag yalnız avukatın onayıyla atılır.
- **Ses ve gizlilik:** ses kaydı Google'a gider (Gemini). İlk açılışta ayrıca söylenir.
- **Groq dakikalık token sınırı:** hukuk araçları istenince açılır (Python denemesinde çalıştı).

## Açık sorular

- Arayüz: B ile C birleşti, hızlı aramanın içinde (taslaktaki "Birleşik" çalışma; 20.11.2026).
- Sesli cevap varsayılan olarak açık mı olsun, yalnız sesle sorulunca mı?
- Gemini'nin hangi sesi (kadın / erkek) ve hangi hızda?
