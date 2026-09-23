import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/api_client.dart';
import 'package:foodtakip/core/session.dart';
import 'package:foodtakip/screens/approvals_screen.dart';
import 'package:foodtakip/screens/logs_screen.dart';
import 'package:foodtakip/screens/sales_screen.dart';
import 'package:foodtakip/widgets/panels.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

final _movements = {
  'items': [
    {'id': 1, 'kind': 'sale', 'quantity': 2, 'unit_price': 150, 'total': 300,
     'at': '2026-09-20T10:00:00.000Z', 'product_name': 'Çikolatalı Pasta',
     'product_type_id': 7, 'user_name': 'Ayşe Çiftçi', 'store_name': 'Merkez'},
    {'id': 2, 'kind': 'sale', 'quantity': 3, 'unit_price': null, 'total': null,
     'at': '2026-09-20T11:00:00.000Z', 'product_name': 'Poğaça',
     'product_type_id': 8, 'user_name': 'Ali Gündüz', 'store_name': 'Merkez'},
    {'id': 3, 'kind': 'ikram', 'quantity': 1, 'unit_price': 200, 'total': 200,
     'at': '2026-09-20T12:00:00.000Z', 'product_name': 'Tiramisu',
     'product_type_id': 9, 'user_name': 'Ayşe Çiftçi', 'store_name': 'Merkez'},
    {'id': 4, 'kind': 'discard', 'quantity': 2, 'unit_price': 260, 'total': 520,
     'at': '2026-09-20T13:00:00.000Z', 'product_name': 'Opera',
     'product_type_id': 10, 'user_name': 'Ali Gündüz', 'store_name': 'Merkez',
     'reason': 'SKT süresi doldu', 'price_is_current': true},
  ],
  'totals': {
    'sale_qty': 5, 'revenue': 300, 'ikram_qty': 1, 'ikram_value': 200,
    'discard_qty': 2, 'discard_value': 520, 'count': 4,
  },
};

final _logs = [
  {'id': 1, 'action': 'SATIS', 'details': 'Çikolatalı Pasta 2 adet satıldı',
   'username': 'ayse', 'store_name': 'Merkez', 'created_at': '2026-09-20T10:00:00.000Z'},
  {'id': 2, 'action': 'IMHA', 'details': 'Poğaça imha edildi',
   'username': 'ali', 'store_name': 'Merkez', 'created_at': '2026-09-20T09:00:00.000Z'},
  {'id': 3, 'action': 'SATIS', 'details': 'Poğaça 1 adet satıldı',
   'username': 'ali', 'store_name': 'Merkez', 'created_at': '2026-09-20T08:00:00.000Z'},
];

final _approvals = [
  {'id': 11, 'batch_id': 101, 'status': 'pending', 'reason': 'Vitrin boşaldı',
   'requested_at': '2026-09-20T08:00:00.000Z', 'remaining': 6, 'quantity': 6,
   'product_name': 'Çikolatalı Pasta', 'requested_by_name': 'Ali Gündüz',
   'store_name': 'Merkez', 'thaw_remaining_hours': 3},
  {'id': 12, 'batch_id': 102, 'status': 'rejected', 'reason': 'Acil ihtiyaç',
   'requested_at': '2026-09-19T08:00:00.000Z', 'remaining': 4, 'quantity': 4,
   'product_name': 'Poğaça', 'requested_by_name': 'Ali Gündüz',
   'decided_by_name': 'Ayşe Çiftçi', 'decision_note': 'Çözülme tamamlanmadan alınamaz',
   'store_name': 'Merkez', 'thaw_remaining_hours': 0},
];

