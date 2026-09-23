import 'package:flutter/material.dart';

import '../core/tokens.dart';

/// React tarafindaki .card karsiligi.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final narrow = MediaQuery.sizeOf(context).width < 641;
    return Container(
      width: double.infinity,
      padding: padding ?? EdgeInsets.all(narrow ? 14 : 18),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppTokens.radius),
      ),
      child: child,
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
    final narrow = MediaQuery.sizeOf(context).width < 641;
    final card = Container(
      padding: EdgeInsets.all(narrow ? 11 : 16),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppTokens.radius),
      ),
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
                  style: TextStyle(fontSize: narrow ? 12 : 13, color: t.muted, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: narrow ? 20 : 26,
              fontWeight: FontWeight.w700,
              color: valueColor ?? t.ink,
              letterSpacing: -0.4,
            ),
          ),
          if (sub != null)
            Text(
              sub!,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: narrow ? 11 : 12, color: t.muted),
            ),
        ],
      ),
    );

    if (onTap == null) return card;
    // Tiklanabilir kart: dalga efekti kartin yuvarlak kosesine kirpilir.
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTokens.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        child: card,
      ),
    );
  }
}


/// Uyari bandi (React'teki .alert).
class AppAlert extends StatelessWidget {
  const AppAlert({super.key, required this.message, this.danger = true, this.icon, this.trailing});

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
        color: danger ? t.dangerSoft : t.primarySoft,
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Row(
        children: [
          Icon(icon ?? Icons.warning_amber_rounded, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
          ?trailing,
        ],
      ),
    );
  }
}
