import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/api_client.dart';
import 'package:foodtakip/core/session.dart';
import 'package:foodtakip/screens/product_types_screen.dart';
import 'package:foodtakip/screens/stores_screen.dart';
import 'package:foodtakip/screens/users_screen.dart';
import 'package:foodtakip/widgets/crud_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

final _productTypes = [
  {'id': 1, 'name': 'Çikolatalı Pasta', 'skt_days': 3, 'unit_price': 250, 'active': 1, 'store_id': null},
  {'id': 2, 'name': 'Poğaça', 'skt_days': 2, 'unit_price': null, 'active': 1, 'store_id': 4, 'store_name': 'Merkez'},
  {'id': 3, 'name': 'Eski Ürün', 'skt_days': 5, 'unit_price': 100, 'active': 0, 'store_id': null},
];

final _stores = [
  {'id': 4, 'name': 'Merkez', 'active': 1, 'address': 'Atatürk Cad. 1', 'phone': '0212 000 00 00',
   'user_count': 3, 'active_batch_count': 12},
  {'id': 5, 'name': 'Şube', 'active': 0, 'address': null, 'phone': null,
   'user_count': 0, 'active_batch_count': 0},
];

final _users = [
  {'id': 1, 'username': 'test', 'full_name': 'Test Kullanici', 'role': 'super_admin', 'active': 1, 'store_id': null},
  {'id': 2, 'username': 'ayse', 'full_name': 'Ayşe Çiftçi', 'role': 'store_manager', 'active': 1,
   'store_id': 4, 'store_name': 'Merkez'},
  {'id': 3, 'username': 'ali', 'full_name': 'Ali Gündüz', 'role': 'staff', 'active': 0,
   'store_id': 4, 'store_name': 'Merkez'},
];

