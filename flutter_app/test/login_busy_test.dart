import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/api_client.dart';
import 'package:foodtakip/core/session.dart';
import 'package:foodtakip/core/tokens.dart';
import 'package:foodtakip/screens/login_screen.dart';
import 'package:foodtakip/widgets/busy_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Girisi yavaslatan adaptor: katmanin istek suresince acik kaldigini
/// olcebilmek icin yaniti geciktirir.
class _SlowLoginAdapter implements HttpClientAdapter {
  _SlowLoginAdapter(this.delay);
  final Duration delay;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? s, Future<void>? c) async {
    await Future<void>.delayed(delay);
    return ResponseBody.fromString(
      jsonEncode({
        'token': 'test-token',
        'user': {'id': 1, 'username': 'test', 'full_name': 'Test', 'role': 'staff', 'store_id': 4},
      }),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late HttpClientAdapter original;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    original = api.dio.httpClientAdapter;
  });

  tearDown(() async {
    api.dio.httpClientAdapter = original;
    await session.signOut();
  });

  testWidgets('giriş sırasında yükleme katmanı görünür', (tester) async {
    api.dio.httpClientAdapter = _SlowLoginAdapter(const Duration(milliseconds: 400));

    // Katman uygulamada MaterialApp.builder icinde duruyor; burada da oyle.
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: const LoginScreen(),
      builder: (context, child) => BusyOverlay(child: child ?? const SizedBox.shrink()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Yükleniyor...'), findsNothing);
    expect(find.text('Giriş yapılıyor...'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'test');
    await tester.enterText(find.byType(TextField).last, 'sifre123');
    await tester.tap(find.widgetWithText(FilledButton, 'Giriş Yap'));

    // Istek ucarken katman acik olmali.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Genel metin yerine girise ozel metin yazmali.
    // Katmanda girise ozel metin yazmali. ("Giriş yapılıyor..." ayni anda
    // dugmede de yaziyor, o yuzden katmanin kendi metni hedeflenir.)
    expect(
      find.descendant(of: find.byType(BusyOverlay), matching: find.text('Giriş yapılıyor...')),
      findsWidgets,
      reason: 'giriş isteği sürerken katman çıkmadı ya da genel metin yazdı',
    );
    expect(find.text('Yükleniyor...'), findsNothing);

    // Yanit gelip gizleme gecikmesi dolunca kapanmali.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Giriş yapılıyor...'), findsNothing);
  });
}
