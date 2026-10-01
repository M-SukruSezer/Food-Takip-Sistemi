import 'dart:convert';

import 'package:image/image.dart' as img;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodtakip/core/api_client.dart';
import 'package:foodtakip/core/logout.dart';
import 'package:foodtakip/core/login_branding.dart';
import 'package:foodtakip/core/session.dart';
import 'package:foodtakip/core/tokens.dart';
import 'package:foodtakip/models/batch.dart';
import 'package:foodtakip/models/daily_report.dart';
import 'package:foodtakip/screens/batch_dialogs.dart';
import 'package:foodtakip/screens/daily_report_dialogs.dart';
import 'package:foodtakip/screens/login_screen.dart';
import 'package:foodtakip/widgets/dialogs.dart';
import 'package:foodtakip/widgets/notification_bell.dart';
import 'package:foodtakip/widgets/login_branding_editor.dart';

import 'support/fake_api.dart';

final batchJson = <String, dynamic>{
  'id': 1,
  'product_name': 'YABAN MERSİNLİ MUFFIN',
  'quantity': 3,
  'remaining': 1,
  'status': 'food_cabinet',
  'skt_days': 3,
  'entered_frozen_at': '2026-09-24T14:36:00Z',
  'thawing_started_at': '2026-09-25T08:12:00Z',
  'thawing_finish_at': '2026-09-25T16:12:00Z',
  'food_cabinet_entered_at': '2026-09-25T08:16:00Z',
  'skt_end': '2026-09-28T08:16:00Z',
  'sales': [
    for (var i = 0; i < 2; i++)
      {
        'id': i + 1,
        'sold_at': '2026-09-26T19:12:00Z',
        'quantity': 1,
        'unit_price': 155,
      },
  ],
};
final reportFields = ReportFields.fromJson({
  'entry': [
    {'key': 'net_sales', 'label': 'Net Sales (Ciro)', 'type': 'money'},
    {'key': 'adt', 'label': 'ADT (Fiş Sayısı)', 'type': 'int'},
    {'key': 'product_qty', 'label': 'Product Qty', 'type': 'int'},
    {'key': 'sold_beverage_qty', 'label': 'Sold Beverage', 'type': 'int'},
    {'key': 'modifiers', 'label': 'Modifiers', 'type': 'int'},
    {'key': 'app_amount', 'label': 'App (Mobil Sipariş)', 'type': 'money'},
  ],
  'system': [
    {'key': 'food_usd', 'label': 'FOOD USD', 'type': 'int'},
    {'key': 'food_usd_try', 'label': 'FOOD USD ₺', 'type': 'money'},
    {'key': 'food_mo_try', 'label': 'FOOD MO ₺', 'type': 'money'},
  ],
});

