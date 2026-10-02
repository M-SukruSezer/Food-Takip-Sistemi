import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/tokens.dart';
import 'package:foodtakip/widgets/swipe_actions.dart';

/// Kayıt soldan sağa kaydırılınca Düzenle / Sil açılır.
void main() {
  Future<List<String>> pump(WidgetTester tester) async {
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              for (final n in ['A', 'B'])
                SwipeActions(
                  actions: [
                    SwipeAction(
                      label: 'Düzenle',
                      icon: Icons.edit,
                      color: Colors.teal,
                      onTap: () => taps.add('düzenle $n'),
                    ),
                    SwipeAction(
                      label: 'Sil',
                      icon: Icons.delete,
                      color: Colors.red,
                      onTap: () => taps.add('sil $n'),
                    ),
                  ],
                  child: SizedBox(
                    height: 80,
                    width: 360,
                    child: Text('Kayıt $n'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return taps;
  }

  testWidgets('kapalıyken işlemler görünmez', (tester) async {
    await pump(tester);
    expect(find.text('Düzenle'), findsNothing);
  });

  testWidgets(
    'soldan sağa kaydırınca açılır, işleme dokununca çalışır ve kapanır',
    (tester) async {
      final taps = await pump(tester);
      await tester.drag(find.text('Kayıt A'), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(find.text('Düzenle'), findsOneWidget);
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(taps, ['sil A']);
      expect(find.text('Sil'), findsNothing);
    },
  );

  testWidgets('sağdan sola kaydırma ve kısa kaydırma açmaz', (tester) async {
    await pump(tester);
    await tester.drag(find.text('Kayıt A'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(find.text('Düzenle'), findsNothing);
    await tester.timedDrag(
      find.text('Kayıt A'),
      const Offset(30, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(find.text('Düzenle'), findsNothing);
  });

  testWidgets('yeni satır açılınca önceki kapanır', (tester) async {
    await pump(tester);
    await tester.drag(find.text('Kayıt A'), const Offset(200, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Kayıt B'), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(find.text('Düzenle'), findsOneWidget);
  });
}
