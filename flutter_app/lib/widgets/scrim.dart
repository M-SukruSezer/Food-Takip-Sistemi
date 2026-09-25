import 'dart:ui';

import 'package:flutter/material.dart';

/// Buzlu cam perde. Yukleme katmani ve kisayol menusu ayni gorunumu paylasir;
/// tek tanim olmasi ikisinin zamanla ayrismasini engelliyor.
class AppScrim extends StatelessWidget {
  const AppScrim({super.key, required this.child, this.absorb = true});

  final Widget child;

  /// Yukleme katmaninda tiklamalar yutulur (islem bitene kadar hicbir kontrole
  /// erisilmemeli). Kisayol menusunde perdeye dokunmak menuyu kapatir, bu
  /// yuzden orada kapatilir.
  final bool absorb;

  /// Perdenin zemin rengi. Koyu temada daha koyu ve daha az seffaf.
  static Color color(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0x73020617)
          : const Color(0x59111827);

  @override
  Widget build(BuildContext context) {
    final body = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: ColoredBox(color: color(context), child: child),
    );
    return absorb ? AbsorbPointer(child: body) : body;
  }
}
