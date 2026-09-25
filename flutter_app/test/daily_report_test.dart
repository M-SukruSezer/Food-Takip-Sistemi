import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/api_client.dart';
import 'package:foodtakip/core/nav.dart';
import 'package:foodtakip/core/session.dart';
import 'package:foodtakip/models/daily_report.dart';
import 'package:foodtakip/screens/daily_report_dialogs.dart';
import 'package:foodtakip/screens/daily_report_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

final _fields = {
  'entry': [
    {'key': 'net_sales', 'label': 'NET SALES', 'type': 'money'},
    {'key': 'adt', 'label': 'ADT', 'type': 'int'},
    {'key': 'product_qty', 'label': 'PRODUCT QTY', 'type': 'int'},
    {'key': 'food_usd', 'label': 'FOOD USD', 'type': 'int'},
    {'key': 'food_usd_try', 'label': 'FOOD USD ₺', 'type': 'money'},
    {'key': 'food_mo_try', 'label': 'FOOD MO ₺', 'type': 'money'},
    {'key': 'sold_beverage_qty', 'label': 'SOLD BEVERAGE QTY', 'type': 'int'},
    {'key': 'modifiers', 'label': 'MODIFIERS', 'type': 'int'},
    {'key': 'app_amount', 'label': 'APP', 'type': 'money'},
  ],
  'derived': [
    {'key': 'at', 'label': 'AT', 'type': 'money', 'formula': 'NET SALES / ADT'},
    {'key': 'ipt', 'label': 'IPT', 'type': 'number', 'formula': '(PRODUCT QTY − MODIFIERS) / ADT'},
    {'key': 'food_markout_pct', 'label': 'FOOD MARKOUT %', 'type': 'percent'},
    {'key': 'food_uph', 'label': 'FOOD UPH', 'type': 'number'},
    {'key': 'modifiers_pct', 'label': 'MODIFIERS %', 'type': 'percent'},
    {'key': 'app_pct', 'label': 'APP%', 'type': 'percent'},
  ],
};

final _page = {
  'from': '2026-09-22', 'to': '2026-09-23', 'period': 'week',
  'items': [
    {
      'id': 1, 'store_id': 1, 'report_date': '2026-09-22',
      'net_sales': 10000, 'adt': 200, 'product_qty': 500, 'food_usd': 80,
      'food_usd_try': 4000, 'food_mo_try': 200, 'sold_beverage_qty': 300,
      'modifiers': 60, 'app_amount': 1500,
      'created_by_name': 'Şükrü Sezer', 'store_name': 'Merkez',
      'metrics': {
        'at': 50, 'ipt': 2.2, 'food_markout_pct': 0.05,
        'food_uph': 40, 'modifiers_pct': 0.2, 'app_pct': 0.15,
      },
    },
  ],
  'summary': {
    'days': 2,
    'totals': {
      'net_sales': 20000, 'adt': 300, 'product_qty': 750, 'food_usd': 120,
      'food_usd_try': 6000, 'food_mo_try': 300, 'sold_beverage_qty': 450,
      'modifiers': 90, 'app_amount': 2000,
    },
    'metrics': {
      'at': 66.6667, 'ipt': 2.2, 'food_markout_pct': 0.05,
      'food_uph': 40, 'modifiers_pct': 0.2, 'app_pct': 0.1,
    },
  },
};

