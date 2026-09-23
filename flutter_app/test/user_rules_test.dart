import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/user_rules.dart';
import 'package:foodtakip/models/store.dart';
import 'package:foodtakip/models/user.dart';

AppUser _user(int id, String role, {int? storeId}) =>
    AppUser(id: id, username: 'u$id', fullName: 'User $id', role: role, storeId: storeId);

ManagedUser _managed(int id, String role, {int? storeId, bool active = true, String? name}) =>
    ManagedUser(
      id: id,
      username: 'u$id',
      fullName: name ?? 'User $id',
      role: role,
      active: active,
      storeId: storeId,
    );

void main() {
  group('permissionsFor', () {
    test('ana yonetici baska kullaniciyi tamamen yonetir', () {
      final p = permissionsFor(_user(1, 'super_admin'), _managed(2, 'staff', storeId: 5));
      expect(p.canEdit, isTrue);
      expect(p.canToggleActive, isTrue);
      expect(p.canResetPassword, isTrue);
      expect(p.canDelete, isTrue);
    });

    test('kendi hesabi pasife alinamaz ve silinemez', () {
      final p = permissionsFor(_user(1, 'super_admin'), _managed(1, 'super_admin'));
      expect(p.canToggleActive, isFalse);
      expect(p.canDelete, isFalse);
      // Ana yonetici kendi adini duzenleyebilir, sifresini degistirebilir.
      expect(p.canEdit, isTrue);
      expect(p.canResetPassword, isTrue);
    });

    test('ana yonetici hesabi silinemez', () {
      final p = permissionsFor(_user(1, 'super_admin'), _managed(2, 'super_admin'));
      expect(p.canDelete, isFalse);
      expect(p.canEdit, isTrue);
      expect(p.reason, 'Ana yönetici hesabı silinemez');
    });

    test('magaza yoneticisi baska magazanin kullanicisina dokunamaz', () {
      final p = permissionsFor(
        _user(1, 'store_manager', storeId: 3),
        _managed(2, 'staff', storeId: 4),
      );
      expect(p.canEdit, isFalse);
      expect(p.canToggleActive, isFalse);
      expect(p.canResetPassword, isFalse);
      expect(p.canDelete, isFalse);
    });

    test('magaza yoneticisi kendi magazasindaki personeli yonetir', () {
      final p = permissionsFor(
        _user(1, 'store_manager', storeId: 3),
        _managed(2, 'staff', storeId: 3),
      );
      expect(p.canEdit, isTrue);
      expect(p.canDelete, isTrue);
    });

    test('magaza yoneticisi kendi hesabini buradan duzenleyemez', () {
      final p = permissionsFor(
        _user(7, 'store_manager', storeId: 3),
        _managed(7, 'store_manager', storeId: 3),
      );
      expect(p.canEdit, isFalse);
      expect(p.canResetPassword, isTrue);
    });

    test('personelin kullanici yonetimi yetkisi yok', () {
      final p = permissionsFor(_user(1, 'staff', storeId: 3), _managed(2, 'staff', storeId: 3));
      expect(p.canEdit, isFalse);
      expect(p.canResetPassword, isFalse);
    });
  });

  group('assignableRoles', () {
    test('ana yonetici her rolu atar', () {
      expect(assignableRoles(_user(1, 'super_admin')),
          containsAll(<String>['super_admin', 'store_manager', 'staff']));
    });

    test('magaza yoneticisi ana yonetici olusturamaz', () {
      expect(assignableRoles(_user(1, 'store_manager', storeId: 2)),
          isNot(contains('super_admin')));
    });
  });

  test('roleLocked yalnizca kendi kaydinda acik', () {
    final me = _user(4, 'super_admin');
    expect(roleLocked(me, _managed(4, 'super_admin')), isTrue);
    expect(roleLocked(me, _managed(5, 'staff')), isFalse);
  });

  group('filterUsers', () {
    final items = [
      _managed(1, 'staff', name: 'Şükrü Şen'),
      _managed(2, 'staff', name: 'Ali Gündüz'),
      _managed(3, 'store_manager', name: 'Ayşe Çiftçi'),
    ];

    test('bos arama tum listeyi doner', () {
      expect(filterUsers(items, '').length, 3);
    });

    test('Turkce karakter yazmadan da bulur', () {
      expect(filterUsers(items, 'sukru').single.id, 1);
      expect(filterUsers(items, 'gunduz').single.id, 2);
      expect(filterUsers(items, 'ciftci').single.id, 3);
    });

    test('kullanici adiyla da arar', () {
      expect(filterUsers(items, 'u2').single.id, 2);
    });
  });
}
