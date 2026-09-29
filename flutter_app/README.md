# foodtakip

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Giriş görseli yönetimi

Super admin, **Profilim → Giriş Ekranı Görseli** bölümünden görsel seçebilir,
önizleyebilir, kaydedebilir veya varsayılan görsele dönebilir. Görsel kırpılmadan
1280 piksele küçültülür; tüm kullanıcıların giriş ekranında kullanılır.

Bu özellik `GET /api/branding/login` ve super-admin yetkisi gerektiren
`PUT /api/branding/login` uçlarını kullanır. Sunucu değişikliği APK ile birlikte
yayımlanmalıdır. `server/supabase/schema.sql` içindeki `app_settings` tablosu
sunucunun mevcut `initialize()` akışı tarafından oluşturulur. Eski sunucuda
login yerel görselle çalışmaya devam eder; görsel kaydetme kullanılamaz.

Doğrulama: `flutter analyze`, `flutter test test/mobile_refresh_test.dart` ve
proje kökünden `node --test server/test/branding.test.js`.
