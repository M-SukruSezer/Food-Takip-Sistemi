num _num(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

int _int(dynamic v) => _num(v).toInt();

const approvalStatusLabels = {
  'pending': 'Bekliyor',
  'approved': 'Onaylandı',
  'rejected': 'Reddedildi',
  'cancelled': 'İptal',
};

class TransferApproval {
  const TransferApproval({
    required this.id,
    required this.batchId,
    required this.status,
    required this.reason,
    required this.requestedAt,
    required this.remaining,
    this.productName,
    this.requestedByName,
    this.decidedByName,
    this.decisionNote,
    this.storeName,
    this.thawRemainingHours,
  });

  final int id;
  final int batchId;
  final String status;
  final String reason;
  final String requestedAt;
  final int remaining;
  final String? productName;
  final String? requestedByName;
  final String? decidedByName;
  final String? decisionNote;
  final String? storeName;
  final int? thawRemainingHours;

  bool get pending => status == 'pending';
  String get statusLabel => approvalStatusLabels[status] ?? status;

  factory TransferApproval.fromJson(Map<String, dynamic> j) => TransferApproval(
        id: _int(j['id']),
        batchId: _int(j['batch_id']),
        status: j['status'] as String? ?? 'pending',
        reason: j['reason'] as String? ?? '',
        requestedAt: j['requested_at'] as String? ?? '',
        remaining: _int(j['remaining']),
        productName: j['product_name'] as String?,
        requestedByName: j['requested_by_name'] as String?,
        decidedByName: j['decided_by_name'] as String?,
        decisionNote: j['decision_note'] as String?,
        storeName: j['store_name'] as String?,
        thawRemainingHours:
            j['thaw_remaining_hours'] == null ? null : _int(j['thaw_remaining_hours']),
      );
}
