import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/models/pdks.dart';
import 'package:foodtakip/screens/roster_screen.dart';
import 'package:foodtakip/widgets/shortcut_fab.dart';

import 'support/fake_api.dart';

// Cizelge hucreleri: kategori renkleri, net sure, yasal uyari ve duzenleme.
//
// Siniflandirma ve net sure SUNUCUDA hesaplaniyor; burada dogrulanan sey
// istemcinin o veriyi bozmadan tasidigi ve dogru gosterdigi.

Map<String, Object?> _hucre({
  required String b,
  required String e,
  int mola = 60,
  required int net,
  required int span,
  required String kategori,
  bool geceYarisi = false,
  List<Map<String, Object?>> uyarilar = const [],
  int id = 1,
}) => {
  'assignment_id': id,
  'shift_id': 10 + id,
  'shift_name': 'V$id',
  'start_time': b,
  'end_time': e,
  'break_duration_minutes': mola,
  'is_day_off': false,
  'crosses_midnight': geceYarisi,
  'minutes': net,
  'span_minutes': span,
  'category': kategori,
  'night_minutes': 0,
  'warnings': uyarilar,
};

Map<String, Object?> _cizelge({
  bool canEdit = true,
  List<Map<String, Object?>>? kisiler,
}) => {
  'from': '2026-09-28',
  'to': '2026-09-28',
  'dates': ['2026-09-28'],
  'store': 'DÜZCE MERKEZ',
  'can_edit': canEdit,
  'holidays': <String, Object?>{},
  'people':
      kisiler ??
      [
        {
          'user': {
            'id': 2,
            'full_name': 'SENA ÜSTÜNEL',
            'role': 'barista',
            'store_id': 1,
          },
          'cells': {
            '2026-09-28': [
              _hucre(
                b: '08:00',
                e: '16:30',
                net: 450,
                span: 510,
                kategori: 'sabah',
              ),
            ],
          },
          'planned_minutes': 450,
          'shift_days': 1,
          'day_off_days': 0,
          'unassigned_days': 0,
        },
      ],
  'totals': {
    '2026-09-28': {'working': 1, 'day_off': 0, 'unassigned': 0, 'minutes': 450},
  },
};

