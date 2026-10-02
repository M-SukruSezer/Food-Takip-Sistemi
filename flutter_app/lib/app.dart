import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/api_client.dart';
import 'core/nav.dart';
import 'core/notify.dart';
import 'core/session.dart';
import 'core/theme_mode.dart';
import 'core/tokens.dart';
import 'screens/login_screen.dart';
import 'navigation/app_screen_factory.dart';
import 'navigation/route_access_strategy.dart';
import 'widgets/app_shell.dart';
import 'widgets/busy_overlay.dart';

/// Kabuk icindeki ekranlar. nav.dart'taki her yolun burada bir karsiligi
/// olmak zorunda; aksi halde menudeki baglanti bos sayfaya gider (testle
/// dogrulanir).
///
/// Ekranlar sorgu parametresi alabilir: ana sayfadaki ozet kutulari
/// /batches?tab=... ve /sales?range=...&kind=... ile dogrudan ilgili
/// sekmeye/filtreye gidiyor.
final shellScreens = AppScreenFactory.builders;

class FoodTakipApp extends StatefulWidget {
  const FoodTakipApp({super.key});

  @override
  State<FoodTakipApp> createState() => _FoodTakipAppState();
}

class _FoodTakipAppState extends State<FoodTakipApp> {
  late final GoRouter _router;
  final RouteAccessStrategy _routeAccess = const RoleBasedRouteAccessStrategy();

  @override
  void initState() {
    super.initState();
    // 401 alinirsa oturum dusurulur; router otomatik giris ekranina gecer.
    api.onUnauthorized = () => session.signOut();
    // Operasyon alani acik mesai istiyorsa Devam Takibi ekranina goturuluyor.
    // shift=1 sorgusu ekranda sebebi yazdiriyor; ayni ekranda zaten isek
    // gereksiz gezinme yapilmiyor.
    //
    // Yalnizca Operasyon sayfasindayken: PDKS sayfalarindaki (Cizelge, PIN
    // Dogrulama...) arka plan istekleri (orn. oneri rozeti) mesaiye girmemis
    // vardiya sorumlusunu bulundugu sayfadan atmamali.
    api.onShiftRequired = () {
      final yol = _router.routerDelegate.currentConfiguration.uri.path;
      if (yol != '/pdks' && isOperationsPath(yol)) _router.go('/pdks?shift=1');
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
        final landing = _routeAccess.landingPath(session.user);
        if (atLogin) return landing;

        // Rolune kapali bir yola URL yazarak gidilemez. Sunucu zaten 403
        // veriyor; burada da kesilmesi bos ya da hatali bir ekran yerine
        // dogrudan kendi sayfasina dusurmek icin.
        if (!_routeAccess.canAccess(session.user, state.matchedLocation)) {
          return landing;
        }
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
          title: 'Saha Takip',
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
