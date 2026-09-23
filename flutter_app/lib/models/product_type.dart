num _num(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

int _int(dynamic v) => _num(v).toInt();

class ProductType {
  const ProductType({
    required this.id,
    required this.name,
    required this.sktDays,
    required this.active,
    this.storeId,
    this.storeName,
    this.unitPrice,
    this.description,
  });

  final int id;
  final String name;
  final int sktDays;
  final bool active;
  final int? storeId;
  final String? storeName;
  final num? unitPrice;
  final String? description;

  bool get hasPrice => unitPrice != null;
  bool get isGlobal => storeId == null;

  factory ProductType.fromJson(Map<String, dynamic> j) => ProductType(
        id: _int(j['id']),
        name: j['name'] as String? ?? '',
        sktDays: _int(j['skt_days']),
        active: _int(j['active']) == 1,
        storeId: j['store_id'] == null ? null : _int(j['store_id']),
        storeName: j['store_name'] as String?,
        unitPrice: j['unit_price'] == null ? null : _num(j['unit_price']),
        description: j['description'] as String?,
      );
}

class SaleRecord {
  const SaleRecord({
    required this.id,
    required this.quantity,
    required this.soldAt,
    this.unitPrice,
    this.soldByName,
    this.productName,
    this.storeName,
    this.batchCode,
    this.kind = 'sale',
  });

  final int id;
  final int quantity;
  final String soldAt;
  final num? unitPrice;
  final String? soldByName;

  /// Satis gecmisi listesinde dolu gelir; parti detayinda gerekmez.
  final String? productName;
  final String? storeName;
  final String? batchCode;

  /// 'sale' ya da 'ikram'. Ikram stoktan duser ama ciroya ve satis adedine
  /// girmez; eski kayitlarda alan bos gelirse satis sayilir.
  final String kind;

  bool get isIkram => kind == 'ikram';

  num get total => (unitPrice ?? 0) * quantity;

  factory SaleRecord.fromJson(Map<String, dynamic> j) => SaleRecord(
        id: _int(j['id']),
        quantity: _int(j['quantity']),
        soldAt: j['sold_at'] as String? ?? '',
        unitPrice: j['unit_price'] == null ? null : _num(j['unit_price']),
        soldByName: j['sold_by_name'] as String?,
        productName: j['product_name'] as String?,
        storeName: j['store_name'] as String?,
        batchCode: j['batch_code'] as String?,
        kind: j['kind'] as String? ?? 'sale',
      );
}
