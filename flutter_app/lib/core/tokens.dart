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

  /// Giris ekraninin panel rengi. Temaya gore DEGISMEZ: koyu temanin acik
  /// teali tum ekrani kaplayinca goz aliyor. Derin orman yesili (sistemin
  /// secondary tonu) iki temada da beyaz yaziyla 9.59 kontrast veriyor.
  static const Color brandGreen = Color(0xFF134E3F);

  /// Dokunma hedefi. Sistem birincil eylemler icin 48px istiyor; magazada
  /// telefon tek elle ve acele kullaniliyor. [tapMin] mutlak taban olarak
  /// testlerde zorlanmaya devam ediyor.
  ///
  /// React karsiligi: --tap / --tap-min.
  static const double tap = 48;
  static const double tapMin = 44;

  /// Kose yaricapi. Sistem "Rounded 2" tabani: 8px kucuk ogeler,
  /// 16px kart/dugme, 24px alt sayfa ve modal.
  static const double radiusSm = 8;
  static const double radius = 16;
  static const double radiusLg = 24;

  /// 4px/8px artimli bosluk izgarasi.
  static const double gap = 12;
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  /// Yazi tipleri. Basliklar ve sayisal gostergeler Plus Jakarta Sans,
  /// govde metni Inter. Ikisi de assets/fonts altindan gomulu geliyor.
  static const String fontDisplay = 'PlusJakartaSans';
  static const String fontBody = 'Inter';

  /// Acik tema. Kaynak: stitch yeniden tasarim paketi
  /// (retail_operations_system/DESIGN.md). Her deger React tarafindaki
  /// index.css :root ile ELLE ESLENIYOR.
  static const AppTokens light = AppTokens(
    // Derin perakende yesili. Beyaz metinle 7.89 (olculdu).
    primary: Color(0xFF005C55),
    onPrimary: Color(0xFFFFFFFF),
    dangerStrong: Color(0xFF991B1B),
    primary600: Color(0xFF0F766E),
    primaryDark: Color(0xFF00403B),
    primarySoft: Color(0xFFD6F0EC),
    danger: Color(0xFFBA1A1A),
    dangerSoft: Color(0xFFFEE2E2),
    warning: Color(0xFFB45309),
    warningSoft: Color(0xFFFEF3C7),
    warningText: Color(0xFF92400E),
    infoSoft: Color(0xFFE0F2FE),
    infoText: Color(0xFF075985),
    successSoft: Color(0xFFD1FAE5),
    okText: Color(0xFF065F46),
    // Sistemin parlak zumrutu (#10B981) BILEREK kullanilmadi: beyaz
    // metinle 2.54 veriyor ve kucuk metin esigini gecmiyor. Ayni ailenin
    // koyu tonu hem esigi geciyor hem ayni okumayi veriyor.
    success: Color(0xFF047857),
    info: Color(0xFF0369A1),
    ink: Color(0xFF0B1C30),
    muted: Color(0xFF475569),
    border: Color(0xFFE2E8F0),
    borderStrong: Color(0xFFCBD5E1),
    bg: Color(0xFFF8FAFC),
    card: Color(0xFFFFFFFF),
    sidebar: Color(0xFFFFFFFF),
    sidebarInk: Color(0xFF0B1C30),
    sidebarMuted: Color(0xFF475569),
    sidebarBorder: Color(0xFFE2E8F0),
  );

  /// Koyu tema. Kaynak sistemde TANIMLI DEGIL — yalnizca acik tema icin
  /// ayarlanmis. Buradaki degerler ayni teal kimligi koruyacak sekilde
  /// TURETILDI ve tek tek olculdu; contrast_test.dart hepsini zorluyor.
  static const AppTokens dark = AppTokens(
    primary: Color(0xFF5EEAD4),
    // Acik teal uzerine koyu yazi: 11.56 (olculdu).
    onPrimary: Color(0xFF03201D),
    dangerStrong: Color(0xFFFCA5A5),
    primary600: Color(0xFF2DD4BF),
    primaryDark: Color(0xFF99F6E4),
    primarySoft: Color(0xFF16343A),
    danger: Color(0xFFFCA5A5),
    dangerSoft: Color(0xFF3A2230),
    warning: Color(0xFFFBBF24),
    warningSoft: Color(0xFF33332D),
    warningText: Color(0xFFFBBF24),
    infoSoft: Color(0xFF17304A),
    infoText: Color(0xFF7DD3FC),
    successSoft: Color(0xFF18363D),
    okText: Color(0xFF34D399),
    success: Color(0xFF34D399),
    info: Color(0xFF7DD3FC),
    ink: Color(0xFFE6EDF5),
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
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: t.primary,
          brightness: brightness,
        ).copyWith(
          primary: t.primary,
          onPrimary: t.onPrimary,
          error: t.danger,
          surface: t.card,
        ),
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
        foregroundColor: t.onPrimary,
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