void main() {
  setUpAll(initTestFormatting);

  void tall(WidgetTester tester, [double h = 2200]) {
    tester.view.physicalSize = Size(900, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('Model', () {
    test('kategori cozumlemesi', () {
      expect(shiftCategoryOf('sabah'), ShiftCategory.sabah);
      expect(shiftCategoryOf('gunduz'), ShiftCategory.gunduz);
      expect(shiftCategoryOf('aksam'), ShiftCategory.aksam);
      expect(shiftCategoryOf('gece'), ShiftCategory.gece);
      expect(shiftCategoryOf(null), ShiftCategory.bilinmiyor);
      expect(shiftCategoryOf('sacma'), ShiftCategory.bilinmiyor);
    });

    test('net sure ile brut sure AYRI tasiniyor', () {
      final c = RosterCell.fromJson(
        _hucre(b: '08:00', e: '16:30', net: 450, span: 510, kategori: 'sabah'),
      );
      // minutes NET: mola dusulmus. Cizelgedeki planli sure bunu kullaniyor.
      expect(c.minutes, 450);
      expect(c.spanMinutes, 510);
      expect(c.spanMinutes - c.minutes, 60, reason: 'dusulen mola');
    });

    test('yasal uyarilar tasiniyor', () {
      final c = RosterCell.fromJson(
        _hucre(
          b: '08:00',
          e: '20:00',
          net: 660,
          span: 720,
          kategori: 'sabah',
          uyarilar: [
            {
              'kod': 'GUNLUK_ASIM',
              'etiket': '11 sa aşımı',
              'aciklama': 'Günlük çalışma 12 saat; 4857 m.63.',
            },
          ],
        ),
      );
      expect(c.warnings, hasLength(1));
      expect(c.warnings.first.kod, 'GUNLUK_ASIM');
      expect(c.warnings.first.etiket, '11 sa aşımı');
    });

    test('atama kimligi tasiniyor', () {
      final c = RosterCell.fromJson(
        _hucre(
          b: '08:00',
          e: '16:30',
          net: 450,
          span: 510,
          kategori: 'sabah',
          id: 7,
        ),
      );
      expect(c.assignmentId, 7);
    });
  });

  group('ShiftDef net sure ve uyari', () {
    ShiftDef v(String b, String e, int mola) => ShiftDef(
      id: 1,
      name: 'V',
      startTime: b,
      endTime: e,
      breakMinutes: mola,
    );

    test('brut sure gece yarisini geciyor', () {
      expect(v('22:00', '06:00', 60).spanMinutes, 480);
      expect(v('08:00', '16:30', 60).spanMinutes, 510);
    });

    test('yasal asgari mola m.68', () {
      expect(v('09:00', '13:00', 0).legalBreak, 15);
      expect(v('09:00', '16:00', 0).legalBreak, 30);
      expect(v('08:00', '16:30', 0).legalBreak, 60);
    });

    test('net sure: tanimli ile yasalin KUCUGU dusulur', () {
      // Sunucudaki netDakika ile ayni sonuclar.
      expect(v('08:00', '16:30', 60).netMinutes, 450);
      expect(v('08:00', '16:30', 30).netMinutes, 480);
      expect(v('08:00', '16:30', 0).netMinutes, 510);
      expect(v('09:00', '13:00', 60).netMinutes, 225);
    });

    test('uyari metinleri', () {
      expect(v('08:00', '20:00', 60).warning, contains('11 saat'));
      expect(v('08:00', '16:30', 30).warning, contains('60 dk'));
      expect(v('08:00', '16:30', 60).warning, isNull);
    });
  });

  group('Cizelge hucresi', () {
    testWidgets('kategori etiketi ve saat gosterilir', (tester) async {
      tall(tester);
      installFakeApi({'GET /pdks/roster': _cizelge()});
      signInAs('store_manager', storeId: 1);
      await tester.pumpWidget(host(const RosterScreen()));
      await tester.pumpAndSettle();

      expect(find.text('08:00–16:30'), findsOneWidget);
      // Renk TEK BASINA bilgi tasimasin: kategori adi da yaziyor.
      expect(find.text('Sabah'), findsOneWidget);
      // Planli sure NET: 450 dk = 7s 30dk
      expect(find.text('7s 30dk'), findsWidgets);
    });

    testWidgets('yasal uyari ETIKETI hucrede yaziyor', (tester) async {
      tall(tester);
      installFakeApi({
        'GET /pdks/roster': _cizelge(
          kisiler: [
            {
              'user': {
                'id': 2,
                'full_name': 'SENA ÜSTÜNEL',
                'role': 'barista',
                'store_id': 1,
              },
              'cells': {
                '2026-09-28': [
                  _hucre(
                    b: '08:00',
                    e: '20:00',
                    net: 660,
                    span: 720,
                    kategori: 'sabah',
                    uyarilar: [
                      {'kod': 'GUNLUK_ASIM', 'etiket': '11 sa aşımı'},
                    ],
                  ),
                ],
              },
              'planned_minutes': 660,
              'shift_days': 1,
              'day_off_days': 0,
              'unassigned_days': 0,
            },
          ],
        ),
      });
      signInAs('store_manager', storeId: 1);
      await tester.pumpWidget(host(const RosterScreen()));
      await tester.pumpAndSettle();

      expect(find.text('11 sa aşımı'), findsOneWidget);
    });

    testWidgets('duzenleme yetkisi olan bos hucrede + gorur', (tester) async {
      tall(tester);
      installFakeApi({
        'GET /pdks/roster': _cizelge(
          kisiler: [
            {
              'user': {
                'id': 2,
                'full_name': 'SENA ÜSTÜNEL',
                'role': 'barista',
                'store_id': 1,
              },
              'cells': {'2026-09-28': <Object?>[]},
              'planned_minutes': 0,
              'shift_days': 0,
              'day_off_days': 0,
              'unassigned_days': 1,
            },
          ],
        ),
      });
      signInAs('store_manager', storeId: 1);
      await tester.pumpWidget(host(const RosterScreen()));
      await tester.pumpAndSettle();
      expect(find.text('+'), findsOneWidget);
    });

    testWidgets('yetkisi olmayan bos hucrede - gorur', (tester) async {
      tall(tester);
      installFakeApi({
        'GET /pdks/roster': _cizelge(
          canEdit: false,
          kisiler: [
            {
              'user': {
                'id': 2,
                'full_name': 'SENA ÜSTÜNEL',
                'role': 'barista',
                'store_id': 1,
              },
              'cells': {'2026-09-28': <Object?>[]},
              'planned_minutes': 0,
              'shift_days': 0,
              'day_off_days': 0,
              'unassigned_days': 1,
            },
          ],
        ),
      });
      signInAs('barista', storeId: 1);
      await tester.pumpWidget(host(const RosterScreen()));
      await tester.pumpAndSettle();
      // Ekranda birden fazla "-" var (sifir sureler de boyle yaziliyor);
      // anlamli iddia duzenleme isaretinin HIC olmamasi.
      expect(find.text('-'), findsWidgets);
      expect(find.text('+'), findsNothing);
    });
  });

  group('Yuzen dugme modul islemine doner', () {
    test('eslesen yollar', () {
      // Ana sayfa: menu davranisi (modul islemi YOK)
      expect(moduleActionLabelFor('barista', '/dashboard'), isNull);
      // Moduller: kendi islemleri
      expect(moduleActionLabelFor('barista', '/batches'), 'Yeni Ürün');
      expect(
        moduleActionLabelFor('store_manager', '/petty-cash'),
        'Masraf Gir',
      );
      expect(
        moduleActionLabelFor('store_manager', '/daily-report'),
        'Günlük Rapor',
      );
    });

    test('rol yetkisi olmayan modulde islem cikmaz', () {
      // Masraf girisi yalnizca magaza kasasini kullanan rollerde.
      expect(moduleActionLabelFor('barista', '/petty-cash'), isNull);
      // Gunluk rapor yalnizca rapor paneli rollerinde.
      expect(moduleActionLabelFor('barista', '/daily-report'), isNull);
    });
  });
}
