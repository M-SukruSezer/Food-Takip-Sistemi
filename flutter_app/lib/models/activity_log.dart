class ActivityLog {
  const ActivityLog({
    required this.id,
    required this.action,
    required this.createdAt,
    this.details,
    this.username,
    this.storeName,
  });

  final int id;
  final String action;
  final String createdAt;
  final String? details;
  final String? username;
  final String? storeName;

  factory ActivityLog.fromJson(Map<String, dynamic> j) => ActivityLog(
        id: (j['id'] as num).toInt(),
        action: j['action'] as String? ?? '',
        createdAt: j['created_at'] as String? ?? '',
        details: j['details'] as String?,
        username: j['username'] as String?,
        storeName: j['store_name'] as String?,
      );
}
