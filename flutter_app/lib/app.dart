import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/api_client.dart';
import 'core/notify.dart';
import 'core/nav.dart';
import 'core/session.dart';
import 'core/theme_mode.dart';
import 'core/tokens.dart';
import 'screens/approvals_screen.dart';
import 'screens/batches_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/recommendations_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/daily_report_screen.dart';
import 'screens/pdks_admin_screen.dart';
import 'screens/pdks_screen.dart';
import 'screens/petty_cash_screen.dart';
import 'screens/product_types_screen.dart';
import 'screens/roster_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/sales_screen.dart';
import 'screens/stock_coverage_screen.dart';
import 'screens/stores_screen.dart';
import 'screens/timesheet_screen.dart';
import 'screens/users_screen.dart';
import 'widgets/app_shell.dart';
import 'widgets/busy_overlay.dart';

/// Kabuk icindeki ekranlar. nav.dart'taki her yolun burada bir karsiligi
/// olmak zorunda; aksi halde menudeki baglanti bos sayfaya gider (testle
/// dogrulanir).
///
/// Ekranlar sorgu parametresi alabilir: ana sayfadaki ozet kutulari
/// /batches?tab=... ve /sales?range=...&kind=... ile dogrudan ilgili
/// sekmeye/filtreye gidiyor.
final shellScreens = <String, Widget Function(GoRouterState)>{
  '/dashboard': (s) => const DashboardScreen(),
  '/recommendations': (s) => const RecommendationsScreen(),
  '/batches': (s) => BatchesScreen(
    // Ayni yolda filtre degisince State yeniden kurulsun.
    key: ValueKey(s.uri.toString()),
    initialTab: s.uri.queryParameters['tab'],
  ),
  '/roster': (s) => const RosterScreen(),
  '/product-types': (s) => const ProductTypesScreen(),
  '/stores': (s) => const StoresScreen(),
  '/users': (s) => const UsersScreen(),
  '/sales': (s) => SalesScreen(
    key: ValueKey(s.uri.toString()),
    initialRange: s.uri.queryParameters['range'],
    initialKind: s.uri.queryParameters['kind'],
  ),
  '/logs': (s) => const LogsScreen(),
  '/approvals': (s) => const ApprovalsScreen(),
  '/petty-cash': (s) => const PettyCashScreen(),
  '/daily-report': (s) => const DailyReportScreen(),
  '/stock-coverage': (s) => const StockCoverageScreen(),
  '/pdks': (s) => PdksScreen(
    // shift=1 ile gelindiyse sebep yazisi gosterilsin.
    key: ValueKey(s.uri.toString()),
    shiftRequired: s.uri.queryParameters['shift'] == '1',
  ),
  '/pdks-admin': (s) => const PdksAdminScreen(),
  '/timesheet': (s) => const TimesheetScreen(),
  '/profile': (s) => const ProfileScreen(),
};

class FoodTakipApp extends StatefulWidget {
  const FoodTakipApp({super.key});

  @override
  State<FoodTakipApp> createState() => _FoodTakipAppState();
}

class _FoodTakipAppState extends State<FoodTakipApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // 401 alinirsa oturum dusurulur; router otomatik giris ekranina gecer.
    api.onUnauthorized = () => session.signOut();
    // Operasyon alani acik mesai istiyorsa Devam Takibi ekranina goturuluyor.
    // shift=1 sorgusu ekranda sebebi yazdiriyor; ayni ekranda zaten isek
    // gereksiz gezinme yapilmiyor.
    api.onShiftRequired = () {
      final yol = _router.routerDelegate.currentConfiguration.uri.path;
      if (yol != '/pdks') _router.go('/pdks?shift=1');
    };
    _router = GoRouter(
      refreshListenable: session,
      // Ilk acilista PDKS ekrani. Oturum henuz yuklenmemis olabilecegi icin
      // sabit bir yol veriliyor; rol bazli yon degistirme redirect'te.
      initialLocation: '/pdks',
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        // Tum ic ekranlar ayni kabugu paylasir; yalnizca govde degisir.
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            for (final entry in shellScreens.entries)
              GoRoute(
                path: entry.key,
                builder: (context, state) => entry.value(state),
              ),
          ],
        ),
      ],
      redirect: (context, state) {
        if (session.loading) return null;
        final atLogin = state.matchedLocation == '/login';
        if (!session.signedIn) return atLogin ? null : '/login';

        // Girişte PDKS ekrani acilir. IK gibi PDKS'te farkli bir ilk sayfasi
        // olan roller icin landingPathFor dogru yolu veriyor.
        final landing = landingPathFor(session.user);
        if (atLogin) return landing;

        // Rolune kapali bir yola URL yazarak gidilemez. Sunucu zaten 403
        // veriyor; burada da kesilmesi bos ya da hatali bir ekran yerine
        // dogrudan kendi sayfasina dusurmek icin.
        final allowed = navFor(session.user).map((i) => i.path).toSet();
        if (!allowed.contains(state.matchedLocation)) return landing;
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themePreference,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'Operasyon Takip',
          debugShowCheckedModeBanner: false,
          // Tarih seciciler ve takvim basliklari Turkce gelsin; aksi halde
          // Material varsayilani yalnizca Ingilizce destekler.
          locale: const Locale('tr', 'TR'),
          supportedLocales: const [Locale('tr', 'TR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          scaffoldMessengerKey: messengerKey,
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: themePreference.mode,
          routerConfig: _router,
          // Yukleme katmani tum ekranlarin uzerinde durur.
          builder: (context, child) =>
              BusyOverlay(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
