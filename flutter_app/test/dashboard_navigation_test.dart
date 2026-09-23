import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/app.dart';
import 'package:foodtakip/core/api_client.dart';
import 'package:foodtakip/core/session.dart';
import 'package:foodtakip/core/tokens.dart';
import 'package:foodtakip/screens/batches_screen.dart';
import 'package:foodtakip/screens/recommendations_screen.dart';
import 'package:foodtakip/screens/sales_screen.dart';
import 'package:foodtakip/widgets/panels.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

final _dashboard = {
  'counts': {
    'frozen': 2, 'frozen_qty': 8,
    'thawing': 1, 'thawing_qty': 4,
    'food_cabinet': 5, 'food_cabinet_qty': 33,
    'expiring_qty': 3, 'expired_qty': 2, 'expiring_count': 4,
  },
  'soldToday': {'count': 7, 'qty': 9, 'revenue': 1350},
  'ikramToday': {'count': 0, 'qty': 0, 'value': 0},
};

/// Ana sayfadan hedef ekrana gidip gelmeyi olcmek icin gercek router.
Widget _app() {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        // Kabuk yerine sade bir govde: olculen sey yonlendirme.
        builder: (c, s, child) => Scaffold(body: child),
        routes: [
          for (final entry in shellScreens.entries)
            GoRoute(path: entry.key, builder: (c, s) => entry.value(s)),
        ],
      ),
    ],
  );
  return MaterialApp.router(theme: buildAppTheme(Brightness.light), routerConfig: router);
}

void main() {
  late HttpClientAdapter original;

  setUp(() {
    initTestFormatting();
    SharedPreferences.setMockInitialValues({});
    original = api.dio.httpClientAdapter;
    installFakeApi({
      'GET /dashboard': _dashboard,
      'GET /reports/summary': {'type': 'single', 'store': {'id': 4, 'name': 'Merkez'},
        'sold_qty': 98, 'revenue': 17855, 'sold_count': 98, 'discarded_qty': 36,
        'frozen_qty': 8, 'thawing_qty': 4, 'cabinet_qty': 33, 'ikram_qty': 0, 'product_count': 61},
      'GET /reports/sales7': const <Object>[],
      'GET /reports/status': const <Object>[],
      'GET /reports/products': {'week': {'from': '', 'days': 7, 'sold': [], 'wasted': []},
        'month': {'from': '', 'days': 30, 'sold': [], 'wasted': []}},
      'GET /approvals': const <Object>[],
      'GET /batches': const <Object>[],
      'GET /product-types': const <Object>[],
      'GET /reports/movements': {'items': [], 'totals': {}},
      'GET /recommendations': const <Object>[],
    });
    signInAs('store_manager', storeId: 4);
  });

  tearDown(() async {
    api.dio.httpClientAdapter = original;
    await session.signOut();
  });

  Future<void> pumpDashboard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
  }

  testWidgets('özet kutuları masaüstünde de katlanmadan açık gelir', (tester) async {
    await pumpDashboard(tester);

    // Katlama dugmesi kaldirildi; kutular dogrudan gorunur.
    expect(find.text('Operasyon Özeti'), findsNothing);
    for (final label in ['Donuk Depo', 'Çözülme', 'Food Dolabı', 'SKT Geçen']) {
      expect(find.text(label), findsOneWidget, reason: '$label kutusu yok');
    }
  });

  testWidgets('kutular tıklanabilir', (tester) async {
    await pumpDashboard(tester);

    final cards = tester.widgetList<StatCard>(find.byType(StatCard));
    expect(cards, isNotEmpty);
    for (final card in cards) {
      expect(card.onTap, isNotNull, reason: '"${card.label}" kutusu tıklanamıyor');
    }
  });

  testWidgets('Donuk Depo kutusu stok ekranını donuk sekmesinde açar', (tester) async {
    await pumpDashboard(tester);

    await tester.tap(find.text('Donuk Depo'));
    await tester.pumpAndSettle();

    expect(find.byType(BatchesScreen), findsOneWidget);
    expect(tester.widget<BatchesScreen>(find.byType(BatchesScreen)).initialTab, 'frozen');
  });

  testWidgets('Food Dolabı kutusu doğru sekmeye gider', (tester) async {
    await pumpDashboard(tester);

    await tester.tap(find.text('Food Dolabı'));
    await tester.pumpAndSettle();

    expect(tester.widget<BatchesScreen>(find.byType(BatchesScreen)).initialTab, 'food_cabinet');
  });

  testWidgets('Bugün Satılan kutusu raporu bugüne ve satışa filtreler', (tester) async {
    await pumpDashboard(tester);

    await tester.tap(find.text('Bugün Satılan'));
    await tester.pumpAndSettle();

    final screen = tester.widget<SalesScreen>(find.byType(SalesScreen));
    expect(screen.initialRange, 'today');
    expect(screen.initialKind, 'sale');
  });

  testWidgets('SKT Geçen kutusu öneri listesini açar', (tester) async {
    await pumpDashboard(tester);

    await tester.tap(find.text('SKT Geçen'));
    await tester.pumpAndSettle();

    expect(find.byType(RecommendationsScreen), findsOneWidget);
  });
}
