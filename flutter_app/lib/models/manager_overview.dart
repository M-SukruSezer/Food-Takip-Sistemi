import 'daily_report.dart';

num? _numOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

num _num(dynamic v) => _numOrNull(v) ?? 0;
int _int(dynamic v) => _num(v).toInt();

/// Petty cash haftalik limit durumu.
class PettyCashStatus {
  const PettyCashStatus({
    required this.weeklyLimit,
    required this.spentThisWeek,
    required this.remaining,
    required this.expenseCount,
    required this.limitSet,
    required this.overLimit,
    this.usedPct,
  });

  final num weeklyLimit;
  final num spentThisWeek;
  final num remaining;
  final int expenseCount;

  /// Limit hic tanimlanmamissa oran anlamsiz olur; arayuz bunu yazar.
  final bool limitSet;
  final bool overLimit;
  final num? usedPct;

  factory PettyCashStatus.fromJson(Map<String, dynamic> j) => PettyCashStatus(
        weeklyLimit: _num(j['weekly_limit']),
        spentThisWeek: _num(j['spent_this_week']),
        remaining: _num(j['remaining']),
        expenseCount: _int(j['expense_count']),
        limitSet: j['limit_set'] == true,
        overLimit: j['over_limit'] == true,
        usedPct: _numOrNull(j['used_pct']),
      );

  static const empty = PettyCashStatus(
    weeklyLimit: 0, spentThisWeek: 0, remaining: 0,
    expenseCount: 0, limitSet: false, overLimit: false,
  );
}

/// Ay basindan bugune ciro, ciro hizi ve ay sonu tahmini.
class RevenuePace {
  const RevenuePace({
    required this.month,
    required this.daysInMonth,
    required this.daysElapsed,
    required this.daysWithData,
    required this.daysMissing,
    required this.mtdNetSales,
    required this.remainingDays,
    required this.monthTotals,
    required this.monthMetrics,
    this.dailyAvg,
    this.forecastMonthEnd,
    this.today,
  });

  final String month;
  final int daysInMonth;
  final int daysElapsed;

  /// Rapor girilmis gun sayisi. Ortalama buna bolunur; girilmemis gunleri
  /// sifir saymak tahmini yapay olarak dusururdu.
  final int daysWithData;
  final int daysMissing;

  final num mtdNetSales;

  /// Ay sonuna kalan gun sayisi.
  final int remainingDays;

  final Map<String, num> monthTotals;
  final ReportMetrics monthMetrics;

  /// Veri girilmemisse null.
  final num? dailyAvg;
  final num? forecastMonthEnd;

  /// Bugunun kaydi (varsa).
  final DailyReport? today;

  factory RevenuePace.fromJson(Map<String, dynamic> j) => RevenuePace(
        month: j['month'] as String? ?? '',
        daysInMonth: _int(j['days_in_month']),
        daysElapsed: _int(j['days_elapsed']),
        daysWithData: _int(j['days_with_data']),
        daysMissing: _int(j['days_missing']),
        mtdNetSales: _num(j['mtd_net_sales']),
        remainingDays: _int(j['remaining_days']),
        monthTotals: ((j['month_totals'] as Map<String, dynamic>?) ?? {})
            .map((k, v) => MapEntry(k, _num(v))),
        monthMetrics: j['month_metrics'] == null
            ? ReportMetrics.empty
            : ReportMetrics.fromJson(j['month_metrics'] as Map<String, dynamic>),
        dailyAvg: _numOrNull(j['daily_avg']),
        forecastMonthEnd: _numOrNull(j['forecast_month_end']),
        today: j['today'] == null
            ? null
            : DailyReport.fromJson(j['today'] as Map<String, dynamic>),
      );

  static const empty = RevenuePace(
    month: '', daysInMonth: 0, daysElapsed: 0, daysWithData: 0, daysMissing: 0,
    mtdNetSales: 0, remainingDays: 0, monthTotals: {},
    monthMetrics: ReportMetrics.empty,
  );
}

