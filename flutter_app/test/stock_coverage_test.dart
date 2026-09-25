import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/nav.dart';
import 'package:foodtakip/screens/stock_coverage_screen.dart';

import 'support/fake_api.dart';

Map<String, Object?> _item({
  required int id,
  required String name,
  int frozen = 0,
  int thawing = 0,
  int cabinet = 0,
  int sold = 0,
  double velocity = 0,
  double? cover,
  String? depletion,
  int? risk,
  num? price,
}) => {
      'product_type_id': id, 'name': name,
      'frozen_qty': frozen, 'thawing_qty': thawing, 'cabinet_qty': cabinet,
      'available_qty': frozen + thawing + cabinet,
      'sold_qty': sold, 'daily_velocity': velocity,
      'days_of_cover': cover, 'depletion_date': depletion, 'risk': risk,
      'unit_price': price, 'frozen_value': price == null ? null : frozen * price,
    };

Map<String, Object?> _overview(List<Map<String, Object?>> items, {int window = 14}) => {
      'store': {'id': 1, 'name': 'DÜZCE MERKEZ'},
      'petty_cash': {'weekly_limit': 0, 'spent_this_week': 0, 'remaining': 0,
        'expense_count': 0, 'used_pct': null, 'over_limit': false, 'limit_set': false},
      'revenue': {'month': '2026-09', 'days_in_month': 30, 'days_elapsed': 25,
        'days_with_data': 0, 'days_missing': 25, 'mtd_net_sales': 0, 'daily_avg': null,
        'forecast_month_end': null, 'remaining_days': 5, 'month_totals': {},
        'month_metrics': {}},
      'stock': {'window_days': window, 'items': items},
    };

final _full = [
  _item(id: 1, name: 'YULAFLI ÜZÜMLÜ COOKİE', cabinet: 1, sold: 3,
      velocity: 0.214, cover: 0, depletion: '2026-09-25', risk: 0, price: 120),
  _item(id: 2, name: 'OPERA FRAMBUAZ', frozen: 1, cabinet: 1, sold: 3,
      velocity: 0.214, cover: 4.666, depletion: '2026-09-29', risk: 2, price: 150),
  _item(id: 3, name: 'LOTUS CUP', frozen: 42, sold: 15,
      velocity: 1.071, cover: 39.2, depletion: '2026-11-03', risk: 3, price: 100),
  _item(id: 4, name: 'MARLENKA', frozen: 16, risk: null, price: 90),
];

void main() {
  setUpAll(initTestFormatting);

  void tall(WidgetTester tester, [double h = 3000]) {
    tester.view.physicalSize = Size(800, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  test('Stok Yeterliliği menüde iki role açık', () {
    final item = navItems.firstWhere((i) => i.path == '/stock-coverage');
    expect(item.label, 'Stok Yeterliliği');
    expect(item.roles, reportPanelRoles);
    expect(item.roles, ['store_manager', 'shift_supervisor']);
  });

  testWidgets('ürün ürün adet, hız ve yeterlilik gösterilir', (tester) async {
    tall(tester);
    installFakeApi({'GET /manager-overview': _overview(_full)});
    signInAs('store_manager', storeId: 1);

    await tester.pumpWidget(host(const StockCoverageScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Stok Yeterliliği'), findsOneWidget);
    expect(find.text('LOTUS CUP'), findsOneWidget);
    expect(find.text('39 gün'), findsOneWidget);
    expect(find.text('4.7 gün'), findsOneWidget);
    // Stogu bitmis ama satan urun "bugun biter" yazar.
    expect(find.text('bugün biter'), findsOneWidget);
    // Risk etiketleri.
    expect(find.text('Stok yok'), findsOneWidget);
    expect(find.text('Azalıyor'), findsOneWidget);
    expect(find.text('Yeterli'), findsOneWidget);
    // Adet kirilimi.
    expect(find.text('Donuk depo'), findsNWidgets(3));
    expect(find.text('1.07/gün'), findsOneWidget);
  });

  testWidgets('satışı olmayan çeşitler ayrı bölümde', (tester) async {
    tall(tester);
    installFakeApi({'GET /manager-overview': _overview(_full)});
    signInAs('shift_supervisor', storeId: 1);

    await tester.pumpWidget(host(const StockCoverageScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Satış hareketi olmayan 1 çeşit'), findsOneWidget);
    expect(find.text('MARLENKA · 16 adet'), findsOneWidget);
    expect(find.textContaining('yeterlilik hesaplanamaz'), findsOneWidget);
  });

  testWidgets('kritik çeşit sayısı uyarı olarak çıkar', (tester) async {
    tall(tester);
    installFakeApi({'GET /manager-overview': _overview(_full)});
    signInAs('store_manager', storeId: 1);

    await tester.pumpWidget(host(const StockCoverageScreen()));
    await tester.pumpAndSettle();

    // risk 0 (stok yok) + risk 1 (kritik) sayilir; buradaki veride 1 tane var.
    expect(find.textContaining('1 çeşidin donuk deposu'), findsOneWidget);
  });

  testWidgets('arama ürünü filtreler', (tester) async {
    tall(tester);
    installFakeApi({'GET /manager-overview': _overview(_full)});
    signInAs('store_manager', storeId: 1);

    await tester.pumpWidget(host(const StockCoverageScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'lotus');
    await tester.pumpAndSettle();

    expect(find.text('LOTUS CUP'), findsOneWidget);
    expect(find.text('OPERA FRAMBUAZ'), findsNothing);
    // Aramada satis hareketi olmayan bolum de daralir.
    expect(find.textContaining('Satış hareketi olmayan'), findsNothing);
  });

  testWidgets('stok yoksa açıklama gösterir', (tester) async {
    tall(tester, 1200);
    installFakeApi({'GET /manager-overview': _overview(const [])});
    signInAs('store_manager', storeId: 1);

    await tester.pumpWidget(host(const StockCoverageScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('aktif stok veya satış kaydı yok'), findsOneWidget);
  });

  testWidgets('pencere değişince yeniden sorgulanır', (tester) async {
    tall(tester);
    final fake = installFakeApi({'GET /manager-overview': _overview(_full, window: 7)});
    signInAs('store_manager', storeId: 1);

    await tester.pumpWidget(host(const StockCoverageScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('7 gün'));
    await tester.pumpAndSettle();

    expect(fake.calls.where((c) => c.contains('days=7')).isNotEmpty, isTrue);
  });
}
