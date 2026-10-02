import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/api_client.dart';
import 'package:foodtakip/core/nav.dart';
import 'package:foodtakip/core/session.dart';
import 'package:foodtakip/core/tokens.dart';
import 'package:foodtakip/widgets/app_shell.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

/// Kabuk icinde her menu yoluna bos bir ekran baglanir; alt cubuk ve menu
/// gercek nav.dart tanimindan besleniyor.
Widget _shell({
  String at = '/dashboard',
  Brightness brightness = Brightness.light,
  Widget page = const SizedBox.expand(),
}) {
  final router = GoRouter(
    initialLocation: at,
    routes: [
      ShellRoute(
        builder: (c, s, child) => AppShell(child: child),
        routes: [
          for (final i in navItems)
            GoRoute(path: i.path, builder: (c, s) => page),
        ],
      ),
    ],
  );
  return MaterialApp.router(
    theme: buildAppTheme(brightness),
    routerConfig: router,
  );
}

/// AppShell 60sn'lik periyodik timer kuruyor; agac sokulup saat ilerletilmeden
/// test "bekleyen timer" diye duser.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 61));
}

List<Map<String, Object?>> _recs(List<int> remainings) => [
  for (var i = 0; i < remainings.length; i++)
    {
      'id': i + 1,
      'product_name': 'Ürün ${i + 1}',
      'remaining': remainings[i],
      'quantity': remainings[i],
      'status': 'food_cabinet',
      'urgency': 'normal',
      'remaining_hours': 50,
      'days_left': 2,
      'skt_end': '2026-09-30T10:00:00.000Z',
    },
];

