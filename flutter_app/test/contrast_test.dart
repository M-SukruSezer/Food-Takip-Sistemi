import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/tokens.dart';

// Renk kontrasti denetimi.
//
// Bu testler TEMADAN okuyor, sabit degerlerle kiyaslamiyor: bir belirtec
// ilerde degistiginde test kirilir ve kontrast dususu fark edilir.
//
// Esikler WCAG 2.2: kucuk metin 4.5, buyuk/kalin metin ve grafik oge 3.0.

double _lin(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _lum(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

/// Iki rengin kontrast orani.
double kontrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const temalar = {'açık': AppTokens.light, 'koyu': AppTokens.dark};

  group('Dolu dügme metni okunabilir', () {
    for (final e in temalar.entries) {
      test('${e.key} tema: onPrimary / primary', () {
        final k = kontrast(e.value.onPrimary, e.value.primary);
        expect(
          k,
          greaterThanOrEqualTo(4.5),
          reason:
              '${e.key} temada birincil dügme metni ${k.toStringAsFixed(2)} '
              'kontrast veriyor. Sabit Colors.white kullanildiginda koyu temada '
              '1.92 cikiyordu ve dügme okunmuyordu.',
        );
      });

      test('${e.key} tema: beyaz / dangerStrong', () {
        final k = kontrast(const Color(0xFFFFFFFF), e.value.dangerStrong);
        expect(
          k,
          greaterThanOrEqualTo(4.5),
          reason: '${e.key} temada ${k.toStringAsFixed(2)}',
        );
      });
    }
  });

  group('Govde ve soluk metin', () {
    for (final e in temalar.entries) {
      test('${e.key} tema: ink / card', () {
        expect(kontrast(e.value.ink, e.value.card), greaterThanOrEqualTo(4.5));
      });
      test('${e.key} tema: ink / bg', () {
        expect(kontrast(e.value.ink, e.value.bg), greaterThanOrEqualTo(4.5));
      });
      test('${e.key} tema: muted / card', () {
        expect(
          kontrast(e.value.muted, e.value.card),
          greaterThanOrEqualTo(4.5),
        );
      });
      test('${e.key} tema: warningText / card', () {
        expect(
          kontrast(e.value.warningText, e.value.card),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });

  group('Grafik ögeler (esik 3.0)', () {
    for (final e in temalar.entries) {
      test('${e.key} tema: danger / card', () {
        expect(
          kontrast(e.value.danger, e.value.card),
          greaterThanOrEqualTo(3.0),
        );
      });
      test('${e.key} tema: success / card', () {
        expect(
          kontrast(e.value.success, e.value.card),
          greaterThanOrEqualTo(3.0),
        );
      });
      test('${e.key} tema: primary / card — odak halkasi', () {
        expect(
          kontrast(e.value.primary, e.value.card),
          greaterThanOrEqualTo(3.0),
        );
      });
    }
  });

  test('tema kurulumu dolu dügmeye onPrimary veriyor', () {
    for (final parlaklik in [Brightness.light, Brightness.dark]) {
      final tema = buildAppTheme(parlaklik);
      final t = parlaklik == Brightness.dark ? AppTokens.dark : AppTokens.light;
      final stil = tema.filledButtonTheme.style!;
      final on = stil.foregroundColor!.resolve({});
      expect(
        on,
        t.onPrimary,
        reason: '$parlaklik temada dolu dügme metni onPrimary olmali',
      );
      expect(tema.colorScheme.onPrimary, t.onPrimary);
    }
  });
}
