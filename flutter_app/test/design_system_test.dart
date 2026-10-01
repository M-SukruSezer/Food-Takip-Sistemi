import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/tokens.dart';
import 'package:foodtakip/widgets/dialogs.dart';
import 'package:foodtakip/widgets/panels.dart';

void main() {
  test('tema seçimi Strategy Pattern üzerinden doğru nesneyi üretir', () {
    final light = AppThemeStrategy.resolve(Brightness.light);
    final dark = AppThemeStrategy.resolve(Brightness.dark);

    expect(light, isA<LightThemeStrategy>());
    expect(light.tokens, AppTokens.light);
    expect(light.brightness, Brightness.light);
    expect(dark, isA<DarkThemeStrategy>());
    expect(dark.tokens, AppTokens.dark);
    expect(dark.brightness, Brightness.dark);
    expect(light.shadowAlpha, lessThan(dark.shadowAlpha));
  });

  test('Material renk şeması semantik tokenlarla iki temada eşleşir', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final theme = buildAppTheme(brightness);
      final t = brightness == Brightness.dark
          ? AppTokens.dark
          : AppTokens.light;
      final scheme = theme.colorScheme;

      expect(scheme.surface, t.card);
      expect(scheme.onSurface, t.ink);
      expect(scheme.surfaceContainer, t.bg);
      expect(scheme.onSurfaceVariant, t.muted);
      expect(scheme.outline, t.borderStrong);
      expect(scheme.outlineVariant, t.border);
      expect(scheme.primaryContainer, t.primarySoft);
      expect(scheme.errorContainer, t.dangerSoft);
    }
  });

  test('tema temel bileşenleri aynı tasarım ölçeğine bağlar', () {
    final theme = buildAppTheme(Brightness.light);

    expect(theme.extensions[AppTokens], AppTokens.light);
    expect(theme.cardTheme.elevation, 1);
    expect(theme.dialogTheme.shape, isA<RoundedRectangleBorder>());
    expect(theme.bottomSheetTheme.showDragHandle, isTrue);
    expect(theme.textButtonTheme.style?.minimumSize, isNotNull);
    expect(theme.inputDecorationTheme.filled, isTrue);
  });

  testWidgets('FormRow çok dar alanda alanları dikey dizer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: FormRow(
                left: SizedBox(key: Key('left'), height: 40),
                right: SizedBox(key: Key('right'), height: 40),
              ),
            ),
          ),
        ),
      ),
    );

    final left = tester.getTopLeft(find.byKey(const Key('left')));
    final right = tester.getTopLeft(find.byKey(const Key('right')));
    expect(right.dy, greaterThan(left.dy));
    expect(right.dx, left.dx);
  });

  testWidgets('FormRow kullanılabilir alanda iki sütunu korur', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              child: FormRow(
                left: SizedBox(key: Key('left'), height: 40),
                right: SizedBox(key: Key('right'), height: 40),
              ),
            ),
          ),
        ),
      ),
    );

    final left = tester.getTopLeft(find.byKey(const Key('left')));
    final right = tester.getTopLeft(find.byKey(const Key('right')));
    expect(right.dy, left.dy);
    expect(right.dx, greaterThan(left.dx));
  });

  testWidgets('AppCard ortak radius ve responsive padding kullanır', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(body: AppCard(child: Text('İçerik'))),
      ),
    );

    final ink = tester.widget<Ink>(find.byType(Ink));
    final decoration = ink.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(AppRadius.md));
    expect(decoration.color, AppTokens.light.card);
  });
}
