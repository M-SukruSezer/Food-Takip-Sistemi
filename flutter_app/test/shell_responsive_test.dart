import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/session.dart';
import 'package:foodtakip/core/tokens.dart';
import 'package:foodtakip/models/user.dart';
import 'package:foodtakip/widgets/app_shell.dart';
import 'package:foodtakip/widgets/crud_scaffold.dart';
import 'package:foodtakip/widgets/shell_scope.dart';
import 'package:go_router/go_router.dart';

/// Kabugun kirilma noktalarini olcer: React tarafinda tarayicida olctugumuz
/// davranisin Flutter karsiligi burada headless dogrulanir.
Future<void> _pumpShell(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, _) => const Text('govde')),
          GoRoute(path: '/profile', builder: (_, _) => const Text('profil')),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    MaterialApp.router(
      theme: buildAppTheme(Brightness.light),
      routerConfig: router,
    ),
  );
  await tester.pumpAndSettle();

  // AppShell oneri sayaci icin 60sn'lik periyodik timer kuruyor; agac
  // sokulmadan test biterse "bekleyen timer" hatasi veriyor.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 61));
  });
}

void main() {
  setUp(() {
    session.updateUser(
      const AppUser(
        id: 1,
        username: 'admin',
        fullName: 'Muhammed Şükrü Sezer',
        role: 'super_admin',
        storeName: 'Merkez Mağaza',
      ),
    );
  });

  testWidgets('telefon (375): alt cubuk var, sabit kenar menu yok', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(375, 812));
    expect(find.byKey(bottomBarKey), findsOneWidget);
    // Cekmece kapali oldugu icin kenar menu agacta olmamali.
    expect(find.text('Saha Takip'), findsNothing);
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });

  testWidgets('dar telefon (320): üst bar ve alt menü taşmıyor', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(320, 700));
    expect(tester.takeException(), isNull);
    expect(find.text('Ana Sayfa'), findsWidgets);
    expect(find.byKey(bottomBarKey), findsOneWidget);
  });

  testWidgets('mobil CrudScaffold sayfa başlığını içerikte tekrarlamıyor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: AppShellScope(
          mobile: true,
          child: CrudScaffold(
            title: 'Devam Yönetimi',
            loaded: true,
            error: null,
            onRetry: () {},
            onRefresh: () async {},
            children: const [Text('İçerik')],
          ),
        ),
      ),
    );
    expect(find.text('Devam Yönetimi'), findsNothing);
    expect(find.text('İçerik'), findsOneWidget);
  });

  testWidgets('tablet dikey (768): alt cubuk var', (tester) async {
    await _pumpShell(tester, const Size(768, 1024));
    expect(find.byKey(bottomBarKey), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });

  testWidgets('yatay tablet (1024): kenar menu serit halinde', (tester) async {
    await _pumpShell(tester, const Size(1024, 768));
    expect(find.byKey(bottomBarKey), findsNothing);
    expect(find.byIcon(Icons.menu), findsNothing);
    // Serit modunda marka metni ve etiketler gizli, daraltma dugmesi acik yonde.
    expect(find.text('Saha Takip'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('genis masaustu (1440): kenar menu acik', (tester) async {
    await _pumpShell(tester, const Size(1440, 900));
    expect(find.byKey(bottomBarKey), findsNothing);
    expect(find.text('Saha Takip'), findsOneWidget);
    expect(find.text('Ana Sayfa'), findsWidgets);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
  });

  testWidgets('cikis dugmesi ve kullanici blogu parmak boyutunda', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(375, 812));
    final logout = tester.getSize(find.byTooltip('Çıkış yap'));
    expect(logout.height, greaterThanOrEqualTo(AppTokens.tap));
    final userBlock = tester.getSize(find.byType(InkWell).first);
    expect(userBlock.height, greaterThanOrEqualTo(AppTokens.tap));
  });
}