/// Bir cesidin donuk depo stogu ve satis hizina gore yeterliligi.
class StockCoverageItem {
  const StockCoverageItem({
    required this.productTypeId,
    required this.name,
    required this.frozenQty,
    required this.thawingQty,
    required this.cabinetQty,
    required this.availableQty,
    required this.soldQty,
    required this.dailyVelocity,
    this.unitPrice,
    this.frozenValue,
    this.daysOfCover,
    this.daysOfCoverAvailable,
    this.depletionDate,
    this.risk,
  });

  final int productTypeId;
  final String name;
  final int frozenQty;
  final int thawingQty;
  final int cabinetQty;
  final int availableQty;

  /// Pencere icinde satilan adet (ikram haric).
  final int soldQty;
  final num dailyVelocity;

  final num? unitPrice;
  final num? frozenValue;

  /// Donuk depo stogunun kac gun yetecegi. Satis yoksa null (sifira bolme yok).
  final num? daysOfCover;
  final num? daysOfCoverAvailable;
  final String? depletionDate;

  /// 0 stok yok, 1 <3 gun, 2 <7 gun, 3 yeterli, null satis yok.
  final int? risk;

  factory StockCoverageItem.fromJson(Map<String, dynamic> j) => StockCoverageItem(
        productTypeId: _int(j['product_type_id']),
        name: j['name'] as String? ?? '',
        frozenQty: _int(j['frozen_qty']),
        thawingQty: _int(j['thawing_qty']),
        cabinetQty: _int(j['cabinet_qty']),
        availableQty: _int(j['available_qty']),
        soldQty: _int(j['sold_qty']),
        dailyVelocity: _num(j['daily_velocity']),
        unitPrice: _numOrNull(j['unit_price']),
        frozenValue: _numOrNull(j['frozen_value']),
        daysOfCover: _numOrNull(j['days_of_cover']),
        daysOfCoverAvailable: _numOrNull(j['days_of_cover_available']),
        depletionDate: j['depletion_date'] as String?,
        risk: j['risk'] == null ? null : _int(j['risk']),
      );
}

class StockCoverage {
  const StockCoverage({required this.windowDays, required this.items});

  final int windowDays;
  final List<StockCoverageItem> items;

  factory StockCoverage.fromJson(Map<String, dynamic> j) => StockCoverage(
        windowDays: _int(j['window_days']),
        items: ((j['items'] as List<dynamic>?) ?? [])
            .map((e) => StockCoverageItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static const empty = StockCoverage(windowDays: 14, items: []);
}

/// Ana sayfadaki genel rapor. Yalnizca magaza muduru ve vardiya muduru gorur.
class ManagerOverview {
  const ManagerOverview({
    required this.storeName,
    required this.pettyCash,
    required this.revenue,
    required this.stock,
  });

  final String? storeName;
  final PettyCashStatus pettyCash;
  final RevenuePace revenue;
  final StockCoverage stock;

  factory ManagerOverview.fromJson(Map<String, dynamic> j) => ManagerOverview(
        storeName: (j['store'] as Map<String, dynamic>?)?['name'] as String?,
        pettyCash: j['petty_cash'] == null
            ? PettyCashStatus.empty
            : PettyCashStatus.fromJson(j['petty_cash'] as Map<String, dynamic>),
        revenue: j['revenue'] == null
            ? RevenuePace.empty
            : RevenuePace.fromJson(j['revenue'] as Map<String, dynamic>),
        stock: j['stock'] == null
            ? StockCoverage.empty
            : StockCoverage.fromJson(j['stock'] as Map<String, dynamic>),
      );

  static const empty = ManagerOverview(
    storeName: null,
    pettyCash: PettyCashStatus.empty,
    revenue: RevenuePace.empty,
    stock: StockCoverage.empty,
  );
}
