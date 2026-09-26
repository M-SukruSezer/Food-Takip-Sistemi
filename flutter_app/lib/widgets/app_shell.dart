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
import 'scrim.dart';
import 'shortcut_fab.dart';

/// Kirilma noktalari React tarafiyla ayni:
///   < 900   -> alt cubuk + alt cubuktan acilan menu
///   >= 900  -> sabit kenar menu (1200 altinda varsayilan serit)
const double kSidebarBreakpoint = 900;
const double kRailDefaultBelow = 1200;

/// Alt cubugun yuksekligi. Menu tabakasi cubugun uzerine oturmali.
const double kBottomBarHeight = 64;

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool? _railOverride;

  /// Yolu bir ekrana baglanamayan sayfalarda (Profilim) hangi ekranda
  /// kaldigimizi hatirlar; kullanici ekran degistirmis gibi olmasin.
  AppSection _lastSection = AppSection.pdks;

  /// Alt cubuktaki Oneri rozeti. React tarafiyla ayni araliklarla yenilenir.
  int _recommendationCount = 0;
  Timer? _countTimer;

  bool _isRail(double width) => _railOverride ?? (width < kRailDefaultBelow);

  @override
  void initState() {
    super.initState();
    _lastSection = landingSectionFor(session.user);
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
  ///
  /// Sessiz: arka plan yenilemesi oldugu icin yukleme katmani acilmaz, hata
  /// bildirimi verilmez. Oneri listesini gormeyen roller (IK) icin hic
  /// istenmez — 403 alacagi bir uca saniyede bir vurmanin anlami yok.
  Future<void> _loadCount() async {
    if (!navFor(session.user).any((i) => i.path == '/recommendations')) return;
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

  void _goSection(NavSection s) {
    final path = s.groups.first.items.first.path;
    if (GoRouterState.of(context).matchedLocation != path) context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= kSidebarBreakpoint;
    final user = session.user;
    final location = GoRouterState.of(context).matchedLocation;

    final sections = sectionsFor(user);
    final resolved = sectionOfPath(location);
    if (resolved != null) _lastSection = resolved;
    final section = resolved ?? _lastSection;
    final groups = navGroupsFor(user, section);

    return Scaffold(
      backgroundColor: t.bg,
      // Cekmece KALDIRILDI: menu artik alt cubugun kendi alaninda aciliyor.
      // Yan cekmece telefonda ekranin karsi kenarindan geliyordu; parmak alt
      // cubuktayken menunun ust solda belirmesi hedefi kaybettiriyordu.
      bottomNavigationBar: wide
          ? null
          : _BottomBar(
              location: location,
              section: section,
              sections: sections,
              groups: groups,
              recommendationCount: _recommendationCount,
              onSection: _goSection,
            ),
      // Kisayol dugmesi: rolunde hic kisayol yoksa cizilmez.
      //
      // PDKS bolumunde HIC cizilmiyor: kisayollarin tamami operasyon islemi
      // (donuk depoya urun, masraf, gunluk rapor, onaylar) ve PDKS ekraninda
      // giris/mola dugmelerinin uzerine geliyordu.
      floatingActionButton: section == AppSection.operations
          ? ShortcutFab(bottomInset: wide ? 0 : kBottomBarHeight)
          : null,
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              _SideNav(
                groups: groups,
                sections: sections,
                section: section,
                location: location,
                rail: _isRail(width),
                onSection: _goSection,
                onToggleRail: () =>
                    setState(() => _railOverride = !_isRail(width)),
              ),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    // Telefonda hamburger yok: menu alt cubuktan aciliyor.
                    // Bunun yerine bulundugun ekranin adi yaziyor ki iki ekran
                    // arasinda nerede oldugun belli olsun.
                    sectionLabel: wide
                        ? null
                        : sections
                              .where((s) => s.id == section)
                              .map((s) => s.label)
                              .firstOrNull,
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

/// Iki ekran arasindaki secici. Tek ekrana erisen rolde (IK) hic cizilmez.
class SectionSwitcher extends StatelessWidget {
  const SectionSwitcher({
    super.key,
    required this.sections,
    required this.section,
    required this.onSection,
    this.compact = false,
  });

  final List<NavSection> sections;
  final AppSection section;
  final ValueChanged<NavSection> onSection;

  /// Daraltilmis kenar seritte yalnizca ikonlar sigiyor.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (sections.length < 2) return const SizedBox.shrink();
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.sidebarBorder.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm + 3),
      ),
      child: Row(
        children: sections.map((s) {
          final active = s.id == section;
          return Expanded(
            child: Tooltip(
              message: compact ? s.label : s.description,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                onTap: active ? null : () => onSection(s),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 38),
                  decoration: BoxDecoration(
                    color: active ? t.primary : null,
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        s.icon,
                        size: 17,
                        color: active ? t.card : t.sidebarMuted,
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            s.label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: active ? t.card : t.sidebarMuted,
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
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.groups,
    required this.sections,
    required this.section,
    required this.location,
    required this.rail,
    required this.onSection,
    this.onToggleRail,
  });

  final List<NavGroup> groups;
  final List<NavSection> sections;
  final AppSection section;
  final String location;
  final bool rail;
  final ValueChanged<NavSection> onSection;
  final VoidCallback? onToggleRail;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final user = session.user;
    return Container(
      width: rail ? 76 : 280,
      decoration: BoxDecoration(
        color: t.sidebar,
        border: Border(right: BorderSide(color: t.sidebarBorder)),
      ),
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
            if (sections.length > 1)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  rail ? 8 : 12,
                  0,
                  rail ? 8 : 12,
                  10,
                ),
                child: SectionSwitcher(
                  sections: sections,
                  section: section,
                  onSection: onSection,
                  compact: rail,
                ),
              ),
            Divider(height: 1, color: t.sidebarBorder),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: rail ? 8 : 12,
                  vertical: 12,
                ),
                children: [
                  for (var gi = 0; gi < groups.length; gi++) ...[
                    if (gi > 0)
                      SizedBox(height: rail ? 8 : 14)
                    else
                      const SizedBox.shrink(),
                    if (rail && gi > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Divider(height: 1, color: t.sidebarBorder),
                      ),
                    if (!rail && groups[gi].title != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 14, bottom: 6),
                        child: Text(
                          groups[gi].title!.toUpperCase(),
                          style: TextStyle(
                            color: t.sidebarMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    if (!rail && groups[gi].title == null && gi > 0)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 14,
                          right: 14,
                          bottom: 8,
                        ),
                        child: Divider(height: 1, color: t.sidebarBorder),
                      ),
                    ...groups[gi].items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: _SideTile(
                          item: item,
                          active: location == item.path,
                          rail: rail,
                          onTap: () => context.go(item.path),
                        ),
                      ),
                    ),
                  ],
                ],
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

class _SideTile extends StatelessWidget {
  const _SideTile({
    required this.item,
    required this.active,
    required this.rail,
    required this.onTap,
  });

  final NavItem item;
  final bool active;
  final bool rail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message: rail ? item.label : '',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTokens.tap),
          padding: EdgeInsets.symmetric(horizontal: rail ? 0 : 14),
          decoration: BoxDecoration(
            // primary600 uzerinde beyaz yazi 3.3 kontrast veriyordu
            // (AA siniri 4.5); primary ile 5.02.
            color: active ? t.primary : null,
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
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
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({this.sectionLabel});

  /// Telefonda bulundugun ekranin adi. Genis ekranda kenar menu bunu zaten
  /// gosterdigi icin null gecilir.
  final String? sectionLabel;

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
          if (sectionLabel != null)
            // Esnek ve kisaltmali: 375 px'te kullanici blogu (en fazla 230) +
            // cikis dugmesi ile birlikte olculdugunde sabit metin satiri
            // 72 px tasiyordu.
            Flexible(
              child: Text(
                sectionLabel!,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: t.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
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

/// Testlerin alt cubuga tutunmasi icin sabit anahtarlar.
const bottomBarKey = Key('bottomBar');
const bottomMenuButtonKey = Key('bottomMenuButton');
const bottomMenuSheetKey = Key('bottomMenuSheet');

class _BottomBar extends StatefulWidget {
  const _BottomBar({
    required this.location,
    required this.section,
    required this.sections,
    required this.groups,
    required this.recommendationCount,
    required this.onSection,
  });

  final String location;
  final AppSection section;
  final List<NavSection> sections;
  final List<NavGroup> groups;

  /// Oneri listesindeki aktif urun adedi; 0 ise rozet cizilmez.
  final int recommendationCount;
  final ValueChanged<NavSection> onSection;

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  bool _menuOpen = false;

  Future<void> _openMenu() async {
    setState(() => _menuOpen = true);
    try {
      await showGeneralDialog<void>(
        context: context,
        // Perdeyi kendimiz ciziyoruz; hazir bariyer kapatilir.
        barrierColor: Colors.transparent,
        barrierDismissible: true,
        barrierLabel: 'Menüyü kapat',
        transitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (_, _, _) => const SizedBox.shrink(),
        transitionBuilder: (ctx, anim, _, _) => _NavMenuSheet(
          animation: anim,
          groups: widget.groups,
          sections: widget.sections,
          section: widget.section,
          location: widget.location,
          onSection: widget.onSection,
        ),
      );
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final items = bottomBarFor(session.user, widget.section);
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
            children: [
              ...items.map(
                (item) => Expanded(
                  child: _BottomTab(
                    icon: item.icon,
                    label: item.shortLabel,
                    active: widget.location == item.path,
                    // Rozet yalnizca oneri listesinde.
                    badge: item.path == '/recommendations'
                        ? widget.recommendationCount
                        : 0,
                    onTap: () => context.go(item.path),
                  ),
                ),
              ),
              // Profil gorselinin yerini Menu aldi: profil zaten menunun
              // icinde: alt cubuktaki bes yuvadan birini tek bir sayfaya
              // ayirmak yerine tum menuyu acmak daha fazla yol kazandiriyor.
              Expanded(
                child: _BottomTab(
                  key: bottomMenuButtonKey,
                  icon: _menuOpen ? Icons.close : Icons.menu,
                  label: 'Menü',
                  active: _menuOpen,
                  badge: 0,
                  onTap: _menuOpen ? () => Navigator.pop(context) : _openMenu,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Alt cubuktan yukselen menu tabakasi.
///
/// Yan cekmece yerine buradan aciliyor: parmak alt cubuktayken menunun karsi
/// kenardan gelmesi hedefi kaybettiriyordu. Icerik aynidir — aktif ekranin
/// tum menu agaci, ekran secici, profil ve cikis.
class _NavMenuSheet extends StatelessWidget {
  const _NavMenuSheet({
    required this.animation,
    required this.groups,
    required this.sections,
    required this.section,
    required this.location,
    required this.onSection,
  });

  final Animation<double> animation;
  final List<NavGroup> groups;
  final List<NavSection> sections;
  final AppSection section;
  final String location;
  final ValueChanged<NavSection> onSection;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final user = session.user;
    // Menu en fazla ekranin %78'i; uzun listede kendi icinde kayar.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;

    return Material(
      type: MaterialType.transparency,
      // Perde animasyonun DISINDA: BackdropFilter fade icinde oldugunda tam
      // ekran bulanti her karede yeniden hesaplaniyor (saveLayer) ve menu
      // oturduktan sonra bile kareler devam ediyor. Kisayol menusunde bu
      // olculdu; ayni desen burada da uygulaniyor.
      child: AppScrim(
        absorb: false,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          behavior: HitTestBehavior.opaque,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              // Perdeye dokunmak kapatir; menunun kendisine dokunmak kapatmaz.
              child: GestureDetector(
                onTap: () {},
                // Bosluk DISTA: Container'in margin'i olcum kutusuna dahil
                // oldugu icin anahtar boyanan kutuya takiliyor; testin
                // "menu cubugun uzerinde mi" olcumu boylece gercek kenari
                // goruyor.
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    8,
                    0,
                    8,
                    kBottomBarHeight + 8,
                  ),
                  child: Container(
                    key: bottomMenuSheetKey,
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                      border: Border.all(color: t.border),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                            child: Row(
                              children: [
                                Avatar(user: user, size: 34),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user?.fullName ?? '',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: t.ink,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                      Text(
                                        roleLabels[user?.role] ?? '',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: t.muted,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Kapat',
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close),
                                  color: t.muted,
                                  constraints: const BoxConstraints(
                                    minWidth: AppTokens.tap,
                                    minHeight: AppTokens.tap,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (sections.length > 1)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                              child: SectionSwitcher(
                                sections: sections,
                                section: section,
                                onSection: (s) {
                                  Navigator.pop(context);
                                  onSection(s);
                                },
                              ),
                            ),
                          Divider(height: 1, color: t.border),
                          Flexible(
                            child: ListView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              shrinkWrap: true,
                              children: [
                                for (var gi = 0; gi < groups.length; gi++) ...[
                                  if (groups[gi].title != null)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        left: 12,
                                        top: gi == 0 ? 0 : 12,
                                        bottom: 6,
                                      ),
                                      child: Text(
                                        groups[gi].title!.toUpperCase(),
                                        style: TextStyle(
                                          color: t.muted,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    )
                                  else if (gi > 0)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      child: Divider(
                                        height: 1,
                                        color: t.border,
                                      ),
                                    ),
                                  ...groups[gi].items.map(
                                    (item) => _MenuTile(
                                      item: item,
                                      active: location == item.path,
                                      onTap: () {
                                        Navigator.pop(context);
                                        context.go(item.path);
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Divider(height: 1, color: t.border),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  confirmSignOut(context);
                                },
                                icon: const Icon(Icons.logout, size: 18),
                                label: const Text('Çıkış yap'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: t.danger,
                                  side: BorderSide(color: t.danger),
                                  minimumSize: const Size.fromHeight(
                                    AppTokens.tap,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTokens.tap),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? t.primarySoft : null,
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 20, color: active ? t.primary : t.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? t.primary : t.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
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
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = active ? t.primary : t.muted;

    return InkWell(
      onTap: onTap,
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
                  Icon(icon, size: 24, color: color),
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
              label,
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
