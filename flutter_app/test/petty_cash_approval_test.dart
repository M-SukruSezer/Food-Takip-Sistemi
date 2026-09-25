import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/nav.dart';
import 'package:foodtakip/models/petty_cash.dart';
import 'package:foodtakip/screens/petty_cash_screen.dart';
import 'package:foodtakip/widgets/crud_scaffold.dart';

import 'support/fake_api.dart';

Map<String, Object?> _expense({
  int id = 1,
  num amount = 300,
  String description = 'Temizlik malzemesi',
  String status = 'pending',
  String createdBy = 'MEHMET ALİ CANBULAT',
  bool hasReceipt = true,
  String? note,
}) => {
      'id': id, 'store_id': 1, 'amount': amount, 'description': description,
      'spent_at': '2026-09-25T09:00:00.000Z', 'created_at': '2026-09-25T09:00:00.000Z',
      'status': status, 'has_receipt': hasReceipt,
      'created_by_name': createdBy, 'decision_note': note,
    };

Map<String, Object?> _page({
  List<Map<String, Object?>>? items,
  bool canApprove = false,
  num pending = 300,
  int pendingCount = 1,
}) => {
      'items': items ?? [_expense()],
      'status': {
        'store_id': 1, 'weekly_limit': 5000, 'spent_this_week': 500,
        'approved_this_week': 200, 'pending_this_week': pending,
        'pending_count': pendingCount, 'remaining': 4500,
        'week_start': '2026-09-21T00:00:00.000Z', 'can_approve': canApprove,
      },
    };

