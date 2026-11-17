# Swipelist — Ürün ve Proje Brifi (Master Prompt)

> **Bu belge nasıl kullanılır:** Aşağıdaki metin, Swipelist üzerinde çalışacak herhangi bir yapay zekâya,
> geliştiriciye veya tasarımcıya tek seferde verilebilecek şekilde yazıldı. En alttaki **"Görev"**
> bölümünü doldurup tamamını yapıştırman yeterli. Kod tabanının 7 Ekim 2026 itibarıyla gerçek
> durumunu yansıtır. "Hedef" bölümleri ise kod yorumlarından ve geçmiş kararlardan çıkarılmış niyettir.

---

## 0. Rolün

Swipelist adlı bir iOS uygulaması üzerinde çalışıyorsun. Ürünün ne olduğunu, neden bu şekilde
tasarlandığını, hangi ilkelerin pazarlık konusu olmadığını ve şu an nerede durduğunu aşağıda
bulacaksın. Bir şey önermeden ya da değiştirmeden önce bu ilkeleri oku. Özellikle **§4 (Öneri motoru)** ve
**§5 (Pazarlık konusu olmayan ilkeler)** bölümlerindeki kararlar bilinçli alındı. Bunlar hata değil.

---

## 1. Tek cümlede Swipelist

**Swipelist, aklındaki playlisti kendi cümlelerinle anlattığın ve önüne gelen şarkıları Tinder gibi
sağa (ekle) ya da sola (geç) kaydırarak birkaç dakikada Spotify'a kaydedilmiş, gerçekten senin
zevkine göre şekillenmiş bir playlist çıkardığın bir iOS uygulamasıdır.**

Slogan: **"Swipe. Build. Listen."**

## 2. Çözdüğü problem ve ürün felsefesi

- **Playlist yapmak zahmetli.** Arama yapmak, tek tek şarkı eklemek, ne istediğini hatırlamak gerekir.
  Hazır algoritmik playlistler ise *senin* o anki niyetini bilmez.
- **Yapay zekâ playlist üreticileri "al sana 30 şarkı" der ve orada biter.** Sonuç ya tutar ya tutmaz. Kullanıcının
  araya girip yön vermesi mümkün değildir.
- Swipelist ikisinin arasında duruyor. **Yapay zekâ küratörlük yapar, son kararı kullanıcı verir.** Her kart 30 saniyelik
  bir önizlemeyle çalar. Kullanıcı duyarak karar verir. Her kaydırma bir sinyaldir ve deste kullanıcı
  kaydırdıkça onun zevkine doğru daralır.
- **Niş ve İngilizce olmayan müzik birinci sınıf vatandaştır.** Ürünün çıkış noktası "Türkçe hip-hop",
  "Motive tarzı" gibi isteklerdi. Etiket veritabanları (ör. Last.fm'de "turkish hip hop" etiketli
  yalnızca 2 şarkı var) bu istekleri karşılayamıyor. Swipelist bu yüzden şarkıları bir dil modeline adıyla
  söyletiyor ve gerçek kataloğa (Spotify) eşliyor.
- **Dürüstlük, gösterişten önce gelir.** Bulunamayan bir şarkının yerine rastgele popüler bir şarkı konmaz.
  Sesi olmayan kart desteye girmez. Kaydedilemeyen playlist kaydedilmiş gibi gösterilmez.

## 3. Kullanıcı deneyimi (ekran ekran)

Uygulama yalnızca karanlık modda ve dikey yönde çalışır. Üç sekmesi vardır: **Create**, **Library** ve **Profile**. Sekmeler,
parmakla sürüklenebilen, "sıvı" gibi esneyen özel bir Liquid Glass tab bar'da durur (iOS 26 glass API'leri,
eski sürümlerde material fallback).

