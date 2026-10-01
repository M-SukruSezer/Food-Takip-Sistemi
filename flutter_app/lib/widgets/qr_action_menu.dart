import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../models/pdks.dart';

/// Only covers page content: the identity header and navigation stay visible.
class QrActionMenu extends StatelessWidget {
  const QrActionMenu({
    super.key,
    required this.status,
    required this.error,
    required this.onClose,
    required this.onShift,
    required this.onBreak,
    required this.onRetry,
  });
  final PdksStatus? status;
  final String? error;
  final VoidCallback onClose, onShift, onBreak, onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = status;
    final minutes = s?.shifts.firstOrNull?.breakMinutes;
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: GestureDetector(
                onTap: onClose,
                child: ColoredBox(
                  color: dark
                      ? const Color(0xA6020617)
                      : const Color(0x66111827),
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (error != null)
                    Material(
                      color: t.card,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(error!, style: TextStyle(color: t.ink)),
                            TextButton(
                              onPressed: onRetry,
                              child: const Text("Tekrar dene"),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    _ActionCard(
                      title: "Vardiya Giriş / Çıkış",
                      subtitle: "Mesai başlangıcı veya sonu",
                      icon: Icons.login_rounded,
                      accent: context.tokens.success,
                      iconBackground: dark
                          ? t.primarySoft
                          : context.tokens.successSoft,
                      badge: s == null
                          ? "…"
                          : s.isInside
                          ? "AKTİF"
                          : "GİRİŞ",
                      badgeBackground: dark
                          ? t.primarySoft
                          : context.tokens.successSoft,
                      badgeColor: dark ? t.primary : context.tokens.success,
                      onTap: s == null ? null : onShift,
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      title: "Mola Giriş / Çıkış",
                      subtitle: "Kahve ve dinlenme molası",
                      icon: Icons.coffee_outlined,
                      accent: context.tokens.warning,
                      iconBackground: dark ? t.bg : context.tokens.warningSoft,
                      badge: s == null
                          ? "…"
                          : s.onBreak
                          ? "MOLADA"
                          : minutes != null && minutes > 0
                          ? "$minutes dk"
                          : "MOLA",
                      badgeBackground: t.bg,
                      badgeColor: t.muted,
                      onTap: s == null ? null : onBreak,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.iconBackground,
    required this.badge,
    required this.badgeBackground,
    required this.badgeColor,
    required this.onTap,
  });
  final String title, subtitle, badge;
  final IconData icon;
  final Color accent, iconBackground, badgeBackground, badgeColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: t.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(color: t.border.withValues(alpha: .55)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: accent, size: 23),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: t.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: t.muted,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBackground,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
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
