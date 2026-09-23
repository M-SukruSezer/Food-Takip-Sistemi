/// Ana Yoneticinin devredebildigi yetkiler. Rol sabit kalir; bunlar rolun
/// ustune eklenen izinlerdir ve sunucudaki ALL_PERMISSIONS ile ayni sirada.
const allPermissions = <String>[
  'manage_product_types',
  'adjust_batches',
  'discard',
  'ikram',
];

const permissionLabels = <String, String>{
  'manage_product_types': 'Pasta çeşidi yönetimi',
  'adjust_batches': 'Parti düzeltme (tarih/adet)',
  'discard': 'İmha',
  'ikram': 'İkram',
};

List<String> parsePermissions(dynamic raw) {
  if (raw is! List) return const [];
  return raw.whereType<String>().where(allPermissions.contains).toList();
}

class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    this.storeId,
    this.storeName,
    this.avatar,
    this.permissions = const [],
  });

  final int id;
  final String username;
  final String fullName;
  final String role;
  final int? storeId;
  final String? storeName;
  final String? avatar;

  /// Sunucudan gelen yetki listesi. Ana Yonetici icin sunucu tam listeyi
  /// doner, yine de [can] rolu de kontrol eder ki eski token'lar takilmasin.
  final List<String> permissions;

  bool get isSuperAdmin => role == 'super_admin';
  bool get canManage => role == 'super_admin' || role == 'store_manager';

  /// Arayuz yetkisiz dugmeleri gizler; son sozu sunucu soyler.
  bool can(String permission) => isSuperAdmin || permissions.contains(permission);

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: (json['id'] as num).toInt(),
        username: json['username'] as String? ?? '',
        fullName: json['full_name'] as String? ?? '',
        role: json['role'] as String? ?? 'staff',
        storeId: (json['store_id'] as num?)?.toInt(),
        storeName: json['store_name'] as String?,
        avatar: json['avatar'] as String?,
        permissions: parsePermissions(json['permissions']),
      );

  AppUser copyWith({String? avatar, bool clearAvatar = false}) => AppUser(
        id: id,
        username: username,
        fullName: fullName,
        role: role,
        storeId: storeId,
        storeName: storeName,
        avatar: clearAvatar ? null : (avatar ?? this.avatar),
        permissions: permissions,
      );
}
