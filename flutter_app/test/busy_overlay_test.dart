import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/busy.dart';
import 'package:foodtakip/core/tokens.dart';
import 'package:foodtakip/widgets/busy_overlay.dart';

Widget _app(Brightness brightness) {
  final theme = buildAppTheme(brightness);
  return MaterialApp(
    theme: theme,
    home: Scaffold(
      backgroundColor: theme.extension<AppTokens>()!.bg,
      body: BusyOverlay(child: const SizedBox.expand()),
    ),
  );
}

/// Gizleme 180ms geciktirmeli; bekleyen timer testi dusurmesin.
Future<void> _finish(WidgetTester tester) async {
  busy.end();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('katman kapalıyken hiçbir şey çizilmez', (tester) async {
    await tester.pumpWidget(_app(Brightness.light));
    await tester.pump();

    expect(find.text('Yükleniyor...'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('katman açıkken spinner, metin ve tıklama kalkanı var', (tester) async {
    busy.begin();
    await tester.pumpWidget(_app(Brightness.light));
    await tester.pump();

    expect(find.text('Yükleniyor...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Arkadaki hicbir kontrole erisilememeli.
    expect(find.byType(AbsorbPointer), findsWidgets);

    await _finish(tester);
  });

  testWidgets('spinner iz halkası çizer', (tester) async {
    for (final b in [Brightness.light, Brightness.dark]) {
      busy.begin();
      await tester.pumpWidget(_app(b));
      await tester.pump();

      final spinner =
          tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      // Iz olmadan yalnizca hareket eden yay goruluyor; halka olarak okunmasi
      // icin arka plan rengi sart.
      expect(spinner.backgroundColor, isNotNull, reason: '$b temasinda iz yok');
      expect(spinner.color, isNotNull);
      expect(spinner.backgroundColor, isNot(spinner.color));

      await _finish(tester);
    }
  });

  testWidgets('kart yumuşak gölgeli ve yuvarlak', (tester) async {
    for (final b in [Brightness.light, Brightness.dark]) {
      busy.begin();
      await tester.pumpWidget(_app(b));
      await tester.pump();

      final box = tester
          .widget<Container>(
            find.ancestor(of: find.text('Yükleniyor...'), matching: find.byType(Container)).last,
          )
          .decoration! as BoxDecoration;
      expect(box.boxShadow, isNotNull, reason: '$b temasinda gölge yok');
      expect(box.boxShadow!.length, greaterThanOrEqualTo(2));
      expect(
        (box.borderRadius! as BorderRadius).topLeft.x,
        18,
        reason: '$b temasinda yarıçap React istemcisiyle aynı olmalı',
      );

      await _finish(tester);
    }
  });
  testWidgets('metin sarı alt çizgiyle çizilmez', (tester) async {
    busy.begin();
    await tester.pumpWidget(_app(Brightness.light));
    await tester.pump();

    // Katman MaterialApp.builder icinde, Material'in disinda duruyor.
    // Material sarmalayici olmazsa Flutter metni sari cift alt cizgiyle
    // ciziyor (eksik Material isareti).
    expect(
      find.ancestor(of: find.text('Yükleniyor...'), matching: find.byType(Material)),
      findsWidgets,
    );

    final style = tester.widget<Text>(find.text('Yükleniyor...')).style!;
    expect(style.decoration ?? TextDecoration.none, TextDecoration.none);

    await _finish(tester);
  });

}
