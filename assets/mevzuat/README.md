# Mevzuat veri paketi

`laws.json` — kısaltma ve kanun numarası eşlemesi. Motor bu dosyayı okur;
alan bilgisi koda gömülü değildir, bu dosya ayrı sürümlenir. `tertip` alanı
kanun numarasından türetilemez ve mevzuat.gov.tr onu istiyor: 213 dördüncü,
2004 üçüncü, geri kalanların çoğu beşinci tertipte. Her satır gerçekten
çekilerek doğrulanmıştır; `tertip` yanlışsa özellik sessizce boş döner.
Sürüm 2'de 89 kanunun numarası, adı ve tertibi Bedesten kataloğundan tek
tek okundu (26 Eylül 2026). `mulga: true` kanunun yürürlükten kalktığını,
`adla: false` adının yürürlükteki bir kanunla aynı olduğunu söyler: o kanun
adıyla değil yalnız numarasıyla tanınır ("818 s. BK m. 41"). Tabloda
olmayan bir kanun da "NNNN sayılı Kanun'un 8. maddesi" diye yazılmışsa
numarasıyla tanınır; adını resmî kaynak söyler.

`courts.json` — karar atıflarında tanınan mahkemeler. `yayin` kararlarının
bir bankada yayımlanıp yayımlanmadığını, `kaynak` nereden isteneceğini
(`bedesten`: Bedesten, gerekirse UYAP Emsal; `aym`: AYM bilgi bankası),
`tur` aynı numara birden çok dairede çıkınca hangisinin öne alınacağını,
`etiket` dairenin gösterilen adını söyler. Kalıptaki `{no}` daire
numarasının yazılışıdır ("15.", "15", "On Beşinci"). Kalıplar büyük harfli
yazımı da bulsun diye motor İ/ı harflerini kendisi genişletir.

`mevzuat-chain.pem` — mevzuat.gov.tr'nin ara sertifikası.

Sunucu TLS el sıkışmasında ara sertifikayı göndermiyor. Tarayıcılar bunu
sertifikanın içindeki AIA adresinden kendileri indirip tamamlıyor; Dart
tamamlamıyor ve bağlantı "Handshake error in client" ile düşüyor. Ara
sertifika burada taşınır ve `SecurityContext`e eklenir. Kök sertifika
zaten işletim sisteminde olduğu için yalnız bu halka eksik.

Sertifikanın geçerlilik sonu dosyanın kendisinde yazılıdır; süresi
dolduğunda yenisi `http://cacerts.geotrust.com/GeoTrustTLSRSACAG1.crt`
adresinden alınır. Süre dolarsa madde getirme durur, uygulamanın kalanı
etkilenmez.

`faiz.json` — faiz hesabının oranları. `tcmb`, Merkez Bankasının reeskont
ve avans oranlarının yürürlük tarihleriyle tam tablosudur (tcmb.gov.tr).
`turler` her faiz türünün dönemlerini verir: bir dönem ya sabit `oran`
taşır ya da `tcmb` serisine bağlıdır. Seriye bağlı dönemde motor 3095
sayılı Kanunun kuralını uygular: yılın oranı önceki yılın 31 Aralık
günündeki orandır; 30 Haziran günü oran bundan beş puan ya da daha çok
farklıysa yılın ikinci yarısında 30 Haziran'daki oran geçer. `carpan`
oranı çarpar (31.07.2026'dan beri kanuni faiz reeskontun %80'i). `enAz`
türün o gün en az hangi türün oranı kadar olacağını söyler (ticari
temerrüt faizi kanuni faizden az olamaz). TCMB yeni bir oran açıkladığında
yalnız `tcmb` tablosuna satır eklenir ve `dogrulandi` güncellenir.
