import '../models/batch.dart';
import 'format.dart';

/// Bir partinin o anda hangi islemleri sundugunu belirler.
/// Arayuzden ayri tutuluyor ki kural test edilebilsin.
enum BatchAction {
  thaw,
  completeThaw,
  awaitingApproval,
  detail,
  adjust,
  addStock,
  earlyRequest,
  discard,

  /// Cozulmeye alinan adet yanlis girildiyse duzeltir; fark donuk depoya doner.
  correctThaw,

  /// Partiyi ve bagli kayitlari siler. Yalnizca ana yonetici.
  deleteBatch,
}

class BatchActions {
  const BatchActions({required this.primary, required this.menu});

  /// Satirda gorunen tek ana islem (yoksa null).
  final BatchAction? primary;

  /// Tasma menusundeki islemler.
  final List<BatchAction> menu;
}

BatchActions batchActionsFor(
  Batch b, {
  required bool canAdjust,
  bool canDiscard = true,
  bool canDelete = false,
}) {
  BatchAction? primary;
  if (b.status == 'frozen') {
    primary = BatchAction.thaw;
  } else if (b.status == 'thawing' && b.thawReady) {
    primary = BatchAction.completeThaw;
  } else if (b.status == 'thawing' && b.pendingApprovalId != null) {
    primary = BatchAction.awaitingApproval;
  }

  final active = ['frozen', 'thawing', 'food_cabinet'].contains(b.status);
  return BatchActions(
    primary: primary,
    menu: [
      BatchAction.detail,
      if (canAdjust) BatchAction.adjust,
      if (b.status == 'frozen') BatchAction.addStock,
      if (b.status == 'thawing' && !b.thawReady && b.pendingApprovalId == null)
        BatchAction.earlyRequest,
      // Cozulmeye alinan adet duzeltmesi yalnizca cozulme surecinde anlamli:
      // food dolabina gecmis urun tekrar dondurulamaz.
      if (canAdjust && b.status == 'thawing') BatchAction.correctThaw,
      // Zayi yetkisi olmayan kullanici menude gormez; sunucu da reddeder.
      if (active && canDiscard) BatchAction.discard,
      // Silme geri alinamaz; yalnizca ana yoneticide.
      if (canDelete) BatchAction.deleteBatch,
    ],
  );
}

/// Sekme kimliklerinin sunucuya gidecek status parametresi karsiligi.
const batchTabStatus = <String, String>{
  'frozen': 'frozen',
  'thawing': 'thawing',
  'food_cabinet': 'food_cabinet',
  'history': 'sold,discarded',
};

/// Arama: urun ve magaza adinda, Turkce karakter duyarsiz.
List<Batch> filterBatches(List<Batch> items, String search) {
  final q = normalizeSearch(search.trim());
  if (q.isEmpty) return items;
  return items
      .where((b) =>
          normalizeSearch(b.productName).contains(q) ||
          normalizeSearch(b.storeName).contains(q))
      .toList();
}