void main() {
  late FakeAdapter adapter;
  late HttpClientAdapter original;

  setUp(() {
    initTestFormatting();
    SharedPreferences.setMockInitialValues({});
    original = api.dio.httpClientAdapter;
    adapter = installFakeApi({
      'GET /reports/movements': _movements,
      'GET /product-types': const <Object>[],
      'GET /logs': _logs,
      'GET /approvals': _approvals,
      'GET /stores': const <Object>[],
      'POST /approvals/11/reject': {'ok': true},
    });
  });

  tearDown(() async {
    api.dio.httpClientAdapter = original;
    await session.signOut();
  });

  group('Hareket Kayıtları', () {
    testWidgets('kayıtlar listelenir ve işlem türüne göre süzülür', (tester) async {
      signInAs('super_admin');
      await tester.pumpWidget(host(const LogsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Çikolatalı Pasta 2 adet satıldı'), findsOneWidget);
      expect(find.text('Poğaça imha edildi'), findsOneWidget);
      expect(find.text('Tüm İşlemler (3)'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('IMHA').last);
      await tester.pumpAndSettle();

      expect(find.text('Poğaça imha edildi'), findsOneWidget);
      expect(find.text('Çikolatalı Pasta 2 adet satıldı'), findsNothing);
      // Suzme istemcide yapilir, sunucuya yeni istek gitmez.
      expect(adapter.calls.where((c) => c.startsWith('GET /logs')).length, 1);
    });
  });

  group('Erken Aktarım Onayları', () {
    testWidgets('varsayılan olarak bekleyenler istenir', (tester) async {
      signInAs('store_manager', storeId: 4);
      await tester.pumpWidget(host(const ApprovalsScreen()));
      await tester.pumpAndSettle();

      expect(adapter.calls, contains('GET /approvals?status=pending'));
      expect(find.text('1 bekleyen istek var.'), findsOneWidget);
    });

    testWidgets('karara bağlanmış istekte işlem düğmesi yok, karar notu var', (tester) async {
      signInAs('store_manager', storeId: 4);
      await tester.pumpWidget(host(const ApprovalsScreen()));
      await tester.pumpAndSettle();

      // Bekleyen kayitta iki dugme; reddedilen kayitta hic yok.
      expect(find.text('Onayla'), findsOneWidget);
      expect(find.text('Reddet'), findsOneWidget);
      expect(
        find.text('Ayşe Çiftçi karar verdi — Çözülme tamamlanmadan alınamaz'),
        findsOneWidget,
      );
      expect(find.text('çözülmeye 3 saat'), findsOneWidget);
    });

    testWidgets('onay öncesi SKT uyarısı gösterilir ve vazgeçilebilir', (tester) async {
      signInAs('store_manager', storeId: 4);
      await tester.pumpWidget(host(const ApprovalsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Onayla'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('SKT süresi şu andan itibaren başlar, çözülmeye 3 saat kalmıştı'),
        findsOneWidget,
      );

      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(adapter.calls.where((c) => c.contains('approve')), isEmpty);
    });

    testWidgets('red notu istekle birlikte gönderilir', (tester) async {
      signInAs('store_manager', storeId: 4);
      await tester.pumpWidget(host(const ApprovalsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reddet'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Henüz çözülmedi');
      await tester.tap(find.widgetWithText(FilledButton, 'Reddet'));
      await tester.pumpAndSettle();

      expect(adapter.calls, contains('POST /approvals/11/reject'));
      expect(adapter.bodies['POST /approvals/11/reject'], {'note': 'Henüz çözülmedi'});
    });

    testWidgets('boş red notu gönderilmez', (tester) async {
      signInAs('store_manager', storeId: 4);
      await tester.pumpWidget(host(const ApprovalsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reddet'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reddet'));
      await tester.pumpAndSettle();

      // Sunucu note alanini opsiyonel kabul ediyor; bos metin yerine hic
      // gonderilmez ki hareket kaydinda " : " gibi kalintilar olusmasin.
      expect(adapter.bodies['POST /approvals/11/reject'], <String, Object?>{});
    });
  });

  test('log ikonları bilinen işlemler için özelleşir', () {
    expect(logIcon('SATIS'), isNot(logIcon('BILINMEYEN_ISLEM')));
    expect(logIcon('FOOD_DOLABI_OTOMATIK'), logIcon('FOOD_DOLABI'));
  });

  group('Hareket Raporu', () {
    testWidgets('satış, ikram ve imha toplamları ayrı gösterilir', (tester) async {
      signInAs('store_manager', storeId: 4);
      await tester.pumpWidget(host(const SalesScreen()));
      await tester.pumpAndSettle();

      // Satis 5 adet / 300 TL; ikram 1 adet / 200 TL; imha 2 adet / 520 TL.
      expect(find.widgetWithText(StatCard, '5'), findsOneWidget);
      expect(find.widgetWithText(StatCard, '300,00 TL'), findsOneWidget);
      expect(find.text('değeri 200,00 TL'), findsOneWidget);
      expect(find.text('değeri 520,00 TL'), findsOneWidget);
      expect(find.text('4 hareket'), findsOneWidget);
      expect(find.text('yalnızca satışlar'), findsOneWidget);
    });

    testWidgets('her satır türüyle etiketlenir, imha nedeni görünür', (tester) async {
      signInAs('store_manager', storeId: 4);
      await tester.pumpWidget(host(const SalesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('İkram'), findsWidgets);
      expect(find.text('SKT süresi doldu'), findsOneWidget);
      // Imhada fiyat anlik goruntu degil, cesidin guncel fiyati.
      expect(find.text('güncel birim 260,00 TL'), findsOneWidget);
      expect(find.text('birim 150,00 TL'), findsOneWidget);
      expect(find.text('Fiyat yok'), findsOneWidget);
    });

    testWidgets('varsayılan aralık son 30 gün ve tür parametresi gitmez', (tester) async {
      signInAs('store_manager', storeId: 4);
      await tester.pumpWidget(host(const SalesScreen()));
      await tester.pumpAndSettle();

      final call = adapter.calls.firstWhere((c) => c.startsWith('GET /reports/movements'));
      expect(call, contains('from='));
      expect(call, contains('to='));
      // Tum turler seciliyken kind parametresi gonderilmez.
      expect(call, isNot(contains('kind=')));
    });

    testWidgets('tür filtresi kapatıldığında kalanlar sunucuya gider', (tester) async {
      signInAs('store_manager', storeId: 4);
      await tester.pumpWidget(host(const SalesScreen()));
      await tester.pumpAndSettle();

      adapter.calls.clear();
      await tester.tap(find.widgetWithText(FilterChip, 'İmha'));
      await tester.pumpAndSettle();

      final call = adapter.calls.firstWhere((c) => c.startsWith('GET /reports/movements'));
      expect(call, contains('kind=sale%2Cikram'));
    });

    testWidgets('son tür de kapatılamaz', (tester) async {
      signInAs('store_manager', storeId: 4);
      await tester.pumpWidget(host(const SalesScreen()));
      await tester.pumpAndSettle();

      for (final label in ['İmha', 'İkram', 'Satış']) {
        await tester.tap(find.widgetWithText(FilterChip, label));
        await tester.pumpAndSettle();
      }
      // Ucu de kapatilamaz; en az biri secili kalir.
      final selected = tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .where((c) => c.selected)
          .length;
      expect(selected, 1);
    });

    testWidgets('Tümü seçildiğinde tarih parametresi gitmez', (tester) async {
      signInAs('store_manager', storeId: 4);
      await tester.pumpWidget(host(const SalesScreen()));
      await tester.pumpAndSettle();

      adapter.calls.clear();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tümü'));
      await tester.pumpAndSettle();

      final call = adapter.calls.firstWhere((c) => c.startsWith('GET /reports/movements'));
      expect(call, isNot(contains('from=')));
      expect(call, isNot(contains('to=')));
    });

    testWidgets('mağaza yöneticisi mağaza seçiciyi görmez', (tester) async {
      signInAs('store_manager', storeId: 4);
      await tester.pumpWidget(host(const SalesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Tüm Mağazalar'), findsNothing);
      expect(adapter.calls.where((c) => c.startsWith('GET /stores')), isEmpty);
    });

    testWidgets('telefonda dört özet kutusu 2x2 ve eşit', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      signInAs('store_manager', storeId: 4);
      await tester.pumpWidget(host(const SalesScreen()));
      await tester.pumpAndSettle();

      final cards = find.byType(StatCard);
      expect(cards, findsNWidgets(4));
      final rects =
          tester.widgetList<StatCard>(cards).map((c) => tester.getRect(find.byWidget(c))).toList();
      expect(rects[0].top, rects[1].top);
      expect(rects[2].top, greaterThan(rects[0].bottom - 1));
      expect(rects[0].width, closeTo(rects[1].width, 0.5));
      expect(rects[0].height, closeTo(rects[1].height, 0.5));
    });
  });

}
