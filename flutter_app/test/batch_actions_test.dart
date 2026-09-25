import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/batch_actions.dart';
import 'package:foodtakip/models/batch.dart';

Batch _b({
  required String status,
  String name = 'TİRAMİSU',
  int remaining = 3,
  bool thawReady = false,
  int? pendingApprovalId,
  String? urgency,
  String? store,
}) =>
    Batch.fromJson({
      'id': 1,
      'product_name': name,
      'quantity': remaining,
      'remaining': remaining,
      'status': status,
      'thaw_ready': thawReady,
      'pending_approval_id': pendingApprovalId,
      'urgency': urgency,
      'store_name': store,
      'thaw_remaining_hours': thawReady ? 0 : 5,
    });

void main() {
  test('donuk depo: ana islem cozulmeye al, menude stok ekle ve zayi', () {
    final a = batchActionsFor(_b(status: 'frozen'), canAdjust: false);
    expect(a.primary, BatchAction.thaw);
    expect(a.menu, [BatchAction.detail, BatchAction.addStock, BatchAction.discard]);
  });

  test('cozulme tamamlandi: ana islem food dolabina al', () {
    final a = batchActionsFor(_b(status: 'thawing', thawReady: true), canAdjust: false);
    expect(a.primary, BatchAction.completeThaw);
    expect(a.menu.contains(BatchAction.earlyRequest), isFalse);
  });

  test('cozulme suruyor: menude erken aktarim istegi var', () {
    final a = batchActionsFor(_b(status: 'thawing'), canAdjust: false);
    expect(a.primary, isNull);
    expect(a.menu.contains(BatchAction.earlyRequest), isTrue);
  });

  test('bekleyen onay varsa erken aktarim tekrar istenemez', () {
    final a = batchActionsFor(_b(status: 'thawing', pendingApprovalId: 7), canAdjust: false);
    expect(a.primary, BatchAction.awaitingApproval);
    expect(a.menu.contains(BatchAction.earlyRequest), isFalse);
  });

  test('satisa hazir: SATIS ISLEMI YOK — satis Oneri listesinden yapilir', () {
    final a = batchActionsFor(
      _b(status: 'food_cabinet', urgency: 'normal'),
      canAdjust: true,
    );
    expect(a.primary, isNull);
    expect(a.menu, [BatchAction.detail, BatchAction.adjust, BatchAction.discard]);
  });

  test('gecmis kayitlarda zayi yok', () {
    for (final s in ['sold', 'discarded']) {
      final a = batchActionsFor(_b(status: s), canAdjust: true);
      expect(a.primary, isNull, reason: s);
      expect(a.menu.contains(BatchAction.discard), isFalse, reason: s);
      expect(a.menu, [BatchAction.detail, BatchAction.adjust], reason: s);
    }
  });

  test('duzeltme yalnizca yetkili kullaniciya gorunur', () {
    expect(batchActionsFor(_b(status: 'frozen'), canAdjust: false).menu.contains(BatchAction.adjust), isFalse);
    expect(batchActionsFor(_b(status: 'frozen'), canAdjust: true).menu.contains(BatchAction.adjust), isTrue);
  });

  test('sekme kimlikleri sunucu status parametresine eslenir', () {
    expect(batchTabStatus['history'], 'sold,discarded');
    expect(batchTabStatus['food_cabinet'], 'food_cabinet');
  });

  test('arama urun ve magaza adinda Turkce duyarsiz calisir', () {
    final items = [
      _b(status: 'frozen', name: 'ÇİKOLATALI BROWNİE'),
      _b(status: 'frozen', name: 'DEREOTLU POĞAÇA', store: 'Merkez Mağaza'),
      _b(status: 'frozen', name: 'SUFLE'),
    ];
    expect(filterBatches(items, 'cikolata').single.productName, 'ÇİKOLATALI BROWNİE');
    expect(filterBatches(items, 'pogaca').single.productName, 'DEREOTLU POĞAÇA');
    expect(filterBatches(items, 'merkez').single.productName, 'DEREOTLU POĞAÇA');
    expect(filterBatches(items, '').length, 3);
  });
}
