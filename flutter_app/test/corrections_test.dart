import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/batch_actions.dart';
import 'package:foodtakip/models/batch.dart';
import 'package:foodtakip/models/movement.dart';
import 'package:foodtakip/screens/batch_dialogs.dart';
import 'package:foodtakip/screens/movement_dialogs.dart';

import 'support/fake_api.dart';

Batch _batch({
  int id = 1,
  String status = 'thawing',
  int quantity = 12,
  int remaining = 12,
  bool thawReady = false,
}) => Batch.fromJson({
      'id': id, 'store_id': 1, 'product_type_id': 1,
      'product_name': 'LOTUS CUP', 'store_name': 'DÜZCE',
      'quantity': quantity, 'remaining': remaining, 'status': status,
      'thaw_ready': thawReady,
    });

Movement _movement({
  int id = 5,
  String kind = 'sale',
  int quantity = 8,
  String? reason,
}) => Movement.fromJson({
      'id': id, 'kind': kind, 'quantity': quantity,
      'at': '2026-09-24T10:00:00.000Z',
      'product_name': 'LOTUS CUP', 'unit_price': 100, 'total': 100 * quantity,
      'user_name': 'Test', 'reason': reason,
    });

Future<void> _open(WidgetTester tester, Future<void> Function(BuildContext) show) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => ElevatedButton(onPressed: () => show(ctx), child: const Text('aç')),
    ),
  ));
  await tester.tap(find.text('aç'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestFormatting);

  group('Eylem kuralları', () {
    test('çözülme adedi düzeltmesi yalnızca çözülmede ve yetkiyle', () {
      final thawing = batchActionsFor(_batch(), canAdjust: true);
      expect(thawing.menu, contains(BatchAction.correctThaw));

      // Food dolabina gecmis urun tekrar dondurulamaz.
      final cabinet = batchActionsFor(_batch(status: 'food_cabinet'), canAdjust: true);
      expect(cabinet.menu, isNot(contains(BatchAction.correctThaw)));

      final frozen = batchActionsFor(_batch(status: 'frozen'), canAdjust: true);
      expect(frozen.menu, isNot(contains(BatchAction.correctThaw)));

      // Yetkisi olmayanda menude gorunmez.
      final noPerm = batchActionsFor(_batch(), canAdjust: false);
      expect(noPerm.menu, isNot(contains(BatchAction.correctThaw)));
    });

    test('kayıt silme yalnızca yetkiliye görünür', () {
      expect(batchActionsFor(_batch(), canAdjust: true).menu,
          isNot(contains(BatchAction.deleteBatch)));
      expect(batchActionsFor(_batch(), canAdjust: true, canDelete: true).menu,
          contains(BatchAction.deleteBatch));
      // Gecmis kayitta da silinebilir.
      expect(batchActionsFor(_batch(status: 'discarded'), canAdjust: false, canDelete: true).menu,
          contains(BatchAction.deleteBatch));
    });
  });

  group('Çözülme adedi düzeltme', () {
    testWidgets('geri dönecek adedi önceden gösterir', (tester) async {
      installFakeApi({});
      signInAs('store_manager', storeId: 1);

      await _open(tester, (ctx) => showCorrectThawDialog(ctx, _batch()));
      expect(find.textContaining('şu anda 12 adet çözülmede'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '6');
      await tester.pumpAndSettle();
      expect(find.textContaining('6 adet donuk depoya geri dönecek'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '0');
      await tester.pumpAndSettle();
      expect(find.textContaining('12 adet donuk depoya geri dönecek'), findsOneWidget);
    });

    testWidgets('doğru adet gönderilir', (tester) async {
      final fake = installFakeApi({
        'POST /batches/1/correct-thaw-quantity': {'ok': true, 'returned_to_frozen': 6},
      });
      signInAs('store_manager', storeId: 1);

      await _open(tester, (ctx) => showCorrectThawDialog(ctx, _batch()));
      await tester.enterText(find.byType(TextField).first, '6');
      await tester.tap(find.text('Düzelt'));
      await tester.pumpAndSettle();

      expect(fake.lastBody('POST /batches/1/correct-thaw-quantity'), {'quantity': 6});
    });

    testWidgets('geçersiz adet sunucuya gitmez', (tester) async {
      final fake = installFakeApi({
        'POST /batches/1/correct-thaw-quantity': {'ok': true},
      });
      signInAs('store_manager', storeId: 1);

      await _open(tester, (ctx) => showCorrectThawDialog(ctx, _batch()));

      for (final (girdi, mesaj) in [
        ('99', 'Doğru adet mevcut adetten (12) büyük olamaz'),
        ('-1', 'Doğru adet 0 veya daha büyük bir tam sayı olmalıdır'),
        ('12', 'Adet değişmedi'),
      ]) {
        await tester.enterText(find.byType(TextField).first, girdi);
        await tester.tap(find.text('Düzelt'));
        await tester.pumpAndSettle();
        expect(find.text(mesaj), findsOneWidget, reason: 'girdi: $girdi');
      }
      expect(fake.called('POST /batches/1/correct-thaw-quantity'), isFalse);
    });
  });

  group('Hareket kaydı düzeltme', () {
    testWidgets('satış adedi azaltılınca stoka dönüşü yazar', (tester) async {
      installFakeApi({});
      signInAs('store_manager', storeId: 1);

      await _open(tester, (ctx) => showMovementCorrectDialog(ctx, _movement()));
      expect(find.text('Satış Adedini Düzelt'), findsOneWidget);
      expect(find.textContaining('Kayıtlı adet: 8'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '3');
      await tester.pumpAndSettle();
      expect(find.textContaining('5 adet stoka geri dönecek'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '10');
      await tester.pumpAndSettle();
      expect(find.textContaining('2 adet stoktan düşecek'), findsOneWidget);
    });

    testWidgets('satış düzeltmesi /sales ucuna gider', (tester) async {
      final fake = installFakeApi({'PUT /sales/5': {'ok': true}});
      signInAs('store_manager', storeId: 1);

      await _open(tester, (ctx) => showMovementCorrectDialog(ctx, _movement()));
      await tester.enterText(find.byType(TextField).first, '3');
      await tester.tap(find.text('Düzelt'));
      await tester.pumpAndSettle();

      expect(fake.lastBody('PUT /sales/5'), {'quantity': 3});
    });

    testWidgets('zayi düzeltmesi sebebi de gönderir', (tester) async {
      final fake = installFakeApi({'PUT /discards/7': {'ok': true}});
      signInAs('store_manager', storeId: 1);

      await _open(tester, (ctx) => showMovementCorrectDialog(
            ctx, _movement(id: 7, kind: 'discard', quantity: 6, reason: 'SKT doldu')));

      expect(find.text('Zayi Adedini Düzelt'), findsOneWidget);
      // Zayide sebep alani da var; satista yok.
      expect(find.text('Zayi Sebebi'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '2');
      await tester.enterText(find.byType(TextField).at(1), 'Sayım hatası');
      await tester.tap(find.text('Düzelt'));
      await tester.pumpAndSettle();

      expect(fake.lastBody('PUT /discards/7'),
          {'quantity': 2, 'reason': 'Sayım hatası'});
    });

    testWidgets('satışta zayi sebebi alanı yok', (tester) async {
      installFakeApi({});
      signInAs('store_manager', storeId: 1);
      await _open(tester, (ctx) => showMovementCorrectDialog(ctx, _movement()));
      expect(find.text('Zayi Sebebi'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('değişiklik yoksa gönderilmez', (tester) async {
      final fake = installFakeApi({'PUT /sales/5': {'ok': true}});
      signInAs('store_manager', storeId: 1);

      await _open(tester, (ctx) => showMovementCorrectDialog(ctx, _movement()));
      await tester.tap(find.text('Düzelt'));
      await tester.pumpAndSettle();

      expect(find.text('Değişiklik yapılmadı'), findsOneWidget);
      expect(fake.called('PUT /sales/5'), isFalse);
    });

    testWidgets('sıfır ve negatif adet reddedilir', (tester) async {
      final fake = installFakeApi({'PUT /sales/5': {'ok': true}});
      signInAs('store_manager', storeId: 1);

      await _open(tester, (ctx) => showMovementCorrectDialog(ctx, _movement()));
      for (final girdi in ['0', '-2', 'abc']) {
        await tester.enterText(find.byType(TextField).first, girdi);
        await tester.tap(find.text('Düzelt'));
        await tester.pumpAndSettle();
        expect(find.text('Adet en az 1 olmalıdır'), findsOneWidget, reason: 'girdi: $girdi');
      }
      expect(fake.called('PUT /sales/5'), isFalse);
    });
  });
}
