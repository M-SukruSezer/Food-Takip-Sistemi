import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/api_client.dart';
import 'package:foodtakip/core/avatar_image.dart';
import 'package:foodtakip/core/nav.dart';
import 'package:foodtakip/core/session.dart';
import 'package:foodtakip/screens/petty_cash_screen.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

Map<String, Object?> _page({num limit = 500, num spent = 120.5, List<Object>? items}) => {
      'items': items ??
          [
            {
              'id': 1, 'store_id': 1, 'amount': 120.5, 'description': 'Temizlik malzemesi',
              'spent_at': '2026-09-22T10:00:00.000Z', 'has_receipt': true,
              'created_by_name': 'Şükrü Sezer', 'store_name': 'Merkez',
            },
          ],
      'status': {
        'store_id': 1, 'weekly_limit': limit, 'spent_this_week': spent,
        'remaining': limit - spent, 'week_start': '2026-09-21T00:00:00.000Z',
      },
    };

Uint8List _photo(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(x, y, (x * 7) % 256, (y * 13) % 256, (x * y) % 256);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late HttpClientAdapter original;

  setUp(() {
    initTestFormatting();
    SharedPreferences.setMockInitialValues({});
    original = api.dio.httpClientAdapter;
  });

  tearDown(() async {
    api.dio.httpClientAdapter = original;
    await session.signOut();
  });

  group('Fiş görseli sıkıştırma', () {
    final pattern = RegExp(r'^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$');

    test('büyük foto sunucu sınırının altına iner', () {
      final url = encodeReceipt(_photo(3000, 2200));
      expect(pattern.hasMatch(url), isTrue);
      expect(url.length, lessThanOrEqualTo(receiptMaxChars));
    });

    test('uzun kenar 1280 pikseli aşmaz ve oran korunur', () {
      final url = encodeReceipt(_photo(3000, 1500));
      final decoded = img.decodeJpg(base64Decode(url.split(',').last))!;
      expect(decoded.width, 1280);
      // Fis kare kirpilmaz; tamami okunabilir kalmali.
      expect(decoded.height, closeTo(640, 2));
    });

    test('bozuk dosya anlaşılır hata verir', () {
      expect(() => encodeReceipt(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<FormatException>()));
    });
  });

  group('Petty Cash ekranı', () {
    testWidgets('haftalık limit durumu gösterilir', (tester) async {
      installFakeApi({'GET /petty-cash': _page()});
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(host(const PettyCashScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Bu Hafta'), findsOneWidget);
      expect(find.text('120,50 TL / 500,00 TL'), findsOneWidget);
      expect(find.text('Kalan: 379,50 TL'), findsOneWidget);
      expect(find.text('Temizlik malzemesi'), findsOneWidget);
      expect(find.text('fişli'), findsOneWidget);
    });

    testWidgets('limit tanımsızsa uyarı çıkar', (tester) async {
      installFakeApi({'GET /petty-cash': _page(limit: 0, spent: 0, items: const [])});
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(host(const PettyCashScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('haftalık petty cash limiti tanımlanmamış'), findsOneWidget);
    });

    testWidgets('masraf girişi yalnızca iki rolde açık', (tester) async {
      for (final rol in ['store_manager', 'shift_supervisor']) {
        installFakeApi({'GET /petty-cash': _page()});
        signInAs(rol, storeId: 1);
        await tester.pumpWidget(host(const PettyCashScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Masraf Ekle'), findsOneWidget, reason: '$rol giriş yapabilmeli');
      }

      // Ust kademeler izler ama giremez.
      for (final rol in ['super_admin', 'operations_manager', 'regional_manager']) {
        installFakeApi({'GET /petty-cash': _page(), 'GET /petty-cash/limits': const <Object>[]});
        signInAs(rol, storeId: 1);
        await tester.pumpWidget(host(const PettyCashScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Masraf Ekle'), findsNothing, reason: '$rol giriş yapamamalı');
      }
    });

    testWidgets('limit %85 üstündeyken uyarı rengine döner', (tester) async {
      installFakeApi({'GET /petty-cash': _page(limit: 100, spent: 90)});
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(host(const PettyCashScreen()));
      await tester.pumpAndSettle();

      final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(bar.value, closeTo(0.9, 0.001));
      expect(find.text('Kalan: 10,00 TL'), findsOneWidget);
    });
  });

  test('menüde Petty Cash barista dışındaki rollerde görünür', () {
    final item = navItems.firstWhere((i) => i.path == '/petty-cash');
    expect(item.roles, contains('store_manager'));
    expect(item.roles, contains('shift_supervisor'));
    expect(item.roles, contains('super_admin'));
    expect(item.roles, isNot(contains('barista')));
  });
}