void main() {
  late HttpClientAdapter original;

  setUp(() {
    initTestFormatting();
    SharedPreferences.setMockInitialValues({});
    original = api.dio.httpClientAdapter;
  });

  tearDown(() async {
    api.dio.httpClientAdapter = original;
    await session.signOut();
  });

  group('Değer biçimleme', () {
    test('tür başına doğru biçim', () {
      expect(formatReportValue(50, 'money'), '50,00 TL');
      expect(formatReportValue(0.05, 'percent'), '5.00%');
      expect(formatReportValue(200, 'int'), '200');
      expect(formatReportValue(2.2, 'number'), '2.20');
    });

    test('paydası sıfır olan oran "-" gösterir', () {
      // Sunucu bolme yapilamadiginda null doner; ekran bunu bos gostermeli.
      expect(formatReportValue(null, 'money'), '-');
      expect(formatReportValue(null, 'percent'), '-');
    });
  });

  group('Rapor paneli', () {
    testWidgets('günlük kayıt ve türetilen ölçüler listelenir', (tester) async {
      // Ozet karti uzun; gunluk kart listenin altinda kaliyor ve tembel liste
      // onu cizmiyor. Uzun bir gorunum alani kullanilir.
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      installFakeApi({'GET /daily-reports': _page, 'GET /daily-reports/fields': _fields});
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(host(const DailyReportScreen()));
      await tester.pumpAndSettle();

      expect(find.text('10.000,00 TL'), findsOneWidget);
      expect(find.text('AT: 50,00 TL'), findsOneWidget);
      expect(find.text('IPT: 2.20'), findsOneWidget);
      expect(find.text('FOOD MARKOUT %: 5.00%'), findsOneWidget);
      expect(find.text('APP%: 15.00%'), findsOneWidget);
    });

    testWidgets('dönem özeti toplamlardan hesaplanan oranları gösterir', (tester) async {
      installFakeApi({'GET /daily-reports': _page, 'GET /daily-reports/fields': _fields});
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(host(const DailyReportScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Dönem Özeti'), findsOneWidget);
      // AT 66.67 = 20000/300; gunluk ortalamasi (50 ve digeri) degil.
      expect(find.text('66,67 TL'), findsOneWidget);
      expect(find.text('20.000,00 TL'), findsOneWidget);
      expect(find.textContaining('günlerin ortalaması değil'), findsOneWidget);
    });

    testWidgets('giriş yalnızca iki rolde açık', (tester) async {
      for (final rol in ['store_manager', 'shift_supervisor']) {
        installFakeApi({'GET /daily-reports': _page, 'GET /daily-reports/fields': _fields});
        signInAs(rol, storeId: 1);
        await tester.pumpWidget(host(const DailyReportScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Gün Ekle'), findsOneWidget, reason: '$rol giriş yapabilmeli');
      }
      for (final rol in ['super_admin', 'regional_manager']) {
        installFakeApi({'GET /daily-reports': _page, 'GET /daily-reports/fields': _fields});
        signInAs(rol, storeId: 1);
        await tester.pumpWidget(host(const DailyReportScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Gün Ekle'), findsNothing, reason: '$rol giriş yapamamalı');
      }
    });

    testWidgets('haftalık/aylık seçimi sunucuya gider', (tester) async {
      final adapter =
          installFakeApi({'GET /daily-reports': _page, 'GET /daily-reports/fields': _fields});
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(host(const DailyReportScreen()));
      await tester.pumpAndSettle();
      expect(adapter.calls.any((c) => c.contains('period=week')), isTrue);

      adapter.calls.clear();
      await tester.tap(find.text('Aylık'));
      await tester.pumpAndSettle();
      expect(adapter.calls.any((c) => c.contains('period=month')), isTrue);
    });

    testWidgets('giriş formunda yalnızca ham alanlar sorulur', (tester) async {
      installFakeApi({
        'GET /daily-reports': _page,
        'GET /daily-reports/fields': _fields,
        'GET /daily-reports/day/2026-09-25': null,
      });
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(host(const DailyReportScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gün Ekle'));
      await tester.pumpAndSettle();

      // 9 ham alan sorulur; oranlar formda yok. Etiketler ozet kartinda da
      // gectigi icin arama pencereyle sinirlanir.
      final dialog = find.byType(AlertDialog);
      expect(find.descendant(of: dialog, matching: find.text('NET SALES')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('SOLD BEVERAGE QTY')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('AT')), findsNothing);
      expect(find.descendant(of: dialog, matching: find.text('FOOD UPH')), findsNothing);
      expect(find.textContaining('otomatik hesaplanır'), findsOneWidget);
    });
  });

  test('menüde Rapor Paneli barista dışındaki rollerde görünür', () {
    final item = navItems.firstWhere((i) => i.path == '/daily-report');
    expect(item.roles, contains('shift_supervisor'));
    expect(item.roles, isNot(contains('barista')));
  });

  test('model paydası sıfır olan ölçüyü null tutar', () {
    final r = DailyReport.fromJson({
      'id': 1, 'store_id': 1, 'report_date': '2026-09-22',
      'metrics': {'at': null, 'ipt': 2.2},
    });
    expect(r.metrics.at, isNull);
    expect(r.metrics.ipt, 2.2);
  });
}
