import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/logout.dart';
import 'package:foodtakip/core/responsive.dart';
import 'package:foodtakip/core/tokens.dart';
import 'package:foodtakip/models/batch.dart';
import 'package:foodtakip/models/dashboard.dart';
import 'package:foodtakip/models/product_type.dart';
import 'package:foodtakip/screens/batch_dialogs.dart';
import 'package:foodtakip/widgets/dialogs.dart';
import 'package:foodtakip/widgets/sell_confirm_bottom_sheet.dart';

import 'support/fake_api.dart';

/// Ortak pencere sisteminin tüm form faktörlerinde taşmasız açıldığını
/// doğrular. Her senaryo 7 ekran boyutu × açık/koyu tema ile kurulur;
/// RenderFlex taşması dahil herhangi bir çizim hatası testi düşürür.
const _viewports = <String, Size>{
  'iPhone SE (320)': Size(320, 568),
  'Android küçük (360)': Size(360, 640),
  'iPhone 14 (390)': Size(390, 844),
  'Tablet dikey (768)': Size(768, 1024),
  'Tablet yatay (1024)': Size(1024, 768),
  'Laptop (1440)': Size(1440, 900),
  'Masaüstü (1920)': Size(1920, 1080),
};

final _batch = Batch.fromJson({
  'id': 7,
  'product_name': 'Frambuazlı Cheesecake Dilim (Uzun Ürün Adı)',
  'quantity': 12,
  'remaining': 12,
  'status': 'food_cabinet',
  'store_name': 'Kadıköy Moda Şubesi',
  'skt_end': '2026-10-02T10:00:00.000Z',
  'urgency': 'critical',
  'remaining_hours': 6,
  'days_left': 0,
  'product_unit_price': 185,
  'skt_days': 3,
});

final _types = [
  ProductType.fromJson({
    'id': 1,
    'name': 'Çikolatalı Pasta',
    'skt_days': 3,
    'active': 1,
  }),
  ProductType.fromJson({
    'id': 2,
    'name': 'Limonlu Cheesecake',
    'skt_days': 4,
    'active': 1,
  }),
];

typedef _Opener = Future<void> Function(BuildContext context);

final _scenarios = <String, _Opener>{
  'onay penceresi': (c) => confirmDialog(
    c,
    title: 'Partiyi silmek istiyor musunuz?',
    body: const Text('Bu işlem geri alınamaz.'),
    confirmLabel: 'Sil',
  ),
  'çıkış onayı': (c) => confirmSignOut(c),
  'satış onayı': (c) => showSellConfirmBottomSheet(c, _batch),
  'yeni ürün ekle': (c) => showAddBatchDialog(
    c,
    types: _types,
    stores: const [StoreOption(id: 1, name: 'Merkez')],
  ),
  'zayi & ikram': (c) => showDiscardDialog(c, _batch),
  'çözülmeye al formu': (c) => showThawDialog(c, _batch),
};

void main() {
  setUpAll(() async {
    initTestFormatting();
    // Test varsayılan yazı tipi her harfi kare çizer ve gerçek genişliği
    // abartır; uygulamanın paketlediği yazı tipiyle ölçülür.
    final font = FontLoader('Roboto')
      ..addFont(
        File('assets/fonts/NotoSans-Regular.ttf')
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    await font.load();
  });

  for (final brightness in Brightness.values) {
    for (final scenario in _scenarios.entries) {
      for (final vp in _viewports.entries) {
        testWidgets(
          '${scenario.key} · ${vp.key} · ${brightness.name} taşmasız açılır',
          (tester) async {
            tester.view.physicalSize = vp.value;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            installFakeApi({});
            signInAs('store_manager', storeId: 1);

            await tester.pumpWidget(
              MaterialApp(
                theme: buildAppTheme(brightness),
                home: Scaffold(
                  body: Builder(
                    builder: (ctx) => Center(
                      child: FilledButton(
                        onPressed: () => scenario.value(ctx),
                        child: const Text('aç'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('aç'));
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);

            final frame = find.byType(StandardDialog).last;
            expect(frame, findsOneWidget);
            final box = tester.getRect(frame);
            final screen = Offset.zero & vp.value;

            // Pencere ekrandan taşmaz.
            expect(screen.contains(box.topLeft), isTrue);
            expect(box.right, lessThanOrEqualTo(vp.value.width));
            expect(box.bottom, lessThanOrEqualTo(vp.value.height));

            if (Breakpoints.of(vp.value.width).isCompact) {
              // Telefonda alttan tam genişlikte panel.
              expect(box.width, vp.value.width);
              expect(box.bottom, vp.value.height);
            } else {
              // Geniş ekranda ortalanmış, okunabilir genişlikte diyalog.
              expect(box.width, lessThanOrEqualTo(560));
              expect((box.center.dx - vp.value.width / 2).abs(), lessThan(1));
            }
          },
        );
      }
    }
  }

  group('Tasarım sistemi koruması', () {
    Iterable<File> kaynaklar() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    // Opak renkler yalnızca tasarım sisteminde tanımlanır; ekranlarda sabit
    // renk koyu temada okunmaz metni geri getirir.
    test('opak renk sabitleri yalnızca core/tokens.dart içinde', () {
      final literal = RegExp(r'Color\(0x[fF]{2}[0-9A-Fa-f]{6}\)');
      final offenders = [
        for (final f in kaynaklar())
          if (!f.path.endsWith('core/tokens.dart') &&
              literal.hasMatch(f.readAsStringSync()))
            f.path,
      ];
      expect(offenders, isEmpty);
    });

    // Yazı boyutları AppFontSize ölçeğinden gelir. PDF dışa aktarımları
    // baskı punto ölçüsü kullandığı için hariçtir.
    test('sayısal fontSize yalnızca tip ölçeğinde', () {
      final literal = RegExp(r'fontSize:\s*\d');
      final offenders = [
        for (final f in kaynaklar())
          if (!f.path.endsWith('core/tokens.dart') &&
              !f.path.endsWith('_export.dart') &&
              literal.hasMatch(f.readAsStringSync()))
            f.path,
      ];
      expect(offenders, isEmpty);
    });

    test('ekranlarda ham showDialog / AlertDialog kullanılmaz', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        if (RegExp(r'\bshowDialog\s*<|\bAlertDialog\(').hasMatch(src)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('kırılım eşikleri tek yerde tanımlı', () {
      final offenders = <String>[];
      final magic = RegExp(
        r'(width|maxWidth)\s*(<|>=)\s*(600|641|900|1000|1200)\b',
      );
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('core/responsive.dart') ||
            f.path.endsWith('core/tokens.dart')) {
          continue;
        }
        if (magic.hasMatch(f.readAsStringSync())) offenders.add(f.path);
      }
      expect(offenders, isEmpty);
    });
  });
}
