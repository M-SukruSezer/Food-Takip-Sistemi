import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/models/daily_report.dart';
import 'package:foodtakip/screens/daily_report_dialogs.dart';
import 'package:foodtakip/screens/petty_cash_dialogs.dart';
import 'package:foodtakip/widgets/dialogs.dart';

import 'support/fake_api.dart';

/// Cep ekraninda formlarin sigdigini dogrular.
///
/// Olculen sorun: 375x667 telefonda gunluk rapor formu 1011px icerik uretip
/// 640px kaydirma gerektiriyordu ve dialog ekranin tamamini kapliyordu.
void main() {
  setUpAll(initTestFormatting);

  const phone = Size(375, 667);

  void onPhone(WidgetTester tester) {
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Dialogun kaydirma miktari ve gercek kutusu.
  ({double content, double viewport, double scroll, Size box, Offset at}) measure(
      WidgetTester tester) {
    final scroll = find
        .descendant(of: find.byType(AlertDialog), matching: find.byType(Scrollable))
        .first;
    final pos = tester.state<ScrollableState>(scroll).position;
    final mat = find
        .descendant(of: find.byType(AlertDialog), matching: find.byType(Material))
        .first;
    return (
      content: pos.maxScrollExtent + pos.viewportDimension,
      viewport: pos.viewportDimension,
      scroll: pos.maxScrollExtent,
      box: tester.getSize(mat),
      at: tester.getTopLeft(mat),
    );
  }

  final reportFields = ReportFields.fromJson({
    'entry': [
      {'key': 'net_sales', 'label': 'NET SALES', 'type': 'money'},
      {'key': 'adt', 'label': 'ADT', 'type': 'int'},
      {'key': 'product_qty', 'label': 'PRODUCT QTY', 'type': 'int'},
      {'key': 'sold_beverage_qty', 'label': 'SOLD BEVERAGE QTY', 'type': 'int'},
      {'key': 'modifiers', 'label': 'MODIFIERS', 'type': 'int'},
      {'key': 'app_amount', 'label': 'APP', 'type': 'money'},
    ],
    'system': [
      {'key': 'food_usd', 'label': 'FOOD USD', 'type': 'int'},
      {'key': 'food_usd_try', 'label': 'FOOD USD ₺', 'type': 'money'},
      {'key': 'food_mo_try', 'label': 'FOOD MO ₺', 'type': 'money'},
    ],
    'derived': [],
  });

  Future<void> open(WidgetTester tester, Future<void> Function(BuildContext) show) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => ElevatedButton(onPressed: () => show(ctx), child: const Text('aç')),
      ),
    ));
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
  }

  group('Cep ekranında form yoğunluğu', () {
    testWidgets('dialog ekrana yapışmaz, kenarda boşluk kalır', (tester) async {
      onPhone(tester);
      installFakeApi({
        'GET /daily-reports/day/2026-09-25': {'report': null, 'suggested': {}},
      });
      signInAs('store_manager', storeId: 1);

      await open(tester, (ctx) => showDailyReportDialog(ctx, fields: reportFields));
      final m = measure(tester);

      // Dialog ekrandan dar ve kenarlarda bosluk var.
      expect(m.box.width, lessThan(phone.width));
      expect(m.at.dx, greaterThanOrEqualTo(12));
      expect(m.box.height, lessThan(phone.height));
    });

    testWidgets('günlük rapor formu ölçülebilir ölçüde kısaldı', (tester) async {
      onPhone(tester);
      installFakeApi({
        'GET /daily-reports/day/2026-09-25': {
          'report': null,
          'suggested': {'food_usd': 31, 'food_usd_try': 5980, 'food_mo_try': 400},
        },
      });
      signInAs('store_manager', storeId: 1);

      await open(tester, (ctx) => showDailyReportDialog(ctx, fields: reportFields));
      final m = measure(tester);

      // Onceki tasarim: 1011px icerik, 640px kaydirma.
      expect(m.content, lessThan(700));
      expect(m.scroll, lessThan(200));
    });

    testWidgets('altı sayısal alan üç satırda durur', (tester) async {
      onPhone(tester);
      installFakeApi({
        'GET /daily-reports/day/2026-09-25': {'report': null, 'suggested': {}},
      });
      signInAs('store_manager', storeId: 1);

      await open(tester, (ctx) => showDailyReportDialog(ctx, fields: reportFields));

      final rows = find.descendant(of: find.byType(AlertDialog), matching: find.byType(FormRow));
      expect(rows, findsNWidgets(3));

      // Yan yana duran alanlar ayni hizada.
      final net = tester.getTopLeft(find.text('NET SALES')).dy;
      final adt = tester.getTopLeft(find.text('ADT')).dy;
      expect(net, adt);
    });

    testWidgets('petty cash formunda tutar ve tarih yan yana', (tester) async {
      onPhone(tester);
      installFakeApi({'GET /petty-cash': {'items': [], 'status': null}});
      signInAs('store_manager', storeId: 1);

      await open(tester, (ctx) => showExpenseDialog(ctx));
      await tester.pumpAndSettle();

      expect(find.byType(FormRow), findsWidgets);
      final tutar = tester.getTopLeft(find.text('Tutar (₺)')).dy;
      final tarih = tester.getTopLeft(find.text('Tarih')).dy;
      expect(tutar, tarih);
      // Tarih alani tek kere var (eskiden iki yerde kalmisti).
      expect(find.text('Tarih'), findsOneWidget);
    });
  });

  test('pairFields tek sayıda alanı boş eşle tamamlar', () {
    final rows = pairFields([
      const Text('a'), const Text('b'), const Text('c'),
    ]);
    expect(rows.length, 2);
    expect((rows[1] as FormRow).right, isNull);
  });
}