void main() {
  setUpAll(() async {
    final textFont = FontLoader('Roboto')
      ..addFont(
        File('assets/fonts/NotoSans-Regular.ttf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)),
      );
    await textFont.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  late HttpClientAdapter original;

  setUp(() {
    initTestFormatting();
    SharedPreferences.setMockInitialValues({});
    original = api.dio.httpClientAdapter;
    signInAs('store_manager', storeId: 4);
  });

  tearDown(() async {
    api.dio.httpClientAdapter = original;
    await session.signOut();
  });

  Future<void> phone(WidgetTester tester, {String at = '/dashboard'}) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    installFakeApi({'GET /recommendations': _recs(const [])});
    await tester.pumpWidget(_shell(at: at));
    await tester.pumpAndSettle();
  }

  group('Alt cubuk', () {
    testWidgets('Operasyon ekraninda dort kisayol ve Menu sekmesi', (
      tester,
    ) async {
      await phone(tester);
      for (final label in [
        'Ana Sayfa',
        'Ürünler',
        'Öneri/SKT',
        'Rapor',
        'Menü',
      ]) {
        expect(find.text(label), findsWidgets, reason: '$label sekmesi yok');
      }
      // Profil gorseli alt cubuktan kalkti: yerini Menu aldi.
      expect(find.text('Profil'), findsNothing);
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('goldens/operations_navigation.png'),
      );
      await _teardown(tester);
    });

    testWidgets('PDKS ekraninda PDKS kisayollari gorunur', (tester) async {
      await phone(tester, at: '/pdks');
      expect(find.text('Devam'), findsWidgets);
      expect(find.text('Çizelge'), findsWidgets);
      expect(find.text('QR Okut'), findsOneWidget);
      expect(find.text('Yönetim'), findsWidgets);
      expect(find.text('Menü'), findsWidgets);
      // Operasyon kisayollari bu ekranda cubukta durmaz.
      expect(find.text('Ana Sayfa'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('QR menüsü kartları açar ve kapat düğmesiyle kapanır', (
      tester,
    ) async {
      await phone(tester, at: '/pdks');
      installFakeApi({
        'GET /pdks/me': {
          'is_inside': true,
          'can': {'check_out': true, 'break_start': true},
          'shifts': [
            {'break_duration_minutes': 30},
          ],
        },
      });
      await tester.tap(find.text('QR Okut'));
      await tester.pumpAndSettle();
      expect(find.text('Vardiya Giriş / Çıkış'), findsOneWidget);
      expect(find.text('Mola Giriş / Çıkış'), findsOneWidget);
      expect(find.text('AKTİF'), findsOneWidget);
      expect(find.text('30 dk'), findsOneWidget);
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('goldens/qr_action_menu.png'),
      );
      expect(find.text('Devam'), findsWidgets);
      await tester.tap(find.text('Kapat'));
      await tester.pumpAndSettle();
      expect(find.text('Vardiya Giriş / Çıkış'), findsNothing);
      expect(find.text('QR Okut'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('öneri listesindeki adet rozette görünür', (tester) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      installFakeApi({
        'GET /recommendations': _recs(const [20, 13]),
      });
      await tester.pumpWidget(_shell());
      await tester.pumpAndSettle();
      // 20 + 13 = 33 adet.
      expect(find.text('33'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('liste boşken rozet çizilmez', (tester) async {
      await phone(tester);
      expect(find.text('0'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('aktif sekmenin ikonu hap içinde, etiketi altında durur', (
      tester,
    ) async {
      await phone(tester, at: '/batches');
      final label = find.descendant(
        of: find.byKey(bottomBarKey),
        matching: find.text('Ürünler'),
      );
      final pill = find
          .ancestor(
            of: find.byIcon(Icons.view_in_ar_outlined),
            matching: find.byType(Container),
          )
          .evaluate()
          .map((e) => e.widget as Container)
          .firstWhere((c) => (c.decoration as BoxDecoration?)?.color != null);
      final decoration = pill.decoration! as BoxDecoration;
      expect(decoration.color, AppTokens.light.primarySoft);

      final pillRect = tester.getRect(find.byWidget(pill));
      final labelRect = tester.getRect(label);
      expect(pillRect.bottom, lessThanOrEqualTo(labelRect.top));
      expect(
        tester.getRect(find.byIcon(Icons.view_in_ar_outlined)).center.dx,
        labelRect.center.dx,
      );
      await _teardown(tester);
    });

    testWidgets('sekmeler dokunma hedefini korur', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      installFakeApi({'GET /recommendations': _recs(const [])});
      await tester.pumpWidget(_shell());
      await tester.pumpAndSettle();

      for (final label in [
        'Ana Sayfa',
        'Ürünler',
        'Öneri/SKT',
        'Rapor',
        'Menü',
      ]) {
        final tab = find
            .ancestor(of: find.text(label), matching: find.byType(InkWell))
            .first;
        expect(tester.getSize(tab).height, greaterThanOrEqualTo(AppTokens.tap));
      }
      await _teardown(tester);
    });
  });

  group('Alt cubuktan acilan menu', () {
    testWidgets('yan cekmece yok; menu ekranin altindan aciliyor', (
      tester,
    ) async {
      await phone(tester);
      // Cekmece hic kurulmadi: menu artik yan sekmede degil.
      expect(find.byType(Drawer), findsNothing);
      expect(find.byKey(bottomMenuSheetKey), findsNothing);

      await tester.tap(find.byKey(bottomMenuButtonKey));
      await tester.pumpAndSettle();

      final sheet = find.byKey(bottomMenuSheetKey);
      expect(sheet, findsOneWidget);
      // Yine cekmece degil.
      expect(find.byType(Drawer), findsNothing);

      // Gercek bottom sheet: tabakanin alt kenari ekran ve alt cubukla ayni
      // hizada, ortada yuzen bir kart degil.
      final sheetRect = tester.getRect(sheet);
      final barRect = tester.getRect(find.byKey(bottomBarKey));
      expect(sheetRect.bottom, barRect.bottom);
      expect(sheetRect.left, 0);
      await _teardown(tester);
    });

    testWidgets('menude alt cubuga sigmayan ogeler de var', (tester) async {
      await phone(tester);
      // Onaylar alt cubukta yok.
      expect(find.text('Onaylar'), findsNothing);

      await tester.tap(find.byKey(bottomMenuButtonKey));
      await tester.pumpAndSettle();

      // Tam etiketler menude gorunur (alt cubukta kisa etiket kullaniliyor).
      expect(find.text('Onaylar'), findsOneWidget);
      expect(find.text('Petty Cash'), findsOneWidget);
      // Cikis sabit kuyrukta: listeyi kaydirmadan erisilebiliyor.
      expect(find.text('Çıkış yap'), findsOneWidget);

      // 13 ogeli menu ekrana sigmiyor; liste kendi icinde kayiyor.
      await tester.scrollUntilVisible(
        find.text('Profilim'),
        120,
        scrollable: find
            .descendant(
              of: find.byKey(bottomMenuSheetKey),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Profilim'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets(
      'menudeki ekran secici sayfaya gitmez, yalnizca alt menuleri degistirir',
      (tester) async {
        await phone(tester);
        String yol() =>
            GoRouter.of(tester.element(find.byKey(bottomBarKey)))
                .routeInformationProvider
                .value
                .uri
                .path;

        await tester.tap(find.byKey(bottomMenuButtonKey));
        await tester.pumpAndSettle();
        expect(find.byType(SectionSwitcher), findsOneWidget);
        expect(find.text('Devam Takibi'), findsNothing);

        await tester.tap(find.text('PDKS').last);
        await tester.pumpAndSettle();

        // Menu acik kaldi, sayfa degismedi; PDKS alt menuleri listelendi.
        expect(find.byKey(bottomMenuSheetKey), findsOneWidget);
        expect(yol(), '/dashboard');
        expect(find.text('Devam Takibi'), findsOneWidget);

        // Geri Operasyon'a donmek de sayfaya gitmez.
        await tester.tap(find.text('Operasyon').last);
        await tester.pumpAndSettle();
        expect(find.byKey(bottomMenuSheetKey), findsOneWidget);
        expect(yol(), '/dashboard');
        expect(find.text('Devam Takibi'), findsNothing);

        // Sayfaya gecis ancak bir alt menu secilince olur.
        await tester.tap(find.text('PDKS').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Devam Takibi'));
        await tester.pumpAndSettle();
        expect(find.byKey(bottomMenuSheetKey), findsNothing);
        expect(yol(), '/pdks');
        await _teardown(tester);
      },
    );

    testWidgets('menuden oge secmek menuyu kapatir ve gider', (tester) async {
      await phone(tester);
      await tester.tap(find.byKey(bottomMenuButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Onaylar'));
      await tester.pumpAndSettle();

      expect(find.byKey(bottomMenuSheetKey), findsNothing);
      expect(
        GoRouter.of(tester.element(find.byKey(bottomBarKey)))
            .routeInformationProvider
            .value
            .uri
            .path,
        '/approvals',
      );
      await _teardown(tester);
    });
  });

  testWidgets(
    'sistem cubugu boslugu sayfaya ikinci kez iletilmez, icerik nefes alir',
    (tester) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 24);
      addTearDown(tester.view.reset);
      installFakeApi({'GET /recommendations': _recs(const [])});
      EdgeInsets? padding;
      const icerik = Key('icerik');
      await tester.pumpWidget(
        _shell(
          page: Builder(
            builder: (c) {
              padding = MediaQuery.paddingOf(c);
              return const SizedBox.expand(key: icerik);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ust bar durum cubugunu, alt menu sistem cubugunu zaten karsiliyor;
      // sayfaya iletilse GridView/ListView onu bir daha ekliyordu.
      expect(padding, EdgeInsets.zero);
      // Icerik ust bar ve alt menuye yapismiyor.
      final alan = tester.getRect(find.byKey(icerik));
      final alt = tester.getRect(find.byKey(bottomBarKey));
      expect(alt.top - alan.bottom, greaterThanOrEqualTo(AppSpacing.md));
      await _teardown(tester);
    },
  );

  group('IK rolu', () {
    testWidgets('tek ekran: ekran secici cizilmez', (tester) async {
      signInAs('hr');
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      installFakeApi({});

      await tester.pumpWidget(_shell(at: '/timesheet'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(bottomMenuButtonKey));
      await tester.pumpAndSettle();
      // Tek ekrana erisen rolde secici gizli: sececek baska ekran yok.
      expect(find.byType(SectionSwitcher), findsNothing);
      // Operasyon menusunden hicbir sey gorunmuyor.
      expect(find.text('Ana Sayfa'), findsNothing);
      expect(find.text('Petty Cash'), findsNothing);
      expect(find.text('Puantaj'), findsWidgets);
      expect(find.text('Profilim'), findsOneWidget);
      await _teardown(tester);
    });
  });
}
