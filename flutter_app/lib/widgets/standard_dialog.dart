import 'package:flutter/material.dart';

import '../core/responsive.dart';
import '../core/tokens.dart';
import 'scrim.dart';

/// Uygulamadaki tüm form, onay ve detay pencerelerinin tek giriş noktası.
///
/// Telefonda ([WindowSize.compact]) alttan kayan panel, tablet ve
/// masaüstünde ortalanmış diyalog olarak açılır. İçerik her iki durumda da
/// aynı [StandardDialog] çerçevesini kullanır; ekranların kendi köşe
/// yarıçapı, tutamaç, gölge veya perde rengi tanımlaması gerekmez.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final asSheet = context.isCompact;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Kapat',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: barrierDismissible ? () => Navigator.maybePop(ctx) : null,
            child: const AppScrim(absorb: false, child: SizedBox.expand()),
          ),
        ),
        SafeArea(
          bottom: !asSheet,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: Align(
              alignment: asSheet ? Alignment.bottomCenter : Alignment.center,
              child: Padding(
                padding: asSheet
                    ? EdgeInsets.zero
                    : const EdgeInsets.all(AppSpacing.xxl),
                child: _Presentation(
                  asSheet: asSheet,
                  child: Builder(builder: builder),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      if (asSheet) {
        return SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      }
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: .96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// [showAppSheet] içeriğe hangi biçimde açıldığını bu kapsamla bildirir.
class _Presentation extends InheritedWidget {
  const _Presentation({required this.asSheet, required super.child});

  final bool asSheet;

  static bool? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Presentation>()?.asSheet;

  @override
  bool updateShouldNotify(_Presentation old) => old.asSheet != asSheet;
}

/// Standart pencere çerçevesi: başlık, kaydırılabilir gövde, sabit alt bar.
///
/// * Gövde her zaman kaydırılır; klavye açıldığında ya da 320px telefonda
///   hiçbir alan taşmaz.
/// * Yükseklik ekranın %94'ü ile, genişlik [maxWidth] ile sınırlanır.
/// * Panel modunda üstteki tutamaç aşağı sürüklenerek kapatılabilir;
///   [busy] iken kapatma (geri tuşu dahil) engellenir.
class StandardDialog extends StatelessWidget {
  const StandardDialog({
    super.key,
    required this.title,
    required this.child,
    this.footer,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.busy = false,
    this.background,
    this.maxWidth = 560,
    this.showClose = true,
  });

  final Widget title;
  final Widget child;
  final Widget? footer;
  final String? subtitle;
  final IconData? icon;

  /// Başlık simgesinin vurgu rengi (ör. zayi için tehlike rengi).
  final Color? iconColor;
  final bool busy;
  final Color? background;
  final double maxWidth;
  final bool showClose;

  /// İçerik alttan panel olarak mı açıldı? Kendi yüzeyini çizen içerikler
  /// (bildirim listesi gibi) köşe ve boşluk kararını buradan alır.
  static bool isSheet(BuildContext context) =>
      _Presentation.maybeOf(context) ?? context.isCompact;

  /// Panelde yalnızca üst köşeler, diyalogda dört köşe yuvarlanır.
  static BorderRadius radiusOf(BuildContext context) => isSheet(context)
      ? const BorderRadius.vertical(top: Radius.circular(AppRadius.lg))
      : BorderRadius.circular(AppRadius.lg);

  void _close(BuildContext context) {
    if (!busy) Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    final asSheet = isSheet(context);
    final gutter = asSheet ? AppSpacing.xl : AppSpacing.xxl;
    final accent = iconColor ?? t.primary;
    final radius = radiusOf(context);

    final header = Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        asSheet ? 0 : AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, size: 20, color: accent),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DefaultTextStyle(
                  style: text.titleMedium!.copyWith(
                    color: t.ink,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  child: title,
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall!.copyWith(color: t.muted),
                    ),
                  ),
              ],
            ),
          ),
          if (showClose)
            IconButton(
              tooltip: 'Kapat',
              onPressed: busy ? null : () => _close(context),
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
        ],
      ),
    );

    return PopScope(
      canPop: !busy,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight:
              (media.size.height -
                  media.padding.top -
                  media.viewInsets.bottom) *
              .94,
        ),
        child: Material(
          color: background ?? t.card,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          elevation: asSheet ? 0 : Theme.of(context).dialogTheme.elevation ?? 6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (asSheet)
                // Tutamaç ve başlık birlikte sürüklenir; hızlı aşağı
                // kaydırma paneli kapatır.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) > 600) _close(context);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                          decoration: BoxDecoration(
                            color: t.border,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                        ),
                      ),
                      header,
                    ],
                  ),
                )
              else
                header,
              Flexible(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    AppSpacing.xs,
                    gutter,
                    AppSpacing.lg,
                  ),
                  child: child,
                ),
              ),
              if (footer != null)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: t.border.withValues(alpha: .5)),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    bottom: asSheet,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        gutter,
                        AppSpacing.md,
                        gutter,
                        AppSpacing.lg,
                      ),
                      child: footer,
                    ),
                  ),
                )
              else if (asSheet)
                SafeArea(top: false, child: const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pencerenin ana eyleminin anlamı; buton rengini belirler.
enum ActionTone { primary, danger, success }

/// Standart alt bar: "Vazgeç" + ana eylem.
///
/// Butonlar yan yana durur (ana eylem daha geniş). Kullanılabilir genişlik
/// 280px altına düşerse (320px telefon + büyük yazı tipi) alt alta dizilir;
/// sabit genişlik kullanılmadığı için etiketler hiçbir zaman taşmaz.
class DialogActions extends StatelessWidget {
  const DialogActions({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    this.cancelLabel = 'Vazgeç',
    this.onCancel,
    this.confirmIcon,
    this.tone = ActionTone.primary,
    this.color,
    this.busy = false,
    this.busyLabel = 'Kaydediliyor...',
  });

  final String confirmLabel;
  final VoidCallback? onConfirm;
  final String cancelLabel;

  /// Verilmezse pencere `false` ile kapanır.
  final VoidCallback? onCancel;
  final IconData? confirmIcon;
  final ActionTone tone;

  /// [tone] yerine özel vurgu rengi (ör. çeşide özgü renk).
  final Color? color;
  final bool busy;
  final String busyLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bg =
        color ??
        switch (tone) {
          ActionTone.primary => t.primary,
          ActionTone.danger => t.dangerStrong,
          ActionTone.success => t.success,
        };
    final fg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? Colors.white
        : t.ink;
    final label = Text(
      busy ? busyLabel : confirmLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final confirmStyle = FilledButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      minimumSize: const Size(0, 48),
    );
    final confirm = busy
        ? FilledButton.icon(
            style: confirmStyle,
            onPressed: null,
            icon: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.muted),
            ),
            label: label,
          )
        : confirmIcon != null
        ? FilledButton.icon(
            style: confirmStyle,
            onPressed: onConfirm,
            icon: Icon(confirmIcon, size: 18),
            label: label,
          )
        : FilledButton(style: confirmStyle, onPressed: onConfirm, child: label);
    final cancel = OutlinedButton(
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
      onPressed: busy
          ? null
          : (onCancel ?? () => Navigator.maybePop(context, false)),
      child: Text(cancelLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < AppLayout.compactForm) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              confirm,
              const SizedBox(height: AppSpacing.sm),
              cancel,
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 2, child: cancel),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 3, child: confirm),
          ],
        );
      },
    );
  }
}

/// Satır içi hata kutusu. Formlar sunucu hatasını alanların üstünde gösterir.
class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = t.dangerText;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: t.dangerSoft,
        border: Border.all(color: t.danger.withValues(alpha: .3)),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: fg),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall!
                  .copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
