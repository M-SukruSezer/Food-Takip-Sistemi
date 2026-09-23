import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/format.dart';
import 'package:foodtakip/core/tokens.dart';
import 'package:foodtakip/screens/login_screen.dart';

void main() {
  testWidgets('giris ekrani alanlari ve dokunma hedefleri', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: const LoginScreen(),
    ));

    expect(find.text('Giriş Yap'), findsWidgets);
    expect(find.byType(TextField), findsNWidgets(2));

    // Sifre goster dugmesi parmak boyutunda olmali.
    final eye = tester.getSize(find.byType(IconButton).first);
    expect(eye.height, greaterThanOrEqualTo(AppTokens.tap));
    expect(eye.width, greaterThanOrEqualTo(AppTokens.tap));
  });

  test('normalizeSearch Turkce karakterleri duyarsizlastirir', () {
    expect(normalizeSearch('ÇİKOLATA'), normalizeSearch('cikolata'));
    expect(normalizeSearch('POĞAÇA'), normalizeSearch('pogaca'));
    expect(normalizeSearch('ÜZÜMLÜ'), normalizeSearch('uzumlu'));
    expect(normalizeSearch('TİRAMİSU'), 'tiramisu');
  });

  test('isUrgent yalnizca 48 saat altindaki kademeleri kapsar', () {
    expect(isUrgent('expired'), isTrue);
    expect(isUrgent('critical'), isTrue);
    expect(isUrgent('warning'), isTrue);
    expect(isUrgent('normal'), isFalse);
    expect(isUrgent(null), isFalse);
  });

  test('formatHours gun ve saati birlikte yazar', () {
    expect(formatHours(0), 'Süre doldu');
    expect(formatHours(5), '5 saat');
    expect(formatHours(24), '1 gün');
    expect(formatHours(53), '2 gün 5 saat');
  });
}
