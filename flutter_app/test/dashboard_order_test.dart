import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/screens/dashboard_screen.dart';
import 'package:foodtakip/screens/manager_overview_block.dart';
import 'package:foodtakip/widgets/panels.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

/// Ana sayfada Ciro Forecast ve Petty Cash en ustte duruyor mu?
///
/// Bu sira istenen davranis: magaza muduru ve vardiya muduru gune bu iki
/// rakamla basliyor, ozet kutularini ve grafikleri aramak icin kaydirmiyor.
final _dashboard = {
  'counts': {
    'frozen': 2, 'frozen_qty': 8,
    'thawing': 1, 'thawing_qty': 4,
    'food_cabinet': 5, 'food_cabinet_qty': 33,
    // SKT'si dolmus urun var: uyari bandi da cizilecek.
    'expiring_qty': 3, 'expired_qty': 2, 'expiring_count': 4,
  },
  'soldToday': {'count': 7, 'qty': 9, 'revenue': 1350},
  'ikramToday': {'count': 0, 'qty': 0, 'value': 0},
};

final _overview = {
  'store': {'id': 4, 'name': 'Merkez'},
  'petty_cash': {
    'weekly_limit': 10000, 'spent_this_week': 2500, 'remaining': 7500,
    'expense_count': 3, 'used_pct': 0.25, 'over_limit': false, 'limit_set': true,
  },
  'revenue': {
    'month': '2026-09', 'days_in_month': 30, 'days_elapsed': 25,
    'days_with_data': 10, 'days_missing': 15, 'mtd_net_sales': 250000,
    'daily_avg': 25000, 'forecast_month_end': 750000, 'remaining_days': 5,
    'month_totals': {'net_sales': 250000}, 'month_metrics': {'at': 62.5},
  },
  'stock': {'window_days': 14, 'items': []},
};

Map<String, Object?> _routes() => {
      'GET /dashboard': _dashboard,
      'GET /manager-overview': _overview,
      'GET /daily-reports/fields': {
        'entry': [], 'system': [],
        'derived': [{'key': 'at', 'label': 'AT', 'type': 'money'}],
      },
      'GET /reports/summary': {
        'type': 'single', 'store': {'id': 4, 'name': 'Merkez'},
        'sold_qty': 98, 'revenue': 17855, 'sold_count': 98, 'discarded_qty': 36,
        'frozen_qty': 8, 'thawing_qty': 4, 'cabinet_qty': 33, 'ikram_qty': 0,
        'product_count': 61,
      },
      'GET /reports/sales7': const <Object>[],
      'GET /reports/status': const <Object>[],
      'GET /reports/products': {
        'week': {'from': '', 'days': 7, 'sold': [], 'wasted': []},
        'month': {'from': '', 'days': 30, 'sold': [], 'wasted': []},
      },
      'GET /approvals': const <Object>[],
    };

void main() {
  setUp(() {
    initTestFormatting();
    SharedPreferences.setMockInitialValues({});
  });

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('Ciro Forecast ve Petty Cash sayfanın en üstünde', (tester) async {
    tall(tester);
    installFakeApi(_routes());
    signInAs('store_manager', storeId: 4);

    await tester.pumpWidget(host(const DashboardScreen()));
    await tester.pumpAndSettle();

    final forecast = tester.getTopLeft(find.text('Ciro Forecast')).dy;
    final petty = tester.getTopLeft(find.text('Petty Cash')).dy;

    // Ciro Forecast birinci, Petty Cash ikinci.
    expect(forecast, lessThan(petty));

    // Ozet kutularindan, uyari bandindan ve grafiklerden once.
    final stat = tester.getTopLeft(find.text('Donuk Depo')).dy;
    expect(petty, lessThan(stat),
        reason: 'Petty Cash özet kutularının üstünde olmalı');

    final alert = tester.getTopLeft(find.byType(AppAlert).first).dy;
    expect(petty, lessThan(alert),
        reason: 'Petty Cash uyarı bandının üstünde olmalı');

    final chart = tester.getTopLeft(find.text('Son 7 Günlük Satış')).dy;
    expect(petty, lessThan(chart));
  });

  testWidgets('blok yalnızca iki role çizilir', (tester) async {
    tall(tester);
    installFakeApi(_routes());
    // Barista ana sayfayi gorur ama genel raporu gormez.
    signInAs('barista', storeId: 4);

    await tester.pumpWidget(host(const DashboardScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(ManagerOverviewBlock), findsNothing);
    expect(find.text('Ciro Forecast'), findsNothing);
    // Ozet kutulari yine yerinde.
    expect(find.text('Donuk Depo'), findsOneWidget);
  });

  testWidgets('stok yeterliliği ana sayfada çizilmez', (tester) async {
    tall(tester);
    installFakeApi(_routes());
    signInAs('shift_supervisor', storeId: 4);

    await tester.pumpWidget(host(const DashboardScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(ManagerOverviewBlock), findsOneWidget);
    // Kendi modulune tasindi.
    expect(find.text('Donuk Depo Yeterliliği'), findsNothing);
  });
}
