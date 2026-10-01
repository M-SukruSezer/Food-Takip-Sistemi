import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/logout.dart';
import '../core/nav.dart';
import '../core/push.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../core/responsive.dart';
import '../models/user.dart';
import '../models/pdks.dart';
import '../core/api_client.dart';
import '../core/notify.dart';
import 'pdks_qr_action.dart';
import 'qr_action_menu.dart';
import 'avatar.dart';
import 'notification_bell.dart';
import 'scrim.dart';
import 'shell_scope.dart';

/// Kirilma noktalari React tarafiyla ayni:
///   < 900   -> alt cubuk + alt cubuktan acilan menu
///   >= 900  -> sabit kenar menu (1200 altinda varsayilan serit)
const double kSidebarBreakpoint = 900;
const double kRailDefaultBelow = 1200;

/// Alt cubugun yuksekligi. Menu tabakasi cubugun uzerine oturmali.
const double kBottomBarHeight = 82;

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool? _railOverride;
  bool _qrOpen = false;
  bool _qrBusy = false;
  PdksStatus? _qrStatus;
  String? _qrError;

  Future<void> _toggleQr() async {
    if (_qrOpen) {
      setState(() => _qrOpen = false);
      return;
    }
    setState(() {
      _qrOpen = true;
      _qrStatus = null;
      _qrError = null;
    });
    try {
      final status = await repo.pdksStatus(silent: true);
      if (mounted) setState(() => _qrStatus = status);
    } catch (e) {
      if (mounted) setState(() => _qrError = errorMessage(e));
    }
  }

  Future<void> _chooseQr(bool isBreak) async {
    final status = _qrStatus;
    if (status == null || _qrBusy) return;
    final action = isBreak
        ? (status.onBreak ? PdksPunch.breakEnd : PdksPunch.breakStart)
        : (status.isInside ? PdksPunch.checkOut : PdksPunch.checkIn);
    final allowed = switch (action) {
      PdksPunch.checkIn => status.canCheckIn,
      PdksPunch.checkOut => status.canCheckOut,
      PdksPunch.breakStart => status.canBreakStart,
      PdksPunch.breakEnd => status.canBreakEnd,
    };
    if (!status.canUseQr || !allowed) {
      toast(
        'Bu işlem şu an kullanılamıyor. Devam ekranındaki durumunuzu kontrol edin.',
        kind: ToastKind.info,
      );
      return;
    }
    setState(() {
      _qrOpen = false;
      _qrBusy = true;
    });
    try {
      await performPdksQr(context, action);
    } finally {
      if (mounted) setState(() => _qrBusy = false);
    }
  }

  /// Yolu bir ekrana baglanamayan sayfalarda (Profilim) hangi ekranda
  /// kaldigimizi hatirlar; kullanici ekran degistirmis gibi olmasin.
  AppSection _lastSection = AppSection.pdks;

  /// Alt cubuktaki Oneri rozeti. React tarafiyla ayni araliklarla yenilenir.
  int _recommendationCount = 0;
  Timer? _countTimer;

  /// Sunucudaki yeni bildirimleri telefonun bildirim merkezine dusuruyor.
  /// Uygulama kabugunda duruyor: hangi ekranda olursak olalim calisiyor.
  final _bildirimler = PushPoller();

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
    // Izin ilk acilista isteniyor: kullanici uygulamayi kullanmaya
    // baslamadan izin penceresi cikarmak yerine oturum acildiktan sonra.
    unawaited(requestPushPermission());
    // Jeton her acilista kaydediliyor: yenilenmis olabilir ve kullanici
    // degismis olabilir. Sunucu ayni jetonu tekrar yazmiyor, sahibini
    // guncelliyor.
    unawaited(registerDeviceToken());
    _bildirimler.start();
  }

  @override
  void dispose() {
    _countTimer?.cancel();
    _bildirimler.dispose();
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
    final pageTitle = navFor(user)
        .where((item) => item.path == location)
        .map((item) => item.label)
        .firstOrNull;

    final sections = sectionsFor(user);
    final resolved = sectionOfPath(location);
    if (resolved != null) _lastSection = resolved;
    final section = resolved ?? _lastSection;
    final groups = navGroupsFor(user, section);

    return AppShellScope(
      mobile: !wide,
      child: PopScope(
        canPop: !_qrOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _qrOpen) setState(() => _qrOpen = false);
        },
        child: Scaffold(
          backgroundColor: t.bg,
          // Cekmece KALDIRILDI: menu artik alt cubugun kendi alaninda aciliyor.
          // Yan cekmece telefonda ekranin karsi kenarindan geliyordu; parmak alt
          // cubuktayken menunun ust solda belirmesi hedefi kaybettiriyordu.
          bottomNavigationBar: wide
              ? null
              : _BottomBar(
                  qrOpen: _qrOpen,
                  onQr: _qrBusy ? null : _toggleQr,
                  onNavigate: () => setState(() => _qrOpen = false),
                  location: location,
                  section: section,
                  sections: sections,
                  groups: groups,
                  recommendationCount: _recommendationCount,
                  onSection: _goSection,
                ),
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
                        okunmamis: _bildirimler.okunmamis,
                        // Telefonda hamburger yok: menu alt cubuktan aciliyor.
                        // Bunun yerine bulundugun ekranin adi yaziyor ki iki ekran
                        // arasinda nerede oldugun belli olsun.
                        sectionLabel: wide
                            ? null
                            : (pageTitle ??
                                  sections
                                      .where((s) => s.id == section)
                                      .map((s) => s.label)
                                      .firstOrNull),
                      ),
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Align(
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: switch (Breakpoints.of(width)) {
                                    _ when width < Breakpoints.narrowPhone =>
                                      AppSpacing.sm,
                                    WindowSize.compact => 10,
                                    WindowSize.medium => AppSpacing.lg,
                                    _ => 18,
                                  },
                                  // Mobil içerik üst bar ile alt menü arasındaki
                                  // alanı tam kullanır. Dikey dış boşluk yalnızca
                                  // masaüstü yerleşiminde gerekir.
                                  vertical: wide ? 18 : 0,
                                ),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1440,
                                  ),
                                  child: SizedBox.expand(child: widget.child),
                                ),
                              ),
                            ),
                            if (_qrOpen && !wide)
                              QrActionMenu(
                                status: _qrStatus,
                                error: _qrError,
                                onClose: () => setState(() => _qrOpen = false),
                                onShift: () => _chooseQr(false),
                                onBreak: () => _chooseQr(true),
                                onRetry: () {
                                  setState(() => _qrOpen = false);
                                  _toggleQr();
                                },
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? t.sidebarBorder.withValues(alpha: 0.45)
            : const Color(0xFFF1F5F9),
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
                  constraints: const BoxConstraints(minHeight: 40),
                  decoration: BoxDecoration(
                    color: active ? t.primary : null,
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        s.id == AppSection.pdks
                            ? Icons.badge_outlined
                            : Icons.storefront_outlined,
                        size: 18,
                        color: active
                            ? t.onPrimary
                            : (isDark
                                  ? t.sidebarMuted
                                  : const Color(0xFF475569)),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 7),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  s.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: active
                                        ? Colors.white
                                        : (isDark
                                              ? t.sidebarMuted
                                              : const Color(0xFF475569)),
                                  ),
                                ),
                                Text(
                                  s.id == AppSection.pdks
                                      ? ' & Kadro'
                                      : ' & Vitrin',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: active
                                        ? Colors.white
                                        : (isDark
                                              ? t.sidebarMuted
                                              : const Color(0xFF475569)),
                                  ),
                                ),
                              ],
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
                          'Saha Takip',
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
                            // React'teki .side-group-title ile ayni taban.
                            fontSize: 11,
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
  const _TopBar({this.sectionLabel, required this.okunmamis});

  /// Zil rozetindeki okunmamis bildirim sayisi.
  final ValueListenable<int> okunmamis;

  /// Telefonda bulundugun ekranin adi. Genis ekranda kenar menu bunu zaten
  /// gosterdigi icin null gecilir.
  final String? sectionLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final user = session.user;
    // Başlıktaki arama/menü öğeleri 560px altında simgeye indirgenir.
    final narrow = context.screenWidth < 561;
    if (sectionLabel != null) {
      return _MobileTopBar(
        user: user,
        okunmamis: okunmamis,
        pageTitle: sectionLabel!,
      );
    }
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
          const SizedBox(width: 4),
          NotificationBell(okunmamis: okunmamis),
          const SizedBox(width: 4),
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

