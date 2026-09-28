import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/pages/profile_page.dart';

/// Profil onizleme sayfasi bagimsiz pompalanir; uygulama kabuguna ihtiyaci
/// yoktur (ProfilePageApp kendi MaterialApp'ini tasir).
Future<void> _pump(
  WidgetTester tester,
  Brightness brightness, {
  Size size = const Size(412, 915),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(platformBrightness: brightness),
      child: const ProfilePageApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('profil sayfası tüm bölümleri gösterir', (tester) async {
    await _pump(tester, Brightness.light);

    expect(find.text('Elif Yılmaz'), findsOneWidget);
    expect(find.text('Kıdemli Ürün Tasarımcısı'), findsOneWidget);
    expect(find.text('Profili Düzenle'), findsOneWidget);
    expect(find.text('Paylaş'), findsOneWidget);
    // 12840 kisa bicimde 12,8B yazilir.
    expect(find.text('12,8B'), findsOneWidget);
    expect(find.text('Bildirimler'), findsOneWidget);

    // Cikis karti ilk viewport'un altinda kalir; scroll ile acilir.
    await tester.scrollUntilVisible(
      find.text('Çıkış Yap'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Çıkış Yap'), findsOneWidget);
  });

  testWidgets('ayar anahtarı tıklanınca durumu değişir', (tester) async {
    await _pump(tester, Brightness.light);

    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
  });

  testWidgets('koyu temada hatasız render eder', (tester) async {
    await _pump(tester, Brightness.dark);
    expect(find.text('Elif Yılmaz'), findsOneWidget);
  });

  testWidgets('dar ekranda taşma yok', (tester) async {
    await _pump(tester, Brightness.light, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
  });
}
