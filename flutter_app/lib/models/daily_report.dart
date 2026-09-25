num? _numOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

num _num(dynamic v) => _numOrNull(v) ?? 0;
int _int(dynamic v) => _num(v).toInt();

/// Sunucudan gelen alan tanimi. Etiketler ve turler tek yerde (sunucuda)
/// duruyor; istemci listeyi oradan uretiyor ki iki yerde tekrar olmasin.
class ReportField {
  const ReportField({
    required this.key,
    required this.label,
    required this.type,
    this.formula,
  });

  final String key;
  final String label;

  /// 'money' | 'int' | 'number' | 'percent'
  final String type;

  /// Turetilen alanlarda hesabin nasil yapildigi; arayuz ipucu olarak gosterir.
  final String? formula;

  bool get isInt => type == 'int';

  factory ReportField.fromJson(Map<String, dynamic> j) => ReportField(
        key: j['key'] as String,
        label: j['label'] as String,
        type: j['type'] as String? ?? 'number',
        formula: j['formula'] as String?,
      );
}

class ReportFields {
  const ReportFields({
    required this.entry,
    required this.system,
    required this.derived,
  });

  /// Kullanicinin elle girdigi alanlar — form yalnizca bunlari gosterir.
  final List<ReportField> entry;

  /// Sistemin satis ve imha kayitlarindan hesapladigi alanlar. Formda yer
  /// almaz; tabloda ve ozette okunur olarak gosterilir.
  final List<ReportField> system;

  final List<ReportField> derived;

  static List<ReportField> _list(dynamic v) => ((v as List<dynamic>?) ?? [])
      .map((e) => ReportField.fromJson(e as Map<String, dynamic>))
      .toList();

  factory ReportFields.fromJson(Map<String, dynamic> j) => ReportFields(
        entry: _list(j['entry']),
        system: _list(j['system']),
        derived: _list(j['derived']),
      );

  static const empty = ReportFields(entry: [], system: [], derived: []);
}

/// Turetilen olculer. Payda sifirsa null gelir; arayuz "-" gosterir.
class ReportMetrics {
  const ReportMetrics({
    this.at,
    this.ipt,
    this.foodMarkoutPct,
    this.foodUph,
    this.modifiersPct,
    this.appPct,
  });

  final num? at;
  final num? ipt;
  final num? foodMarkoutPct;
  final num? foodUph;
  final num? modifiersPct;
  final num? appPct;

  num? operator [](String key) => switch (key) {
        'at' => at,
        'ipt' => ipt,
        'food_markout_pct' => foodMarkoutPct,
        'food_uph' => foodUph,
        'modifiers_pct' => modifiersPct,
        'app_pct' => appPct,
        _ => null,
      };

  factory ReportMetrics.fromJson(Map<String, dynamic> j) => ReportMetrics(
        at: _numOrNull(j['at']),
        ipt: _numOrNull(j['ipt']),
        foodMarkoutPct: _numOrNull(j['food_markout_pct']),
        foodUph: _numOrNull(j['food_uph']),
        modifiersPct: _numOrNull(j['modifiers_pct']),
        appPct: _numOrNull(j['app_pct']),
      );

  static const empty = ReportMetrics();
}

/// Bir gunun kaydi: ham alanlar + turetilen olculer.
class DailyReport {
  const DailyReport({
    required this.id,
    required this.storeId,
    required this.date,
    required this.values,
    required this.metrics,
    this.storeName,
    this.createdByName,
  });

  final int id;
  final int storeId;
  final String date;

  /// Ham alanlar, sunucudaki anahtarlarla.
  final Map<String, num> values;
  final ReportMetrics metrics;
  final String? storeName;
  final String? createdByName;

  static const _keys = [
    'net_sales', 'adt', 'product_qty', 'food_usd', 'food_usd_try',
    'food_mo_try', 'sold_beverage_qty', 'modifiers', 'app_amount',
  ];

  factory DailyReport.fromJson(Map<String, dynamic> j) => DailyReport(
        id: _int(j['id']),
        storeId: _int(j['store_id']),
        date: j['report_date'] as String? ?? '',
        values: {for (final k in _keys) k: _num(j[k])},
        metrics: j['metrics'] == null
            ? ReportMetrics.empty
            : ReportMetrics.fromJson(j['metrics'] as Map<String, dynamic>),
        storeName: j['store_name'] as String?,
        createdByName: j['created_by_name'] as String?,
      );
}

