num _num(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

int _int(dynamic v) => _num(v).toInt();

/// Magaza kasasindan yapilan tek bir masraf.
class PettyCashExpense {
  const PettyCashExpense({
    required this.id,
    required this.storeId,
    required this.amount,
    required this.description,
    required this.spentAt,
    required this.hasReceipt,
    this.createdByName,
    this.storeName,
  });

  final int id;
  final int storeId;
  final num amount;
  final String description;
  final String spentAt;

  /// Fis gorseli listede tasinmaz; ayri uc noktadan cekilir.
  final bool hasReceipt;
  final String? createdByName;
  final String? storeName;

  factory PettyCashExpense.fromJson(Map<String, dynamic> j) => PettyCashExpense(
        id: _int(j['id']),
        storeId: _int(j['store_id']),
        amount: _num(j['amount']),
        description: j['description'] as String? ?? '',
        spentAt: j['spent_at'] as String? ?? '',
        hasReceipt: j['has_receipt'] == true,
        createdByName: j['created_by_name'] as String?,
        storeName: j['store_name'] as String?,
      );
}

/// Haftalik limit durumu. Yalnizca tek magazaya daraltilmis listede dolu gelir.
class PettyCashStatus {
  const PettyCashStatus({
    required this.storeId,
    required this.weeklyLimit,
    required this.spentThisWeek,
    required this.remaining,
    required this.weekStart,
  });

  final int storeId;
  final num weeklyLimit;
  final num spentThisWeek;
  final num remaining;
  final String weekStart;

  bool get hasLimit => weeklyLimit > 0;
  double get usedRatio => weeklyLimit <= 0 ? 0 : (spentThisWeek / weeklyLimit).clamp(0, 1).toDouble();

  factory PettyCashStatus.fromJson(Map<String, dynamic> j) => PettyCashStatus(
        storeId: _int(j['store_id']),
        weeklyLimit: _num(j['weekly_limit']),
        spentThisWeek: _num(j['spent_this_week']),
        remaining: _num(j['remaining']),
        weekStart: j['week_start'] as String? ?? '',
      );
}

class PettyCashPage {
  const PettyCashPage({required this.items, this.status});

  final List<PettyCashExpense> items;
  final PettyCashStatus? status;

  factory PettyCashPage.fromJson(Map<String, dynamic> j) => PettyCashPage(
        items: ((j['items'] as List<dynamic>?) ?? [])
            .map((e) => PettyCashExpense.fromJson(e as Map<String, dynamic>))
            .toList(),
        status: j['status'] == null
            ? null
            : PettyCashStatus.fromJson(j['status'] as Map<String, dynamic>),
      );
}

/// Ana Yoneticinin belirledigi magaza basina haftalik limit.
class PettyCashLimit {
  const PettyCashLimit({
    required this.storeId,
    required this.storeName,
    required this.weeklyAmount,
  });

  final int storeId;
  final String storeName;
  final num weeklyAmount;

  factory PettyCashLimit.fromJson(Map<String, dynamic> j) => PettyCashLimit(
        storeId: _int(j['store_id']),
        storeName: j['store_name'] as String? ?? '',
        weeklyAmount: _num(j['weekly_amount']),
      );
}
