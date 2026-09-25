import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/notify.dart';
import 'package:foodtakip/core/tokens.dart';
import 'package:foodtakip/widgets/scrim.dart';
import 'package:foodtakip/widgets/shortcut_fab.dart';
import 'package:go_router/go_router.dart';

import 'support/fake_api.dart';

/// Kisayol dugmesi go_router'a bagimli (Onaylar kisayolu yonlendiriyor), bu
/// yuzden gercek bir router ile kuruluyor.
Widget _app({Brightness brightness = Brightness.light}) {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      GoRoute(
        path: '/dashboard',
        builder: (c, s) => const Scaffold(
          body: Center(child: Text('ana sayfa')),
          floatingActionButton: ShortcutFab(bottomInset: 64),
        ),
      ),
      GoRoute(path: '/approvals', builder: (c, s) => const Scaffold(body: Text('onaylar ekranı'))),
    ],
  );
  // toast ScaffoldMessenger uzerinden ciziliyor; anahtar baglanmadan gorunmez.
  return MaterialApp.router(
    scaffoldMessengerKey: messengerKey,
    theme: buildAppTheme(brightness),
    routerConfig: router,
  );
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestFormatting);

  group('Kısayol listesi role göre', () {
    testWidgets('mağaza müdürü dört kısayol görür', (tester) async {
      installFakeApi({});
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(_app());
      await _openMenu(tester);

      expect(find.text('Donuk Depoya Ürün Ekle'), findsOneWidget);
      expect(find.text('Masraf Gir'), findsOneWidget);
      expect(find.text('Günlük Rapor Gir'), findsOneWidget);
      expect(find.text('Onaylar'), findsOneWidget);
    });

    testWidgets('vardiya müdürü onaylar kısayolunu görmez', (tester) async {
      installFakeApi({});
      signInAs('shift_supervisor', storeId: 1);

      await tester.pumpWidget(_app());
      await _openMenu(tester);

      // Masraf ve rapor girisi onda; onay yetkisi yok.
      expect(find.text('Masraf Gir'), findsOneWidget);
      expect(find.text('Günlük Rapor Gir'), findsOneWidget);
      expect(find.text('Onaylar'), findsNothing);
    });

    testWidgets('barista yalnızca ürün eklemeyi görür', (tester) async {
      installFakeApi({});
      signInAs('barista', storeId: 1);

      await tester.pumpWidget(_app());
      await _openMenu(tester);

      expect(find.text('Donuk Depoya Ürün Ekle'), findsOneWidget);
      expect(find.text('Masraf Gir'), findsNothing);
      expect(find.text('Günlük Rapor Gir'), findsNothing);
      expect(find.text('Onaylar'), findsNothing);
    });

    test('rol kısayol listesi', () {
      expect(hasShortcuts('barista'), isTrue);
      expect(hasShortcuts('store_manager'), isTrue);
      expect(hasShortcuts(null), isFalse);
    });
  });

  group('Menü davranışı', () {
    testWidgets('açılan menü yükleniyor perdesiyle aynı zemini kullanır',
        (tester) async {
      installFakeApi({});
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(_app());
      expect(find.byType(AppScrim), findsNothing);

      await _openMenu(tester);
      // Yukleme katmaniyla ortak perde.
      expect(find.byType(AppScrim), findsOneWidget);
      // Perdeye dokunmak kapatir, bu yuzden tiklamalar yutulmuyor.
      expect(tester.widget<AppScrim>(find.byType(AppScrim)).absorb, isFalse);
    });

    testWidgets('perde rengi temaya göre değişir', (tester) async {
      installFakeApi({});
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(_app());
      await _openMenu(tester);
      final light = AppScrim.color(tester.element(find.byType(AppScrim)));

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_app(brightness: Brightness.dark));
      await _openMenu(tester);
      final dark = AppScrim.color(tester.element(find.byType(AppScrim)));

      expect(light, isNot(dark));
      // Koyu temada perde daha koyu.
      expect(dark.computeLuminance(), lessThan(light.computeLuminance()));
    });

    testWidgets('perdeye dokunmak menüyü kapatır', (tester) async {
      installFakeApi({});
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(_app());
      await _openMenu(tester);
      expect(find.text('Masraf Gir'), findsOneWidget);

      // Ust bolgeye dokun: oge yok, yalnizca perde var.
      await tester.tapAt(const Offset(200, 80));
      await tester.pumpAndSettle();
      expect(find.text('Masraf Gir'), findsNothing);
    });

    testWidgets('kapat düğmesi menüyü kapatır', (tester) async {
      installFakeApi({});
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(_app());
      await _openMenu(tester);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(AppScrim), findsNothing);
      expect(find.byIcon(Icons.bolt), findsOneWidget);
    });

    testWidgets('Onaylar kısayolu ilgili ekrana gider', (tester) async {
      installFakeApi({});
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(_app());
      await _openMenu(tester);
      await tester.tap(find.text('Onaylar'));
      await tester.pumpAndSettle();

      expect(find.text('onaylar ekranı'), findsOneWidget);
    });
  });

  group('Kısayol işleri', () {
    testWidgets('ürün ekleme formu çeşit listesiyle açılır', (tester) async {
      installFakeApi({
        'GET /product-types': [
          {'id': 1, 'name': 'LOTUS CUP', 'skt_days': 3, 'unit_price': 100, 'active': 1},
        ],
      });
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(_app());
      await _openMenu(tester);
      await tester.tap(find.text('Donuk Depoya Ürün Ekle'));
      await tester.pumpAndSettle();

      expect(find.text('Yeni Ürün'), findsOneWidget);
      expect(find.textContaining('LOTUS CUP'), findsWidgets);
    });

    testWidgets('çeşit yoksa uyarı verir, form açılmaz', (tester) async {
      installFakeApi({'GET /product-types': const <Object>[]});
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(_app());
      await _openMenu(tester);
      await tester.tap(find.text('Donuk Depoya Ürün Ekle'));
      await tester.pumpAndSettle();

      expect(find.text('Yeni Ürün'), findsNothing);
      expect(find.textContaining('pasta çeşidi tanımlanmalı'), findsOneWidget);
    });

    testWidgets('masraf formu limit durumuyla açılır', (tester) async {
      installFakeApi({
        'GET /petty-cash': {
          'items': [],
          'status': {
            'store_id': 1, 'weekly_limit': 5000, 'spent_this_week': 500,
            'remaining': 4500, 'week_start': '2026-09-21T00:00:00.000Z',
            'pending_this_week': 0, 'pending_count': 0, 'can_approve': true,
          },
        },
      });
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(_app());
      await _openMenu(tester);
      await tester.tap(find.text('Masraf Gir'));
      await tester.pumpAndSettle();

      // Form kalan tutari gosteriyor.
      expect(find.textContaining('4.500,00 TL'), findsWidgets);
    });

    testWidgets('günlük rapor formu alanlarıyla açılır', (tester) async {
      installFakeApi({
        'GET /daily-reports/fields': {
          'entry': [{'key': 'net_sales', 'label': 'NET SALES', 'type': 'money'}],
          'system': [],
          'derived': [],
        },
        'GET /daily-reports/day/2026-09-25': {'report': null, 'suggested': {}},
      });
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(_app());
      await _openMenu(tester);
      await tester.tap(find.text('Günlük Rapor Gir'));
      await tester.pumpAndSettle();

      expect(find.text('Günlük Rapor'), findsOneWidget);
      expect(find.text('NET SALES'), findsOneWidget);
    });
  });
}
