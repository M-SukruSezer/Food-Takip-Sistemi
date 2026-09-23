import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/tokens.dart';
import 'package:foodtakip/screens/login_screen.dart';
import 'package:foodtakip/widgets/login_art.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Brightness brightness) => MaterialApp(
      theme: buildAppTheme(brightness),
      home: const LoginScreen(),
    );

/// Bir rengin uzerindeki yazinin okunurlugu: WCAG kontrast orani.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('illustrasyon, iki alan ve giriş düğmesi var', (tester) async {
    await tester.pumpWidget(_app(Brightness.light));

    expect(find.byType(LoginArt), findsOneWidget);
    expect(find.text('Hoş geldin!'), findsOneWidget);
    // Marka yazisi ve alt baslik kaldirildi.
    expect(find.text('FOOD TAKİP'), findsNothing);
    expect(find.text('Stok ve SKT takibi tek ekranda'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Kullanıcı adı'), findsOneWidget);
    expect(find.text('Şifre'), findsOneWidget);
    expect(find.text('Şifremi unuttum?'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Giriş Yap'), findsOneWidget);
  });

  testWidgets('alanlar ve düğme hap biçiminde, 44px üstünde', (tester) async {
    await tester.pumpWidget(_app(Brightness.light));

    final button = tester.getSize(find.widgetWithText(FilledButton, 'Giriş Yap'));
    expect(button.height, greaterThanOrEqualTo(AppTokens.tap));

    // Sifre goster dugmesi parmak boyutunda olmali.
    final eye = tester.getSize(find.byType(IconButton).first);
    expect(eye.height, greaterThanOrEqualTo(AppTokens.tap));
    expect(eye.width, greaterThanOrEqualTo(AppTokens.tap));

    // "Sifremi unuttum?" de dokunulabilir yukseklikte.
    final forgot = tester.getSize(find.widgetWithText(TextButton, 'Şifremi unuttum?'));
    expect(forgot.height, greaterThanOrEqualTo(AppTokens.tap));
  });

  testWidgets('şifre alanı gizli başlar ve göz düğmesiyle açılır', (tester) async {
    await tester.pumpWidget(_app(Brightness.light));

    TextField passwordField() => tester.widgetList<TextField>(find.byType(TextField)).last;
    expect(passwordField().obscureText, isTrue);

    await tester.tap(find.byType(IconButton).first);
    await tester.pump();
    expect(passwordField().obscureText, isFalse);
  });

  testWidgets('panel yazısı her iki temada okunur kalır', (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(_app(brightness));
      await tester.pump();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      final panel = scaffold.backgroundColor!;
      final heading = tester.widget<Text>(find.text('Hoş geldin!'));
      // WCAG AA buyuk yazi esigi 3:1; basligi bunun uzerinde tutuyoruz.
      expect(
        _contrast(panel, heading.style!.color!),
        greaterThan(3.0),
        reason: '$brightness temasinda baslik kontrasti yetersiz',
      );

      // Siyah hap dugmenin yazisi da zeminiyle ayrismali.
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      final style = btn.style!;
      final bg = style.backgroundColor!.resolve({})!;
      final fg = style.foregroundColor!.resolve({})!;
      expect(_contrast(bg, fg), greaterThan(4.5), reason: '$brightness temasinda düğme kontrastı');
    }
  });

  testWidgets('küçük telefonda taşma olmaz ve klavye açılınca kaydırılır', (tester) async {
    // 360x640: yaygin kucuk Android ekrani.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(Brightness.light));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Icerik kaydirilabilir olmali ki klavye acilinca dugme erisilebilsin.
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('geniş ekranda içerik ortalanır ve aşırı genişlemez', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(Brightness.light));
    await tester.pumpAndSettle();

    final button = tester.getRect(find.widgetWithText(FilledButton, 'Giriş Yap'));
    expect(button.width, lessThanOrEqualTo(460));
    // Yatayda ortalanmis olmali.
    expect(button.center.dx, closeTo(700, 1));
  });
  group('Beni hatırla', () {
    testWidgets('kayıtlı kullanıcı adı alana yazılır ve kutu işaretli gelir', (tester) async {
      SharedPreferences.setMockInitialValues({'rememberedUser': 'ayse'});

      await tester.pumpWidget(_app(Brightness.light));
      await tester.pumpAndSettle();

      expect(find.text('ayse'), findsOneWidget);
      final box = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(box.value, isTrue);
    });

    testWidgets('kayıt yoksa kutu boş gelir', (tester) async {
      await tester.pumpWidget(_app(Brightness.light));
      await tester.pumpAndSettle();

      final box = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(box.value, isFalse);
      expect(find.text('Beni hatırla'), findsOneWidget);
    });

    testWidgets('kutu dokunma hedefini korur', (tester) async {
      await tester.pumpWidget(_app(Brightness.light));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(Checkbox));
      expect(size.height, greaterThanOrEqualTo(AppTokens.tap));
      expect(size.width, greaterThanOrEqualTo(AppTokens.tap));
    });
  });

  testWidgets('alan odaklanınca görsel geri bildirim verir', (tester) async {
    await tester.pumpWidget(_app(Brightness.light));
    await tester.pumpAndSettle();

    BoxDecoration pill() {
      // Hap gövdesi, TextField'i saran AnimatedContainer.
      final finder = find.ancestor(
        of: find.byType(TextField).first,
        matching: find.byType(AnimatedContainer),
      );
      return tester.widget<AnimatedContainer>(finder.first).decoration! as BoxDecoration;
    }

    // Kendi çerçevesi olmadığı için odak halkası olmadan hiçbir işaret yoktu.
    expect(pill().boxShadow, isNull);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(pill().boxShadow, isNotNull);
  });

  testWidgets('illüstrasyon kart içinde değil, doğrudan zemin üzerinde', (tester) async {
    await tester.pumpWidget(_app(Brightness.light));
    await tester.pumpAndSettle();

    // Gorselin ustunde arka plani olan bir kap kalmamali.
    final kaplar = find
        .ancestor(of: find.byType(LoginArt), matching: find.byType(Container))
        .evaluate()
        .map((e) => (e.widget as Container).decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.color != null);
    expect(kaplar, isEmpty, reason: 'illüstrasyonun etrafında hâlâ bir kart var');
  });

  testWidgets('sayfa zemini temaya göre değişir', (tester) async {
    final zeminler = <Color>[];
    for (final b in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(_app(b));
      await tester.pumpAndSettle();
      zeminler.add(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor!);
    }
    expect(zeminler[0], AppTokens.light.bg);
    expect(zeminler[1], AppTokens.dark.bg);
  });

  testWidgets('koyu temada görselin arkasında açık daire var', (tester) async {
    BoxDecoration? arkaPlan(WidgetTester t) {
      final kaplar = find
          .ancestor(of: find.byType(LoginArt), matching: find.byType(Container))
          .evaluate()
          .map((e) => (e.widget as Container).decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color != null);
      return kaplar.isEmpty ? null : kaplar.first;
    }

    // Acik temada zemin zaten acik; daireye gerek yok.
    await tester.pumpWidget(_app(Brightness.light));
    await tester.pumpAndSettle();
    expect(arkaPlan(tester), isNull);

    // Koyu temada gorselin siyah konturlari lacivert zeminle birlesiyordu.
    await tester.pumpWidget(_app(Brightness.dark));
    await tester.pumpAndSettle();
    final daire = arkaPlan(tester);
    expect(daire, isNotNull, reason: 'koyu temada daire yok');
    expect(daire!.shape, BoxShape.circle);
    expect(daire.color, const Color(0xFFFFFFFF));
  });

}
