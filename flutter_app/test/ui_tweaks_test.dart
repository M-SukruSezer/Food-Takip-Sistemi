import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/api_client.dart';
import 'package:foodtakip/core/nav.dart';
import 'package:foodtakip/core/session.dart';
import 'package:foodtakip/core/tokens.dart';
import 'package:foodtakip/screens/batches_screen.dart';
import 'package:foodtakip/screens/recommendations_screen.dart';
import 'package:foodtakip/widgets/app_shell.dart';
import 'package:foodtakip/widgets/search_field.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

final _recs = [
  {'id': 1, 'product_name': 'Çikolatalı Pasta', 'remaining': 4, 'quantity': 6,
   'status': 'food_cabinet', 'urgency': 'normal', 'remaining_hours': 60, 'days_left': 2,
   'skt_end': '2026-09-30T10:00:00.000Z', 'product_unit_price': 250},
];

Widget _shell(Brightness b) {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        builder: (c, s, child) => AppShell(child: child),
        routes: [GoRoute(path: '/dashboard', builder: (c, s) => const SizedBox.expand())],
      ),
    ],
  );
  return MaterialApp.router(theme: buildAppTheme(b), routerConfig: router);
}

Future<void> _teardownShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 61));
}

void main() {
  late HttpClientAdapter original;

  setUp(() {
    initTestFormatting();
    SharedPreferences.setMockInitialValues({});
    original = api.dio.httpClientAdapter;
    signInAs('super_admin');
  });

  tearDown(() async {
    api.dio.httpClientAdapter = original;
    await session.signOut();
  });

  testWidgets('kademe etiketleri "2 Gün" ve "3 Gün"', (tester) async {
    installFakeApi({'GET /recommendations': _recs});
    await tester.pumpWidget(host(const RecommendationsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Son Gün'), findsOneWidget);
    expect(find.text('2 Gün'), findsOneWidget);
    expect(find.text('3 Gün'), findsOneWidget);
    expect(find.text('1-2 Gün Kalan'), findsNothing);
    expect(find.text('2 Günden Fazla'), findsNothing);
  });

  testWidgets('ürünler ekranının adı "Ürünler"', (tester) async {
    installFakeApi({
      'GET /batches': const <Object>[],
      'GET /product-types': const <Object>[],
      'GET /stores': const <Object>[],
    });
    await tester.pumpWidget(host(const BatchesScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Ürünler'), findsOneWidget);
    expect(find.text('Ürünler / Stok'), findsNothing);
    // Menude de ayni ad.
    expect(navItems.firstWhere((i) => i.path == '/batches').label, 'Ürünler');
  });

  testWidgets('iki ekran da aynı arama kutusunu kullanır', (tester) async {
    installFakeApi({
      'GET /recommendations': _recs,
      'GET /batches': const <Object>[],
      'GET /product-types': const <Object>[],
      'GET /stores': const <Object>[],
    });

    await tester.pumpWidget(host(const RecommendationsScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(ProductSearchField), findsOneWidget);

    await tester.pumpWidget(host(const BatchesScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(ProductSearchField), findsOneWidget);
    expect(find.text('Ürün ara...'), findsOneWidget);
  });

  testWidgets('arama yazılınca Temizle çıkar ve alanı boşaltır', (tester) async {
    installFakeApi({
      'GET /batches': const <Object>[],
      'GET /product-types': const <Object>[],
      'GET /stores': const <Object>[],
    });
    await tester.pumpWidget(host(const BatchesScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Temizle'), findsNothing);
    await tester.enterText(find.byType(TextField), 'pasta');
    await tester.pumpAndSettle();
    expect(find.text('Temizle'), findsOneWidget);

    await tester.tap(find.text('Temizle'));
    await tester.pumpAndSettle();
    expect(find.text('Temizle'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('kenar menü zemini temaya göre değişir', (tester) async {
    tester.view.physicalSize = const Size(1440, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    installFakeApi({'GET /recommendations': const <Object>[]});

    final zeminler = <Color>[];
    for (final b in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(_shell(b));
      await tester.pumpAndSettle();
      final nav = tester.widget<Container>(
        find.ancestor(of: find.text('Operasyon Takip'), matching: find.byType(Container)).last,
      );
      zeminler.add((nav.decoration! as BoxDecoration).color!);
      await _teardownShell(tester);
    }
    expect(zeminler[0], AppTokens.light.sidebar);
    expect(zeminler[1], AppTokens.dark.sidebar);
    expect(zeminler[0], isNot(zeminler[1]));
  });

  testWidgets('çıkış önce onay ister', (tester) async {
    tester.view.physicalSize = const Size(1440, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    installFakeApi({'GET /recommendations': const <Object>[]});

    await tester.pumpWidget(_shell(Brightness.light));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.logout).first);
    await tester.pumpAndSettle();
    expect(find.text('Çıkış Yap'), findsWidgets);
    expect(find.textContaining('Devam etmek istiyor musunuz?'), findsOneWidget);

    // Vazgecince oturum acik kalmali.
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(session.signedIn, isTrue);

    await _teardownShell(tester);
  });
}
