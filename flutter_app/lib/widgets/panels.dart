import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../core/responsive.dart';

/// React tarafindaki .card karsiligi.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final narrow = context.isCompact;
    final content = Ink(
      width: double.infinity,
      padding:
          padding ?? EdgeInsets.all(narrow ? AppSpacing.md : AppSpacing.lg),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: elevated
            ? AppElevation.low(Theme.of(context).brightness)
            : null,
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// React tarafindaki .stat-card karsiligi: etiket, deger, alt not.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.icon,
    this.valueColor,
    this.onTap,
  });

  final String label;
  final String value;
  final String? sub;
  final IconData? icon;
  final Color? valueColor;

  /// Verilirse kart tiklanabilir olur ve ilgili ekrana gider.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final narrow = context.isCompact;
    final card = AppCard(
      padding: EdgeInsets.all(narrow ? 11 : AppSpacing.lg),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: t.muted),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: narrow ? AppFontSize.label : AppFontSize.body,
                    color: t.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Uzun değer (ör. "1.250 adet") dar kutuda taşmaz, küçülerek sığar.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: narrow
                    ? AppFontSize.headline
                    : AppFontSize.headlineLarge,
                fontWeight: FontWeight.w700,
                color: valueColor ?? t.ink,
                letterSpacing: -0.4,
              ),
            ),
          ),
          if (sub != null)
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: narrow ? AppFontSize.caption : AppFontSize.label,
                color: t.muted,
              ),
            ),
        ],
      ),
    );

    return card;
  }
}

/// Uyari bandi (React'teki .alert).
class AppAlert extends StatelessWidget {
  const AppAlert({
    super.key,
    required this.message,
    this.danger = true,
    this.icon,
    this.trailing,
  });

  final String message;
  final bool danger;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = danger ? t.danger : t.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: danger ? t.dangerSoft : t.warningSoft,
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Row(
        children: [
          Icon(icon ?? Icons.warning_amber_rounded, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Standart boş durum bileşeni (ikon, başlık, açıklama, opsiyonel işlem).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String message;
  final String? title;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: t.card,
                shape: BoxShape.circle,
                border: Border.all(color: t.border),
              ),
              child: Icon(icon, size: 36, color: t.muted),
            ),
            if (title != null) ...[
              const SizedBox(height: 16),
              Text(
                title!,
                style: TextStyle(
                  fontSize: AppFontSize.title,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(fontSize: AppFontSize.bodyLarge, color: t.muted),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Standart hata durumu bileşeni.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.title = 'Bir Hata Oluştu',
  });

  final String message;
  final VoidCallback onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: t.dangerSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 36,
                color: t.danger,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: AppFontSize.title,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(fontSize: AppFontSize.bodyLarge, color: t.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Eşit boyutlu, responsive kutucuk ızgarası.
///
/// Önceki ızgaralar kutu yüksekliğini en-boy oranıyla (1.45, 1.55, 1.8…)
/// hesaplıyordu: kutular ekran genişledikçe büyüyor, bölümler arasında
/// farklı boyutlarda kalıyordu. Burada yükseklik SABİT ([tileHeight]),
/// sütun sayısı ise kullanılabilir genişlikten hesaplanır: her kutu en az
/// [minTileWidth] genişlikte olur, en fazla [maxColumns] sütun açılır.
/// Böylece ana sayfa ve diğer ekranlardaki tüm kutular aynı boyuttadır.
class EqualTileGrid extends StatelessWidget {
  const EqualTileGrid({
    super.key,
    required this.children,
    this.minTileWidth = 150,
    this.maxColumns = 6,
    this.minColumns = 2,
    this.tileHeight = EqualTileGrid.defaultHeight,
    this.spacing = AppTokens.gap,
  });

  /// Tüm uygulamada kutucuk yüksekliği.
  static const double defaultHeight = 112;

  final List<Widget> children;
  final double minTileWidth;
  final int maxColumns;
  final int minColumns;
  final double tileHeight;
  final double spacing;

  /// Verilen genişlikte kaç sütun açılacağı (test edilebilir saf hesap).
  static int columnsFor(
    double width, {
    double minTileWidth = 150,
    int maxColumns = 6,
    int minColumns = 2,
    double spacing = AppTokens.gap,
  }) {
    final fit = ((width + spacing) / (minTileWidth + spacing)).floor();
    return fit.clamp(minColumns, maxColumns);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = math.min(
          columnsFor(
            c.maxWidth,
            minTileWidth: minTileWidth,
            maxColumns: maxColumns,
            minColumns: minColumns,
            spacing: spacing,
          ),
          math.max(children.length, 1),
        );
        return GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            mainAxisExtent: tileHeight,
          ),
          children: children,
        );
      },
    );
  }
}
