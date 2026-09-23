import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/image_pick.dart';

void main() {
  test('masaustunde dosya secici kullanilir', () {
    for (final p in [TargetPlatform.linux, TargetPlatform.windows, TargetPlatform.macOS]) {
      expect(usesFileSelector(p), isTrue, reason: '$p');
    }
  });

  test('telefonda galeri kullanilir', () {
    expect(usesFileSelector(TargetPlatform.android), isFalse);
    expect(usesFileSelector(TargetPlatform.iOS), isFalse);
  });

  test('webde image_picker calisir, dosya secicisine gerek yok', () {
    // Web'de defaultTargetPlatform ana isletim sistemini bildirir; masaustu
    // dalina girmemesi icin kIsWeb ayrica kontrol edilir.
    expect(usesFileSelector(TargetPlatform.linux, isWeb: true), isFalse);
    expect(usesFileSelector(TargetPlatform.windows, isWeb: true), isFalse);
  });
}
