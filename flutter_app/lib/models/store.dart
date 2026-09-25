import 'user.dart';

num _num(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

int _int(dynamic v) => _num(v).toInt();

class Store {
  const Store({
    required this.id,
    required this.name,
    required this.active,
    this.address,
    this.phone,
    this.userCount = 0,
    this.activeBatchCount = 0,
  });

  final int id;
  final String name;
  final bool active;
  final String? address;
  final String? phone;

  /// Liste uc noktasi bu iki sayiyi alt sorgu ile doner.
  final int userCount;
  final int activeBatchCount;

  /// Kullanici veya urun kaydi olan magaza silinemez, pasife alinir.
  bool get deletable => userCount == 0 && activeBatchCount == 0;

  factory Store.fromJson(Map<String, dynamic> j) => Store(
        id: _int(j['id']),
        name: j['name'] as String? ?? '',
        active: _int(j['active']) == 1,
        address: j['address'] as String?,
        phone: j['phone'] as String?,
        userCount: _int(j['user_count']),
        activeBatchCount: _int(j['active_batch_count']),
      );
}

class ManagedUser {
  const ManagedUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.active,
    this.storeId,
    this.storeName,
    this.permissions = const [],
    this.storeIds = const [],
  });

  final int id;
  final String username;
  final String fullName;
  final String role;
  final bool active;
  final int? storeId;
  final String? storeName;

  /// Ana Yoneticinin verdigi ek yetkiler. Ana Yonetici hesaplarinda sunucu
  /// tam listeyi doner.
  final List<String> permissions;

  /// Cok magazali rollerde (operations/regional manager) sorumlu olunan
  /// magazalar; digerlerinde bos.
  final List<int> storeIds;

  bool get isMultiStore => const ['operations_manager', 'regional_manager'].contains(role);

  factory ManagedUser.fromJson(Map<String, dynamic> j) => ManagedUser(
        id: _int(j['id']),
        username: j['username'] as String? ?? '',
        fullName: j['full_name'] as String? ?? '',
        role: j['role'] as String? ?? 'barista',
        active: _int(j['active']) == 1,
        storeId: j['store_id'] == null ? null : _int(j['store_id']),
        storeName: j['store_name'] as String?,
        permissions: parsePermissions(j['permissions']),
        storeIds: (j['store_ids'] as List<dynamic>? ?? const [])
            .map((e) => _int(e))
            .toList(),
      );
}
