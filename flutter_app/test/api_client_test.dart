import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/api_client.dart';
import 'package:foodtakip/core/busy.dart';
import 'package:foodtakip/core/opts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bu testler canli API'ye gercek istek atar: dio yapilandirmasi, hata
/// eslemesi ve yukleme sayacinin simetrisi baska turlu dogrulanamiyor.
/// Yalnizca okuma ve basarisiz giris denenir; veri yazilmaz.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saglik ucu erisilebilir ve taban adres dogru', () async {
    final r = await api.dio.get<Map<String, dynamic>>(
      '/health',
      options: apiOptions(silent: true),
    );
    expect(r.statusCode, 200);
    expect(r.data?['ok'], isTrue);
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('yanlis giris sunucu mesajini dondurur', () async {
    try {
      await api.dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'username': '__test__', 'password': '__yanlis__'},
        options: apiOptions(noToast: true),
      );
      fail('401 beklenirken istek basarili oldu');
    } on DioException catch (e) {
      expect(e.response?.statusCode, 401);
      expect(errorMessage(e), 'Kullanıcı adı veya şifre hatalı');
    }
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('token olmadan korumali uc 401 doner', () async {
    try {
      await api.dio.get<List<dynamic>>(
        '/recommendations',
        options: apiOptions(noToast: true),
      );
      fail('401 beklenirken istek basarili oldu');
    } on DioException catch (e) {
      expect(e.response?.statusCode, 401);
      expect(errorMessage(e), 'Giriş yapmanız gerekiyor');
    }
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('yukleme katmani istekte acilir, bitince kapanir', () async {
    // Onceki testin 180 ms'lik birlestirme gecikmesi dolana kadar bekle:
    // sayac global oldugu icin testler birbirinin kuyrugunu yakalayabiliyor.
    for (var i = 0; i < 20 && busy.visible; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(busy.visible, isFalse, reason: 'baslangicta katman kapali olmali');

    final pending = api.dio
        .get('/auth/me', options: apiOptions(noToast: true))
        .catchError((Object _) => Response<dynamic>(
              requestOptions: RequestOptions(path: '/auth/me'),
            ));

    // dio interceptor zinciri birkac async adim sonra calisiyor; sayacin
    // acilmasini bekliyoruz. Kapanis 180 ms gecikmeli oldugu icin bir kez
    // acildiginda gozlemlenmeden kapanmasi mumkun degil.
    var acildi = false;
    for (var i = 0; i < 60 && !acildi; i++) {
      if (busy.visible) {
        acildi = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(acildi, isTrue, reason: 'istek sirasinda katman acilmali');

    await pending;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(busy.visible, isFalse, reason: 'istek bitince katman kapanmali');
  }, timeout: const Timeout(Duration(seconds: 45)));
}
