import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/user_rules.dart';
import 'package:foodtakip/models/store.dart';
import 'package:foodtakip/models/user.dart';

AppUser _user(int id, String role, {int? storeId, List<int> storeIds = const []}) => AppUser(
      id: id,
      username: 'u$id',
      fullName: 'User $id',
      role: role,
      storeId: storeId,
      storeIds: storeIds,
    );

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
      final p = permissionsFor(_user(1, 'super_admin'), _managed(2, 'barista', storeId: 5));
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

    test('aynı kademedeki hesap yönetilemez', () {
      // Kural degisti: artik yalnizca KENDINDEN ASAGI kademedekiler yonetilir,
      // bu yuzden bir Ana Yonetici baska bir Ana Yoneticiye dokunamaz.
      final p = permissionsFor(_user(1, 'super_admin'), _managed(2, 'super_admin'));
      expect(p.canDelete, isFalse);
      expect(p.canEdit, isFalse);
      expect(p.reason, 'Bu kullanıcı sizinle aynı ya da üst kademede');
    });

    test('üst kademe alt kademeyi yönetir, tersi olmaz', () {
      // Cok magazali rolde yetki atanan magazalardan gelir.
      final ops = _user(1, 'operations_manager', storeIds: const [4]);
      expect(permissionsFor(ops, _managed(2, 'store_manager', storeId: 4)).canEdit, isTrue);

      // Atanmamis magazadaki kullaniciya dokunamaz.
      expect(permissionsFor(ops, _managed(5, 'store_manager', storeId: 9)).canEdit, isFalse);

      final sm = _user(3, 'store_manager', storeId: 4);
      expect(permissionsFor(sm, _managed(1, 'operations_manager')).canEdit, isFalse);
      expect(permissionsFor(sm, _managed(9, 'shift_supervisor', storeId: 4)).canEdit, isTrue);
    });

    test('magaza yoneticisi baska magazanin kullanicisina dokunamaz', () {
      final p = permissionsFor(
        _user(1, 'store_manager', storeId: 3),
        _managed(2, 'barista', storeId: 4),
      );
      expect(p.canEdit, isFalse);
      expect(p.canToggleActive, isFalse);
      expect(p.canResetPassword, isFalse);
      expect(p.canDelete, isFalse);
    });

    test('magaza yoneticisi kendi magazasindaki personeli yonetir', () {
      final p = permissionsFor(
        _user(1, 'store_manager', storeId: 3),
        _managed(2, 'barista', storeId: 3),
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
      final p = permissionsFor(_user(1, 'barista', storeId: 3), _managed(2, 'barista', storeId: 3));
      expect(p.canEdit, isFalse);
      expect(p.canResetPassword, isFalse);
    });
  });

  group('assignableRoles', () {
    test('ana yonetici kendisi haric her rolu atar', () {
      final roles = assignableRoles(_user(1, 'super_admin'));
      expect(roles, containsAll(<String>[
        'operations_manager', 'regional_manager',
        'store_manager', 'shift_supervisor', 'barista',
      ]));
      // Kendi kademesini atayamaz.
      expect(roles, isNot(contains('super_admin')));
    });

    test('store manager yalnizca kendi altini olusturur', () {
      final roles = assignableRoles(_user(1, 'store_manager', storeId: 2));
      expect(roles, ['shift_supervisor', 'barista']);
    });
  });

  test('roleLocked yalnizca kendi kaydinda acik', () {
    final me = _user(4, 'super_admin');
    expect(roleLocked(me, _managed(4, 'super_admin')), isTrue);
    expect(roleLocked(me, _managed(5, 'barista')), isFalse);
  });

  group('filterUsers', () {
    final items = [
      _managed(1, 'barista', name: 'Şükrü Şen'),
      _managed(2, 'barista', name: 'Ali Gündüz'),
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