void main() {
  late FakeAdapter adapter;
  late HttpClientAdapter original;

  setUp(() {
    initTestFormatting();
    SharedPreferences.setMockInitialValues({});
    original = api.dio.httpClientAdapter;
    adapter = installFakeApi({
      'GET /product-types': _productTypes,
      'GET /stores': _stores,
      'GET /users': _users,
    });
  });

  tearDown(() async {
    api.dio.httpClientAdapter = original;
    await session.signOut();
  });

  group('Pasta Çeşitleri', () {
    testWidgets('liste, fiyat ve fiyatsız çeşit uyarısı gösterilir', (tester) async {
      signInAs('super_admin');
      await tester.pumpWidget(host(const ProductTypesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Çikolatalı Pasta'), findsOneWidget);
      expect(find.text('250,00 TL'), findsOneWidget);
      // Fiyati olmayan aktif cesit hem kartta hem uyaride gorunur.
      expect(find.text('Fiyat yok'), findsOneWidget);
      expect(
        find.textContaining('1 aktif çeşidin satış fiyatı tanımlı değil'),
        findsOneWidget,
      );
      // Pasif cesit etiketlenir.
      expect(find.text('pasif'), findsOneWidget);
      expect(find.text('SKT: 3 gün'), findsOneWidget);
    });

    testWidgets('ana yönetici düzenleyebilir, mağaza yöneticisi yalnızca görür', (tester) async {
      signInAs('super_admin');
      await tester.pumpWidget(host(const ProductTypesScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Yeni Çeşit'), findsOneWidget);
      expect(find.text('Düzenle'), findsNWidgets(3));

      signInAs('store_manager', storeId: 4);
      adapter.calls.clear();
      await tester.pumpWidget(host(const ProductTypesScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Yeni Çeşit'), findsNothing);
      expect(find.text('Düzenle'), findsNothing);
      expect(find.text('Sil'), findsNothing);
      // Magaza listesi super_admin'e kapali oldugu icin hic istenmez.
      expect(adapter.calls.where((c) => c == 'GET /stores'), isEmpty);
    });

    testWidgets('düzenleme penceresi mevcut değerlerle açılır', (tester) async {
      signInAs('super_admin');
      await tester.pumpWidget(host(const ProductTypesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Düzenle').first);
      await tester.pumpAndSettle();

      expect(find.text('Çeşidi Düzenle'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Çikolatalı Pasta'), findsOneWidget);
      expect(find.widgetWithText(TextField, '250'), findsOneWidget);
      // Fiyat alaninin ciro etkisi kullaniciya yaziyla anlatilir.
      expect(find.textContaining('ciro bu fiyattan otomatik hesaplanır'), findsOneWidget);
    });

    testWidgets('boş ürün adı sunucuya gitmeden reddedilir', (tester) async {
      signInAs('super_admin');
      await tester.pumpWidget(host(const ProductTypesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Yeni Çeşit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      expect(find.text('Ürün adı zorunludur'), findsOneWidget);
      expect(adapter.calls.where((c) => c.startsWith('POST')), isEmpty);
    });

    testWidgets('SKT süresi 1-14 aralığı dışında reddedilir', (tester) async {
      signInAs('super_admin');
      await tester.pumpWidget(host(const ProductTypesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Yeni Çeşit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Deneme');
      await tester.enterText(find.byType(TextField).at(1), '30');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      expect(find.text('SKT süresi 1-14 gün arasında olmalıdır'), findsOneWidget);
      expect(adapter.calls.where((c) => c.startsWith('POST')), isEmpty);
    });
  });

  group('Mağazalar', () {
    testWidgets('sayaçlar gösterilir, bağlı kaydı olan mağaza silinemez', (tester) async {
      signInAs('super_admin');
      await tester.pumpWidget(host(const StoresScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Merkez'), findsOneWidget);
      expect(find.text('3 personel'), findsOneWidget);
      expect(find.text('12 aktif ürün'), findsOneWidget);
      expect(find.text('Adres girilmemiş'), findsOneWidget);

      final buttons = tester.widgetList<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Sil'));
      // Merkez'in kaydi var -> kapali; Sube bos -> acik.
      expect(buttons.map((b) => b.onPressed != null).toList(), [false, true]);
    });

    testWidgets('yeni mağaza penceresinde aktiflik anahtarı çıkmaz', (tester) async {
      signInAs('super_admin');
      await tester.pumpWidget(host(const StoresScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Yeni Mağaza'));
      await tester.pumpAndSettle();
      // Sunucu POST /stores govdesinde active almiyor.
      expect(find.byType(SwitchListTile), findsNothing);

      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Düzenle').first);
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsOneWidget);
    });
  });

  group('Kullanıcılar', () {
    testWidgets('roller ve mağaza etiketleri listelenir', (tester) async {
      signInAs('super_admin');
      await tester.pumpWidget(host(const UsersScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Ayşe Çiftçi'), findsOneWidget);
      expect(find.text('@ali'), findsOneWidget);
      expect(find.text('Ana Yönetici'), findsOneWidget);
      expect(find.text('Tüm mağazalar'), findsOneWidget);
      expect(find.text('Mağaza Yöneticisi'), findsOneWidget);
      // Pasif kullanici hem etiketle hem aktifleştirme dugmesiyle ayrisir.
      expect(find.text('pasif'), findsOneWidget);
      expect(find.text('Aktifleştir'), findsOneWidget);
    });

    testWidgets('kendi hesabında pasife alma ve silme kapalıdır', (tester) async {
      signInAs('super_admin');
      await tester.pumpWidget(host(const UsersScreen()));
      await tester.pumpAndSettle();

      // Ilk kart oturumdaki kullanici (id 1).
      final toggles = tester
          .widgetList<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Pasife Al'))
          .toList();
      expect(toggles.first.onPressed, isNull);
      final deletes = tester
          .widgetList<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Sil'))
          .toList();
      expect(deletes.first.onPressed, isNull);
      // Baskalarinin kaydinda acik.
      expect(deletes[1].onPressed, isNotNull);
      expect(find.textContaining('Kendi hesabınızı pasife alamaz'), findsOneWidget);
    });

    testWidgets('mağaza yöneticisi ana yönetici rolü atayamaz', (tester) async {
      signInAs('store_manager', storeId: 4);
      await tester.pumpWidget(host(const UsersScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Yeni Kullanıcı'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      expect(find.text('Ana Yönetici').hitTestable(), findsNothing);
      expect(find.text('Personel').hitTestable(), findsWidgets);
    });

    testWidgets('kısa şifre sunucuya gitmeden reddedilir', (tester) async {
      signInAs('super_admin');
      await tester.pumpWidget(host(const UsersScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Şifre').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '123');
      await tester.enterText(find.byType(TextField).at(1), '123');
      await tester.tap(find.text('Şifreyi Kaydet'));
      await tester.pumpAndSettle();

      expect(find.text('Şifre en az 6 karakter olmalıdır'), findsOneWidget);
      expect(adapter.calls.where((c) => c.startsWith('POST')), isEmpty);
    });

    testWidgets('birbirinden farklı şifreler reddedilir', (tester) async {
      signInAs('super_admin');
      await tester.pumpWidget(host(const UsersScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Şifre').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'gizli123');
      await tester.enterText(find.byType(TextField).at(1), 'gizli124');
      await tester.tap(find.text('Şifreyi Kaydet'));
      await tester.pumpAndSettle();

      expect(find.text('Şifreler birbiriyle aynı değil'), findsOneWidget);
      expect(adapter.calls.where((c) => c.startsWith('POST')), isEmpty);
    });
  });

  group('Telefon yerleşimi', () {
    testWidgets('kartlar tek kolona düşer ve dokunma hedefleri 44px', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      signInAs('super_admin');
      await tester.pumpWidget(host(const StoresScreen()));
      await tester.pumpAndSettle();

      // Iki kart yan yana degil, alt alta ve tam genislikte durur.
      final first = tester.getRect(find.text('Merkez'));
      final second = tester.getRect(find.text('Şube'));
      expect(second.top, greaterThan(first.bottom));

      final cards = find.byType(Card);
      final widths = tester.widgetList<Card>(cards).map((c) => tester.getSize(find.byWidget(c)).width);
      for (final w in widths) {
        // Ekran 390, sayfa kenar boslugu 2x12 -> 366.
        expect(w, closeTo(366, 1));
      }

      for (final size in tester
          .widgetList<OutlinedButton>(find.byType(OutlinedButton))
          .map((b) => tester.getSize(find.byWidget(b)))) {
        expect(size.height, greaterThanOrEqualTo(44.0));
      }
    });
  });

  group('Izgara kolon sayisi', () {
    test('telefon tek kolon', () {
      expect(gridColumnsFor(390), 1);
      expect(gridColumnsFor(640), 1);
    });

    test('tablet iki kolon', () {
      // Tablet dikey (768) ve kucuk yatay: uc kolonda kartlar sikisiyordu.
      expect(gridColumnsFor(641), 2);
      expect(gridColumnsFor(768), 2);
      expect(gridColumnsFor(899), 2);
    });

    test('masaustu uc, genis ekran dort kolon', () {
      expect(gridColumnsFor(900), 3);
      expect(gridColumnsFor(1199), 3);
      expect(gridColumnsFor(1200), 4);
      expect(gridColumnsFor(1920), 4);
    });
  });

}
