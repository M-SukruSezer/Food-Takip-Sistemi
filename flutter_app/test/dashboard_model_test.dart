import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/models/dashboard.dart';

void main() {
  test('DashboardCounts string gelen sayilari da cozer', () {
    // Postgres SUM/COUNT bazen string doner; esleme bunu tolere etmeli.
    final d = DashboardData.fromJson({
      'counts': {
        'frozen': '8', 'frozen_qty': 24,
        'thawing': 2, 'thawing_qty': '6',
        'food_cabinet': 12, 'food_cabinet_qty': 14,
        'expiring_qty': 3, 'expired_qty': '1', 'expiring_count': 2,
      },
      'soldToday': {'count': '5', 'qty': 8, 'revenue': '1250.5'},
    });
    expect(d.counts.frozen, 8);
    expect(d.counts.thawingQty, 6);
    expect(d.counts.expiredQty, 1);
    expect(d.counts.totalStock, 24 + 6 + 14);
    expect(d.soldToday.count, 5);
    expect(d.soldToday.revenue, 1250.5);
  });

  test('ReportSummary coklu magaza bicimini ayirt eder', () {
    final multi = ReportSummary.fromJson({
      'type': 'multi',
      'stores': [
        {'id': 1, 'name': 'Merkez', 'frozen_qty': 10, 'thawing_qty': 2, 'cabinet_qty': 5,
         'discarded_qty': 1, 'sold_qty': 20, 'sold_count': 9, 'revenue': 1500, 'product_count': 30},
        {'id': 2, 'name': 'Şube', 'frozen_qty': 4, 'thawing_qty': 0, 'cabinet_qty': 3,
         'discarded_qty': 0, 'sold_qty': 6, 'sold_count': 4, 'revenue': 500, 'product_count': 12},
      ],
    });
    expect(multi.isMulti, isTrue);
    expect(multi.stores.length, 2);
    expect(multi.totalRevenue, 2000);

    final single = ReportSummary.fromJson({
      'type': 'single',
      'store': {'id': 1, 'name': 'Merkez Mağaza'},
      'sold_qty': 44, 'sold_count': 24, 'revenue': '1250', 'discarded_qty': 25,
    });
    expect(single.isMulti, isFalse);
    expect(single.storeName, 'Merkez Mağaza');
    expect(single.totalRevenue, 1250);
    expect(single.discardedQty, 25);
  });

  test('PeriodPerformance en cok/en az/zayi listelerini dogru turetir', () {
    // Sunucu azalan sirada doner.
    final p = PeriodPerformance.fromJson({
      'sold': [
        {'id': 1, 'name': 'OREO CUP', 'qty': 8, 'revenue': 400},
        {'id': 2, 'name': 'LOTUS CUP', 'qty': 7, 'revenue': 350},
        {'id': 3, 'name': 'COOKIE PIE', 'qty': 5, 'revenue': 250},
        {'id': 4, 'name': 'SUFLE', 'qty': 2, 'revenue': 100},
        {'id': 5, 'name': 'MOZAIK', 'qty': 1, 'revenue': 50},
        {'id': 6, 'name': 'TOSCANA', 'qty': 1, 'revenue': 50},
      ],
      'wasted': [
        {'id': 9, 'name': 'BROWNIE CHEESECAKE', 'qty': 20},
        {'id': 3, 'name': 'COOKIE PIE', 'qty': 2},
      ],
    });
    expect(p.kinds, 6);
    expect(p.soldTotal, 24);
    expect(p.wastedTotal, 22);
    expect(p.best.first.name, 'OREO CUP');
    expect(p.best.length, 5);
    // En az satan: ters sirada ilk bes.
    expect(p.worst.first.name, 'TOSCANA');
    expect(p.worst.first.qty, 1);
    expect(p.topWasted.first.qty, 20);
  });

  test('bes veya daha az cesitte en cok ve en az listeleri ortusur', () {
    final p = PeriodPerformance.fromJson({
      'sold': [
        {'id': 1, 'name': 'A', 'qty': 3},
        {'id': 2, 'name': 'B', 'qty': 1},
      ],
      'wasted': <Map<String, dynamic>>[],
    });
    expect(p.kinds, 2);
    expect(p.best.length, 2);
    expect(p.worst.length, 2);
    // Arayuz bu durumda kullaniciyi uyarir; burada sadece ortusmeyi dogruluyoruz.
    expect(p.best.map((e) => e.name).toSet(), p.worst.map((e) => e.name).toSet());
  });

  test('SalesPoint ve StatusSlice esleme', () {
    final s = SalesPoint.fromJson({'date': '2026-09-20', 'qty': '8', 'revenue': 680});
    expect(s.qty, 8);
    expect(s.revenue, 680);
    final st = StatusSlice.fromJson({'status': 'food_cabinet', 'quantity': '14'});
    expect(st.status, 'food_cabinet');
    expect(st.quantity, 14);
  });
}