/// Donem ozeti: ham toplamlar + TOPLAMLARDAN yeniden hesaplanan oranlar.
class ReportSummaryTotals {
  const ReportSummaryTotals({
    required this.days,
    required this.totals,
    required this.metrics,
  });

  final int days;
  final Map<String, num> totals;
  final ReportMetrics metrics;

  factory ReportSummaryTotals.fromJson(Map<String, dynamic> j) => ReportSummaryTotals(
        days: _int(j['days']),
        totals: ((j['totals'] as Map<String, dynamic>?) ?? {})
            .map((k, v) => MapEntry(k, _num(v))),
        metrics: j['metrics'] == null
            ? ReportMetrics.empty
            : ReportMetrics.fromJson(j['metrics'] as Map<String, dynamic>),
      );

  static const empty = ReportSummaryTotals(days: 0, totals: {}, metrics: ReportMetrics.empty);
}

class DailyReportPage {
  const DailyReportPage({
    required this.from,
    required this.to,
    required this.period,
    required this.items,
    required this.summary,
  });

  final String from;
  final String to;
  final String period;
  final List<DailyReport> items;
  final ReportSummaryTotals summary;

  factory DailyReportPage.fromJson(Map<String, dynamic> j) => DailyReportPage(
        from: j['from'] as String? ?? '',
        to: j['to'] as String? ?? '',
        period: j['period'] as String? ?? 'week',
        items: ((j['items'] as List<dynamic>?) ?? [])
            .map((e) => DailyReport.fromJson(e as Map<String, dynamic>))
            .toList(),
        summary: j['summary'] == null
            ? ReportSummaryTotals.empty
            : ReportSummaryTotals.fromJson(j['summary'] as Map<String, dynamic>),
      );

  static const empty = DailyReportPage(
    from: '', to: '', period: 'week', items: [], summary: ReportSummaryTotals.empty,
  );
}

/// Sistemin o gun icin hesapladigi food rakamlari. Satis ve imha
/// kayitlarindan gelir; kullanici bunlari elle girmez ve degistiremez.
class SystemFoodValues {
  const SystemFoodValues({
    required this.foodUsd,
    required this.foodUsdTry,
    required this.foodMoTry,
    required this.discardedQty,
  });

  final num foodUsd;
  final num foodUsdTry;
  final num foodMoTry;
  final int discardedQty;

  num? operator [](String key) => switch (key) {
        'food_usd' => foodUsd,
        'food_usd_try' => foodUsdTry,
        'food_mo_try' => foodMoTry,
        _ => null,
      };

  /// Sistemden gelen alanlar; arayuz bunlari okunur gosterir.
  static const keys = ['food_usd', 'food_usd_try', 'food_mo_try'];

  bool get isEmpty => foodUsd == 0 && foodUsdTry == 0 && foodMoTry == 0;

  factory SystemFoodValues.fromJson(Map<String, dynamic> j) => SystemFoodValues(
        foodUsd: _num(j['food_usd']),
        foodUsdTry: _num(j['food_usd_try']),
        foodMoTry: _num(j['food_mo_try']),
        discardedQty: _int(j['discarded_qty']),
      );

  static const empty =
      SystemFoodValues(foodUsd: 0, foodUsdTry: 0, foodMoTry: 0, discardedQty: 0);
}

/// /daily-reports/day/:date yaniti: varsa kayit + sistemin hesapladigi degerler.
class DailyReportDay {
  const DailyReportDay({this.report, required this.suggested});

  final DailyReport? report;
  final SystemFoodValues suggested;

  factory DailyReportDay.fromJson(Map<String, dynamic> j) => DailyReportDay(
        report: j['report'] == null
            ? null
            : DailyReport.fromJson(j['report'] as Map<String, dynamic>),
        suggested: j['suggested'] == null
            ? SystemFoodValues.empty
            : SystemFoodValues.fromJson(j['suggested'] as Map<String, dynamic>),
      );
}
