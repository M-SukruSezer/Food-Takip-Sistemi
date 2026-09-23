import '../models/store.dart';
import '../models/user.dart';

/// Kullanici yonetimi kurallari. Sunucudaki users.js kontrollerinin aynisi;
/// burada olmasi dugmelerin bastan kapali gelmesini saglar, sunucu son sozu
/// soylemeye devam eder.
class UserPermissions {
  const UserPermissions({
    required this.canEdit,
    required this.canToggleActive,
    required this.canResetPassword,
    required this.canDelete,
    this.reason,
  });

  final bool canEdit;
  final bool canToggleActive;
  final bool canResetPassword;
  final bool canDelete;

  /// Kapali dugmelerin nedeni; kartta ipucu olarak gosterilir.
  final String? reason;
}

UserPermissions permissionsFor(AppUser? current, ManagedUser target) {
  if (current == null) {
    return const UserPermissions(
      canEdit: false,
      canToggleActive: false,
      canResetPassword: false,
      canDelete: false,
    );
  }

  final isSelf = current.id == target.id;
  final isSuper = current.role == 'super_admin';

  if (!isSuper && current.role != 'store_manager') {
    return const UserPermissions(
      canEdit: false,
      canToggleActive: false,
      canResetPassword: false,
      canDelete: false,
      reason: 'Kullanıcı yönetimi yetkiniz yok',
    );
  }

  // Magaza yoneticisi yalnizca kendi magazasindaki kullanicilara dokunabilir.
  if (!isSuper && target.storeId != current.storeId) {
    return const UserPermissions(
      canEdit: false,
      canToggleActive: false,
      canResetPassword: false,
      canDelete: false,
      reason: 'Bu kullanıcı başka mağazaya bağlı',
    );
  }

  if (isSelf) {
    return UserPermissions(
      // Ana yonetici kendi adini/magazasini duzenleyebilir, rolunu degistiremez.
      canEdit: isSuper,
      canToggleActive: false,
      canResetPassword: true,
      canDelete: false,
      reason: 'Kendi hesabınızı pasife alamaz veya silemezsiniz',
    );
  }

  // Ana yonetici hesaplari silinemez.
  final targetIsSuper = target.role == 'super_admin';
  return UserPermissions(
    canEdit: true,
    canToggleActive: true,
    canResetPassword: true,
    canDelete: !targetIsSuper,
    reason: targetIsSuper ? 'Ana yönetici hesabı silinemez' : null,
  );
}

/// Bir kullanicinin atayabilecegi roller.
List<String> assignableRoles(AppUser? current) {
  if (current?.role == 'super_admin') {
    return const ['super_admin', 'store_manager', 'staff'];
  }
  return const ['store_manager', 'staff'];
}

/// Bir kullanicinin devredebilecegi yetkiler: Ana Yonetici hepsini, digerleri
/// yalnizca kendi sahip olduklarini (yetki yukseltmesi olmasin). Sunucu ayni
/// kurali uyguluyor; buradaki liste onay kutularini kilitlemek icin.
List<String> grantablePermissions(AppUser? current) {
  if (current == null) return const [];
  if (current.isSuperAdmin) return List.of(allPermissions);
  return allPermissions.where(current.permissions.contains).toList();
}

/// Kendi rolunu degistirmek yasak oldugu icin duzenleme penceresinde rol
/// alani kilitlenir.
bool roleLocked(AppUser? current, ManagedUser target) =>
    current != null && current.id == target.id;

List<ManagedUser> filterUsers(List<ManagedUser> items, String search) {
  final q = _normalize(search);
  if (q.isEmpty) return items;
  return items
      .where((u) =>
          _normalize(u.fullName).contains(q) ||
          _normalize(u.username).contains(q) ||
          _normalize(u.storeName ?? '').contains(q))
      .toList();
}

String _normalize(String value) {
  var s = value.toLowerCase();
  const map = {
    'ı': 'i', 'İ': 'i', 'ş': 's', 'Ş': 's', 'ğ': 'g', 'Ğ': 'g',
    'ç': 'c', 'Ç': 'c', 'ö': 'o', 'Ö': 'o', 'ü': 'u', 'Ü': 'u',
  };
  map.forEach((k, v) => s = s.replaceAll(k, v));
  return s;
}
