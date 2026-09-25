import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/logout.dart';
import '../core/nav.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import 'avatar.dart';

/// Kirilma noktalari React tarafiyla ayni:
///   < 900   -> cekmece + alt cubuk
///   >= 900  -> sabit kenar menu (1200 altinda varsayilan serit)
const double kSidebarBreakpoint = 900;
const double kRailDefaultBelow = 1200;

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool? _railOverride;

  /// Alt cubuktaki Oneri rozeti. React tarafiyla ayni araliklarla yenilenir.
  int _recommendationCount = 0;
  Timer? _countTimer;

  bool _isRail(double width) => _railOverride ?? (width < kRailDefaultBelow);

  @override
  void initState() {
    super.initState();
    _loadCount();
    _countTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _loadCount(),
    );
  }

  @override
  void dispose() {
    _countTimer?.cancel();
    super.dispose();
  }

  /// Oneri listesindeki aktif urun adedi (kalan adetlerin toplami).
  /// Arka plan yenilemesi oldugu icin sessiz: yukleme katmani acilmaz,
  /// hata bildirimi verilmez.
  Future<void> _loadCount() async {
    try {
      final items = await repo.recommendations(silent: true);
      final total = items.fold<int>(0, (sum, b) => sum + b.remaining);
      if (mounted && total != _recommendationCount) {
        setState(() => _recommendationCount = total);
      }
    } catch (_) {
      // Rozet ikincil bilgi; hata durumunda eski deger kalir.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= kSidebarBreakpoint;
    final user = session.user;
    final items = navFor(user);
    final location = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: t.bg,
      drawer: wide
          ? null
          : Drawer(
              child: _SideNav(items: items, location: location, rail: false),
            ),
      bottomNavigationBar: wide
          ? null
          : _BottomBar(
              location: location,
              recommendationCount: _recommendationCount,
            ),
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              _SideNav(
                items: items,
                location: location,
                rail: _isRail(width),
                onToggleRail: () =>
                    setState(() => _railOverride = !_isRail(width)),
              ),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    showMenuButton: !wide,
                    onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1440),
                        child: Padding(
                          padding: EdgeInsets.all(
                            width < 641 ? 12 : (width < 900 ? 16 : 18),
                          ),
                          child: widget.child,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.items,
    required this.location,
    required this.rail,
    this.onToggleRail,
  });

  final List<NavItem> items;
  final String location;
  final bool rail;
  final VoidCallback? onToggleRail;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final user = session.user;
    return Container(
      width: rail ? 76 : 280,
      decoration: BoxDecoration(
        color: t.sidebar,
        // Acik temada menu de acik; govdeden ince bir cizgiyle ayrisir.
        border: Border(right: BorderSide(color: t.sidebarBorder)),
      ),
      // Cekmece olarak acildiginda menu ekranin en ustunden basliyor ve marka
      // yazisi telefonun durum cubugu simgelerinin altina giriyordu. Renk
      // Container'da kaldigi icin zemin durum cubugunun altina uzanmaya devam
      // eder, yalnizca icerik asagi iner. Genis ekranda govde zaten SafeArea
      // icinde oldugu icin burasi etkisiz kalir.
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 64,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: rail ? 8 : 16),
                child: Row(
                  mainAxisAlignment: rail
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    if (!rail)
                      Expanded(
                        child: Text(
                          'Operasyon Takip',
                          style: TextStyle(
                            color: t.sidebarInk,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (onToggleRail != null)
                      IconButton(
                        tooltip: rail ? 'Menüyü genişlet' : 'Menüyü daralt',
                        onPressed: onToggleRail,
                        icon: Icon(
                          rail ? Icons.chevron_right : Icons.chevron_left,
                        ),
                        color: t.sidebarMuted,
                        constraints: const BoxConstraints(
                          minWidth: AppTokens.tap,
                          minHeight: AppTokens.tap,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: t.sidebarBorder),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: rail ? 8 : 12,
                  vertical: 12,
                ),
                children: items.map((item) {
                  final active = location == item.path;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Tooltip(
                      message: rail ? item.label : '',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                        onTap: () {
                          if (Scaffold.of(context).hasDrawer) {
                              Navigator.of(context).pop();
                            }
                          context.go(item.path);
                        },
                        child: Container(
                          constraints: const BoxConstraints(
                            minHeight: AppTokens.tap,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: rail ? 0 : 14,
                          ),
                          decoration: BoxDecoration(
                            // primary600 uzerinde beyaz yazi 3.3 kontrast
                            // veriyordu (AA siniri 4.5); primary ile 5.02.
                            color: active ? t.primary : null,
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusSm,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: rail
                                ? MainAxisAlignment.center
                                : MainAxisAlignment.start,
                            children: [
                              Icon(
                                item.icon,
                                size: 20,
                                color: active ? t.card : t.sidebarMuted,
                              ),
                              if (!rail) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    item.label,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: active ? t.card : t.sidebarMuted,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Divider(height: 1, color: t.sidebarBorder),
            Padding(
              padding: EdgeInsets.all(rail ? 8 : 16),
              child: rail
                  ? Avatar(user: user, size: 36)
                  : Row(
                      children: [
                        Avatar(user: user, size: 36),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.fullName ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.sidebarInk,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                roleLabels[user?.role] ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.sidebarMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.showMenuButton, required this.onMenu});

  final bool showMenuButton;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final user = session.user;
    final narrow = MediaQuery.sizeOf(context).width < 561;
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(
        color: t.card,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (showMenuButton)
            IconButton(
              tooltip: 'Menü',
              onPressed: onMenu,
              icon: const Icon(Icons.menu),
              constraints: const BoxConstraints(
                minWidth: AppTokens.tap,
                minHeight: AppTokens.tap,
              ),
            ),
          const Spacer(),
          // Kullanici blogu Profilim ekranina goturur: sifre ve tema orada.
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => context.go('/profile'),
            child: Container(
              constraints: const BoxConstraints(
                minHeight: AppTokens.tap,
                maxWidth: 230,
              ),
              padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
              decoration: BoxDecoration(
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Avatar(user: user, size: 28),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.fullName ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.ink,
                            fontSize: narrow ? 12.5 : 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          // Telefonda yer acmak icin magaza adi gizlenir.
                          narrow
                              ? (roleLabels[user?.role] ?? '')
                              : '${roleLabels[user?.role] ?? ''}${user?.storeName != null ? ' • ${user!.storeName}' : ''}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.muted,
                            fontSize: narrow ? 10.5 : 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Çıkış yap',
            color: t.danger,
            onPressed: () => confirmSignOut(context),
            icon: const Icon(Icons.logout),
            style: IconButton.styleFrom(
              side: BorderSide(color: t.danger),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              minimumSize: const Size(AppTokens.tap, AppTokens.tap),
            ),
          ),
        ],
      ),
    );
  }
}

/// Testlerin alt cubuga tutunmasi icin sabit anahtar.
const bottomBarKey = Key('bottomBar');

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.location, required this.recommendationCount});

  final String location;

  /// Oneri listesindeki aktif urun adedi; 0 ise rozet cizilmez.
  final int recommendationCount;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final items = bottomBarFor(session.user);
    return Container(
      key: bottomBarKey,
      decoration: BoxDecoration(
        color: t.card,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            children: items.map((item) {
              return Expanded(
                child: _BottomTab(
                  item: item,
                  active: location == item.path,
                  // Rozet yalnizca oneri listesinde.
                  badge: item.path == '/recommendations'
                      ? recommendationCount
                      : 0,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

/// Tek sekme. Aktif durumda ikon ve etiketin ikisini birden kapsayan yumusak
/// bir hap cizilir (React'teki .bottom-nav a.active ile ayni gorunum).
class _BottomTab extends StatelessWidget {
  const _BottomTab({
    required this.item,
    required this.active,
    required this.badge,
  });

  final NavItem item;
  final bool active;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = active ? t.primary : t.muted;
    final profile = item.path == '/profile';

    return InkWell(
      onTap: () => context.go(item.path),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppTokens.tap),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        decoration: BoxDecoration(
          color: active ? t.primarySoft : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 24,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (profile)
                    Avatar(user: session.user, size: 24)
                  else
                    Icon(item.icon, size: 24, color: color),
                  if (badge > 0)
                    Positioned(
                      top: -8,
                      left: 12,
                      child: _NavBadge(count: badge),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.shortLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kirmizi sayi rozeti. Uc haneden buyuk sayilar sekmeyi tasirmasin diye
/// "99+" olarak kisaltilir.
class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.danger,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.4,
        ),
      ),
    );
  }
}