### 3.1 Giriş (Onboarding)
- Arka planda bulanık bir albüm kapağı duvarı, ortada uygulama ikonu, "Swipelist" başlığı ve "Swipe. Build. Listen." sloganı yer alır.
- **Continue with Google** (Supabase OAuth) ya da **Continue with email** (e-posta ve şifre, kayıt veya giriş) seçenekleri sunulur.
- Müzik servisi burada bağlanmaz. Hesap ve müzik servisi bilerek birbirinden ayrıldı, böylece kullanıcı
  hesaptan çıkmadan servis değiştirebilir.

### 3.2 Create → Brief ekranı ("What are we building?")
- **Title** (opsiyonel): Boş bırakılırsa isim brief'ten türetilir. Örneğin "melancholic indie for a rainy commute"
  → "Melancholic Indie".
- **Brief**: Serbest metin alanıdır ve asıl girdi budur. Örnek placeholder: *"melancholic indie for a rainy commute,
  something like Phoebe Bridgers but less sad…"*
- **Fine-tune** (varsayılan olarak kapalı panel): Beş eksende tek seçimlik ve opsiyonel çipler bulunur. Bunlar brief'i
  daraltır ama yerine geçmez:
  - Energy: Chill / Steady / Upbeat / Driving / Intense
  - Mood: Happy / Nostalgic / Dreamy / Melancholy / Dark / Romantic
  - For: Workout / Focus / Commute / Party / Dinner / Road trip / Sleep
  - Era: Classics / 80s / 90s / 2000s / 2010s / Recent
  - Discovery: Familiar hits / Balanced / Deep cuts
  Her çip, modele açık bir cümle olarak gider. Örneğin "Deep cuts" → "album cuts and under-the-radar artists".
- **Start swiping**: Spotify bağlı değilse kullanıcı Profile'a yönlendirilir ve bağlantı satırı vurgulanır.

### 3.3 Deste kuruluyor (Deck building)
- Spinner kullanılmaz. Toplanıp açılan bir kart yığını animasyonu ve canlı durum metni gösterilir ("Reading your brief" →
  "Finding the songs").
- 8 çalınabilir şarkı hazır olunca deste açılır, kalanlar arka planda yüklenmeye devam eder.
- Hata durumunda iki dürüst ekran vardır: **"No connection"** ya da **"Not enough to swipe on"** (bulunan şarkı sayısıyla birlikte).
  Kullanıcı "Try again" ya da "Edit brief" seçebilir ve yazdığı brief kaybolmaz.

### 3.4 Kaydırma destesi (asıl deneyim)
- Tam ekran bir kart gösterilir: büyük albüm kapağı, şarkı adı, sanatçı, albüm · yıl. Arka planda aktif kartın
  bulanık kapağı crossfade ile değişir.
- Kart açılır açılmaz **30 saniyelik önizleme çalmaya başlar** ve ilerleme göstergesi görünür.
- **Sağa kaydırma ADD, sola kaydırma SKIP** anlamına gelir. Mesafe eşiği 120pt'dir, hızlı fırlatma da sayılır. Eşik geçilince hafif haptic, onayda orta haptic verilir.
  Aynı işler alttaki SKIP | ADD kapsülüyle de yapılabilir.
- **Geri al (undo)** butonu son kararı geri sarar, kart animasyonla geri gelir.
- Üstte "N added" sayacı ve kapatma butonu bulunur. Hiç ekleme yoksa kapatma çıkış yapar, ekleme varsa Review'a gider.
- Deste azaldığında arka planda **otomatik doldurma (refill)** başlar. Kartlar bittiyse ve refill henüz gelmediyse "Finding
  more songs" ekranı çıkar. Eskiden deste sessizce başa sarıyordu, bu bilinçli olarak kaldırıldı.
- **20 şarkıda checkpoint** sheet'i açılır: "20 songs in. That's about 1 hour 12 minutes." Kullanıcı **Keep swiping**
  ya da **Finish playlist** seçebilir. Süre tahmini şarkı başına 215 saniye üzerinden hesaplanır.

