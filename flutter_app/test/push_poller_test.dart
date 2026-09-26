import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/push.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foodtakip/core/session.dart';

import 'support/fake_api.dart';

/// Bildirim yoklayicisi.
///
/// Buradaki asil risk TEKRAR: yoklayici her turda ayni bildirimleri yeniden
/// telefona dusurmemeli. Testler bu davranisi disaridan gozlemlenebilir
/// bicimde dogruluyor (kac istek atildi, ne kaydedildi).
void main() {
  setUpAll(initTestFormatting);

  Map<String, Object?> rotalar(List<Map<String, Object?>> ogeler, int unread) =>
      {
        'GET /pdks/notifications': {'unread': unread, 'items': ogeler},
      };

  Map<String, Object?> bildirim(int id, {bool read = false}) => {
    'id': id,
    'kind': 'SHIFT_PUBLISHED',
    'title': 'Haftalık vardiya planı paylaşıldı',
    'body': '2026-09-21 – 2026-09-27 haftası',
    'read': read,
    'created_at': '2026-09-26T10:00:00.000Z',
    'data': '{"screen":"/roster"}',
  };

  group('Bildirim modeli', () {
    test('data alani METIN olarak gelse de cozumleniyor', () {
      // Sunucu data'yi JSON metin olarak sakliyor; /pdks/notifications onu
      // cozup nesne donduruyor ama eski surumler metin donebilir.
      final metinden = AppNotification.fromJson(bildirim(1));
      expect(metinden.data?['screen'], '/roster');

      final nesneden = AppNotification.fromJson({
        ...bildirim(2),
        'data': {'screen': '/pdks'},
      });
      expect(nesneden.data?['screen'], '/pdks');
    });

    test('data yoksa null kalir, cokmez', () {
      final bos = AppNotification.fromJson({...bildirim(3), 'data': null});
      expect(bos.data, isNull);
      final bosMetin = AppNotification.fromJson({...bildirim(4), 'data': ''});
      expect(bosMetin.data, isNull);
    });
  });

  group('Yoklayici', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'ILK calismada gecmisi telefona DOKMUYOR, yalnizca isaret birakiyor',
      () async {
        installFakeApi(rotalar([bildirim(10), bildirim(9), bildirim(8)], 3));
        signInAs('barista', storeId: 1, id: 2);

        final p = PushPoller();
        p.start();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        p.stop();

        // Hesap acildiginda birikmis bildirimlerin hepsini bildirim merkezine
        // bosaltmak gurultu olurdu: en buyuk kimlik isaretlenip geciliyor.
        final sp = await SharedPreferences.getInstance();
        expect(sp.getInt('bildirim_son_id_2'), 10);
        expect(p.okunmamis.value, 3);
        p.dispose();
      },
    );

    test('isaretten ESKI bildirimler tekrar gosterilmiyor', () async {
      SharedPreferences.setMockInitialValues({'bildirim_son_id_2': 10});
      installFakeApi(rotalar([bildirim(10), bildirim(9)], 0));
      signInAs('barista', storeId: 1, id: 2);

      final p = PushPoller();
      p.start();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      p.stop();

      // Isaret ILERLEMEMELI: yeni bir sey yok.
      final sp = await SharedPreferences.getInstance();
      expect(sp.getInt('bildirim_son_id_2'), 10);
      p.dispose();
    });

    test('yeni bildirim gelince isaret ilerliyor', () async {
      SharedPreferences.setMockInitialValues({'bildirim_son_id_2': 10});
      installFakeApi(rotalar([bildirim(12), bildirim(11), bildirim(10)], 2));
      signInAs('barista', storeId: 1, id: 2);

      final p = PushPoller();
      p.start();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      p.stop();

      final sp = await SharedPreferences.getInstance();
      expect(sp.getInt('bildirim_son_id_2'), 12);
      expect(p.okunmamis.value, 2);
      p.dispose();
    });

    test('isaret KULLANICI BASINA ayri tutuluyor', () async {
      // Ayni telefonda baska biri giris yaptiginda onceki kullanicinin
      // okunmuslugu devralinmamali.
      SharedPreferences.setMockInitialValues({'bildirim_son_id_2': 10});
      installFakeApi(rotalar([bildirim(5)], 1));
      signInAs('store_manager', storeId: 1, id: 1);

      final p = PushPoller();
      p.start();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      p.stop();

      final sp = await SharedPreferences.getInstance();
      // Kullanici 2'nin isareti DEGISMEDI.
      expect(sp.getInt('bildirim_son_id_2'), 10);
      // Yeni kullanici icin ayri isaret olustu.
      expect(sp.getInt('bildirim_son_id_1'), isNotNull);
      p.dispose();
    });

    test('oturum yokken hic istek atmiyor', () async {
      final fake = installFakeApi(rotalar([bildirim(1)], 1));
      await session.signOut();

      final p = PushPoller();
      p.start();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      p.stop();

      expect(fake.calls, isEmpty);
      p.dispose();
    });

    test('sunucu hata verirse sessiz kaliyor ve isaret bozulmuyor', () async {
      SharedPreferences.setMockInitialValues({'bildirim_son_id_2': 7});
      // Uc tanimsiz: fake adapter 404 donuyor.
      installFakeApi(const {});
      signInAs('barista', storeId: 1, id: 2);

      final p = PushPoller();
      p.start();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      p.stop();

      final sp = await SharedPreferences.getInstance();
      expect(sp.getInt('bildirim_son_id_2'), 7);
      p.dispose();
    });
  });
}
