import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/models/pdks.dart';
import 'package:foodtakip/screens/roster_screen.dart';

import 'support/fake_api.dart';

// Toplu kaydetme: hucre duzenlemeleri yerelde birikiyor, tek "Kaydet" ile
// gonderiliyor.
//
// Buradaki iddia: duzenleme aninda SUNUCUYA GIDILMIYOR ve bekleyen degisiklik
// tabloda gorunuyor. "Hepsi ya hicbiri" sozlesmesi sunucuda dogrulandi.

ShiftDef _v(int id, String ad, String b, String e, {int mola = 60}) =>
    ShiftDef(id: id, name: ad, startTime: b, endTime: e, breakMinutes: mola);

Map<String, Object?> _cizelge({bool canEdit = true}) => {
  'from': '2026-09-28',
  'to': '2026-09-29',
  'dates': ['2026-09-28', '2026-09-29'],
  'store': 'DÜZCE MERKEZ',
  'can_edit': canEdit,
  'holidays': <String, Object?>{},
  'people': [
    {
      'user': {
        'id': 2,
        'full_name': 'SENA ÜSTÜNEL',
        'role': 'barista',
        'store_id': 1,
      },
      'cells': {
        '2026-09-28': [
          {
            'assignment_id': 1,
            'shift_id': 10,
            'shift_name': 'Sabah',
            'start_time': '08:00',
            'end_time': '16:30',
            'break_duration_minutes': 60,
            'is_day_off': false,
            'crosses_midnight': false,
            'minutes': 450,
            'span_minutes': 510,
            'category': 'sabah',
            'warnings': <Object?>[],
          },
        ],
        '2026-09-29': <Object?>[],
      },
      'planned_minutes': 450,
      'shift_days': 1,
      'day_off_days': 0,
      'unassigned_days': 1,
    },
  ],
  'totals': {
    '2026-09-28': {'working': 1, 'day_off': 0, 'unassigned': 0, 'minutes': 450},
    '2026-09-29': {'working': 0, 'day_off': 0, 'unassigned': 1, 'minutes': 0},
  },
};

