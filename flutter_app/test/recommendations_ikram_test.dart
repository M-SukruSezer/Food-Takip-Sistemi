import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/api_client.dart';
import 'package:foodtakip/core/session.dart';
import 'package:foodtakip/screens/recommendations_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

/// SKT'si yakin bir food dolabi partisi + SKT'si gecmis bir parti.
final _recommendations = [
  {'id': 101, 'product_name': 'Çikolatalı Pasta', 'remaining': 4, 'quantity': 6,
   'status': 'food_cabinet', 'urgency': 'critical', 'remaining_hours': 10, 'days_left': 0,
   'skt_end': '2026-09-24T10:00:00.000Z', 'store_name': 'Merkez',
   'product_unit_price': 250},
  {'id': 102, 'product_name': 'Poğaça', 'remaining': 2, 'quantity': 2,
   'status': 'food_cabinet', 'urgency': 'expired', 'remaining_hours': -5, 'days_left': 0,
   'skt_end': '2026-09-22T10:00:00.000Z', 'store_name': 'Merkez',
   'product_unit_price': null},
];

void main() {
  late FakeAdapter adapter;
  late HttpClientAdapter original;

  setUp(() {
    initTestFormatting();
    SharedPreferences.setMockInitialValues({});
    original = api.dio.httpClientAdapter;
    adapter = installFakeApi({
      'GET /recommendations': _recommendations,
      'POST /batches/101/sell': {'id': 1, 'remaining': 3, 'status': 'food_cabinet'},
    });
  });

  tearDown(() async {
    api.dio.httpClientAdapter = original;
    await session.signOut();
  });

  testWidgets('kademe başlığı sadece Son Gün yazar', (tester) async {
    signInAs('staff', storeId: 4);
    await tester.pumpWidget(host(const RecommendationsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Son Gün'), findsOneWidget);
    expect(find.textContaining('0-24'), findsNothing);
  });

  testWidgets('SKT\'si geçmemiş ürün Satış, İkram ve Zayi sunar', (tester) async {
    signInAs('staff', storeId: 4);
    await tester.pumpWidget(host(const RecommendationsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Satış'), findsOneWidget);
    expect(find.text('İkram'), findsOneWidget);
    // Iki kart var ama SKT'si gecen urunde yalnizca zayi kalir.
    expect(find.text('Zayi'), findsNWidgets(2));
  });

  testWidgets('ikram onayı ciroya girmeyeceğini söyler ve kind gönderir', (tester) async {
    signInAs('staff', storeId: 4);
    await tester.pumpWidget(host(const RecommendationsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('İkram'));
    await tester.pumpAndSettle();

    expect(find.text('İkramı Onayla'), findsOneWidget);
    expect(find.textContaining('satış adedine sayılmaz'), findsOneWidget);
    expect(find.textContaining('İkram değeri olarak 250,00 TL'), findsOneWidget);

    await tester.tap(find.text('1 Adet İkram Et'));
    await tester.pumpAndSettle();

    expect(adapter.bodies['POST /batches/101/sell'], {'quantity': 1, 'kind': 'ikram'});
  });

  testWidgets('satış onayı kind göndermez, ciroyu söyler', (tester) async {
    signInAs('staff', storeId: 4);
    await tester.pumpWidget(host(const RecommendationsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Satış'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ciroya'), findsOneWidget);

    await tester.tap(find.text('1 Adet Sat'));
    await tester.pumpAndSettle();

    expect(adapter.bodies['POST /batches/101/sell'], {'quantity': 1});
  });

  testWidgets('telefonda üç düğme yan yana sığar ve 44px yüksekliği korur', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    signInAs('staff', storeId: 4);
    await tester.pumpWidget(host(const RecommendationsScreen()));
    await tester.pumpAndSettle();

    final sell = tester.getRect(find.widgetWithText(FilledButton, 'Satış'));
    final ikram = tester.getRect(find.widgetWithText(OutlinedButton, 'İkram'));
    // Ayni satirda: ust kenarlar esit, ikram satisin sagina duser.
    expect(ikram.top, sell.top);
    expect(ikram.left, greaterThan(sell.right));
    expect(sell.height, greaterThanOrEqualTo(44.0));
    expect(ikram.height, greaterThanOrEqualTo(44.0));
  });
  group('Yetkiler', () {
    testWidgets('ikram yetkisi olmayan kullanıcıda İkram düğmesi yok', (tester) async {
      signInAs('staff', storeId: 4, permissions: const ['discard']);
      await tester.pumpWidget(host(const RecommendationsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Satış'), findsOneWidget);
      expect(find.text('İkram'), findsNothing);
      expect(find.text('Zayi'), findsNWidgets(2));
    });

    testWidgets('zayi yetkisi olmayan kullanıcıda Zayi düğmesi yok', (tester) async {
      signInAs('staff', storeId: 4, permissions: const ['ikram']);
      await tester.pumpWidget(host(const RecommendationsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Zayi'), findsNothing);
      expect(find.text('İkram'), findsOneWidget);
    });

    testWidgets('hiç yetkisi olmayan kullanıcı yalnızca satış yapar', (tester) async {
      signInAs('staff', storeId: 4, permissions: const []);
      await tester.pumpWidget(host(const RecommendationsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Satış'), findsOneWidget);
      expect(find.text('İkram'), findsNothing);
      expect(find.text('Zayi'), findsNothing);
    });

    testWidgets('ana yönetici yetki listesi boş olsa da hepsini görür', (tester) async {
      // Sunucu tam listeyi doner ama eski bir token bos gelse bile rol yeter.
      signInAs('super_admin', permissions: const []);
      await tester.pumpWidget(host(const RecommendationsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('İkram'), findsOneWidget);
      expect(find.text('Zayi'), findsNWidgets(2));
    });
  });

}