/// Telefon basligi; magaza durumu ve temel hesap eylemlerini tek bakista sunar.
class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar({
    required this.user,
    required this.okunmamis,
    required this.pageTitle,
  });

  final AppUser? user;
  final ValueListenable<int> okunmamis;
  final String pageTitle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final compact = context.screenWidth < 380;
    final storeName = (user?.storeName?.trim().isNotEmpty ?? false)
        ? user!.storeName!.toUpperCase()
        : 'MERKEZ ŞUBE';
    return Container(
      height: 118,
      padding: EdgeInsets.fromLTRB(compact ? 12 : 18, 13, compact ? 8 : 13, 12),
      decoration: BoxDecoration(
        color: t.card,
        border: Border(bottom: BorderSide(color: t.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2CCB9A),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        storeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .15,
                        ),
                      ),
                    ),
                    if (!compact)
                      Text(
                        '  · Online',
                        style: TextStyle(
                          color: t.muted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  pageTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.ink,
                    fontSize: compact ? 20 : 24,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.7,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user?.fullName ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.muted,
                          fontSize: compact ? 12 : 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (!compact)
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: t.border,
                          shape: BoxShape.circle,
                        ),
                      ),
                    if (!compact)
                      Flexible(
                        child: Text(
                          roleLabels[user?.role] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.primary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 3 : 6),
          _HeaderCircle(
            tooltip: 'Bildirimler',
            onTap: () => showNotificationSheet(context),
            child: ValueListenableBuilder<int>(
              valueListenable: okunmamis,
              builder: (context, count, _) => Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    color: t.muted,
                    size: 21,
                  ),
                  if (count > 0)
                    Positioned(
                      right: -7,
                      top: -9,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 17,
                          minHeight: 17,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE11D48),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: t.card, width: 1.5),
                        ),
                        child: Text(
                          count > 9 ? '9+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(width: compact ? 3 : 7),
          _HeaderCircle(
            tooltip: 'Çıkış yap',
            onTap: () => confirmSignOut(context),
            child: Icon(
              Icons.power_settings_new_rounded,
              color: t.muted,
              size: 21,
            ),
          ),
          SizedBox(width: compact ? 4 : 9),
          Semantics(
            button: true,
            label: 'Profilim',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.go('/profile'),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: t.primary, width: 1.5),
                    ),
                    child: Avatar(user: user, size: compact ? 31 : 35),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: t.card, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCircle extends StatelessWidget {
  const _HeaderCircle({
    required this.child,
    required this.tooltip,
    required this.onTap,
  });

  final Widget child;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: t.bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Center(child: child)),
        ),
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
    required this.qrOpen,
    required this.onQr,
    required this.onNavigate,
    required this.location,
    required this.section,
    required this.sections,
    required this.groups,
    required this.recommendationCount,
    required this.onSection,
  });

  final bool qrOpen;
  final VoidCallback? onQr;
  final VoidCallback onNavigate;
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
    widget.onNavigate();
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
          recommendationCount: widget.recommendationCount,
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
    final showQrAction = widget.section == AppSection.pdks;
    final leadingItems = showQrAction ? items.take(2).toList() : items;
    final trailingItems = showQrAction
        ? items.skip(2).toList()
        : const <NavItem>[];
    return Container(
      key: bottomBarKey,
      decoration: BoxDecoration(
        color: t.card,
        border: Border(top: BorderSide(color: t.border.withValues(alpha: .65))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .07),
            blurRadius: 18,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 7, 6, 7),
          child: Row(
            children: [
              ...leadingItems.map(
                (item) => Expanded(
                  child: item.path == '/recommendations'
                      ? _RecommendationTab(
                          count: widget.recommendationCount,
                          onTap: () {
                            widget.onNavigate();
                            context.go(item.path);
                          },
                        )
                      : _BottomTab(
                          icon: switch (item.path) {
                            '/dashboard' => Icons.grid_view_rounded,
                            '/batches' => Icons.view_in_ar_outlined,
                            _ =>
                              item.shortLabel == 'Rapor'
                                  ? Icons.bar_chart_rounded
                                  : item.icon,
                          },
                          label: item.shortLabel,
                          active: widget.location == item.path,
                          // Rozet yalnizca oneri listesinde.
                          badge: item.path == '/recommendations'
                              ? widget.recommendationCount
                              : 0,
                          onTap: () {
                            widget.onNavigate();
                            context.go(item.path);
                          },
                        ),
                ),
              ),
              if (showQrAction)
                Expanded(
                  child: _QrBottomTab(open: widget.qrOpen, onTap: widget.onQr),
                ),
              ...trailingItems.map(
                (item) => Expanded(
                  child: _BottomTab(
                    icon: switch (item.path) {
                      '/dashboard' => Icons.grid_view_rounded,
                      '/batches' => Icons.view_in_ar_outlined,
                      _ =>
                        item.shortLabel == 'Rapor'
                            ? Icons.bar_chart_rounded
                            : item.icon,
                    },
                    label: item.shortLabel,
                    active: widget.location == item.path,
                    badge: 0,
                    onTap: () {
                      widget.onNavigate();
                      context.go(item.path);
                    },
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
    this.recommendationCount = 0,
  });

  final Animation<double> animation;
  final List<NavGroup> groups;
  final List<NavSection> sections;
  final AppSection section;
  final String location;
  final ValueChanged<NavSection> onSection;
  final int recommendationCount;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final user = session.user;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    final List<NavGroup> displayGroups;
    if (section == AppSection.pdks &&
        sections.any((s) => s.id == AppSection.operations)) {
      final pdksGroups = groups
          .where((g) => !g.items.any((i) => i.path == '/profile'))
          .toList();
      final opGroups = user != null
          ? navGroupsFor(
              user,
              AppSection.operations,
            ).where((g) => g.title != null).toList()
          : const <NavGroup>[];
      final profileGroup = groups.firstWhere(
        (g) => g.items.any((i) => i.path == '/profile'),
        orElse: () =>
            user != null ? navGroupsFor(user, section).last : groups.last,
      );
      displayGroups = [...pdksGroups, ...opGroups, profileGroup];
    } else {
      displayGroups = groups;
    }

    return Material(
      type: MaterialType.transparency,
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
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  key: bottomMenuSheetKey,
                  width: double.infinity,
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    border: Border.all(color: t.border.withValues(alpha: 0.7)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 20,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            margin: const EdgeInsets.only(top: 10, bottom: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFCBD5E1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 8, 10),
                          child: Row(
                            children: [
                              Stack(
                                children: [
                                  Avatar(user: user, size: 44),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 11,
                                      height: 11,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user?.fullName.toUpperCase() ?? '',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: t.ink,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      roleLabels[user?.role] ??
                                          (user?.role ?? ''),
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: t.muted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.location_on,
                                          size: 13,
                                          color: t.primary,
                                        ),
                                        const SizedBox(width: 3),
                                        Flexible(
                                          child: Text(
                                            user?.storeName != null
                                                ? 'Colombia Coffee Co. · ${user!.storeName}'
                                                : 'Colombia Coffee Co.',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: t.primary,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Kapat',
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close_rounded),
                                color: const Color(0xFF94A3B8),
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
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                            child: SectionSwitcher(
                              sections: sections,
                              section: section,
                              onSection: (s) {
                                Navigator.pop(context);
                                onSection(s);
                              },
                            ),
                          ),
                        Divider(
                          height: 1,
                          color: t.border.withValues(alpha: 0.6),
                        ),
                        Flexible(
                          child: ListView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shrinkWrap: true,
                            children: [
                              for (
                                var gi = 0;
                                gi < displayGroups.length;
                                gi++
                              ) ...[
                                if (displayGroups[gi].title != null)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      left: 2,
                                      right: 2,
                                      top: gi == 0 ? 0 : 16,
                                      bottom: 10,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            displayGroups[gi].title ==
                                                    'Operasyon'
                                                ? 'MAĞAZA & ÜRÜN OPERASYONLARI'
                                                : displayGroups[gi].title!
                                                      .toUpperCase(),
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF64748B),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.6,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${displayGroups[gi].items.length} Aktif Modül',
                                          style: TextStyle(
                                            color: t.primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (gi > 0 &&
                                    displayGroups[gi].items.isNotEmpty)
                                  const SizedBox(height: 4),
                                ...displayGroups[gi].items.map(
                                  (item) => _MenuTile(
                                    item: item,
                                    active: location == item.path,
                                    recommendationCount: recommendationCount,
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
                        Divider(
                          height: 1,
                          color: t.border.withValues(alpha: 0.6),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    confirmSignOut(context);
                                  },
                                  icon: const Icon(
                                    Icons.logout_rounded,
                                    size: 19,
                                    color: Color(0xFFDC2626),
                                  ),
                                  label: const Text('Çıkış yap'),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: t.dangerSoft,
                                    foregroundColor: t.danger,
                                    side: BorderSide(
                                      color: t.danger.withValues(alpha: .45),
                                      width: 1.2,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    minimumSize: const Size.fromHeight(48),
                                    textStyle: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'v2.4.1 (Build 1084)',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
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
    );
  }
}

class _MenuTileData {
  const _MenuTileData({
    required this.titlePrefix,
    required this.titleMain,
    required this.titleSuffix,
    required this.subtitle,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    this.badgeText,
    this.badgeBg,
    this.badgeColor,
  });

  final String titlePrefix;
  final String titleMain;
  final String titleSuffix;
  final String subtitle;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String? badgeText;
  final Color? badgeBg;
  final Color? badgeColor;
}

_MenuTileData _menuTileDataFor(NavItem item, int recommendationCount) {
  switch (item.path) {
    case '/pdks':
      return const _MenuTileData(
        titlePrefix: '',
        titleMain: 'Devam Takibi',
        titleSuffix: '',
        subtitle: 'Giriş/çıkış, mola süreleri ve QR doğrulama',
        icon: Icons.access_time_filled_rounded,
        iconBg: Color(0xFF00A86B),
        iconColor: Colors.white,
        badgeText: 'Canlı',
        badgeBg: Color(0xFFD1FAE5),
        badgeColor: Color(0xFF065F46),
      );
    case '/roster':
      return const _MenuTileData(
        titlePrefix: '',
        titleMain: 'Vardiya Çizelgesi',
        titleSuffix: '',
        subtitle: 'Haftalık nöbet planı ve çalışma saatleri',
        icon: Icons.calendar_month_outlined,
        iconBg: Color(0xFFF1F5F9),
        iconColor: Color(0xFF475569),
      );
    case '/pdks-admin':
      return const _MenuTileData(
        titlePrefix: '',
        titleMain: 'Devam Yönetimi',
        titleSuffix: '',
        subtitle: 'Yıllık izin talepleri, mazeret ve onaylar',
        icon: Icons.fact_check_outlined,
        iconBg: Color(0xFFF1F5F9),
        iconColor: Color(0xFF475569),
      );
    case '/timesheet':
      return const _MenuTileData(
        titlePrefix: '',
        titleMain: 'Puantaj',
        titleSuffix: '',
        subtitle: 'Aylık personel çalışma ve devam puantajı',
        icon: Icons.assignment_outlined,
        iconBg: Color(0xFFF1F5F9),
        iconColor: Color(0xFF475569),
      );
    case '/recommendations':
      final count = recommendationCount > 0 ? recommendationCount : 7;
      return _MenuTileData(
        titlePrefix: '',
        titleMain: 'SKT & Aksiyon Takibi',
        titleSuffix: '',
        subtitle: 'Yaklaşan son kullanma & fire aksiyonları',
        icon: Icons.hourglass_top_rounded,
        iconBg: const Color(0xFFFEF3C7),
        iconColor: const Color(0xFFD97706),
        badgeText: '$count Kritik',
        badgeBg: const Color(0xFFFEE2E2),
        badgeColor: const Color(0xFFDC2626),
      );
    case '/batches':
      return const _MenuTileData(
        titlePrefix: '',
        titleMain: 'Ürünler',
        titleSuffix: ' & Donuk Depo',
        subtitle: 'Donuk stok sayımı, çözünme ve vitrin',
        icon: Icons.ac_unit_rounded,
        iconBg: Color(0xFFE0F2FE),
        iconColor: Color(0xFF0284C7),
      );
    case '/product-types':
      return const _MenuTileData(
        titlePrefix: '',
        titleMain: 'Pasta Çeşitleri',
        titleSuffix: ' & Raf Ömrü',
        subtitle: 'Reçete, vitrin saati ve porsiyon takibi',
        icon: Icons.cake_outlined,
        iconBg: Color(0xFFF3E8FF),
        iconColor: Color(0xFF9333EA),
      );
    case '/petty-cash':
      return const _MenuTileData(
        titlePrefix: 'Kasa, ',
        titleMain: 'Petty Cash',
        titleSuffix: ' & Satış',
        subtitle: 'Günlük ciro, gider fişleri ve kasa teslimi',
        icon: Icons.account_balance_wallet_outlined,
        iconBg: Color(0xFFDCFCE7),
        iconColor: Color(0xFF15803D),
      );
    case '/profile':
      return const _MenuTileData(
        titlePrefix: '',
        titleMain: 'Profilim',
        titleSuffix: ' & Ayarlar',
        subtitle: 'PIN kodu, bildirimler ve yetki şablonu',
        icon: Icons.manage_accounts_outlined,
        iconBg: Color(0xFFF1F5F9),
        iconColor: Color(0xFF475569),
      );
    case '/dashboard':
      return const _MenuTileData(
        titlePrefix: '',
        titleMain: 'Ana Sayfa',
        titleSuffix: '',
        subtitle: 'Günlük operasyon özeti ve durum göstergeleri',
        icon: Icons.home_outlined,
        iconBg: Color(0xFFE0F2FE),
        iconColor: Color(0xFF0284C7),
      );
    case '/approvals':
      return const _MenuTileData(
        titlePrefix: '',
        titleMain: 'Onaylar',
        titleSuffix: '',
        subtitle: 'Bekleyen transfer, zayi ve ürün onayları',
        icon: Icons.rule_outlined,
        iconBg: Color(0xFFFEF3C7),
        iconColor: Color(0xFFD97706),
      );
    case '/daily-report':
      return const _MenuTileData(
        titlePrefix: '',
        titleMain: 'Rapor Paneli',
        titleSuffix: '',
        subtitle: 'Ciro, satış ve ürün performans grafikleri',
        icon: Icons.assessment_outlined,
        iconBg: Color(0xFFF1F5F9),
        iconColor: Color(0xFF475569),
      );
    case '/stock-coverage':
      return const _MenuTileData(
        titlePrefix: '',
        titleMain: 'Stok Yeterliliği',
        titleSuffix: '',
        subtitle: 'Tahmini stok tükenme süresi ve hız analizi',
        icon: Icons.inventory_outlined,
        iconBg: Color(0xFFF1F5F9),
        iconColor: Color(0xFF475569),
      );
    case '/sales':
      return const _MenuTileData(
        titlePrefix: '',
        titleMain: 'Hareket Raporu',
        titleSuffix: '',
        subtitle: 'Günlük ve haftalık satış hareketleri',
        icon: Icons.payments_outlined,
        iconBg: Color(0xFFDCFCE7),
        iconColor: Color(0xFF15803D),
      );
    case '/logs':
      return const _MenuTileData(
        titlePrefix: '',
        titleMain: 'Hareket Kayıtları',
        titleSuffix: '',
        subtitle: 'Kullanıcı işlem ve denetim logları',
        icon: Icons.receipt_long_outlined,
        iconBg: Color(0xFFF1F5F9),
        iconColor: Color(0xFF475569),
      );
    case '/users':
      return const _MenuTileData(
        titlePrefix: '',
        titleMain: 'Kullanıcılar',
        titleSuffix: '',
        subtitle: 'Personel hesapları ve yetki yönetimi',
        icon: Icons.group_outlined,
        iconBg: Color(0xFFF1F5F9),
        iconColor: Color(0xFF475569),
      );
    case '/stores':
      return const _MenuTileData(
        titlePrefix: '',
        titleMain: 'Mağazalar',
        titleSuffix: '',
        subtitle: 'Şube bilgileri ve mağaza tanımları',
        icon: Icons.store_outlined,
        iconBg: Color(0xFFF1F5F9),
        iconColor: Color(0xFF475569),
      );
    default:
      return _MenuTileData(
        titlePrefix: '',
        titleMain: item.label,
        titleSuffix: '',
        subtitle: item.shortLabel,
        icon: item.icon,
        iconBg: const Color(0xFFF1F5F9),
        iconColor: const Color(0xFF475569),
      );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.item,
    required this.active,
    required this.onTap,
    this.recommendationCount = 0,
  });

  final NavItem item;
  final bool active;
  final VoidCallback onTap;
  final int recommendationCount;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final d = _menuTileDataFor(item, recommendationCount);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final criticalBadge = d.badgeText?.contains('Kritik') ?? false;
    final iconBg = dark ? t.primarySoft : d.iconBg;
    final iconColor = dark ? t.primary : d.iconColor;
    final badgeBg = dark
        ? (criticalBadge ? t.dangerSoft : t.successSoft)
        : d.badgeBg;
    final badgeColor = dark
        ? (criticalBadge ? t.danger : t.okText)
        : d.badgeColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: active ? t.successSoft : t.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? t.success.withValues(alpha: .55)
                    : t.border.withValues(alpha: 0.8),
                width: active ? 1.4 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(d.icon, color: iconColor, size: 21),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                if (d.titlePrefix.isNotEmpty)
                                  Text(
                                    d.titlePrefix,
                                    style: TextStyle(
                                      color: t.ink,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                Flexible(
                                  child: Text(
                                    d.titleMain,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: t.ink,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (d.titleSuffix.isNotEmpty)
                                  Flexible(
                                    child: Text(
                                      d.titleSuffix,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: t.ink,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (d.badgeText != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: badgeBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                d.badgeText!,
                                style: TextStyle(
                                  color: badgeColor,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        d.subtitle,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          color: t.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: active ? t.primary : t.border,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Aktif sekmenin ikonu yumusak bir hap icinde, etiketi altinda durur.
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
    final color = active ? t.primaryDark : t.muted;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppTokens.tap),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 30,
              decoration: BoxDecoration(
                color: active ? t.primarySoft : null,
                borderRadius: BorderRadius.circular(18),
              ),
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
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// PDKS'nin ana eylemi navigasyondan yukseltilerek tek dokunusla tarayiciyi acar.
class _QrBottomTab extends StatelessWidget {
  const _QrBottomTab({required this.onTap, this.open = false});

  final VoidCallback? onTap;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: const Offset(0, -10),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF115E59),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: open ? const Color(0xFF99D5CD) : t.card,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: t.primary.withValues(alpha: .24),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  open ? Icons.close_rounded : Icons.qr_code_scanner_rounded,
                  color: Colors.white,
                  size: 25,
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -7),
              child: Text(
                open ? 'Kapat' : 'QR Okut',
                maxLines: 1,
                style: TextStyle(
                  color: t.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
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
          // React'teki .nav-badge ile ayni taban.
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.4,
        ),
      ),
    );
  }
}

class _RecommendationTab extends StatelessWidget {
  const _RecommendationTab({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: 'Öneri/SKT, $count öneri',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: const Offset(0, -10),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFF115E59),
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(color: t.card, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: t.primary.withValues(alpha: .14),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.local_fire_department_outlined,
                      color: Colors.white,
                      size: 29,
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE91D48),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: t.card, width: 2),
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -7),
              child: Text(
                'Öneri/SKT',
                style: TextStyle(
                  color: t.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
