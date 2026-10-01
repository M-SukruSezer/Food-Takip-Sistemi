import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('işlem ekranları açık tema yüzeylerini doğrudan kullanmaz', () {
    const files = [
      'lib/screens/batch_dialogs.dart',
      'lib/screens/daily_report_dialogs.dart',
      'lib/screens/daily_report_screen.dart',
      'lib/screens/pdks_admin_screen.dart',
      'lib/screens/pdks_screen.dart',
      'lib/screens/petty_cash_dialogs.dart',
      'lib/screens/profile_screen.dart',
      'lib/screens/qr_scan_screen.dart',
      'lib/screens/recommendations_screen.dart',
    ];

    // Bunlar önceki tasarımda kart, form ve sayfa zemini olarak doğrudan
    // kullanılıyordu. Koyu temada beyaz/açık mavi bloklara dönüşmemeleri için
    // bütün yüzeyler AppTokens üzerinden gelmeli.
    final forbiddenLightSurfaces = RegExp(
      r'0xFF(?:F8FAFC|EFF4FF|F8F9FF|EEF3FF|F0F4FF|E5EDFF|E5EEFF|'
      r'EFF6FF|DBEAFE|E2E8F0|F1F5F9|FFF5F5)',
    );

    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(
        forbiddenLightSurfaces.hasMatch(source),
        isFalse,
        reason: '$path sabit açık tema yüzeyi içeriyor; AppTokens kullanın.',
      );
    }
  });
}