### 3.5 Review
- Playlist adı (kalem ikonuyla düzenlenebilir), "24 songs · 1h 26m" bilgisi ve eklenen şarkıların listesi gösterilir.
- **Save to Spotify** seçeneği Spotify'da gizli bir playlist oluşturur, şarkıları ekler ve sonra Library'ye kaydeder. Hata
  olursa Review ekranında gösterilir ve buton "Try again" olur.
- **Save as draft** seçeneği yalnızca Swipelist kütüphanesine kaydeder, hiçbir servise dokunmaz.

### 3.6 Library
- İki sütunlu ızgara: her playlist için 4 farklı kapaktan mozaik (aynı albümün kapakları tekrar edilmez), ad ve "N SONGS".
  Izgaranın sonunda bir "New Playlist" kutusu yer alır.
- Pull-to-refresh vardır. Sunucuya yazılamayan playlist için "only on this device" uyarı bandı gösterilir.
- **Detay ekranı**: Büyük mozaik, ad, süre, Spotify'a aktarıldıysa **"Open in Spotify"** derin bağlantısı, aktarılmadıysa
  "Saved as a draft" notu ve şarkı listesi.

### 3.7 Profile
- Hesap kartı, ardından "MUSIC" bölümü: **Spotify** (Connect / Disconnect) ve soluk görünen bir
  **"Apple Music · Coming soon"** satırı.
- "Sign out of Swipelist" butonu.

## 4. Öneri motoru — ürünün kalbi

Bu bölüm Swipelist'i benzerlerinden ayıran kısımdır. Akış şöyle işler: **brief → model şarkı adı söyler → her biri gerçek
kataloğa eşlenir → filtrelerden geçer → sanatçılar dağıtılarak desteye dizilir → kullanıcı kaydırdıkça
model yeniden sorgulanır.**

### 4.1 Şarkıları kim seçiyor?
- **Varsayılan: Google Gemini** (`GeminiService`). Google modelleri sık emekliye ayırdığı için bir aday
  listesi sırayla denenir (`gemini-3-flash-preview` → `gemini-flash-latest` → `gemini-2.5-flash` → …) ve ilk cevap veren
  model hatırlanır.
