import 'package:flutter/material.dart';

/// React istemcisindeki index.css :root token'larinin birebir karsiligi.
/// Renkler tek yerde durur; ekranlar dogrudan hex yazmaz.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.primary,
    required this.onPrimary,
    required this.dangerStrong,
    required this.primary600,
    required this.primaryDark,
    required this.primarySoft,
    required this.danger,
    required this.dangerSoft,
    required this.warning,
    required this.warningSoft,
    required this.warningText,
    required this.infoSoft,
    required this.infoText,
    required this.successSoft,
    required this.okText,
    required this.success,
    required this.info,
    required this.ink,
    required this.muted,
    required this.border,
    required this.borderStrong,
    required this.bg,
    required this.card,
    required this.sidebar,
    required this.sidebarInk,
    required this.sidebarMuted,
    required this.sidebarBorder,
  });

  final Color primary;

  /// Birincil zemin UZERINDEKI metin rengi.
  ///
  /// Sabit Colors.white DEGIL: koyu temada primary nane yesili (#34D399) ve
  /// uzerinde beyaz metin yalnizca 1.92 kontrast veriyor — dugme neredeyse
  /// okunmuyor. Koyu temada #0B1220 ayni zeminde 9.74 veriyor.
  /// React tarafindaki --on-primary ile ayni deger.
  final Color onPrimary;

  /// Beyaz metin tasiyan kirmizi zemin. danger koyu temada acik kirmizi
  /// (#F87171) olup beyazla 2.77 veriyor; bu ton 6.47 veriyor.
  final Color dangerStrong;
  final Color primary600;
  final Color primaryDark;
  final Color primarySoft;
  final Color danger;
  final Color dangerSoft;
  final Color warning;
  final Color warningSoft;

  /// Uyari zemini uzerinde KUCUK METIN icin. --warning kucuk yazida acik
  /// temada 3.19 kontrast veriyordu (AA siniri 4.5); nokta ve cubuk gibi
  /// grafik ogelerde 3.0 esigi gecerli oldugu icin --warning orada kaliyor.
  /// React tarafindaki --warning-text ile ayni deger.
  final Color warningText;

  // Cizelgedeki vardiya kategorileri (sabah/gunduz/aksam) ve durum
  // etiketleri icin zemin + KUCUK METIN ciftleri. React tarafindaki
  // --info-soft/--info-text/--success-soft/--ok-text ile ayni degerler.
  //
  // Koyu temada zeminler ONCEDEN BIRLESTIRILMIS kati renkler: saydam ton
  // kullanmak kontrast olcumunu belirsizlestiriyordu (hangi zeminin uzerine
  // dustugu bilinmeden oran hesaplanamiyor).
  //
  // Olculdu (kucuk metin esigi 4.5):
  //   sabah  acik 5.57  koyu 7.83
  //   gunduz acik 4.79  koyu 7.65
  final Color infoSoft;
  final Color infoText;
  final Color successSoft;
  final Color okText;
  final Color success;
  final Color info;
  final Color ink;
  final Color muted;
  final Color border;
  final Color borderStrong;
  final Color bg;
  final Color card;
  final Color sidebar;

  /// Kenar menu artik temayla degisiyor: acik temada acik zemin + koyu yazi,
  /// koyu temada koyu zemin + acik yazi. Yazi renkleri sabit beyaz kalamazdi.
  final Color sidebarInk;
  final Color sidebarMuted;
  final Color sidebarBorder;

  /// Giris ekraninin panel rengi. Temaya gore degismez: koyu temanin
  /// turkuazi tum ekrani kaplayinca goz aliyor, marka rengi ise iki temada da
  /// beyaz yaziyla 5:1 ustu kontrast veriyor.
  static const Color brandGreen = Color(0xFF0F766E);

  /// Dokunma hedefi tabani. React tarafindaki --tap ile ayni.
  static const double tap = 44;
  static const double radiusSm = 10;
  static const double radius = 14;
  static const double radiusLg = 20;
  static const double gap = 12;

  /// Responsive breakpoints — tum ekranlarda ayni sinirlar kullaniyor.
  /// sm: telefon/tablet gecisi | md: tablet/masaustu | lg: genis masaustu
  static const double bpSm = 641;
  static const double bpMd = 900;
  static const double bpLg = 1200;

  static const AppTokens light = AppTokens(
    primary: Color(0xFF0F766E),
    // Turkuaz ana islem rengi; beyaz metinle okunur kontrast.
    onPrimary: Color(0xFFFFFFFF),
    dangerStrong: Color(0xFFDC2626),
    primary600: Color(0xFF0D9488),
    primaryDark: Color(0xFF115E59),
    primarySoft: Color(0xFFE6F8F3),
    danger: Color(0xFFDC2626),
    dangerSoft: Color(0xFFFEF2F2),
    warning: Color(0xFFD97706),
    warningSoft: Color(0xFFFFFBEB),
    warningText: Color(0xFFB45309),
    infoSoft: Color(0xFFECFEFF),
    infoText: Color(0xFF0E7490),
    successSoft: Color(0xFF99FFCD),
    okText: Color(0xFF005E3F),
    success: Color(0xFF007952),
    info: Color(0xFF0E7490),
    ink: Color(0xFF0B1C30),
    muted: Color(0xFF3E4947),
    border: Color(0xFFBDC9C6),
    borderStrong: Color(0xFF6E7977),
    bg: Color(0xFFF8F9FF),
    card: Color(0xFFFFFFFF),
    sidebar: Color(0xFFFFFFFF),
    sidebarInk: Color(0xFF0B1C30),
    sidebarMuted: Color(0xFF3E4947),
    sidebarBorder: Color(0xFFBDC9C6),
  );

  static const AppTokens dark = AppTokens(
    primary: Color(0xFF5EEAD4),
    // Koyu temada acik turkuaz uzerine koyu metin.
    onPrimary: Color(0xFF0B1220),
    dangerStrong: Color(0xFFB91C1C),
    primary600: Color(0xFF10B981),
    primaryDark: Color(0xFF99F6E4),
    primarySoft: Color(0x245EEAD4),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0x1FF87171),
    warning: Color(0xFFFBBF24),
    warningSoft: Color(0x1FFBBF24),
    warningText: Color(0xFFFBBF24),
    infoSoft: Color(0xFF203247),
    infoText: Color(0xFF7DD3FC),
    successSoft: Color(0xFF1A3338),
    okText: Color(0xFF4ADE80),
    success: Color(0xFF4ADE80),
    info: Color(0xFF7DD3FC),
    ink: Color(0xFFE5E9F0),
    muted: Color(0xFF94A3B8),
    border: Color(0xFF243049),
    borderStrong: Color(0xFF33415C),
    bg: Color(0xFF0B1220),
    card: Color(0xFF131C2E),
    sidebar: Color(0xFF070D18),
    sidebarInk: Color(0xFFFFFFFF),
    sidebarMuted: Color(0xFFCBD5E1),
    sidebarBorder: Color(0x2E94A3B8),
  );

  @override
  AppTokens copyWith({
    Color? primary,
    Color? onPrimary,
    Color? dangerStrong,
    Color? primary600,
    Color? primaryDark,
    Color? primarySoft,
    Color? danger,
    Color? dangerSoft,
    Color? warning,
    Color? warningSoft,
    Color? warningText,
    Color? infoSoft,
    Color? infoText,
    Color? successSoft,
    Color? okText,
    Color? success,
    Color? info,
    Color? ink,
    Color? muted,
    Color? border,
    Color? borderStrong,
    Color? bg,
    Color? card,
    Color? sidebar,
    Color? sidebarInk,
    Color? sidebarMuted,
    Color? sidebarBorder,
  }) {
    return AppTokens(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      dangerStrong: dangerStrong ?? this.dangerStrong,
      primary600: primary600 ?? this.primary600,
      primaryDark: primaryDark ?? this.primaryDark,
      primarySoft: primarySoft ?? this.primarySoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      warningText: warningText ?? this.warningText,
      infoSoft: infoSoft ?? this.infoSoft,
      infoText: infoText ?? this.infoText,
      successSoft: successSoft ?? this.successSoft,
      okText: okText ?? this.okText,
      success: success ?? this.success,
      info: info ?? this.info,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      bg: bg ?? this.bg,
      card: card ?? this.card,
      sidebar: sidebar ?? this.sidebar,
      sidebarInk: sidebarInk ?? this.sidebarInk,
      sidebarMuted: sidebarMuted ?? this.sidebarMuted,
      sidebarBorder: sidebarBorder ?? this.sidebarBorder,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      dangerStrong: Color.lerp(dangerStrong, other.dangerStrong, t)!,
      primary600: Color.lerp(primary600, other.primary600, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      warningText: Color.lerp(warningText, other.warningText, t)!,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t)!,
      infoText: Color.lerp(infoText, other.infoText, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      okText: Color.lerp(okText, other.okText, t)!,
      success: Color.lerp(success, other.success, t)!,
      info: Color.lerp(info, other.info, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      sidebarInk: Color.lerp(sidebarInk, other.sidebarInk, t)!,
      sidebarMuted: Color.lerp(sidebarMuted, other.sidebarMuted, t)!,
      sidebarBorder: Color.lerp(sidebarBorder, other.sidebarBorder, t)!,
    );
  }
}

/// Standart boşluk ölçeği (Spacing Scale).
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12; // AppTokens.gap
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

/// Standart köşe yuvarlama ölçeği (Border Radius Scale).
abstract final class AppRadius {
  static const double sm = AppTokens.radiusSm; // 10
  static const double md = AppTokens.radius; // 14
  static const double lg = AppTokens.radiusLg; // 20
  static const double full = 9999;
}

/// Ortak yüzey derinlikleri. Gölge renkleri temaya göre üretildiği için
/// ekranların kendi siyah opaklıklarını tanımlamasına gerek kalmaz.
abstract final class AppElevation {
  static List<BoxShadow> low(Brightness brightness) => [
    BoxShadow(
      color: Colors.black.withValues(
        alpha: brightness == Brightness.dark ? .20 : .055,
      ),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ];

  static List<BoxShadow> medium(Brightness brightness) => [
    BoxShadow(
      color: Colors.black.withValues(
        alpha: brightness == Brightness.dark ? .28 : .09,
      ),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];
}

/// Sayfa ve pencere ölçüleri için ortak responsive sınırlar.
abstract final class AppLayout {
  // 320px cihazda dialog içeriği kenar boşluklarından sonra yaklaşık 270px
  // kalır. Daha geniş telefonlarda yoğun sayısal formlar iki sütunu korur.
  static const double compactForm = 280;
  static const double dialogMaxWidth = 480;
  static const double contentMaxWidth = 1440;

  static double pageGutter(double width) {
    if (width < AppTokens.bpSm) return AppSpacing.lg;
    if (width < AppTokens.bpMd) return AppSpacing.xl;
    return AppSpacing.xxl;
  }
}

extension AppTokensContext on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ?? AppTokens.light;
}

/// Tema üretim algoritmasının sözleşmesi.
///
/// Yeni bir tema varyantı eklenirken [buildAppTheme] içine yeni koşullar
/// yazmak yerine bu strateji genişletilir. Böylece palet, Material renk
/// rolleri ve yüzey davranışları tek bir nesnenin sorumluluğunda kalır.
sealed class AppThemeStrategy {
  const AppThemeStrategy();

  Brightness get brightness;
  AppTokens get tokens;
  Color get scrim;
  double get shadowAlpha;

  /// Açık kırmızı zemin (`dangerSoft`) üzerindeki metin rengi. `danger`
  /// açık temada bu zeminde 4.41:1 kalıyordu (WCAG AA 4.5 altı).
  Color get onDangerSoft;

  ColorScheme buildColorScheme() {
    final t = tokens;
    return ColorScheme.fromSeed(
      seedColor: t.primary,
      brightness: brightness,
    ).copyWith(
      primary: t.primary,
      onPrimary: t.onPrimary,
      primaryContainer: t.primarySoft,
      onPrimaryContainer: t.primaryDark,
      secondary: t.primary600,
      onSecondary: t.onPrimary,
      secondaryContainer: t.successSoft,
      onSecondaryContainer: t.okText,
      error: t.danger,
      onError: const Color(0xFFFFFFFF),
      errorContainer: t.dangerSoft,
      onErrorContainer: onDangerSoft,
      surface: t.card,
      onSurface: t.ink,
      surfaceContainerLowest: t.card,
      surfaceContainerLow: t.card,
      surfaceContainer: t.bg,
      surfaceContainerHigh: t.border,
      surfaceContainerHighest: t.borderStrong,
      onSurfaceVariant: t.muted,
      outline: t.borderStrong,
      outlineVariant: t.border,
      shadow: Colors.black,
      scrim: scrim,
    );
  }

  static AppThemeStrategy resolve(Brightness brightness) =>
      brightness == Brightness.dark
      ? const DarkThemeStrategy()
      : const LightThemeStrategy();
}

final class LightThemeStrategy extends AppThemeStrategy {
  const LightThemeStrategy();

  @override
  Brightness get brightness => Brightness.light;

  @override
  AppTokens get tokens => AppTokens.light;

  @override
  Color get scrim => const Color(0x73111B2E);

  @override
  Color get onDangerSoft => const Color(0xFFB91C1C);

  @override
  double get shadowAlpha => .08;
}

final class DarkThemeStrategy extends AppThemeStrategy {
  const DarkThemeStrategy();

  @override
  Brightness get brightness => Brightness.dark;

  @override
  AppTokens get tokens => AppTokens.dark;

  @override
  Color get scrim => const Color(0xB3020617);

  @override
  Color get onDangerSoft => AppTokens.dark.danger;

  @override
  double get shadowAlpha => .28;
}

ThemeData buildAppTheme(Brightness brightness) {
  final strategy = AppThemeStrategy.resolve(brightness);
  final t = strategy.tokens;
  final base = ThemeData(
    brightness: strategy.brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: t.bg,
    colorScheme: strategy.buildColorScheme(),
  );

  final textTheme = base.textTheme
      .copyWith(
        displayLarge: base.textTheme.displayLarge?.copyWith(
          fontSize: 42,
          height: 1.08,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
        ),
        displayMedium: base.textTheme.displayMedium?.copyWith(
          fontSize: 34,
          height: 1.12,
          fontWeight: FontWeight.w800,
          letterSpacing: -.8,
        ),
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontSize: 28,
          height: 1.18,
          fontWeight: FontWeight.w800,
          letterSpacing: -.45,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontSize: 24,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: -.3,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontSize: 16,
          height: 1.3,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontSize: 16,
          height: 1.5,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.45,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          height: 1.4,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontSize: 14,
          height: 1.2,
          fontWeight: FontWeight.w700,
        ),
      )
      .apply(bodyColor: t.ink, displayColor: t.ink);

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
  );

  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[t],
    textTheme: textTheme,
    dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: t.card,
      elevation: 1,
      margin: EdgeInsets.zero,
      shadowColor: Colors.black.withValues(alpha: strategy.shadowAlpha),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: t.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.card,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.card,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: t.card,
      modalElevation: 8,
      showDragHandle: true,
      dragHandleColor: t.border,
      // Geniş ekranda panel kenardan kenara uzamaz (M3 önerisi 640px).
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.primary,
        foregroundColor: t.onPrimary,
        minimumSize: const Size(0, AppTokens.tap),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        textStyle: textTheme.labelLarge,
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        side: BorderSide(color: t.borderStrong),
        minimumSize: const Size(0, AppTokens.tap),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        textStyle: textTheme.labelLarge,
        shape: buttonShape,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: t.card,
        foregroundColor: t.ink,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: strategy.shadowAlpha),
        minimumSize: const Size(0, AppTokens.tap),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        textStyle: textTheme.labelLarge,
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.primary,
        minimumSize: const Size(0, AppTokens.tap),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        textStyle: textTheme.labelLarge,
        shape: buttonShape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: t.muted,
        minimumSize: const Size.square(AppTokens.tap),
        shape: const CircleBorder(),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.muted,
      textColor: t.ink,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      minTileHeight: AppTokens.tap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: t.bg,
      selectedColor: t.primarySoft,
      disabledColor: t.border.withValues(alpha: .45),
      side: BorderSide(color: t.border),
      labelStyle: textTheme.labelMedium?.copyWith(color: t.ink),
      secondaryLabelStyle: textTheme.labelMedium?.copyWith(
        color: t.primaryDark,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      shape: const StadiumBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.ink,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: t.card),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.primary),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.card,
      // 16px alti yazi iOS'ta sayfayi yakinlastirir; web hedefi oldugu icin korunur.
      hintStyle: TextStyle(color: t.muted, fontSize: 16),
      // 14 -> 11: cep ekraninda formlar cok uzuyordu. 16px yazi boyutu
      // korunuyor, yoksa iOS sayfayi yakinlastiriyor.
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        borderSide: BorderSide(color: t.borderStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        borderSide: BorderSide(color: t.borderStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        borderSide: BorderSide(color: t.primary600, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: t.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: t.danger, width: 2),
      ),
    ),
  );
}
