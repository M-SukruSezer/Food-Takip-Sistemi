import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/api_client.dart';
import 'package:foodtakip/core/session.dart';
import 'package:foodtakip/core/tokens.dart';
import 'package:foodtakip/widgets/app_shell.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

const _paths = ['/dashboard', '/batches', '/recommendations', '/sales', '/profile'];

Widget _shell({String at = '/dashboard', Brightness brightness = Brightness.light}) {
  final router = GoRouter(
    initialLocation: at,
    routes: [
      ShellRoute(
        builder: (c, s, child) => AppShell(child: child),
        routes: [
          for (final p in _paths) GoRoute(path: p, builder: (c, s) => const SizedBox.expand()),
        ],
      ),
    ],
  );
  return MaterialApp.router(theme: buildAppTheme(brightness), routerConfig: router);
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

  testWidgets('beş sekme, etiketleriyle birlikte', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    installFakeApi({'GET /recommendations': _recs(const [])});

    await tester.pumpWidget(_shell());
    await tester.pumpAndSettle();

    for (final label in ['Ana Sayfa', 'Ürünler', 'Öneri', 'Rapor', 'Profil']) {
      expect(find.text(label), findsWidgets, reason: '$label sekmesi yok');
    }
    await _teardown(tester);
  });

  testWidgets('öneri listesindeki adet rozette görünür', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    installFakeApi({'GET /recommendations': _recs(const [20, 13])});

    await tester.pumpWidget(_shell());
    await tester.pumpAndSettle();

    // 20 + 13 = 33 adet.
    expect(find.text('33'), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('liste boşken rozet çizilmez', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    installFakeApi({'GET /recommendations': _recs(const [])});

    await tester.pumpWidget(_shell());
    await tester.pumpAndSettle();

    expect(find.text('0'), findsNothing);
    await _teardown(tester);
  });

  testWidgets('aktif sekmenin hapı ikonu ve etiketi birlikte kapsar', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    installFakeApi({'GET /recommendations': _recs(const [])});

    await tester.pumpWidget(_shell(at: '/batches'));
    await tester.pumpAndSettle();

    final label = find.text('Ürünler');
    final pill = find
        .ancestor(of: label, matching: find.byType(Container))
        .evaluate()
        .map((e) => e.widget as Container)
        .firstWhere((c) => (c.decoration as BoxDecoration?)?.color != null);
    final decoration = pill.decoration! as BoxDecoration;
    final tokens = AppTokens.light;
    expect(decoration.color, tokens.primarySoft);

    // Hap hem ikonu hem etiketi icine almali.
    final pillRect = tester.getRect(find.byWidget(pill));
    final labelRect = tester.getRect(label);
    expect(pillRect.contains(labelRect.topLeft), isTrue);
    expect(pillRect.contains(labelRect.bottomRight), isTrue);

    await _teardown(tester);
  });

  testWidgets('sekmeler dokunma hedefini korur', (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    installFakeApi({'GET /recommendations': _recs(const [])});

    await tester.pumpWidget(_shell());
    await tester.pumpAndSettle();

    for (final label in ['Ana Sayfa', 'Ürünler', 'Öneri', 'Rapor', 'Profil']) {
      final tab = find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
      expect(tester.getSize(tab).height, greaterThanOrEqualTo(AppTokens.tap));
    }
    await _teardown(tester);
  });
}