- **Alternatif: Claude** (`PromptParser`). Tek satırlık bir switch ile değiştirilebilir. Karşılaştırma için tutuluyor.
- Etiket veritabanı (Last.fm vb.) bilinçli olarak **kullanılmıyor**, çünkü ana akım dışında çok zayıf kalıyor.
- Sistem promptu modele şu kuralları verir: tür, dil ve bölgeye kesin sadakat; referans sanatçıyı "stil rehberi" olarak alma;
  aynı sanatçıdan en fazla 2 şarkı (brief'te adı geçen sanatçı için 5); yalnızca saf şarkı adı ve ana sanatçı
  (feat., Remastered ya da Live eki yok); **çeşitlilik zorunlu** (en az ~2/3 oranında farklı sanatçı, bilinenlerle
  az bilinenler karışık, single'ların yanında albüm şarkıları); çıktı ham JSON dizisi.

### 4.2 Çözümleme (resolution)
- İlk istekte 26 aday, refill'de 18 aday istenir. Bunlar 6'lı paralel gruplar halinde Spotify'da aranır.
- Spotify araması üç kademelidir: alan kısıtlı sorgu → geniş sorgu → ham metin. Önce hem sanatçı hem başlık eşleşmesi aranır,
  sonra ikisinden biri. **Hiçbiri eşleşmezse `results.first`'e düşülmez**, şarkı atılır. Bunun sebebi, o sonucun yanlış
  sanatçının popüler bir şarkısı olması ve desteyi eskiye kaydırmasıdır.
- **Önizleme sesi zinciri:** Spotify → iTunes → Deezer (Deezer, İngilizce olmayan müzikte daha iyi). Bulunan önizleme
  "aynı kayıt mı?" kontrolünden geçer. Remix, instrumental, sped up, live, karaoke gibi varyantlar, istenmediyse reddedilir.
- **Desteye giremeyenler:** bulunamayan, kanonik olmayan sürüm (instrumental, karaoke, tribute, skit, interlude…),
  tekrar eden ve **önizlemesi olmayan** şarkılar.
- Sanatçı eşleştirmesi Türkçe'ye duyarlıdır. `ı` ve `İ` önce elle katlanır, aksi halde "Şanışer" eşleşmez. Ayrıca bileşen
  bazlı eşleştirme yapılır, böylece "Joker" araması "Joker Bra"yı kabul etmez (bu gerçekten yaşanmış bir hataydı).

### 4.3 Dağıtım ve sıralama
- **Sanatçı başına üst sınır 2 şarkı**, brief'te adı geçen sanatçı için 5. Sınır refill'ler boyunca geçerlidir.
- Bir parti en az **6 farklı sanatçı** biriktirmeden desteye eklenmez. Az sanatçıyla yapılan karıştırma A/B/A/B gibi tekdüze görünür.
- **Interleave algoritması:** Her adımda en çok şarkısı kalan sanatçı seçilir, bir önceki sanatçı atlanır, eşitlikte rastgele
  seçim yapılır. Partiler arasındaki dikişte bile aynı sanatçı arka arkaya gelmez.

### 4.4 Uyarlanan deste (adaptive refill)
- Kalan kart sayısı 6 veya altına düşünce model tekrar çağrılır. Bu çağrıya şunlar eklenir: son 10 tutulan ve son 10 geçilen
  şarkı, sanatçı bazında özet ("KEEPING: X (kept 3)", "REJECTING: Y (skipped 2)") ve
  zaten desteye girmiş sanatçılar (tekrar önerilmesin diye).
- **Geçme zamanlaması bir sinyaldir.** "Skipped after 3s" o sesin kesin reddi demektir, "skipped after 25s" ise kıl payı kaçmış bir şarkıdır. Model
  bu farkı bilir.
- "TASTE SO FAR — weight this above the original request where they conflict" ifadesiyle kullanıcının gösterdiği zevk,
  ilk brief'in önüne geçer.

### 4.5 Kalıcı hafıza
- `SwipeHistory` (cihazda JSON, Application Support): Geçilen şarkılar **180 gün** boyunca sonraki destelere girmez.
  Kayıt üst sınırı 1200'dür ve en yeni karar geçerlidir. **Tutulan şarkılar hariç tutulmaz**, çünkü sevdiğin bir şarkı bir sonraki
  playlistte de yer alabilir. Beğeniler, ileride bir zevk profili kurulabilsin diye yine de kaydedilir.

### 4.6 Model eğitim kesim tarihinden sonraki müzik ("date-blind top-up")
- Model, eğitim tarihinden sonra çıkan şarkıların adını bilemez. Bu yüzden yeni albümlerin desteye girme ihtimali sıfırdı.
- Çözüm: **brief'te adı geçen sanatçılar** için modelin doldurmadığı kontenjan, sanatçının canlı Spotify kataloğundan
  **tarihe kör, düz rastgele** örneklemeyle doldurulur. Modelin seçtiği şarkıların her zaman önceliği vardır.
- Sanatçı ID'si, desteye zaten kabul edilmiş bir şarkıdan alınır. Ad üzerinden tekrar çözümleme yapılmaz, çünkü aynı adı
  taşıyan farklı sanatçılar olabilir.

## 5. Pazarlık konusu olmayan ilkeler

1. **Öneriler tarihe kör kalır.** Yeni çıkan şarkılar *uygun* olmalı ama **asla öne çıkarılmamalı**. Seçimde
   çıkış tarihi bir girdi olamaz (tarihe göre sıralama ya da filtreleme yapılmaz). **Spotify `popularity` alanı da kullanılmaz**, çünkü
   popülerlik zamanla birikir ve gizli bir "eskiyi tercih et" filtresine dönüşür. Homojenlik debug loglarındaki
   `years=[...]` histogramıyla kontrol edilir. Kullanıcının sözüyle: *"homojen olsun."*
2. **İkame yok.** Bulunamayan şarkının yerine popüler bir şarkı konmaz. Brief dışından sanatçı sokulmaz. Desteye giren her şey
   ya modelin seçtiği ya da brief'te adı geçen bir sanatçıdan gelir.
3. **Sessiz kart yok.** Önizlemesi olmayan şarkı desteye girmez.
4. **Çeşitlilik bir özelliktir.** "Aynı beş kişi dönüp duruyor" hissi ürünün en büyük düşmanıdır.
5. **Dürüst hata gösterimi.** Kaydedilmemiş bir şey kaydedilmiş gibi görünmez. Hata, kullanıcının bulunduğu ekranda gösterilir.
6. **Çalışan sistem bozulmaz.** Yalnızca doğrulanabilen iyileştirmeler gönderilir. Kullanıcının çıtası şu: "eskisinden iyi olsun ve
   çalıştığından emin ol."
7. **Kullanıcının emeği kaybolmaz.** Ağ hatasında playlist cihazda kalır, brief hata ekranında silinmez.

## 6. Tasarım dili

- **Yalnızca karanlık tema.** Arka plan `#0B0B0D`, kart yüzeyi `#18181B`, sheet `#1C1C1F`, metin beyaz ve %70 / %45 opaklık
  basamakları, ayraçlar %8 beyaz.
- **Marka rengi: lime `#D4FF3F`.** Vurgu öğelerinde, ana butonlarda ve seçili çiplerde kullanılır. Vurgu üstündeki metin arka plan rengindedir.
  Skip grisi `#6E6E73`, yıkıcı işlem rengi `#FF453A`.
- Tipografi sistem fontudur: Display 32 bold, Title 26, Headline 20 semibold, Body 16, Caption 14, Label 12 semibold
  ve geniş harf aralıklı BÜYÜK HARF.
- **Liquid Glass** (iOS 26): Tab bar ve seçim hapı camdır. Hap parmakla sürüklenir, hıza göre uzayıp incelir, kenarlarda
  lastik gibi sıkışır ve yayla geri döner.
- **Hareket ve haptic bilinçli kullanılır.** Spinner yerine kart yığını animasyonu, eşik haptic'i ve kart çıkış ile geri alma yayları var.
- **İkon:** Yelpaze gibi açılmış üç kart ve öndeki kartta dört çubuklu bir dalga formu. Açık, koyu ve renklendirilmiş varyantları
  vardır (`Branding/`).
- Boş durumlar için iki çapraz yuvarlatılmış kare ("DeckMotif") kullanılır.

## 7. Teknik mimari

| Katman | Teknoloji / Dosya |
|---|---|
| İstemci | SwiftUI, iOS (iOS 26 glass API'leri + fallback), `@MainActor` ObservableObject'ler |
| Uygulama durumu | `AppState` (sekme, kütüphane, kaydetme), `DeckSession`, `DeckFlowView` |
| Deste motoru | `Services/DeckBuilder.swift` |
| Öneri modelleri | `GeminiService.swift` (varsayılan), `PromptParser.swift` (Claude) |
| Müzik servisi soyutlaması | `MusicProvider` protokolü: `resolve`, `artistCatalog`, `export`. Şu an tek uygulaması `SpotifyProvider` |
| Spotify | PKCE OAuth (`swipelist://callback`), token'lar Keychain'de. Arama, sanatçı kataloğu, playlist oluşturma (`/me/playlists`) ve ekleme (`/items`, çünkü `/tracks` 403 dönüyor) |
| Önizleme yedekleri | `ITunesService` (rate-limit'li), `DeezerService`, `PreviewPlayer` (AVPlayer) |
| Hesap ve veri | Supabase: Auth (Google OAuth + e-posta), PostgREST üzerinden elle yazılmış bir REST istemcisi (`SupabaseClient/Auth/Repository`) |
| Sunucu fonksiyonu | `supabase/functions/suggest-songs` (Deno). Gemini anahtarını sunucuda tutmak için var |
| Yerel hafıza | `SwipeHistory` (JSON dosyası) |

### Veritabanı (Supabase / Postgres)
- `profiles`: Kayıtta trigger ile otomatik oluşur.
- `platform_connections`: Bağlı servisler ve OAuth bilgileri (spotify / apple_music / deezer).
- `playlists` + `playlist_tracks`: Brief metni, energy ve occasion, export bilgisi, şarkılar (sıra, kapak, önizleme, provider URI).
- `taste_artists`: Sanatçı bazında kept/skipped sayaçları. `bump_taste` RPC'si ile atomik olarak artırılır.
- `shown_tracks`: Gösterilmiş her şarkının anahtarı. Amaç, cihazlar arasında tekrarı önlemek.
- Güvenlik: Her tabloda RLS var ve kullanıcı yalnızca kendi satırlarını görür. `anon` rolünün tüm yetkileri alındı (TRUNCATE RLS'i
  atlattığı için). Yeni tablolar varsayılan olarak `anon`'a açılmaz.

### Geliştirici araçları
- Yalnızca DEBUG modunda çalışan başlatma argümanları: `-uiState <onboarding|brief|deck|deck-live|checkpoint|review|library|library-empty|playlist|profile>`,
  `-uiBrief "<metin>" -uiEnergy … -uiFor …` (gerçek akışı başsız çalıştırır), `-testSpotifyExport`.
- Teşhis logları: `SWDECK` (sanatçı çeşitliliği, yıl histogramı), `SWFUNNEL` (adaylar nerede elendi),
  `SWTOPUP`, `SWREFILL`, `SWSEARCH`, `SWGEMINI`, `SWEXPORT`.
- Derleme: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild …`. Simülatörlerde Spotify oturumu
  olmadığı için uçtan uca deste testi yalnızca kullanıcının kendi cihazında yapılabiliyor.
- Proje bir git deposu **değil**. Silinen kod geri getirilemez.

## 8. Bugünkü durum

**Çalışan:** Hesap girişi, Spotify bağlantısı, brief ve fine-tune, tüm öneri hattı (Gemini → Spotify → önizleme zinciri →
filtreler → interleave), adaptive refill, geçme zamanlaması sinyali, 180 günlük geçilen şarkı hafızası, tarihe kör katalog
top-up'ı, kaydırma, geri alma, checkpoint, review, Spotify'a aktarma, Supabase'e kaydetme ve kütüphane.

**Kurulmuş ama bağlanmamış / eksik olanlar:**
- `taste_artists` ve `shown_tracks` tabloları ile repository fonksiyonları (`loadTaste`, `recordTaste`,
  `loadShownTrackKeys`, `markShown`) yazıldı ama **uygulamada hiçbir yerden çağrılmıyor**. Zevk ve geçmiş şu an
  yalnızca cihazda tutuluyor. Profile ekranındaki "Playlists, taste and history sync to this account" yazısı bu yüzden şimdilik yalnızca
  playlistler için doğru.
- Uygulama Gemini'yi **doğrudan istemciden** çağırıyor ve API anahtarı uygulama binary'sinin içinde. `suggest-songs` edge function'ı
  depoda istemci promptuyla senkronize edildi ama **deploy edilmedi**, yani sunucudaki sürüm eski.
- Apple Music: Ücretli Apple Developer hesabı olmadığı için engelli. MusicKit, yetki vermesine rağmen katalog aramasında
  `developerTokenRequestFailed` hatası veriyor. Bir uygulaması yazılıp kaldırıldı, şimdilik yalnızca "Coming soon" satırı duruyor.
- Library'de playlist silme ya da düzenleme, Review'da şarkı çıkarma ya da sıralama değiştirme yok.
- Terms of Service ve Privacy Policy metinleri giriş ekranında görünüyor ama bağlantıları yok.

## 9. Ne olmayı hedefliyor (yol haritası)

**Vizyon:** Swipelist'in, "aklımdaki playlisti anlatayım, birkaç dakika kaydırayım, bitti" deneyiminin en iyi adresi olması. Bu ürün
**hangi müzik servisini kullandığın fark etmeksizin** çalışmalı ve **seni her playlistte biraz daha iyi tanımalı**.

Kısa ve orta vade (kod yorumlarında ve geçmiş kararlarda açıkça adı geçen işler):
1. **Anahtarları sunucuya taşımak (TestFlight öncesi zorunlu).** Tüm öneri çağrıları `suggest-songs` edge function üzerinden
   yapılmalı. Böylece anahtar binary'de olmaz ve model, uygulama güncellemesi gerekmeden değiştirilebilir.
   `platform_connections` içindeki refresh token'lar da ileride service-role kullanan bir fonksiyonun arkasına alınmalı.
2. **Cihazlar arası zevk profili.** `taste_artists` / `shown_tracks` bağlanmalı ve yeni bir deste "soğuk" değil, bilinen
   zevkten başlamalı. Swipe geçmişi ve deste metrikleri Supabase'e taşınmalı.
3. **Apple Music desteği.** `AppleMusicProvider`, mevcut `MusicProvider` protokolüne yeni bir uygulama olarak eklenecek. `Track.spotifyURI` genelleştirilip
   `providerID` / `providerTrackID` haline gelecek. Bağlantı anında bir katalog yoklaması yapılmalı ki yetki sorunu boş deste olarak
   değil, orada görünsün. Ön koşul: ücretli geliştirici hesabı, App ID'de MusicKit etkinleştirilmesi ve team ayarı. Deezer da şemada
   şimdiden yer alıyor.
4. **Tam uzunlukta çalma.** 30 saniyelik önizleme yerine Spotify App Remote kullanılması.
5. **Model kesim tarihinden sonraki *sanatçılar*.** Şu an yalnızca adı bilinen sanatçıların yeni şarkıları geliyor. Spotify playlist
   taraması ve "grounded search" ile model tarafından hiç bilinmeyen yeni sanatçılar da keşfedilebilir. Tarihe körlük ilkesi bozulmadan yapılmalı.
6. **Yayına hazırlık.** TestFlight, yasal metinler, kütüphane yönetimi (silme ve düzenleme), Review'da düzenleme.

## 10. Kısıtlar ve bağlam

- Tek geliştirici, kişisel proje. Ücretli Apple Developer hesabı yok, `DEVELOPMENT_TEAM` boş.
- Bundle ID: `com.batuyilmaz.Swipelist`. URL scheme: `swipelist://`.
- Spotify önizleme URL'lerini kataloğun büyük kısmında artık vermiyor. Bu yüzden iTunes ve Deezer yedekleri hayati.
- Gemini model isimleri hızla emekliye ayrılıyor. Kodda tek bir modele sabitlenmemeli.
- Kod stili: Açıklayıcı, "neden"i anlatan yorumlar. Her sihirli sayının yanında gerekçesi yazılı. Benzer kod yazarken bu
  yoğunluk ve üslup korunmalı.

## 11. Kapsam dışı (bilinçli olarak yapılmayanlar)

- Etiket ya da tür veritabanından şarkı seçmek.
- Yeni çıkan şarkıları ya da popüler şarkıları öne çıkarmak.
- Önizlemesi olmayan şarkıları göstermek.
- Açık tema.
- Hesap ile müzik servisini tek bir girişte birleştirmek.

---

## Görev

> _Buraya bu belgeyi kime ve ne için verdiğini yaz. Örnekler:_
> - "Bu brife dayanarak App Store açıklaması ve 5 ekran görüntüsü başlığı yaz."
> - "§9.2'yi uygula: `taste_artists` ve `shown_tracks`'i desteye bağla. §5'teki ilkeleri bozma."
> - "Bu ürün için bir yatırımcı / portföy sunumu hazırla."
> - "Swipelist'in UX'ini eleştir ve §5 ile çelişmeyen 10 iyileştirme öner."
