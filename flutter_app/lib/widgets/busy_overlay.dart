import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/busy.dart';
import '../core/tokens.dart';

/// Tam ekran, buzlu cam efektli yukleme katmani. Tum ekrani ortuger, boylece
/// islem bitene kadar arkadaki hicbir kontrole erisilemez.
class BusyOverlay extends StatelessWidget {
  const BusyOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        AnimatedBuilder(
          animation: busy,
          builder: (context, _) {
            if (!busy.visible) return const SizedBox.shrink();
            // Mesaj parametre olarak gecirilir: const _Overlay() ayni ornek
            // oldugu icin metin degisse de yeniden cizilmiyordu.
            return _Overlay(message: busy.message);
          },
        ),
      ],
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Positioned.fill(
      // Katman MaterialApp.builder icinde, yani Navigator'in ve dolayisiyla
      // Material'in disinda duruyor. Material olmadan Text, Flutter'in
      // "eksik Material" isareti olan sari cift alt cizgiyle ciziliyordu.
      child: Material(
        type: MaterialType.transparency,
        // Katman tiklamalari yutar: yukleme sirasinda islem yapilamaz.
        child: AbsorbPointer(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: ColoredBox(
              color: dark ? const Color(0x73020617) : const Color(0x59111827),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: t.card,
                    border: Border.all(color: t.border),
                    borderRadius: BorderRadius.circular(18),
                    // React'teki --shadow-lg'nin karsiligi: kart koyu zeminden
                    // ayrissin diye yumusak golge.
                    // Koyu zeminde yogun golge bant gibi duruyordu; daha genis
                    // ve daha seffaf iki katman yumusak hale veriyor.
                    boxShadow: dark
                        ? const [
                            BoxShadow(
                              color: Color(0x40020617),
                              blurRadius: 28,
                              offset: Offset(0, 6),
                            ),
                            BoxShadow(
                              color: Color(0x4D020617),
                              blurRadius: 72,
                              offset: Offset(0, 18),
                            ),
                          ]
                        : const [
                            BoxShadow(
                              color: Color(0x14111827),
                              blurRadius: 16,
                              offset: Offset(0, 8),
                            ),
                            BoxShadow(
                              color: Color(0x1A111827),
                              blurRadius: 48,
                              offset: Offset(0, 24),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: t.primary,
                          // Iz olmadan yalnizca hareket eden yay goruluyordu;
                          // izle birlikte halka olarak okunuyor (React'teki
                          // .spinner ile ayni gorunum).
                          backgroundColor: t.border,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        message,
                        style: TextStyle(
                          color: t.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
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
    );
  }
}
