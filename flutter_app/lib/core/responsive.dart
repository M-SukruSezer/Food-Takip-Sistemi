import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Pencere sınıfı. Ekranlar piksel karşılaştırması yazmak yerine bu sınıfa
/// göre karar verir; eşikler yalnızca [Breakpoints] içinde tanımlıdır.
enum WindowSize {
  /// Telefon (dikey). Alt menü, tek sütun, alttan açılan paneller.
  compact,

  /// Büyük telefon yatay / küçük tablet. İki sütun.
  medium,

  /// Tablet yatay / küçük masaüstü. Kenar menü, üç sütun.
  expanded,

  /// Geniş masaüstü. İçerik [AppLayout.contentMaxWidth] ile sınırlanır.
  large;

  bool get isCompact => this == WindowSize.compact;
  bool get isAtLeastMedium => index >= WindowSize.medium.index;
  bool get isAtLeastExpanded => index >= WindowSize.expanded.index;
}

/// Uygulamanın tek kırılım tablosu. Web istemcisindeki CSS eşikleriyle aynı.
abstract final class Breakpoints {
  static const double medium = AppTokens.bpSm; // 641
  static const double expanded = AppTokens.bpMd; // 900
  static const double large = AppTokens.bpLg; // 1200

  /// 360px altı (iPhone SE, eski Android). Yalnızca yoğunluk ayarı için;
  /// yerleşim kararı [WindowSize] ile verilir.
  static const double narrowPhone = 360;

  static WindowSize of(double width) {
    if (width < medium) return WindowSize.compact;
    if (width < expanded) return WindowSize.medium;
    if (width < large) return WindowSize.expanded;
    return WindowSize.large;
  }

  /// Kart ızgarası sütun sayısı.
  static int gridColumns(double width) => switch (of(width)) {
    WindowSize.compact => 1,
    WindowSize.medium => 2,
    WindowSize.expanded => 3,
    WindowSize.large => 4,
  };
}

extension ResponsiveContext on BuildContext {
  /// Yalnızca genişlik değişince yeniden kurar (klavye açılması tetiklemez).
  double get screenWidth => MediaQuery.sizeOf(this).width;

  WindowSize get windowSize => Breakpoints.of(screenWidth);
  bool get isCompact => windowSize.isCompact;
  bool get isNarrowPhone => screenWidth < Breakpoints.narrowPhone;

  /// Sayfa kenar boşluğu; ekran büyüdükçe artar.
  double get pageGutter => AppLayout.pageGutter(screenWidth);
}

/// Geniş ekranda içeriği ortalayıp okunabilir genişlikte tutar.
///
/// 1920px masaüstünde formların ve listelerin kenardan kenara uzaması
/// yerine bu sarmalayıcı kullanılır. Dar ekranda hiçbir etkisi yoktur.
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.contentMaxWidth,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Ebeveynin verdiği genişliğe göre farklı ağaç kurar. Ekran yerine
/// gerçek kullanılabilir alanı ölçtüğü için kenar menü açıkken de doğru
/// karar verir.
class AdaptiveLayout extends StatelessWidget {
  const AdaptiveLayout({
    super.key,
    required this.compact,
    this.medium,
    this.expanded,
  });

  final WidgetBuilder compact;
  final WidgetBuilder? medium;
  final WidgetBuilder? expanded;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Breakpoints.of(constraints.maxWidth);
        if (size.isAtLeastExpanded && expanded != null) {
          return expanded!(context);
        }
        if (size.isAtLeastMedium && medium != null) return medium!(context);
        return compact(context);
      },
    );
  }
}
