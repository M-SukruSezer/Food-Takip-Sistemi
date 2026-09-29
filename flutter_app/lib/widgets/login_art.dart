import 'package:flutter/material.dart';

/// Giris ekranindaki illustrasyon.
///
/// Sabit bir raster gorsel (assets/login-art.png): eller beyaz dolgulu ve
/// siyah konturlu, zemini saydam. Bu yuzden her zaman acik bir kart uzerinde
/// gosterilir — koyu kartta siyah konturlar kaybolurdu. Kart rengini
/// [LoginArt] degil cagiran ekran belirler.
class LoginArt extends StatelessWidget {
  const LoginArt({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/colombia_cafe.png',
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Image.asset(
        'assets/login-art.png',
        fit: BoxFit.contain,
        semanticLabel: 'Colombia Cafe illüstrasyonu',
      ),
      semanticLabel: 'Colombia Cafe illüstrasyonu',
    );
  }
}
