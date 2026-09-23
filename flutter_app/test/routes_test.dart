import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/app.dart';
import 'package:foodtakip/core/nav.dart';

void main() {
  test('menudeki her yolun bir ekrani var', () {
    for (final item in navItems) {
      expect(
        shellScreens.containsKey(item.path),
        isTrue,
        reason: '${item.label} (${item.path}) icin ekran tanimlanmamis',
      );
    }
  });

  test('fazladan ekran yolu yok', () {
    final navPaths = navItems.map((i) => i.path).toSet();
    expect(shellScreens.keys.toSet().difference(navPaths), isEmpty);
  });
}
