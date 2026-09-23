# Flutter istemcisi — taşıma planı

Mevcut React istemcisi web'de kalır, Flutter yanına gelir. **Sunucuda hiçbir
değişiklik gerekmez**: Flutter aynı Express API'yi tüketir.

## Platform gerçeği

| Platform | Bu makinede | Nasıl derlenir |
| --- | --- | --- |
| Web | ✅ derlenir + doğrulanır | `flutter build web` |
| Android | ✅ derlenir (SDK `~/Android/Sdk`, JDK `~/jdk` mevcut) | `flutter build apk` |
| Linux | ✅ derlenir (toolchain kurulduktan sonra) | `flutter build linux` |
| iOS | ❌ macOS + Xcode şart | GitHub Actions `macos-latest` |
| Windows | ❌ Windows + Visual Studio şart | GitHub Actions `windows-latest` |

iOS ve Windows için proje dosyaları ve CI yapılandırması hazırlanır; derleme
ve test yalnızca ilgili işletim sisteminde ya da CI'da yapılabilir.

## Android uygulama kimliği

Capacitor APK'sı `com.skt.pastatakip` kimliğini kullanıyor. Flutter aynı kimliği
kullanırsa telefona kurulduğunda mevcut uygulamanın **üzerine yazar**. React
istemcisi kullanımda kaldığı sürece Flutter ayrı kimlikle gider:
`com.skt.foodtakip`. Geçiş tamamlanınca kimlik devralınabilir.

## Paket seçimleri

| İhtiyaç | Paket | Neden |
| --- | --- | --- |
| HTTP | `dio` | Interceptor'lar mevcut yükleme/bildirim mekanizmasına birebir karşılık gelir |
| Durum | `provider` | Mevcut React Context yapısının doğrudan karşılığı, düşük risk |
| Yönlendirme | `go_router` | Web'de gerçek URL desteği (web hedefi olduğu için şart) |
| Yerel depolama | `shared_preferences` | Token, tema, menü tercihi — 5 platformda da çalışır |
| Grafik | `fl_chart` | 7 günlük satış/ciro çubuk grafikleri |
| Fotoğraf | `image_picker` + `image` | Seçim ve 256×256 kırpma/küçültme |
| Biçimlendirme | `intl` | tr_TR tarih ve para biçimi |

## Proje yapısı

```
flutter_app/
  lib/
    main.dart
    app.dart                 # tema + router kurulumu
    core/
      api_client.dart        # dio + busy/toast interceptor'lari
      busy.dart              # acik istek sayaci (busy.js karsiligi)
      theme.dart             # tasarim token'lari (index.css :root karsiligi)
      format.dart            # fmtDateTime, fmtMoney, normalizeSearch
      session.dart           # token + kullanici durumu (auth.jsx karsiligi)
    models/                  # User, Store, ProductType, Batch, Sale, ...
    widgets/                 # Avatar, BusyOverlay, ToastHost, ActionMenu, StatCard
    screens/                 # login, dashboard, batches, recommendations, ...
  android/ ios/ web/ windows/ linux/   # flutter create ile uretilir
```

## API yüzeyi (41 uç nokta)

Taban: `https://food-takip-sistemi.vercel.app/api`

- **auth**: `POST /auth/login`, `GET /auth/me`, `POST /auth/password`, `POST /auth/avatar`
- **batches**: `GET /batches`, `GET /batches/:id`, `POST /batches`,
  `POST /batches/:id/{thaw,complete-thaw,discard,sell,add-stock,request-early-transfer}`,
  `PUT /batches/:id/adjust`
- **product-types**: `GET|POST /product-types`, `PUT|DELETE /product-types/:id`
- **stores**: `GET|POST /stores`, `GET|PUT|DELETE /stores/:id`
- **users**: `GET|POST /users`, `PUT|DELETE /users/:id`, `POST /users/:id/password`
- **recommendations**: `GET /recommendations`
- **sales**: `GET|POST /sales`
- **dashboard**: `GET /dashboard`
- **reports**: `GET /reports/{summary,sales7,status,activity,products}`
- **logs**: `GET /logs`
- **approvals**: `GET /approvals`, `POST /approvals/:id/{approve,reject}`

## Ekran taşıma sırası — tamamlandı

Her adım `flutter analyze`, `flutter test` ve derleme ile doğrulandı.

1. ✅ **Altyapı** — tema token'ları, api_client, busy overlay, toast, session, router
2. ✅ **Login** — token, hata, yükleme akışı
3. ✅ **Dashboard** — operasyon özeti + raporlar + grafikler + ürün performansı
4. ✅ **Öneri Satış Listesi** — arama, kademeler, tek adetlik satış onayı
5. ✅ **Ürünler / Stok** — 4 sekme, işlem menüsü, 7 diyalog
6. ✅ **Pasta Çeşitleri · Mağazalar · Kullanıcılar** — CRUD ekranları
7. ✅ **Satış Geçmişi · Hareket Kayıtları · Onaylar** — liste ekranları
8. ✅ **Profil** — fotoğraf yükleme, tema seçimi, şifre değiştirme, çıkış
9. ✅ **Platform paketleme** — `.github/workflows/flutter-release.yml`

`nav.dart`'taki her yolun `app.dart`'ta bir ekranı olduğu testle korunuyor
(`test/routes_test.dart`), yani menüye yeni giriş eklenip ekranı yazılmazsa
test kırılır.

## Taşıma sırasında ortaya çıkan ve düzeltilen konular

- **Izgara kartlarında taşma** — sabit `childAspectRatio` uzun ürün adında
  içeriği kesiyordu. Satırlar `IntrinsicHeight` ile kendi içeriği kadar
  yükseliyor; aynı satırdaki kartlar eşit kalıyor.
- **`image_picker` masaüstünde yok** — Linux ve Windows'ta profil fotoğrafı
  seçimi `MissingPluginException` atardı. `lib/core/image_pick.dart`
  masaüstünde `file_selector`, telefonda `image_picker` kullanıyor.
- **Bozuk görsel** — `decodeImage` null dönmek yerine `RangeError` atabiliyor;
  tek bir `FormatException`'a çevrilip ekranda mesaj olarak gösteriliyor.
- **Avatar boyutu** — sunucu 400.000 karakterin üstünü reddediyor. Kare kırpma
  + 256×256 küçültme istemcide yapılıyor, gerekirse JPEG kalitesi kademeli
  düşürülüyor (React'te canvas ile yapılan işin `image` paketi karşılığı).

## Platform durumu

| Platform | Durum | Not |
|---|---|---|
| Web | ✅ yerel `flutter build web --release` geçiyor | |
| Linux | ✅ yerel `flutter build linux --release` geçiyor | çalıştırıldı |
| Android | ⏳ CI'da derleniyor, yerelde denenmedi | `com.skt.foodtakip` (Capacitor APK'sı `com.skt.pastatakip`, çakışmaz) |
| Windows | ⏳ yalnızca CI (`windows-latest`) | Ubuntu'da derlenemez |
| iOS | ⏳ yalnızca CI (`macos-latest`), imzasız | App Store için Apple Developer hesabı gerekir |

Mevcut React istemcisi 3143 satır; Dart karşılığı 7102 satır + 74 test.
