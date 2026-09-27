# Saha Takip — Arayüz Tasarım Belgesi

Bu belge projenin **mevcut** arayüz sistemini anlatır: hangi değer nerede
tanımlı, neden öyle, ve bir şeyi değiştirirken nereye bakmak gerekiyor.
Tasarlanması *planlanan* bir sistem değil, kodda çalışan sistemin dökümüdür.

Uygulamanın **iki istemcisi** var ve ikisi de aynı tasarım dilini uygular:

| İstemci | Teknoloji | Kaynak |
|---|---|---|
| Web | React + Vite | `client/src/` |
| Mobil / masaüstü | Flutter | `flutter_app/lib/` |

İki istemci birbirinin kopyası **değil**, aynı jetonların iki ayrı uygulaması.
Bu yüzden her bölümde "React'te nerede / Flutter'da nerede" ayrı verilmiştir.

---

## 1. Temel ilke: renk tek başına bilgi taşımaz

Arayüzde hiçbir bilgi **yalnızca** renkle anlatılmaz. Her renkli öğenin
yanında metin karşılığı bulunur.

Gerekçe iki tane: renk körlüğü (erkeklerin ~%8'i) ve **yazdırma**. Vardiya
çizelgesi basılıp mağazaya asılıyor; siyah-beyaz çıktıda yalnızca renge
dayanan bir çizelge okunamaz hale gelirdi.

Uygulaması:

- Vardiya hücresi hem renkli hem kategori etiketli (`Sabah`, `Kapanış`…)
- Durum rozetleri hem renkli hem metinli (`Onaylandı`, `Bekliyor`…)
- Hafta tatili `OFF`, resmî tatil `RT` olarak **yazılır**

---

## 2. Tasarım jetonları

Tek bir kaynak yok — iki istemci ayrı çalıştığı için jetonlar iki yerde
tanımlı ve **elle eşlenmiş** durumda. Değiştirirken ikisine de dokunmak
gerekir.

| | React | Flutter |
|---|---|---|
| Tanım yeri | `client/src/index.css` → `:root` | `flutter_app/lib/core/tokens.dart` → `AppTokens` |
| Erişim | `var(--ink)` | `context.tokens.ink` |

### 2.1 Renk

Marka rengi koyu turkuaz (`#005c55`); 2026 Stitch yeniden tasarım setinden
(Material 3, tohum rengi `#005c55`) geldi. Önceki sürümde marka rengi yeşildi
(`#15803d`) — palet bu setle birlikte değiştirildi, jeton **isimleri**
(`--primary`, `--danger`…) aynı kaldı ki tüketen ~200 bileşen dokunulmadan
kalsın.

| Jeton | Açık tema | Rol |
|---|---|---|
| `--primary` | `#005c55` | Birincil eylem, marka |
| `--primary-600` | `#006a63` | Vurgu, kenarlık, odak halkası |
| `--primary-dark` | `#00504a` | Büyük harfli etiket, bağlantı metni |
| `--primary-soft` | `#b5efda` | Seçili/bekleyen zemin |
| `--on-primary` | `#ffffff` | Birincil zemin üstü metin |
| `--danger` | `#ba1a1a` | Yıkıcı işlem, hata |
| `--warning` | `#d97706` | Uyarı |
| `--success` | `#007952` | Onay, olumlu |
| `--info` | `#0e7490` | Bilgi |
| `--ink` | `#0b1c30` | Ana metin |
| `--muted` | `#3e4947` | İkincil metin |
| `--bg` / `--card` | `#f8f9ff` / `#ffffff` | Sayfa / yüzey |
| `--border` | `#bdc9c6` | Kenarlık |

Kaynak dosyalar `stitch_t_m_ekranlar_n_yeniden_tasar_m/` klasöründeki 30
ekranın hepsinde **aynı** Tailwind/M3 renk paletini kullanıyor (tek kaynaktan
üretilmiş); bu yüzden tüm paletin buraya taşınması güvenliydi. Koyu tema için
eşdeğer bir mockup verilmedi — koyu temanın marka ailesi (`--primary`,
`--primary-600`, `--primary-dark`, `--primary-soft`, `--on-primary`) aynı M3
setinin "koyu zeminde okunmak için üretilmiş" `inverse-primary` /
`primary-fixed` tonlarına (`#80d5cb`, `#4edea3`, `#9cf2e8`) çekildi; nötr
yüzeyler (`--bg`, `--card`, `--ink`, `--muted`, `--border`, `--surface-invert`)
ölçülmüş kontrastları bozmamak için **değiştirilmedi**.

`--success` artık M3 setinin "tertiary" (yeşil) ailesinden geliyor — mockuplarda
zaten pozitif/onay anlamı bu renkle veriliyor (bkz. `ana_sayfa_operasyon_paneli`
ekranındaki "Ay Sonu Tahmini" ve "En Çok Satanlar" blokları). `--warning`
değişmedi: mockuplarda kullanılan Tailwind `amber-600/700/800` üçlüsü zaten
eski değerlerle (`#d97706` / `#b45309`) örtüşüyordu.

Başlık ve rakam yazı ailesi de bu setle geldi: `Plus Jakarta Sans` (govde
metni yine Inter). React'te `h1-h4`, `.page-head h2`, `.stat .value`,
`.login-title` bu aileyi kullanır; yükleme `client/index.html`'de Google
Fonts üzerinden yapılır. Flutter tarafı şimdilik sistem fontunda kalıyor —
`google_fonts` paketi eklenmedi (bkz. §12 bilinen boşluklar).

**`-soft` / `-text` çifti kuralı:** yumuşak zeminlerin (`--warning-soft`)
üstünde ana metin rengi kullanılmaz; o zemin için ayrı bir metin jetonu
vardır (`--warning-text`). Sebep ölçüm: `--warning` rengi `--warning-soft`
üstünde küçük metin eşiğini geçmiyor, `--warning-text` geçiyor.

**`--surface-invert` / `--on-surface-invert`:** koyu zeminli paneller için.
Daha önce bu paneller zeminini `--sidebar-b`'den alıyordu; açık temada o
değer beyaza dönünce sabit açık gri metinle kontrast **1.23**'e düşüyor ve
panel okunamaz hale geliyordu. Ayrı jeton çifti tam bu yüzden var.

### 2.2 Ölçü ve biçim

| Jeton | Değer | Not |
|---|---|---|
| `--tap` | `44px` | Dokunma hedefi tabanı, **pazarlık dışı** |
| `--radius-sm` | `10px` | Düğme, girdi, küçük kart |
| `--radius` | `14px` | Kart, panel |
| `--radius-lg` | `20px` | Büyük yüzey, modal |
| `gap` (Flutter) | `12` | Standart boşluk |

`44px` iOS/Android erişilebilirlik kılavuzlarının tabanıdır. Mağazada
telefon çoğu zaman tek elle ve acele kullanılıyor; bunun altına inen bir
hedef pratikte ıskalanıyor.

### 2.3 Tipografi

- Yazı ailesi: `Inter, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif`
- Gövde: `15px`, satır yüksekliği `1.55`
- **Form girdileri `16px`** — bunun altındaki her değerde iOS Safari sayfayı
  kendiliğinden yakınlaştırıyor ve kullanıcı her girdide elle geri çıkmak
  zorunda kalıyor. Bu yüzden `input, select, textarea` sabit `16px`.
- Rakam hizalaması: `font-variant-numeric: tabular-nums` (Flutter'da
  `FontFeature.tabularFigures()`). Tablo içindeki tutar ve süreler alt alta
  hizalanmalı. **Şu an her yerde uygulanmıyor** — React'te sıralama listesi
  ve vardiya çizelgesinde, Flutter'da yalnızca `roster_screen.dart` içinde
  var. Yeni bir sayı sütunu eklerken elle vermek gerekiyor.

---

## 3. Tema (açık / koyu)

İki tema da **tam** desteklenir; koyu tema sonradan eklenmiş bir filtre
değil, ayrı bir jeton kümesidir.

- React: kök öğede `data-theme="dark"`; jetonlar `:root[data-theme='dark']`
  bloğunda yeniden tanımlanır.
- Flutter: `AppTokens.light` / `AppTokens.dark`, tercih
  `flutter_app/lib/core/theme_mode.dart` içinde saklanır.

**Koyu temada saydamlık kullanılmaz.** Yarı saydam bir zemin altındaki
katmana göre değişir ve kontrast hesaplanamaz hale gelir; koyu tema
renkleri **önceden birleştirilmiş katı renk** olarak yazılır. Örnek:
kapanış vardiyası hücresi açık temada `#EDE9FE`, koyu temada `#252946`.

> Ölçüm uyarısı: tarayıcıda temayı elle `data-theme` yazarak denemeyin.
> Uygulamanın kendi tema yöneticisi `localStorage`'dan okuyup üzerine
> yazıyor; bu yarış sahte kontrast ölçümleri üretiyor. Temayı arayüzden
> değiştirin.

---

## 4. Erişilebilirlik — ölçülen, varsayılmayan

Eşikler WCAG 2.2:

| Öğe | En az |
|---|---|
| Küçük metin | 4.5 |
| Büyük/kalın metin, grafik öğe, ikon | 3.0 |
| Odak göstergesi | 3.0 |

Bu eşikler **testle zorlanıyor**: `flutter_app/test/contrast_test.dart`
kontrastı temanın kendisinden okur, jeton bozulursa test kırılır.

```bash
flutter test test/contrast_test.dart
```

Geçmişte yakalanan gerçek kusurlar — belge bunları kayıt altına alıyor ki
tekrar edilmesin:

| Kusur | Ölçülen | Düzeltme |
|---|---|---|
| Koyu temada birincil düğme metni sabit beyaz | 1.92 | `--on-primary` / `t.onPrimary` |
| Açık temada koyu panel metni sabit açık gri | 1.23 | `--surface-invert` çifti |
| Çıktıda macenta OFF hücresinde beyaz metin | 3.14 | Siyah metin → 6.70 |

Diğer kurallar:

- Saydam zeminli metnin kontrastı, **arkasındaki katmanla birleştirilerek**
  hesaplanır. Yalnızca ön plan rengine bakmak yanlış sonuç verir.
- Odak halkası her etkileşimli öğede görünür olmalı.
  `element.focus()` çağırmak `:focus-visible`'ı tetiklemez — odak
  görünürlüğünü klavyeyle (Tab) sınayın.

---

## 5. Yerleşim ve kırılma noktaları

CSS'te kullanılan kırılma noktaları: `359, 480, 560, 640/641, 899/900, 1279px`.

Belirleyici olanlar:

| Sınır | Davranış |
|---|---|
| `< 640px` | Telefon. Kartlar tek kolon, tablolar satır-kart'a döner |
| `640–899px` | Tablet. İki kolon |
| `≥ 900px` | Masaüstü. Yan menü açılır, üç/dört kolon |

**İki istemcide yan menü eşiği AYNI DEĞİL:** React'te yan menü `900px`'de
açılıyor (`@media (min-width: 900px)`), Flutter'da ray ↔ yan menü geçişi
`kRailDefaultBelow = 1200`. Yani 900–1200px arasında React yan menü
gösterirken Flutter dar ray gösteriyor. Bilerek seçilmiş bir fark değil,
ayrışma; birleştirilecekse ikisi de tek değere çekilmeli.

Izgara kolon sayılarını ve `44px` dokunma hedefini
`flutter_app/test/crud_screens_test.dart` test ediyor.

### Tablolar

Geniş tablolar sayfayı yatay kaydırmaz; **kendi kapsayıcısı içinde**
kaydırılır (`.table-wrap` → `overflow-x: auto`). Telefonda tablo satırları
`data-label` ile kart görünümüne döner — başlık satırı okunamayacağı için
her hücre kendi etiketini taşır.

### Yapışkan öğeler

`position: sticky` yalnızca **kendi ebeveyninin kutusu içinde** yapışır.
Ürünler ekranında arama alanı yapışmıyordu çünkü ebeveyni 210px'lik bir
paneldi, sayfa ise 8763px. Arama alanı panelin dışına alınarak çözüldü.
Yapışkan bir şey eklerken ebeveynin yüksekliğini kontrol edin.

---

## 6. Ortak bileşenler

Yeni ekran yazarken önce bu listeye bakın; çoğu ihtiyaç karşılanmış
durumda ve yeniden yazmak iki istemcinin ayrışmasına yol açıyor.

| İş | React (`client/src/components/`) | Flutter (`flutter_app/lib/widgets/`) |
|---|---|---|
| Liste/CRUD iskeleti | — (sayfa içinde) | `CrudScaffold` |
| Kart / panel | `.card`, `.surface-panel` | `AppCard`, `StatCard` |
| Rozet | `Badge`, `StatusBadge` | `Pill` |
| Uyarı kutusu | `.alert` | `AppAlert` |
| Modal | `Modal` | `FormDialog` |
| Onay | `Confirm` | `confirmDialog` |
| Form alanı | `.field` | `LabeledField`, `FormRow` |
| Tarih/saat | `<input type="date">` | `DateTimeField` |
| Bildirim (toast) | `ToastHost`, `toast()` | `toast()` (`core/notify.dart`) |
| Yükleme katmanı | `LoadingOverlay`, `BusyHost` | `busy_overlay.dart` |
| Kullanıcı görseli | `Avatar` | `Avatar` |
| Bildirim zili | `NotificationBell` | `NotificationBell` |
| Yüzen eylem düğmesi | `ShortcutFab` | `shortcut_fab.dart` |
| QR göster / oku | `QrCode`, `QrScanner` | `qr_view.dart`, `qr_scan_screen.dart` |

---

## 7. Gezinme

- **Masaüstü:** sol yan menü (daraltılabilir ray).
- **Telefon:** alt çubuk + menü sayfası. Hamburger yok; bulunduğunuz
  ekranın adı üst çubukta yazar.

### İki istemci arasında eşitlik zorunlu

Bir ekranın alt çubukta görünüp görünmemesi iki istemcide **ayrı** tanımlı.
React'te `/pdks-admin` işareti kazara düşürüldü ve mağaza müdürü telefondan
vardiya yönetimine **ulaşamaz** hale geldi. Flutter'ın widget testi aynı
hatayı anında yakaladı, React'te test yoktu.

Bu boşluk bir betikle kapatıldı:

```bash
npm --prefix client run nav-parity
```

İki istemcinin alt bar kümesi ayrışırsa hata verir. Gezinmeye dokunan her
değişiklikten sonra çalıştırın.

### Yüzen eylem düğmesi (FAB) bağlama duyarlıdır

- Ana sayfada: kısayol menüsü açar.
- Bir modülün içindeyken: **o modülün** birincil işlemine döner
  (Ürünler'de "Yeni Ürün" gibi).

Gerekçe: bir modülün içindeyken kullanıcının isteyeceği şey neredeyse her
zaman "bu listeye yeni kayıt". Düğme hiçbir ekranda işlevsiz kalmaz —
birincil işlemi olmayan modüllerde kısayol menüsüne düşer.

---

## 8. Alana özgü görsel dil

### Vardiya kategorileri

Sunucu sınıflandırır (`server/src/pdks/shiftClass.js`), istemci yalnızca
boyar. İki istemcide iki ayrı sınıflandırma olmasın diye kural tek yerde.

| Kategori | Açık zemin / metin | Anlamı |
|---|---|---|
| `sabah` | `#DBEAFE` / `#1E40AF` | 12:00'den önce başlar |
| `gunduz` | `#DCFCE7` / `#166534` | 12:00–16:00 |
| `aksam` | `#FEF3C7` / `#92400E` | 16:00'dan sonra |
| `kapanis` | `#EDE9FE` / `#5B21B6` | Süresinin ⅓'ü 20:00–06:00 arasında |

`kapanis` başlangıç saatine göre değil, **gece dönemine düşen süreye** göre
belirlenir: 16:00–00:30 vardiyası akşam gibi görünür ama 4,5 saati gece
dönemindedir. Etiket işletmenin dilinde ("kapanış"); yasal hesaplar
(4857 m.69) değişmemiştir.

### Çizelge hücre gösterimi

| Gösterim | Anlam |
|---|---|
| `08:00–16:30` | Vardiya saatleri |
| `OFF` | Hafta tatili |
| `RT` | Resmî tatil |
| `-` | Atanmamış |
| `+` | Atanmamış, düzenleme yetkisi var |
| `•` | Kaydedilmemiş bekleyen değişiklik |
| Kırmızı çerçeve | Yasal sınır uyarısı |

### Dışa aktarım ekranla aynı görünür

Basılı çizelge ekrandakiyle aynı renkleri kullanır ve işletmenin kendi
şablonuna uyar: `ÇALIŞMA ŞEKLİ`, `GÖREV`, `AD SOYAD` sütunları + günler.
OFF hücresi macenta zemin **siyah metin** (beyaz metin 3.14 ile eşiğin
altında kalıyordu).

Türkçe karakterler için gömülü yazı tipi zorunlu: jsPDF ve Dart `pdf`
paketinin varsayılan yazı tipleri `/WinAnsiEncoding` kullanıyor ve
`ş ğ ı İ Ş Ğ` karakterleri **bozuk çıkıyor**. Noto Sans (OFL-1.1) gömülü.

---

## 9. Geri bildirim ve durum

| Durum | Gösterim |
|---|---|
| Yükleniyor (ilk açılış) | İskelet / yükleme katmanı |
| Arka plan yenilemesi | **Hiçbir şey** — `silent: true` |
| Başarılı yazma | Toast |
| Başarısız | Toast (hata metni sunucudan) |
| Kaydedilmemiş değişiklik | Yapışkan kaydet çubuğu + hücrede `•` |
| Yıkıcı işlem | Onay penceresi, sonucu açıkça yazar |

Veri okumalarında başarı bildirimi verilmez; her ekran açılışında toast
çıkması gürültü olurdu. Yazma işlemlerinde verilir.

**Kapalı düğme, gizli düğmeye yeğlenir.** Bir işlem yapılamıyorsa düğme
kaybolmaz, kapalı kalır — kullanıcı denemeden sebebini görür. Örnek:
molada çıkış yapılamaz, düğme kapalıdır ve yanında sebebi yazar.

---

## 10. Dil

Arayüz tamamen Türkçe. Teknik terimler kullanıcıya gösterilmez:

| Kodda | Arayüzde |
|---|---|
| `store_manager` | Mağaza Müdürü |
| `SM` / `SSV` / `BARİSTA` | (çizelge çıktısında işletmenin kısaltmaları) |
| `FULL_TIME` | FULL TIME |
| `rotating` / `static` QR | Süreli kod / Sabit kod |

Hata mesajları ne olduğunu **ve ne yapılacağını** söyler:
"QR kodun süresi doldu, ekrandaki yeni kodu okutun."

---

## 11. Değişiklik yaparken

```bash
# React
npm --prefix client run lint
npm --prefix client run build
npm --prefix client run nav-parity

# Flutter
cd flutter_app
flutter analyze
flutter test
```

Kontrol listesi:

- [ ] Yeni renk çifti eklendiyse kontrast ölçüldü mü? (küçük metin 4.5)
- [ ] Koyu temada da tanımlandı mı? Saydamlık yerine katı renk mi?
- [ ] Dokunma hedefi 44px'in altına düşüyor mu?
- [ ] Renk tek başına bilgi taşıyor mu? Metin karşılığı var mı?
- [ ] Aynı değişiklik diğer istemciye de uygulandı mı?
- [ ] Gezinme değiştiyse `nav-parity` geçiyor mu?
- [ ] Geniş içerik sayfayı yatay kaydırıyor mu?

---

## 12. Bilinen boşluklar

Dürüst olmak gerekirse tasarım sistemi eksiksiz değil:

- **Flutter tarafı `Plus Jakarta Sans` kullanmıyor.** React'in yeni başlık
  fontu Flutter'a taşınmadı; iki istemci artık başlıklarda farklı yazı
  ailesi gösteriyor. Taşımak `google_fonts` paketi + font ağırlıklarının
  bundle'a eklenmesini gerektiriyor.
- **Koyu tema için Stitch mockup'ı yok.** Koyu temanın marka rengi aynı M3
  setinin "inverse" tonlarına çekilerek türetildi (bkz. §2.1); nötr yüzeyler
  değiştirilmedi. Tasarım ekibi koyu tema mockup'ı üretirse bu jetonlar
  gözden geçirilmeli.
- **Jetonlar iki yerde elle eşleniyor.** Tek kaynaktan üretilmiyor;
  birini değiştirip diğerini unutmak mümkün. Kontrast testi Flutter
  tarafını koruyor, React tarafında eşdeğer test **yok**.
- **React'te bileşen testi yok.** Flutter'da 319 test var; React tarafı
  yalnızca ESLint, derleme ve `nav-parity` ile korunuyor. Gezinme
  hatasının React'te kaçıp Flutter'da yakalanmasının sebebi bu.
- **Görsel gerileme testi yok.** Yerleşim bozulmaları elle fark ediliyor.
- **Bileşen kataloğu yok.** Mevcut bileşenleri görmek için koda bakmak
  gerekiyor; bu belgedeki tablo o boşluğu kısmen kapatıyor.
- **Yan menü eşiği iki istemcide farklı** (900px / 1200px) — bkz. §5.
- **Tablo rakam hizalaması her yerde değil** — bkz. §2.3.
