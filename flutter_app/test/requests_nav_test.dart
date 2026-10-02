import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/nav.dart';
import 'package:foodtakip/models/pdks.dart';
import 'package:foodtakip/models/user.dart';
import 'package:foodtakip/screens/requests_screen.dart';

AppUser _user(String role) =>
    AppUser(id: 1, username: role, fullName: 'Test', role: role, storeId: 1);

void main() {
  test(
    'Taleplerim yalnızca baristada, alt barda QR’ın sağında (3. kısayol)',
    () {
      final bar = bottomBarFor(_user('barista'), AppSection.pdks);
      expect(bar.map((i) => i.path).toList(), [
        '/pdks',
        '/roster',
        '/requests',
      ]);
      // Alt bar ilk iki kısayolu QR'ın soluna, kalanları sağına koyar.
      expect(bar.skip(2).first.path, '/requests');

      for (final role in ['store_manager', 'shift_supervisor', 'super_admin']) {
        final paths = navFor(_user(role)).map((i) => i.path);
        expect(paths, isNot(contains('/requests')), reason: role);
      }
    },
  );

  test('PIN Doğrulama yalnızca mağaza müdürü ve vardiya sorumlusunda', () {
    for (final role in ['store_manager', 'shift_supervisor']) {
      expect(navFor(_user(role)).map((i) => i.path), contains('/pin'));
    }
    for (final role in ['barista', 'store', 'super_admin']) {
      expect(navFor(_user(role)).map((i) => i.path), isNot(contains('/pin')));
    }
  });

  test('yeni talep türlerinin etiketi ve özeti', () {
    final takas = PersonnelRequest.fromJson({
      'id': 1,
      'type': 'VARDIYA_TAKAS',
      'status': 'PENDING',
      'reason': 'x',
      'shift_date': '2026-10-05',
      'target_shift_date': '2026-10-06',
      'target_user_id': 2,
    });
    expect(takas.typeLabel, 'Vardiya Takası');
    expect(takas.awaitsTarget, isTrue);
    expect(takas.statusLabel, 'Karşı Taraf Onayı');
    expect(requestSummary(takas), 'Pzt 05.10 ↔ Sal 06.10 vardiyaları');

    final rapor = PersonnelRequest.fromJson({
      'id': 2,
      'type': 'RAPOR',
      'status': 'PENDING',
      'reason': '',
      'start_at': '2026-10-05',
      'end_at': '2026-10-07',
      'days': 3,
      'has_attachment': true,
    });
    expect(rapor.hasAttachment, isTrue);
    expect(rapor.statusLabel, 'Müdür Onayında');

    final off = PersonnelRequest.fromJson({
      'id': 3,
      'type': 'HAFTALIK_OFF',
      'status': 'APPROVED',
      'reason': '',
      'shift_date': '2026-10-08',
      'target_shift_date': '2026-10-09',
    });
    expect(requestSummary(off), 'OFF günü Cum 09.10 → Per 08.10');
  });

  test('mesai yönlendirmesi yalnızca Operasyon sayfalarında', () {
    expect(isOperationsPath('/dashboard'), isTrue);
    expect(isOperationsPath('/sales'), isTrue);
    for (final p in ['/pdks', '/roster', '/pin', '/requests', '/profile']) {
      expect(isOperationsPath(p), isFalse, reason: p);
    }
  });
}
