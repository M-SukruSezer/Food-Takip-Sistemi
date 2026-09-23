/// Yardimci: sunucu sayilari kimi yerde string, kimi yerde num donebiliyor.
num _num(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

int _int(dynamic v) => _num(v).toInt();

class DashboardCounts {
  const DashboardCounts({
    required this.frozen,
    required this.frozenQty,
    required this.thawing,
    required this.thawingQty,
    required this.cabinet,
    required this.cabinetQty,
    required this.expiringQty,
    required this.expiredQty,
    required this.expiringCount,
  });

  final int frozen;
  final int frozenQty;
  final int thawing;
  final int thawingQty;
  final int cabinet;
  final int cabinetQty;
  final int expiringQty;
  final int expiredQty;
  final int expiringCount;

  int get totalStock => frozenQty + thawingQty + cabinetQty;

  factory DashboardCounts.fromJson(Map<String, dynamic> j) => DashboardCounts(
        frozen: _int(j['frozen']),
        frozenQty: _int(j['frozen_qty']),
        thawing: _int(j['thawing']),
        thawingQty: _int(j['thawing_qty']),
        cabinet: _int(j['food_cabinet']),
        cabinetQty: _int(j['food_cabinet_qty']),
        expiringQty: _int(j['expiring_qty']),
        expiredQty: _int(j['expired_qty']),
        expiringCount: _int(j['expiring_count']),
      );
}

class SoldToday {
  const SoldToday({required this.count, required this.qty, required this.revenue});

  final int count;
  final int qty;
  final num revenue;

  factory SoldToday.fromJson(Map<String, dynamic> j) => SoldToday(
        count: _int(j['count']),
        qty: _int(j['qty']),
        revenue: _num(j['revenue']),
      );
}

class DashboardData {
  const DashboardData({required this.counts, required this.soldToday});

  final DashboardCounts counts;
  final SoldToday soldToday;

  factory DashboardData.fromJson(Map<String, dynamic> j) => DashboardData(
        counts: DashboardCounts.fromJson(j['counts'] as Map<String, dynamic>),
        soldToday: SoldToday.fromJson(j['soldToday'] as Map<String, dynamic>),
      );
}

class StoreSummaryRow {
  const StoreSummaryRow({
    required this.id,
    required this.name,
    required this.frozenQty,
    required this.thawingQty,
    required this.cabinetQty,
    required this.discardedQty,
    required this.soldQty,
    required this.soldCount,
    required this.revenue,
    required this.productCount,
  });

  final int id;
  final String name;
  final int frozenQty;
  final int thawingQty;
  final int cabinetQty;
  final int discardedQty;
  final int soldQty;
  final int soldCount;
  final num revenue;
  final int productCount;

  factory StoreSummaryRow.fromJson(Map<String, dynamic> j) => StoreSummaryRow(
        id: _int(j['id']),
        name: j['name'] as String? ?? '',
        frozenQty: _int(j['frozen_qty']),
        thawingQty: _int(j['thawing_qty']),
        cabinetQty: _int(j['cabinet_qty']),
        discardedQty: _int(j['discarded_qty']),
        soldQty: _int(j['sold_qty']),
        soldCount: _int(j['sold_count']),
        revenue: _num(j['revenue']),
        productCount: _int(j['product_count']),
      );
}

/// /reports/summary iki bicimde doner: coklu magaza ya da tek magaza.
class ReportSummary {
  const ReportSummary({
    required this.isMulti,
    this.stores = const [],
    this.storeName,
    this.soldQty = 0,
    this.soldCount = 0,
    this.revenue = 0,
    this.discardedQty = 0,
  });

  final bool isMulti;
  final List<StoreSummaryRow> stores;
  final String? storeName;
  final int soldQty;
  final int soldCount;
  final num revenue;
  final int discardedQty;

  num get totalRevenue =>
      isMulti ? stores.fold<num>(0, (a, s) => a + s.revenue) : revenue;

  factory ReportSummary.fromJson(Map<String, dynamic> j) {
    if (j['type'] == 'multi') {
      return ReportSummary(
        isMulti: true,
        stores: (j['stores'] as List<dynamic>? ?? [])
            .map((e) => StoreSummaryRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    }
    final store = j['store'] as Map<String, dynamic>?;
    return ReportSummary(
      isMulti: false,
      storeName: store?['name'] as String?,
      soldQty: _int(j['sold_qty']),
      soldCount: _int(j['sold_count']),
      revenue: _num(j['revenue']),
      discardedQty: _int(j['discarded_qty']),
    );
  }
}

class SalesPoint {
  const SalesPoint({required this.date, required this.qty, required this.revenue});

  final String date;
  final int qty;
  final num revenue;

  factory SalesPoint.fromJson(Map<String, dynamic> j) => SalesPoint(
        date: j['date'] as String? ?? '',
        qty: _int(j['qty']),
        revenue: _num(j['revenue']),
      );
}

class StatusSlice {
  const StatusSlice({required this.status, required this.quantity});

  final String status;
  final int quantity;

  factory StatusSlice.fromJson(Map<String, dynamic> j) => StatusSlice(
        status: j['status'] as String? ?? '',
        quantity: _int(j['quantity']),
      );
}

class ProductRank {
  const ProductRank({required this.id, required this.name, required this.qty, this.revenue = 0});

  final int id;
  final String name;
  final int qty;
  final num revenue;

  factory ProductRank.fromJson(Map<String, dynamic> j) => ProductRank(
        id: _int(j['id']),
        name: j['name'] as String? ?? '',
        qty: _int(j['qty']),
        revenue: _num(j['revenue']),
      );
}

/// Bir donemin satis ve zayi siralamalari. Sunucu tam listeyi doner;
/// ilk/son bes secimi arayuzde yapilir.
class PeriodPerformance {
  const PeriodPerformance({required this.sold, required this.wasted});

  final List<ProductRank> sold;
  final List<ProductRank> wasted;

  List<ProductRank> get best => sold.take(5).toList();
  List<ProductRank> get worst => sold.reversed.take(5).toList();
  List<ProductRank> get topWasted => wasted.take(5).toList();
  int get soldTotal => sold.fold<int>(0, (a, r) => a + r.qty);
  int get wastedTotal => wasted.fold<int>(0, (a, r) => a + r.qty);
  int get kinds => sold.length;

  factory PeriodPerformance.fromJson(Map<String, dynamic> j) => PeriodPerformance(
        sold: (j['sold'] as List<dynamic>? ?? [])
            .map((e) => ProductRank.fromJson(e as Map<String, dynamic>))
            .toList(),
        wasted: (j['wasted'] as List<dynamic>? ?? [])
            .map((e) => ProductRank.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ProductPerformance {
  const ProductPerformance({required this.week, required this.month});

  final PeriodPerformance week;
  final PeriodPerformance month;

  factory ProductPerformance.fromJson(Map<String, dynamic> j) => ProductPerformance(
        week: PeriodPerformance.fromJson(j['week'] as Map<String, dynamic>),
        month: PeriodPerformance.fromJson(j['month'] as Map<String, dynamic>),
      );
}

class StoreOption {
  const StoreOption({required this.id, required this.name});
  final int id;
  final String name;

  factory StoreOption.fromJson(Map<String, dynamic> j) =>
      StoreOption(id: _int(j['id']), name: j['name'] as String? ?? '');
}
