import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/models/manager_overview.dart';
import 'package:foodtakip/models/daily_report.dart';
import 'package:foodtakip/screens/manager_overview_block.dart';

import 'support/fake_api.dart';

final _fields = ReportFields.fromJson({
  'entry': [
    {'key': 'net_sales', 'label': 'NET SALES', 'type': 'money'},
  ],
  'system': [
    {'key': 'food_usd', 'label': 'FOOD USD', 'type': 'int'},
  ],
  'derived': [
    {'key': 'at', 'label': 'AT', 'type': 'money'},
    {'key': 'food_markout_pct', 'label': 'FOOD MARKOUT %', 'type': 'percent'},
  ],
});

Map<String, Object?> _json({
  num limit = 10000,
  num spent = 2500,
  int daysWithData = 10,
  num mtd = 250000,
  List<Map<String, Object?>> stock = const [],
}) => {
      'store': {'id': 1, 'name': 'DÜZCE MERKEZ'},
      'petty_cash': {
        'weekly_limit': limit,
        'spent_this_week': spent,
        'remaining': limit - spent > 0 ? limit - spent : 0,
        'expense_count': 3,
        'used_pct': limit > 0 ? spent / limit : null,
        'over_limit': limit > 0 && spent > limit,
        'limit_set': limit > 0,
      },
      'revenue': {
        'month': '2026-09',
        'days_in_month': 30,
        'days_elapsed': 25,
        'days_with_data': daysWithData,
        'days_missing': 25 - daysWithData,
        'mtd_net_sales': mtd,
        'daily_avg': daysWithData > 0 ? mtd / daysWithData : null,
        'forecast_month_end': daysWithData > 0 ? mtd / daysWithData * 30 : null,
        'remaining_days': 5,
        'month_totals': {'net_sales': mtd},
        'month_metrics': {'at': 62.5, 'food_markout_pct': 0.0669},
      },
      'stock': {'window_days': 14, 'items': stock},
    };

Widget _block(Map<String, Object?> j) => host(
      SingleChildScrollView(
        child: ManagerOverviewBlock(
          overview: ManagerOverview.fromJson(j),
          fields: _fields,
        ),
      ),
    );

void main() {
  setUpAll(initTestFormatting);

  group('Modeller', () {
    test('petty cash limiti tanımsızsa oran null kalır', () {
      final o = ManagerOverview.fromJson(_json(limit: 0, spent: 0));
      expect(o.pettyCash.limitSet, isFalse);
      expect(o.pettyCash.usedPct, isNull);
    });

    test('rapor girilmemişse ciro hızı ve tahmin null', () {
      final o = ManagerOverview.fromJson(_json(daysWithData: 0, mtd: 0));
      expect(o.revenue.dailyAvg, isNull);
      expect(o.revenue.forecastMonthEnd, isNull);
      expect(o.revenue.daysMissing, 25);
    });

    test('tahmin günlük ortalama × aydaki gün sayısı', () {
      final o = ManagerOverview.fromJson(_json(daysWithData: 10, mtd: 250000));
      expect(o.revenue.dailyAvg, 25000);
      expect(o.revenue.forecastMonthEnd, 750000);
    });

    test('satışı olmayan üründe yeterlilik null', () {
      final o = ManagerOverview.fromJson(_json(stock: [
        {
          'product_type_id': 1, 'name': 'MARLENKA', 'frozen_qty': 16,
          'thawing_qty': 0, 'cabinet_qty': 0, 'available_qty': 16,
          'sold_qty': 0, 'daily_velocity': 0, 'days_of_cover': null, 'risk': null,
        },
      ]));
      expect(o.stock.items.single.daysOfCover, isNull);
      expect(o.stock.items.single.risk, isNull);
    });
  });

  group('Ana sayfa genel raporu', () {
    testWidgets('petty cash harcanan, kalan ve limit gösterir', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_block(_json()));
      await tester.pumpAndSettle();

      expect(find.text('Petty Cash'), findsOneWidget);
      expect(find.text('2.500,00 TL'), findsOneWidget); // harcanan
      expect(find.text('7.500,00 TL'), findsOneWidget); // kalan
      expect(find.text('25% kullanıldı'), findsOneWidget);
    });

    testWidgets('limit aşıldığında fazla tutar yazılır', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_block(_json(limit: 1000, spent: 1400)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Limit aşıldı'), findsOneWidget);
      expect(find.textContaining('400,00 TL fazla'), findsOneWidget);
    });

    testWidgets('ciro hızı ve ay sonu tahmini gösterilir', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_block(_json()));
      await tester.pumpAndSettle();

      expect(find.text('Ay sonu tahmini'), findsOneWidget);
      expect(find.text('750.000,00 TL'), findsOneWidget);
      expect(find.text('25.000,00 TL'), findsOneWidget); // gunluk ortalama
      expect(find.textContaining('15 gün eksik'), findsOneWidget);
      // Rapor paneli olculeri de burada.
      expect(find.textContaining('6.69%'), findsOneWidget);
    });

    testWidgets('Ciro Forecast üstte, Petty Cash altında', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_block(_json()));
      await tester.pumpAndSettle();

      final forecast = tester.getTopLeft(find.text('Ciro Forecast')).dy;
      final petty = tester.getTopLeft(find.text('Petty Cash')).dy;
      expect(forecast, lessThan(petty));
      // Eski uzun ad kullanilmiyor.
      expect(find.text('Ciro Hızı ve Ay Sonu Tahmini'), findsNothing);
      // Stok yeterliligi artik kendi modulunde.
      expect(find.text('Donuk Depo Yeterliliği'), findsNothing);
    });

    testWidgets('iki kart da tıklanabilir', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_block(_json()));
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsNWidgets(2));
      // Tiklanabilirligi belli eden ok her kartta var.
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
    });

    testWidgets('veri girilmemişse tahmin yerine uyarı çıkar', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_block(_json(daysWithData: 0, mtd: 0)));
      await tester.pumpAndSettle();

      expect(find.text('Veri girilmedi'), findsOneWidget);
    });

  });
}
