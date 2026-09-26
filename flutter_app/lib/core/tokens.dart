import 'package:flutter/material.dart';

/// React istemcisindeki index.css :root token'larinin birebir karsiligi.
/// Renkler tek yerde durur; ekranlar dogrudan hex yazmaz.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.primary,
    required this.primary600,
    required this.primaryDark,
    required this.primarySoft,
    required this.danger,
    required this.dangerSoft,
    required this.warning,
    required this.warningSoft,
    required this.warningText,
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

  /// Giris ekraninin panel rengi. Temaya gore degismez: koyu temanin nane
  /// yesili tum ekrani kaplayinca goz aliyor, marka yesili ise iki temada da
  /// beyaz yaziyla 5:1 kontrast veriyor.
  static const Color brandGreen = Color(0xFF15803D);

  /// Dokunma hedefi tabani. React tarafindaki --tap ile ayni.
  static const double tap = 44;
  static const double radiusSm = 10;
  static const double radius = 14;
  static const double radiusLg = 20;
  static const double gap = 12;

  static const AppTokens light = AppTokens(
    primary: Color(0xFF15803D),
    primary600: Color(0xFF16A34A),
    primaryDark: Color(0xFF14532D),
    primarySoft: Color(0xFFEAFAF0),
    danger: Color(0xFFDC2626),
    dangerSoft: Color(0xFFFEF2F2),
    warning: Color(0xFFD97706),
    warningSoft: Color(0xFFFFFBEB),
    warningText: Color(0xFFB45309),
    success: Color(0xFF16A34A),
    info: Color(0xFF0284C7),
    ink: Color(0xFF111827),
    muted: Color(0xFF6B7280),
    border: Color(0xFFE5E7EB),
    borderStrong: Color(0xFFD1D5DB),
    bg: Color(0xFFF5F6F8),
    card: Color(0xFFFFFFFF),
    sidebar: Color(0xFFFFFFFF),
    sidebarInk: Color(0xFF111827),
    sidebarMuted: Color(0xFF4B5563),
    sidebarBorder: Color(0xFFE5E7EB),
  );

  static const AppTokens dark = AppTokens(
    primary: Color(0xFF34D399),
    primary600: Color(0xFF10B981),
    primaryDark: Color(0xFF6EE7B7),
    primarySoft: Color(0x2434D399),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0x1FF87171),
    warning: Color(0xFFFBBF24),
    warningSoft: Color(0x1FFBBF24),
    warningText: Color(0xFFFBBF24),
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
    Color? primary600,
    Color? primaryDark,
    Color? primarySoft,
    Color? danger,
    Color? dangerSoft,
    Color? warning,
    Color? warningSoft,
    Color? warningText,
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
      primary600: primary600 ?? this.primary600,
      primaryDark: primaryDark ?? this.primaryDark,
      primarySoft: primarySoft ?? this.primarySoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      warningText: warningText ?? this.warningText,
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
      primary600: Color.lerp(primary600, other.primary600, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      warningText: Color.lerp(warningText, other.warningText, t)!,
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

extension AppTokensContext on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ?? AppTokens.light;
}

ThemeData buildAppTheme(Brightness brightness) {
  final t = brightness == Brightness.dark ? AppTokens.dark : AppTokens.light;
  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: t.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: t.primary,
      brightness: brightness,
    ).copyWith(primary: t.primary, error: t.danger, surface: t.card),
  );

  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[t],
    textTheme: base.textTheme.apply(bodyColor: t.ink, displayColor: t.ink),
    cardTheme: CardThemeData(
      color: t.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: t.border),
        borderRadius: BorderRadius.circular(AppTokens.radius),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, AppTokens.tap),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        side: BorderSide(color: t.borderStrong),
        minimumSize: const Size(0, AppTokens.tap),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
      ),
    ),
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
    ),
  );
}