void main() {
  setUpAll(initTestFormatting);

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('Model', () {
    test('durum etiketleri', () {
      expect(PettyCashExpense.fromJson(_expense(status: 'pending')).statusLabel, 'Onay bekliyor');
      expect(PettyCashExpense.fromJson(_expense(status: 'approved')).statusLabel, 'Onaylandı');
      expect(PettyCashExpense.fromJson(_expense(status: 'rejected')).statusLabel, 'Reddedildi');
    });

    test('durum alanı yoksa onaylı sayılır', () {
      // Kural gelmeden once girilen kayitlar; sunucu da 'approved' varsayiyor.
      final j = _expense()..remove('status');
      expect(PettyCashExpense.fromJson(j).status, 'approved');
      expect(PettyCashExpense.fromJson(j).isPending, isFalse);
    });

    test('bekleyen tutar durumda taşınır', () {
      final st = PettyCashStatus.fromJson(
          (_page(pending: 750, pendingCount: 2)['status'] as Map<String, dynamic>));
      expect(st.pendingThisWeek, 750);
      expect(st.pendingCount, 2);
      expect(st.canApprove, isFalse);
    });
  });

  group('Onay arayüzü', () {
    testWidgets('bekleyen masraf durumuyla işaretlenir', (tester) async {
      tall(tester);
      installFakeApi({'GET /petty-cash': _page()});
      signInAs('shift_supervisor', storeId: 1);

      await tester.pumpWidget(host(const PettyCashScreen()));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Pill, 'Onay bekliyor'), findsOneWidget);
      expect(find.textContaining('300,00 TL onay bekliyor'), findsOneWidget);
      expect(find.textContaining('(1 kayıt)'), findsOneWidget);
    });

    testWidgets('vardiya müdürü onay düğmesi görmez', (tester) async {
      tall(tester);
      installFakeApi({'GET /petty-cash': _page(canApprove: false)});
      signInAs('shift_supervisor', storeId: 1);

      await tester.pumpWidget(host(const PettyCashScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Onayla'), findsNothing);
      expect(find.text('Reddet'), findsNothing);
    });

    testWidgets('mağaza müdürü onaylar', (tester) async {
      tall(tester);
      final fake = installFakeApi({
        'GET /petty-cash': _page(canApprove: true),
        'POST /petty-cash/1/approve': {'ok': true, 'status': 'approved'},
      });
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(host(const PettyCashScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Onayla'));
      await tester.pumpAndSettle();

      // Onay ekraninda fis durumu da yaziyor.
      expect(find.text('Masrafı Onayla'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Onayla').last);
      await tester.pumpAndSettle();

      expect(fake.called('POST /petty-cash/1/approve'), isTrue);
    });

    testWidgets('fişsiz masrafta onay ekranı uyarır', (tester) async {
      tall(tester);
      installFakeApi({
        'GET /petty-cash': _page(items: [_expense(hasReceipt: false)], canApprove: true),
      });
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(host(const PettyCashScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Onayla'));
      await tester.pumpAndSettle();

      expect(find.textContaining('fiş görseli yok'), findsOneWidget);
    });

    testWidgets('ret gerekçesi zorunlu, boşsa istek gitmez', (tester) async {
      tall(tester);
      final fake = installFakeApi({
        'GET /petty-cash': _page(canApprove: true),
        'POST /petty-cash/1/reject': {'ok': true},
      });
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(host(const PettyCashScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reddet'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Reddet'));
      await tester.pumpAndSettle();
      expect(find.text('Ret gerekçesi zorunludur'), findsOneWidget);
      expect(fake.called('POST /petty-cash/1/reject'), isFalse);

      await tester.enterText(find.byType(TextField).last, 'Belgesi yok');
      await tester.tap(find.widgetWithText(FilledButton, 'Reddet'));
      await tester.pumpAndSettle();
      expect(fake.lastBody('POST /petty-cash/1/reject'), {'note': 'Belgesi yok'});
    });

    testWidgets('reddedilen masrafta gerekçe gösterilir', (tester) async {
      tall(tester);
      installFakeApi({
        'GET /petty-cash': _page(
          items: [_expense(status: 'rejected', note: 'Belgesi yok')],
          pending: 0, pendingCount: 0,
        ),
      });
      signInAs('shift_supervisor', storeId: 1);

      await tester.pumpWidget(host(const PettyCashScreen()));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Pill, 'Reddedildi'), findsOneWidget);
      expect(find.text('Ret gerekçesi: Belgesi yok'), findsOneWidget);
      // Bekleyen yoksa satir da cikmaz.
      expect(find.textContaining('onay bekliyor'), findsNothing);
    });
  });

  group('Menü ağacı', () {
    test('gruplar mantıksal sırada', () {
      expect(navGroups.map((g) => g.title).toList(),
          ['Operasyon', 'Kasa ve Raporlar', 'Yönetim', null]);
    });

    test('düz liste gruplardan üretiliyor', () {
      final fromGroups = navGroups.expand((g) => g.items).map((i) => i.path).toList();
      expect(navItems.map((i) => i.path).toList(), fromGroups);
      // Her yol tek kez geciyor.
      expect(navItems.map((i) => i.path).toSet().length, navItems.length);
    });

    test('rolüne açık öğesi olmayan grup çizilmez', () {
      final barista = navGroupsFor(testUser('barista', storeId: 1));
      // Barista Yonetim grubundaki hicbir ogeye erismiyor.
      expect(barista.map((g) => g.title), isNot(contains('Yönetim')));
      // Kasa ve Raporlar'da yalnizca hareket raporu/kayitlari kaliyor.
      final kasa = barista.firstWhere((g) => g.title == 'Kasa ve Raporlar');
      expect(kasa.items.map((i) => i.path), ['/sales', '/logs']);

      final admin = navGroupsFor(testUser('super_admin'));
      expect(admin.map((g) => g.title), ['Operasyon', 'Kasa ve Raporlar', 'Yönetim', null]);
    });

    test('Onaylar Operasyon grubunda', () {
      final op = navGroups.firstWhere((g) => g.title == 'Operasyon');
      expect(op.items.map((i) => i.path), contains('/approvals'));
    });
  });
}
