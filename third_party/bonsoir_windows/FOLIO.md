# bonsoir_windows 7.3.0, Folio'nun düzeltmesiyle

pub.dev'deki bonsoir_windows 7.3.0'ın kopyası (MIT, LICENSE). Değişiklikler yalnız
`windows/` altında:

- Duyuru (register) ya da arama (browse) Windows'un DNS iş parçacığında başarısız
  olunca eylem orada kapatılıyordu; olay kanalı Flutter'ın ana iş parçacığı dışında
  bırakılınca Flutter boş göstericiye erişip programı çökertiyordu (0xc0000409,
  16 Kasım 2026, Windows 11'de açılışta). Artık kapatma ana iş parçacığına iletilir
  (`disposeOnPlatformThread`).
- Kuyruktaki olaylar işlenirken olay kanalı kapanırsa döngü durur.
