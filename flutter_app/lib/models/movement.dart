num _num(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

int _int(dynamic v) => _num(v).toInt();

/// Hareket turleri. Sunucudaki allowedKinds ile ayni.
const movementKinds = <String>['sale', 'ikram', 'discard'];

const movementKindLabels = <String, String>{
  'sale': 'Satış',
  'ikram': 'İkram',
  'discard': 'İmha',
};

/// Satis, ikram ve imha kayitlarinin birlesik satiri.
class Movement {
  const Movement({
    required this.id,
    required this.kind,
    required this.quantity,
    required this.at,
    this.unitPrice,
    this.total,
    this.productName,
    this.productTypeId,
    this.userName,
    this.storeName,
    this.reason,
    this.priceIsCurrent = false,
  });

  final int id;
  final String kind;
  final int quantity;
  final String at;
  final num? unitPrice;
  final num? total;
  final String? productName;
  final int? productTypeId;
  final String? userName;
  final String? storeName;
  final String? reason;

  /// Imha satirlarinda tutar anlik goruntu degil, cesidin guncel fiyatiyla
  /// hesaplanmistir; arayuz bunu belirtir.
  final bool priceIsCurrent;

  String get kindLabel => movementKindLabels[kind] ?? kind;

  factory Movement.fromJson(Map<String, dynamic> j) => Movement(
        id: _int(j['id']),
        kind: j['kind'] as String? ?? 'sale',
        quantity: _int(j['quantity']),
        at: j['at'] as String? ?? '',
        unitPrice: j['unit_price'] == null ? null : _num(j['unit_price']),
        total: j['total'] == null ? null : _num(j['total']),
        productName: j['product_name'] as String?,
        productTypeId: j['product_type_id'] == null ? null : _int(j['product_type_id']),
        userName: j['user_name'] as String?,
        storeName: j['store_name'] as String?,
        reason: j['reason'] as String?,
        priceIsCurrent: j['price_is_current'] == true,
      );
}

class MovementTotals {
  const MovementTotals({
    required this.saleQty,
    required this.revenue,
    required this.ikramQty,
    required this.ikramValue,
    required this.discardQty,
    required this.discardValue,
    required this.count,
  });

  final int saleQty;
  final num revenue;
  final int ikramQty;
  final num ikramValue;
  final int discardQty;
  final num discardValue;
  final int count;

  factory MovementTotals.fromJson(Map<String, dynamic> j) => MovementTotals(
        saleQty: _int(j['sale_qty']),
        revenue: _num(j['revenue']),
        ikramQty: _int(j['ikram_qty']),
        ikramValue: _num(j['ikram_value']),
        discardQty: _int(j['discard_qty']),
        discardValue: _num(j['discard_value']),
        count: _int(j['count']),
      );

  static const empty = MovementTotals(
    saleQty: 0, revenue: 0, ikramQty: 0, ikramValue: 0,
    discardQty: 0, discardValue: 0, count: 0,
  );
}

class MovementReport {
  const MovementReport({required this.items, required this.totals});

  final List<Movement> items;
  final MovementTotals totals;

  factory MovementReport.fromJson(Map<String, dynamic> j) => MovementReport(
        items: ((j['items'] as List<dynamic>?) ?? [])
            .map((e) => Movement.fromJson(e as Map<String, dynamic>))
            .toList(),
        totals: j['totals'] == null
            ? MovementTotals.empty
            : MovementTotals.fromJson(j['totals'] as Map<String, dynamic>),
      );
}
