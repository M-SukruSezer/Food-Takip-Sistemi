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
    // Gorsel kare ve kendi icinde dikey boslugu var; buyutup kirpmak kollari
    // kesiyordu, bu yuzden oldugu gibi sigdirilir.
    return Image.asset(
      'assets/login-art.png',
      fit: BoxFit.contain,
      semanticLabel: 'Çak bir beş illüstrasyonu',
    );
  }
}
