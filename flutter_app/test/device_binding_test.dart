import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/api_client.dart';
import 'package:foodtakip/core/device_identity.dart';
import 'package:foodtakip/models/store.dart';
import 'package:foodtakip/screens/requests_screen.dart';
import 'package:foodtakip/screens/users_screen.dart';
import 'package:foodtakip/widgets/panels.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

// Hesap-telefon eslestirmesi (istemci tarafi): cihaz kimligi her istekte
// gider, bloke yaniti oturumu dusurur, yonetici blokeyi kaldirir/sifirlar.

final _bloke = {
  'id': 7,
  'username': 'ayse',
  'full_name': 'Ayşe Yılmaz',
  'role': 'barista',
  'active': 1,
  'store_id': 4,
  'store_name': 'Merkez',
  'device_bound': true,
  'device_name': 'samsung SM-A515F',
  'device_blocked': true,
  'device_blocked_at': '2026-10-02T06:10:00.000Z',
  'blocked_device_name': 'Xiaomi 2201117TG',
};

/// Her istege verilen durum ve govdeyle yanit veren; basliklari saklayan
/// adaptor.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final Object body;
  final List<Map<String, dynamic>> headers = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    headers.add(Map.of(options.headers));
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    initTestFormatting();
    SharedPreferences.setMockInitialValues({});
  });

  group('Cihaz kimligi', () {
    test(
      'kanal yoksa kalici yedek kimlik uretilir ve isteklere eklenir',
      () async {
        final a = DeviceIdentity();
        await a.load();
        expect(a.id, startsWith('u:'));
        // Ikinci yukleme ayni kimligi verir (uygulama yeniden acildi).
        final b = DeviceIdentity();
        await b.load();
        expect(b.id, a.id);

        await deviceIdentity.load();
        final client = ApiClient();
        final adapter = _Adapter(200, {'ok': true});
        client.dio.httpClientAdapter = adapter;
        await client.dio.get<Object>(
          '/x',
          options: Options(extra: {'silent': true}),
        );
        expect(adapter.headers.single['X-Device-Id'], deviceIdentity.id);
      },
    );

    test('bloke yaniti oturumu dusurur, baska 403 dusurmez', () async {
      final client = ApiClient();
      var dustu = 0;
      client.onUnauthorized = () => dustu++;

      client.dio.httpClientAdapter = _Adapter(403, {
        'error': 'Hesabınız bloke edildi',
        'code': 'DEVICE_BLOCKED',
      });
      await expectLater(
        client.dio.get<Object>('/x', options: Options(extra: {'silent': true})),
        throwsA(isA<DioException>()),
      );
      expect(dustu, 1);

      client.dio.httpClientAdapter = _Adapter(403, {'error': 'Yetkiniz yok'});
      await expectLater(
        client.dio.get<Object>('/x', options: Options(extra: {'silent': true})),
        throwsA(isA<DioException>()),
      );
      expect(dustu, 1);
    });
  });

  test('kullanici modeli cihaz alanlarini okur', () {
    final u = ManagedUser.fromJson(_bloke);
    expect(u.deviceBound, isTrue);
    expect(u.deviceBlocked, isTrue);
    expect(u.deviceName, 'samsung SM-A515F');
    expect(u.blockedDeviceName, 'Xiaomi 2201117TG');
    final yeni = ManagedUser.fromJson({'id': 1, 'role': 'barista'});
    expect(yeni.deviceBound, isFalse);
    expect(yeni.deviceBlocked, isFalse);
  });

  group('Kullanıcılar: bloke hesap', () {
    testWidgets('uyari gorunur; yonetici blokeyi kaldirir ve cihazi sifirlar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = installFakeApi({
        'GET /users': [_bloke],
        'GET /users/templates': const <Object>[],
        'GET /stores': const <Object>[],
        'POST /users/7/device/unblock': {'ok': true},
        'POST /users/7/device/reset': {'ok': true},
      });
      signInAs('store_manager', storeId: 4);
      await tester.pumpWidget(host(const UsersScreen()));
      await tester.pumpAndSettle();

      expect(find.text('bloke'), findsOneWidget);
      expect(find.textContaining('Xiaomi 2201117TG'), findsOneWidget);
      expect(find.text('Telefon: samsung SM-A515F'), findsOneWidget);

      await tester.tap(find.text('Blokeyi Kaldır').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaldır'));
      await tester.pumpAndSettle();
      expect(api.called('POST /users/7/device/unblock'), isTrue);

      await tester.tap(find.text('Cihazı Sıfırla').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sıfırla'));
      await tester.pumpAndSettle();
      expect(api.called('POST /users/7/device/reset'), isTrue);
    });
  });

  testWidgets('Taleplerim: tek yuzen Talep Olustur, kutular tek sirada', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    installFakeApi({
      'GET /pdks/requests': const <Object>[],
      'GET /pdks/requests/balances': {
        'leave': {'remaining_days': 12, 'entitled_days': 14, 'used_days': 2},
      },
    });
    signInAs('barista', storeId: 4);
    await tester.pumpWidget(host(const RequestsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Talep Oluştur'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Talep Oluştur'),
        matching: find.byType(FloatingActionButton),
      ),
      findsOneWidget,
    );
    expect(find.text('Yeni Talep Oluştur'), findsNothing);
    expect(find.text('Yeni Talep'), findsNothing);

    final kutular = find.byType(StatCard);
    expect(kutular, findsNWidgets(3));
    final tops = {
      for (var i = 0; i < 3; i++) tester.getRect(kutular.at(i)).top,
    };
    expect(tops.length, 1, reason: 'üç kutu aynı satırda');
  });
}
