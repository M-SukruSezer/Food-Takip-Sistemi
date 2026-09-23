num _num(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

int _int(dynamic v) => _num(v).toInt();

/// Bir parti (batch). Oneri listesi ve stok ekrani ayni modeli kullanir.
class Batch {
  const Batch({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.remaining,
    required this.status,
    this.storeName,
    this.sktEnd,
    this.urgency,
    this.remainingHours,
    this.daysLeft,
    this.thawRemainingHours,
    this.thawReady = false,
    this.productUnitPrice,
    this.sktDays,
    this.pendingApprovalId,
    this.enteredFrozenAt,
    this.thawingStartedAt,
    this.thawingFinishAt,
    this.foodCabinetEnteredAt,
    this.notes,
  });

  final int id;
  final String productName;
  final int quantity;
  final int remaining;
  final String status;
  final String? storeName;
  final String? sktEnd;
  final String? urgency;
  final num? remainingHours;
  final int? daysLeft;
  final num? thawRemainingHours;
  final bool thawReady;
  final num? productUnitPrice;
  final int? sktDays;
  final int? pendingApprovalId;
  final String? enteredFrozenAt;
  final String? thawingStartedAt;
  final String? thawingFinishAt;
  final String? foodCabinetEnteredAt;
  final String? notes;

  bool get hasPrice => productUnitPrice != null;
  bool get isExpired => urgency == 'expired';

  factory Batch.fromJson(Map<String, dynamic> j) => Batch(
        id: _int(j['id']),
        productName: j['product_name'] as String? ?? '',
        quantity: _int(j['quantity']),
        remaining: _int(j['remaining']),
        status: j['status'] as String? ?? '',
        storeName: j['store_name'] as String?,
        sktEnd: j['skt_end'] as String?,
        urgency: j['urgency'] as String?,
        remainingHours: j['remaining_hours'] == null ? null : _num(j['remaining_hours']),
        daysLeft: j['days_left'] == null ? null : _int(j['days_left']),
        thawRemainingHours:
            j['thaw_remaining_hours'] == null ? null : _num(j['thaw_remaining_hours']),
        thawReady: j['thaw_ready'] == true,
        productUnitPrice:
            j['product_unit_price'] == null ? null : _num(j['product_unit_price']),
        sktDays: j['skt_days'] == null ? null : _int(j['skt_days']),
        pendingApprovalId:
            j['pending_approval_id'] == null ? null : _int(j['pending_approval_id']),
        enteredFrozenAt: j['entered_frozen_at'] as String?,
        thawingStartedAt: j['thawing_started_at'] as String?,
        thawingFinishAt: j['thawing_finish_at'] as String?,
        foodCabinetEnteredAt: j['food_cabinet_entered_at'] as String?,
        notes: j['notes'] as String?,
      );
}