void main() {
  late HttpClientAdapter original;
  setUpAll(() async {
    final font = FontLoader('Roboto')
      ..addFont(
        File('assets/fonts/NotoSans-Regular.ttf')
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    initTestFormatting();
    SharedPreferences.setMockInitialValues({});
    original = api.dio.httpClientAdapter;
    signInAs('store_manager', storeId: 1);
    loginArtwork.value = null;
    installFakeApi({
      'GET /batches/1': batchJson,
      'GET /branding/login': {'image': null},
    });
  });
  tearDown(() async {
    api.dio.httpClientAdapter = original;
    await session.signOut();
  });

  Future<void> open(
    WidgetTester tester,
    void Function(BuildContext) action, {
    double width = 390,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(brightness),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => action(context),
                child: const Text('Aç'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();
  }

  test(
    'giriş görseli oranı korunarak küçültülür ve bozuk dosya reddedilir',
    () {
      final source = img.Image(width: 1600, height: 800);
      final encoded = encodeLoginArtwork(img.encodePng(source));
      final decoded = img.decodeJpg(base64Decode(encoded.split(',').last))!;
      expect(decoded.width, 1280);
      expect(decoded.height, 640);
      expect(encoded.length, lessThanOrEqualTo(900000));
      expect(() => encodeLoginArtwork(Uint8List(3)), throwsFormatException);
    },
  );

  testWidgets('ürün detayı mobil panelde görünür', (tester) async {
    await open(
      tester,
      (context) => showBatchDetail(context, Batch.fromJson(batchJson)),
    );
    expect(find.text('Satış Geçmişi'), findsOneWidget);
    expect(find.text('2 İşlem'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/product_detail.png'),
    );
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    expect(find.text('Satış Geçmişi'), findsNothing);
  });
  testWidgets('düzeltme SKT alanını kilitler ve geçersiz adedi göndermez', (
    tester,
  ) async {
    final api = installFakeApi({});
    await open(
      tester,
      (context) => showAdjustDialog(context, Batch.fromJson(batchJson)),
    );
    expect(
      tester
          .widgetList<DateTimeField>(find.byType(DateTimeField))
          .last
          .onChanged,
      isNull,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/adjust_batch.png'),
    );
    await tester.enterText(find.byType(TextField).last, '9');
    await tester.tap(find.text('Düzeltmeyi Kaydet'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Kalan adet toplam adetten büyük olamaz (toplam:'),
      findsOneWidget,
    );
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('günlük rapor sabit kaydet düğmesi ve dar ekran', (tester) async {
    await open(
      tester,
      (context) => showDailyReportDialog(
        context,
        fields: reportFields,
        initialDate: DateTime(2026, 9, 29, 2, 59),
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/daily_report.png'),
    );
    tester.view.physicalSize = const Size(320, 640);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(find.text('Kaydet')).dy, lessThan(401));
    expect(tester.takeException(), isNull);
  });
  testWidgets('çıkış onayında vazgeçmek oturumu korur', (tester) async {
    await open(tester, confirmSignOut);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/logout.png'),
    );
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(session.user, isNotNull);
  });
  testWidgets('bildirimler kişi ve tarihi ayrı gösterir', (tester) async {
    final fake = installFakeApi({
      'GET /pdks/notifications': {
        'unread': 1,
        'items': [
          {
            'id': 1,
            'title': 'Haftalık vardiya planı paylaşıldı',
            'body': '2026-09-28 – 2026-10-04 haftası: 6 çalışma günü, 1 tatil Paylaşan: MUHAMMED ŞÜKRÜ SEZER.',
            'created_at': '2026-09-29T04:14:00Z',
            'read': false,
          },
          {
            'id': 2,
            'title': 'Çalışma planınız güncellendi',
            'body':
                '3 günün vardiyası değişti. Değiştiren: MUHAMMED ŞÜKRÜ SEZER.',
            'created_at': '2026-09-27T15:48:00Z',
            'read': true,
          },
        ],
      },
      'POST /pdks/notifications/read-all': {'ok': true},
    });
    await open(tester, showNotificationSheet);
    expect(find.text('1 Yeni'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/notifications.png'),
    );
    await tester.tap(find.text('Tümünü okundu işaretle'));
    await tester.pumpAndSettle();
    expect(fake.called('POST /pdks/notifications/read-all'), isTrue);
  });
  testWidgets('login mobil görünümü', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        home: const LoginScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/colombia_cafe.png'),
        tester.element(find.byType(LoginScreen)),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/login.png'),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('görsel varsayılana döndürülebilir ve sunucuya kaydedilir', (
    tester,
  ) async {
    final fake = installFakeApi({
      'GET /branding/login': {'image': null},
      'PUT /branding/login': {'image': null},
    });
    await tester.pumpWidget(host(const LoginBrandingEditor()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Varsayılan Görsele Dön'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Görseli Kaydet'));
    await tester.pumpAndSettle();
    expect(fake.lastBody('PUT /branding/login'), {'image': null});
    expect(find.text('Görseli Kaydet'), findsNothing);
  });
}
