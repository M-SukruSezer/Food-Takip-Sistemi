import 'dart:convert';

import '../core/login_branding.dart';

import 'package:flutter/material.dart';

/// Giris ekranindaki illustrasyon.
///
/// Sabit bir raster gorsel (assets/login-art.png): eller beyaz dolgulu ve
/// siyah konturlu, zemini saydam. Bu yuzden her zaman acik bir kart uzerinde
/// gosterilir — koyu kartta siyah konturlar kaybolurdu. Kart rengini
/// [LoginArt] degil cagiran ekran belirler.
class LoginArt extends StatelessWidget {
  const LoginArt({super.key, this.fit = BoxFit.contain});

  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: loginArtwork,
      builder: (context, value, _) {
        if (value != null) {
          try {
            return Image.memory(
              base64Decode(value.split(',').last),
              width: double.infinity,
              fit: fit,
              gaplessPlayback: true,
              semanticLabel: 'Giriş görseli',
              errorBuilder: (_, _, _) => _defaultArt(),
            );
          } catch (_) {
            return _defaultArt();
          }
        }
        return _defaultArt();
      },
    );
  }

  Widget _defaultArt() => Image.asset(
    'assets/colombia_cafe.png',
    width: double.infinity,
    fit: fit,
    errorBuilder: (context, error, stackTrace) => Image.asset(
      'assets/login-art.png',
      width: double.infinity,
      fit: fit,
      semanticLabel: 'Colombia Cafe illüstrasyonu',
    ),
    semanticLabel: 'Colombia Cafe illüstrasyonu',
  );
}