void main() {
  setUpAll(initTestFormatting);

  void tall(WidgetTester tester, [double h = 2400]) {
    tester.view.physicalSize = Size(900, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('PendingCell', () {
    test('anahtar kullanici ve tarihten olusuyor', () {
      const p = PendingCell(
        userId: 7,
        fullName: 'X',
        workDate: '2026-09-29',
        isDayOff: false,
      );
      expect(p.key, '7|2026-09-29');
      expect(PendingCell.keyOf(7, '2026-09-29'), p.key);
    });

    test('gonderilecek govde sunucunun bekledigi bicimde', () {
      final p = PendingCell(
        userId: 7,
        fullName: 'X',
        workDate: '2026-09-29',
        isDayOff: false,
        shift: _v(10, 'Sabah', '08:00', '16:30'),
      );
      expect(p.toJson(), {
        'user_id': 7,
        'work_date': '2026-09-29',
        'is_day_off': false,
        'shift_id': 10,
      });
    });

    test('hafta tatili ve bosaltmada vardiya kimligi null', () {
      const tatil = PendingCell(
        userId: 7,
        fullName: 'X',
        workDate: '2026-09-29',
        isDayOff: true,
      );
      expect(tatil.shiftId, isNull);
      expect(tatil.netMinutes, 0);
      const bos = PendingCell(
        userId: 7,
        fullName: 'X',
        workDate: '2026-09-29',
        isDayOff: false,
      );
      expect(bos.shiftId, isNull);
      expect(bos.netMinutes, 0);
    });

    test('net sure vardiyadan geliyor (mola dusulmus)', () {
      final p = PendingCell(
        userId: 7,
        fullName: 'X',
        workDate: '2026-09-29',
        isDayOff: false,
        shift: _v(10, 'Sabah', '08:00', '16:30'),
      );
      // 510 - 60 = 450
      expect(p.netMinutes, 450);
    });
  });

  group('Cizelge: bekleyen degisiklik', () {
    testWidgets('hucre duzenlemesi SUNUCUYA GITMIYOR, tabloda beliriyor', (
      tester,
    ) async {
      tall(tester);
      final api = installFakeApi({
        'GET /pdks/roster': _cizelge(),
        'GET /pdks/shifts': [
          {
            'id': 10,
            'name': 'Sabah',
            'start_time': '08:00',
            'end_time': '16:30',
            'break_duration_minutes': 60,
            'active': 1,
          },
          {
            'id': 11,
            'name': 'Gece',
            'start_time': '22:00',
            'end_time': '06:00',
            'break_duration_minutes': 60,
            'active': 1,
          },
        ],
      });
      signInAs('store_manager', storeId: 1);
      await tester.pumpWidget(host(const RosterScreen()));
      await tester.pumpAndSettle();

      // Baslangicta kaydet cubugu YOK.
      expect(find.textContaining('kaydedilmeyi bekliyor'), findsNothing);
      expect(find.text('7s 30dk'), findsWidgets, reason: 'planlı 450 dk');

      // Bos hucreye dokun (29.09), Gece sec, tabloya isle.
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gece'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tabloya işle'));
      await tester.pumpAndSettle();

      // Kaydet cubugu cikti.
      expect(
        find.textContaining('1 değişiklik kaydedilmeyi bekliyor'),
        findsOneWidget,
      );
      expect(find.text('Kaydet'), findsOneWidget);
      expect(find.text('Vazgeç'), findsOneWidget);
      // Hucre yeni degeri gosteriyor ve bekleyen isareti var.
      expect(find.text('22:00–06:00 🌙'), findsOneWidget);
      expect(find.text('•'), findsOneWidget);
      // Planli sure canli guncellendi: 450 + 420 = 870 dk = 14s 30dk
      expect(find.text('14s 30dk'), findsOneWidget);
      // SUNUCUYA KAYIT ISTEGI GITMEDI.
      expect(api.called('PUT /pdks/assignments/cells'), isFalse);
      expect(api.called('PUT /pdks/assignments/cell'), isFalse);
    });

    testWidgets('Kaydet TEK istek atiyor ve cubugu kaldiriyor', (tester) async {
      tall(tester);
      final api = installFakeApi({
        'GET /pdks/roster': _cizelge(),
        'GET /pdks/shifts': [
          {
            'id': 11,
            'name': 'Gece',
            'start_time': '22:00',
            'end_time': '06:00',
            'break_duration_minutes': 60,
            'active': 1,
          },
        ],
        'PUT /pdks/assignments/cells': {
          'ok': true,
          'saved': 1,
          'forced': 0,
          'warnings': <Object?>[],
        },
      });
      signInAs('store_manager', storeId: 1);
      await tester.pumpWidget(host(const RosterScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gece'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tabloya işle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      expect(api.called('PUT /pdks/assignments/cells'), isTrue);
      final govde = api.lastBody('PUT /pdks/assignments/cells') as Map;
      expect(govde['force'], isFalse);
      expect((govde['changes'] as List), hasLength(1));
      expect((govde['changes'] as List).first, {
        'user_id': 2,
        'work_date': '2026-09-29',
        'is_day_off': false,
        'shift_id': 11,
      });
      // Cubuk kalkti.
      expect(find.textContaining('kaydedilmeyi bekliyor'), findsNothing);
    });

    testWidgets('ayni degeri secmek bekleyen olusturmuyor', (tester) async {
      tall(tester);
      installFakeApi({
        'GET /pdks/roster': _cizelge(),
        'GET /pdks/shifts': [
          {
            'id': 10,
            'name': 'Sabah',
            'start_time': '08:00',
            'end_time': '16:30',
            'break_duration_minutes': 60,
            'active': 1,
          },
        ],
      });
      signInAs('store_manager', storeId: 1);
      await tester.pumpWidget(host(const RosterScreen()));
      await tester.pumpAndSettle();

      // 28.09 zaten Sabah; yine Sabah secince degisiklik sayilmamali.
      await tester.tap(find.text('08:00–16:30'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sabah').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tabloya işle'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('kaydedilmeyi bekliyor'),
        findsNothing,
        reason: '"değiştirdim sonra geri aldım" bir değişiklik değil',
      );
    });

    testWidgets('yetkisi olmayan hucreye dokunamiyor', (tester) async {
      tall(tester);
      installFakeApi({'GET /pdks/roster': _cizelge(canEdit: false)});
      signInAs('barista', storeId: 1);
      await tester.pumpWidget(host(const RosterScreen()));
      await tester.pumpAndSettle();
      expect(find.text('+'), findsNothing);
      expect(find.textContaining('kaydedilmeyi bekliyor'), findsNothing);
    });
  });
}
