import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/format.dart';
import 'package:foodtakip/core/nav.dart';

import 'support/fake_api.dart';

/// Rol → alan ayrımı. Sunucudaki ROLE_AREAS ile aynı kural:
///   mağaza hesabı yalnızca Operasyon & Denetim, barista yalnızca PDKS & Kadro.
void main() {
  Set<AppSection> alanlar(String role) =>
      sectionsFor(testUser(role, storeId: 1)).map((s) => s.id).toSet();

  test('mağaza hesabı yalnızca operasyon alanını görür', () {
    expect(alanlar('store'), {AppSection.operations});
    final yollar = navFor(testUser('store', storeId: 1)).map((i) => i.path);
    expect(yollar, containsAll(['/dashboard', '/batches', '/recommendations']));
    expect(yollar, isNot(contains('/pdks')));
    expect(yollar, isNot(contains('/roster')));
    // Kişi olmadığı için açılış ekranı operasyon.
    expect(landingPathFor(testUser('store', storeId: 1)), '/dashboard');
  });

  test('barista yalnızca PDKS & Kadro alanını görür', () {
    expect(alanlar('barista'), {AppSection.pdks});
    final yollar = navFor(testUser('barista', storeId: 1)).map((i) => i.path);
    expect(yollar, containsAll(['/pdks', '/roster']));
    for (final p in ['/dashboard', '/batches', '/recommendations', '/sales']) {
      expect(yollar, isNot(contains(p)), reason: p);
    }
    expect(landingPathFor(testUser('barista', storeId: 1)), '/pdks');
  });

  test('yönetici ve vardiya sorumlusu iki alanı da görür', () {
    for (final role in [
      'super_admin',
      'operations_manager',
      'regional_manager',
      'store_manager',
      'shift_supervisor',
    ]) {
      expect(alanlar(role), {
        AppSection.pdks,
        AppSection.operations,
      }, reason: role);
    }
  });

  test('mağaza hesabı PDKS bildirimlerini almaz', () {
    expect(isPersonnel(testUser('store', storeId: 1)), isFalse);
    expect(isPersonnel(testUser('barista', storeId: 1)), isTrue);
    expect(isPersonnel(null), isFalse);
  });

  test('rol listesi ve etiket sunucuyla aynı sırada', () {
    expect(
      roleOrder.indexOf('store'),
      roleOrder.indexOf('shift_supervisor') + 1,
    );
    expect(roleOrder.last, 'barista');
    expect(roleLabels['store'], 'Mağaza');
  });
}
