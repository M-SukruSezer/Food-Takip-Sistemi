import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/tokens.dart';
import 'package:foodtakip/widgets/panels.dart';

/// Kutucuklar her ekran genişliğinde eşit boyutta ve taşmasız olmalı.
void main() {
  setUpAll(() async {
    final font = FontLoader('Roboto')
      ..addFont(
        File('assets/fonts/NotoSans-Regular.ttf')
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    await font.load();
  });

  test('sütun sayısı genişlikle artar, sınırların dışına çıkmaz', () {
    expect(EqualTileGrid.columnsFor(320), 2);
    expect(EqualTileGrid.columnsFor(390), 2);
    expect(EqualTileGrid.columnsFor(768), 4);
    expect(EqualTileGrid.columnsFor(1920), 6);
    expect(EqualTileGrid.columnsFor(1920, maxColumns: 4), 4);
  });

  for (final w in [320.0, 360.0, 390.0, 768.0, 1024.0, 1440.0, 1920.0]) {
    testWidgets('${w.toInt()}px: kutular eşit ve taşmasız', (tester) async {
      tester.view.physicalSize = Size(w, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: EqualTileGrid(
                children: [
                  for (final (l, v) in const [
                    ('Donuk Depo', '1.250'),
                    ('Çözülme', '12'),
                    ('Food Dolabı', '38'),
                    ('SKT Geçen', '0'),
                    ('Bugün Satılan', '1.204 adet'),
                    ('Bugünkü İşlem', '312'),
                  ])
                    StatCard(label: l, value: v, sub: 'açıklama metni'),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      final sizes = tester
          .widgetList<StatCard>(find.byType(StatCard))
          .map((c) => tester.getSize(find.byWidget(c)))
          .toSet();
      expect(sizes.length, 1, reason: 'Kutular farklı boyutta: $sizes');
      expect(sizes.first.height, EqualTileGrid.defaultHeight);
    });
  }
}
