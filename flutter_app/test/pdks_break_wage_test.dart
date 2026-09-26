import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/nav.dart';
import 'package:foodtakip/core/pdks_export.dart';
import 'package:foodtakip/models/pdks.dart';
import 'package:foodtakip/screens/pdks_screen.dart';
import 'package:foodtakip/screens/roster_screen.dart';

import 'support/fake_api.dart';

// Mola adimlari, ucret hak edisi ve toplu cizelge.
//
// Para hesabi ve yetki sunucuda; burada dogrulanan sey ISTEMCININ sunucunun
// bildirdigi duruma UYMASI: sonraki adimi kendi kafasina gore hesaplamamasi ve
// ucreti yetki yokken hic cizmemesi.

Map<String, Object?> _durum({
  required String state,
  bool checkIn = false,
  bool checkOut = false,
  bool breakStart = false,
  bool breakEnd = false,
  int breakMinutes = 0,
  String? breakSince,
}) => {
  'work_date': '2026-09-21',
  'state': state,
  'is_inside': state != 'DISARIDA',
  'on_break': state == 'MOLADA',
  'open_since': state == 'DISARIDA' ? null : '2026-09-21T05:00:00.000Z',
  'break_since': breakSince,
  'break_minutes_today': breakMinutes,
  'can': {
    'check_in': checkIn,
    'check_out': checkOut,
    'break_start': breakStart,
    'break_end': breakEnd,
  },
  'store': {
    'id': 1,
    'name': 'DÜZCE MERKEZ',
    'pdks_enabled': true,
    'qr_mode': 'static',
    'latitude': 40.8,
    'longitude': 31.1,
    'geofence_radius_m': 100,
    'has_location': true,
  },
  'shifts': <Object?>[],
  'logs': <Object?>[],
};

Map<String, Object?> _pdksYollari(Map<String, Object?> durum) => {
  'GET /pdks/me': durum,
  'GET /pdks/requests/balances': {
    'leave': {'entitled': 14, 'used': 0, 'pending': 0, 'remaining': 14},
    'advance': {'limit': 0, 'used': 0, 'pending': 0, 'remaining': 0},
  },
  'GET /pdks/requests': <Object?>[],
  'GET /pdks/assignments': <Object?>[],
  'GET /pdks/holidays': <Object?>[],
};

Map<String, Object?> _cizelge({bool canEdit = true}) => {
  'from': '2026-09-21',
  'to': '2026-09-23',
  'dates': ['2026-09-21', '2026-09-22', '2026-09-23'],
  'store': 'DÜZCE MERKEZ COLOMBİA',
  'can_edit': canEdit,
  'holidays': {
    '2026-09-23': {'name': 'ZZ Bayram', 'half': false},
  },
  'people': [
    {
      'user': {
        'id': 2,
        'full_name': 'SENA ÜSTÜNEL',
        'role': 'barista',
        'store_id': 1,
        'store_name': 'DÜZCE MERKEZ COLOMBİA',
      },
      'cells': {
        '2026-09-21': [
          {
            'shift_id': 1,
            'shift_name': 'Sabah',
            'start_time': '08:00',
            'end_time': '16:30',
            'break_duration_minutes': 60,
            'is_day_off': false,
            'crosses_midnight': false,
            'minutes': 510,
          },
        ],
        '2026-09-22': [
          {
            'shift_id': null,
            'is_day_off': true,
            'crosses_midnight': false,
            'minutes': 0,
          },
        ],
        '2026-09-23': <Object?>[],
      },
      'planned_minutes': 510,
      'shift_days': 1,
      'day_off_days': 1,
      'unassigned_days': 1,
    },
    {
      'user': {
        'id': 4,
        'full_name': 'MEHMET ALİ CANBULAT',
        'role': 'barista',
        'store_id': 1,
        'store_name': 'DÜZCE MERKEZ COLOMBİA',
      },
      'cells': {
        '2026-09-21': [
          {
            'shift_id': 2,
            'shift_name': 'Gece',
            'start_time': '22:00',
            'end_time': '06:00',
            'break_duration_minutes': 60,
            'is_day_off': false,
            'crosses_midnight': true,
            'minutes': 480,
          },
        ],
        '2026-09-22': <Object?>[],
        '2026-09-23': <Object?>[],
      },
      'planned_minutes': 480,
      'shift_days': 1,
      'day_off_days': 0,
      'unassigned_days': 2,
    },
  ],
  'totals': {
    '2026-09-21': {'working': 2, 'day_off': 0, 'unassigned': 0, 'minutes': 990},
    '2026-09-22': {'working': 0, 'day_off': 1, 'unassigned': 1, 'minutes': 0},
    '2026-09-23': {'working': 0, 'day_off': 0, 'unassigned': 2, 'minutes': 0},
  },
};

void main() {
  setUpAll(initTestFormatting);

  void tall(WidgetTester tester, [double h = 2600]) {
    tester.view.physicalSize = Size(900, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('Mola adimlari', () {
    testWidgets('disarida: yalnizca giris acik, mola dugmeleri kapali', (
      tester,
    ) async {
      tall(tester);
      installFakeApi(_pdksYollari(_durum(state: 'DISARIDA', checkIn: true)));
      signInAs('barista', storeId: 1);
      await tester.pumpWidget(host(const PdksScreen()));
      await tester.pumpAndSettle();

      expect(find.text('İş yerinde değilsiniz'), findsOneWidget);
      expect(_acikMi(tester, 'Konumla İşe Başla'), isTrue);
      // Ana dugme TEK: etiketi duruma gore degisiyor, disarida "İşi Bitir" hic
      // cizilmiyor.
      expect(find.text('Konumla İşi Bitir'), findsNothing);
      expect(_acikMi(tester, 'Molaya Çık'), isFalse);
      expect(_acikMi(tester, 'Moladan Dön'), isFalse);
      expect(find.text('QR Okut (giriş)'), findsOneWidget);
    });

    testWidgets('iceride: cikis ve molaya cikma acik', (tester) async {
      tall(tester);
      installFakeApi(
        _pdksYollari(
          _durum(state: 'ICERIDE', checkOut: true, breakStart: true),
        ),
      );
      signInAs('barista', storeId: 1);
      await tester.pumpWidget(host(const PdksScreen()));
      await tester.pumpAndSettle();

      expect(find.text('İş yerindesiniz'), findsOneWidget);
      expect(find.text('Konumla İşe Başla'), findsNothing);
      expect(_acikMi(tester, 'Konumla İşi Bitir'), isTrue);
      expect(_acikMi(tester, 'Molaya Çık'), isTrue);
      expect(_acikMi(tester, 'Moladan Dön'), isFalse);
      expect(find.text('QR Okut (çıkış)'), findsOneWidget);
    });

    testWidgets('molada: cikis KAPALI, yalnizca moladan donus acik', (
      tester,
    ) async {
      tall(tester);
      installFakeApi(
        _pdksYollari(
          _durum(
            state: 'MOLADA',
            breakEnd: true,
            breakMinutes: 20,
            breakSince: '2026-09-21T09:00:00.000Z',
          ),
        ),
      );
      signInAs('barista', storeId: 1);
      await tester.pumpWidget(host(const PdksScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Moladasınız'), findsOneWidget);
      // Molada cikis yapilamaz: sunucu da engelliyor, dugme de kapali.
      expect(_acikMi(tester, 'Konumla İşi Bitir'), isFalse);
      expect(_acikMi(tester, 'Molaya Çık'), isFalse);
      expect(_acikMi(tester, 'Moladan Dön'), isTrue);
      expect(find.text('QR Okut (mola bitişi)'), findsOneWidget);
      expect(find.text('Bugün toplam mola: 20 dk'), findsOneWidget);
    });

    testWidgets('mesai sarti uyarisi yonlendirmede gosterilir', (tester) async {
      tall(tester);
      installFakeApi(_pdksYollari(_durum(state: 'DISARIDA', checkIn: true)));
      signInAs('barista', storeId: 1);
      await tester.pumpWidget(host(const PdksScreen(shiftRequired: true)));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('önce işe giriş yapmalısınız'),
        findsOneWidget,
      );
    });

    testWidgets('giris yapilmissa uyari gosterilmez', (tester) async {
      tall(tester);
      installFakeApi(
        _pdksYollari(
          _durum(state: 'ICERIDE', checkOut: true, breakStart: true),
        ),
      );
      signInAs('barista', storeId: 1);
      await tester.pumpWidget(host(const PdksScreen(shiftRequired: true)));
      await tester.pumpAndSettle();

      expect(find.textContaining('önce işe giriş yapmalısınız'), findsNothing);
    });
  });

  group('Ucret hak edisi', () {
    test('saat ucreti aylikdan turetilir, fazla mesai 1.5 kat', () {
      // Sunucu hesabi gonderiyor; model onu bozmadan tasimali.
      final w = WageLine.fromJson({
        'defined': true,
        'basis': 'monthly',
        'hourly_rate': 200.0,
        'monthly_salary': 45000.0,
        'meal_daily': 150.0,
        'normal_minutes': 10200,
        'normal_pay': 34000.0,
        'overtime_minutes': 600,
        'overtime_multiplier': 1.5,
        'overtime_pay': 3000.0,
        'leave_minutes': 450,
        'leave_pay': 1500.0,
        'worked_days': 22,
        'meal_pay': 3300.0,
        'gross_total': 41800.0,
      });
      expect(w.basis, 'monthly');
      expect(w.hourlyRate, 200.0);
      // Maas satiri: normal + mesai + izin. Yemek AYRI gosteriliyor.
      expect(w.salaryTotal, 38500.0);
      expect(w.grossTotal, 41800.0);
    });

    test('null ucret SIFIR sayilmaz', () {
      // Sunucu tarafinda tam bu hata olculdu: Number(null) === 0 oldugu icin
      // tanimsiz ucret 0 TL okunuyordu ve herkesin hak edisi sifirlaniyordu.
      final w = WageLine.fromJson({
        'defined': false,
        'hourly_rate': null,
        'monthly_salary': null,
        'meal_daily': null,
        'normal_pay': null,
        'overtime_pay': null,
        'leave_pay': null,
        'meal_pay': null,
        'gross_total': null,
      });
      expect(w.defined, isFalse);
      expect(w.hourlyRate, isNull);
      expect(w.grossTotal, isNull);
      expect(w.mealPay, isNull);
      // Hicbiri tanimli degilse maas satiri da null: "0 TL" yazmak
      // "ucretsiz calisiyor" anlamina gelirdi.
      expect(w.salaryTotal, isNull);
    });

    test('sifir ucret GECERLI bir deger', () {
      final w = WageLine.fromJson({
        'defined': true,
        'basis': 'hourly',
        'hourly_rate': 0.0,
        'normal_pay': 0.0,
        'meal_pay': 0.0,
        'gross_total': 0.0,
      });
      expect(w.hourlyRate, 0.0);
      expect(w.grossTotal, 0.0);
      expect(w.salaryTotal, 0.0);
    });

    test('yetki yoksa ucret alani HIC gelmez', () {
      final r = TimesheetReport.fromJson({
        'from': '2026-09-01',
        'to': '2026-09-30',
        'wages_included': false,
        'items': [
          {
            'user': {'id': 2, 'full_name': 'SENA ÜSTÜNEL'},
            'days': <Object?>[],
            'summary': {'days': 0},
          },
        ],
        'total': {'days': 0},
        'notes': <Object?>[],
      });
      expect(r.wagesIncluded, isFalse);
      expect(r.items.single.wage, isNull);
      expect(r.wageTotal, isNull);
    });

    test('profilde turetilmis saat ucreti ayri tasinir', () {
      final p = PdksProfile.fromJson({
        'user_id': 2,
        'full_name': 'SENA ÜSTÜNEL',
        'role': 'barista',
        'monthly_salary': 45000.0,
        'hourly_rate': null,
        'meal_daily': 150.0,
        'effective_hourly_rate': 200.0,
        'wage_basis': 'monthly',
        'annual_leave_days': 14,
        'monthly_advance_limit': 0,
        'weekly_off_days': [0],
      });
      // hourly_rate NULL ama etkin ucret 200: arayuz "(türetildi)" yaziyor.
      expect(p.hourlyRate, isNull);
      expect(p.effectiveHourlyRate, 200.0);
      expect(p.wageBasis, 'monthly');
    });
  });

  group('Toplu vardiya cizelgesi', () {
    test('menude TUM ekibe acik, IK haric', () {
      final item = navItems.firstWhere((i) => i.path == '/roster');
      expect(item.label, 'Vardiya Çizelgesi');
      expect(item.roles, allRoles);
      // Sunucu IK'yi cizelgeden 403 ile engelliyor; menude gorunmesi bozuk
      // ekrana goturuydu.
      expect(item.roles.contains('hr'), isFalse);
      expect(item.roles.contains('barista'), isTrue);
    });

    test('hucre metni: gece vardiyasi, hafta tatili ve resmi tatil', () {
      final gece = RosterCell.fromJson({
        'start_time': '22:00',
        'end_time': '06:00',
        'crosses_midnight': true,
        'minutes': 480,
        'is_day_off': false,
      });
      final tatil = RosterCell.fromJson({'is_day_off': true});
      final resmi = PublicHoliday.fromJson({
        'holiday_date': '2026-09-23',
        'name': 'ZZ Bayram',
        'is_half_day': false,
      });
      // saatAraligi en-dash (U+2013) kullaniyor; kisa cizgi degil.
      expect(rosterCellText([gece], null), '22:00\u201306:00)');
      expect(rosterCellText([tatil], null), 'HT');
      expect(rosterCellText(const [], null), '-');
      // Resmi tatil atamanin ONUNE geciyor: o gun calisma planlanmaz.
      expect(rosterCellText([gece], resmi), 'RT');
    });

    testWidgets('haftalik tablo ekip, saatler ve toplamlari gosterir', (
      tester,
    ) async {
      tall(tester);
      installFakeApi({'GET /pdks/roster': _cizelge()});
      signInAs('store_manager', storeId: 1);
      await tester.pumpWidget(host(const RosterScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Vardiya Çizelgesi'), findsOneWidget);
      expect(find.text('SENA ÜSTÜNEL'), findsOneWidget);
      expect(find.text('MEHMET ALİ CANBULAT'), findsOneWidget);
      // 510 dk = 8s 30dk, 480 dk = 8s
      expect(find.text('8s 30dk'), findsWidgets);
      // Hafta tatili ve resmi tatil isaretleri.
      expect(find.text('HT'), findsOneWidget);
      expect(find.text('RT'), findsWidgets);
      // Gece vardiyasi ay simgesiyle isaretli.
      expect(find.textContaining('22:00–06:00 🌙'), findsOneWidget);
      expect(find.text('Çalışan sayısı'), findsOneWidget);
    });

    testWidgets('barista cizelgeyi gorur ama PDF dugmesi cikmaz', (
      tester,
    ) async {
      tall(tester);
      installFakeApi({'GET /pdks/roster': _cizelge(canEdit: false)});
      signInAs('barista', storeId: 1);
      await tester.pumpWidget(host(const RosterScreen()));
      await tester.pumpAndSettle();

      expect(find.text('SENA ÜSTÜNEL'), findsOneWidget);
      // can_edit false: disa aktarma yonetici islemi.
      expect(find.text('PDF'), findsNothing);
    });
  });
}

/// Dugme etkin mi. onPressed null ise kapali.
///
/// bySubtype gerekiyor: ButtonStyleButton soyut ve find.byType tam tur
/// esleimesi yapiyor, FilledButton/OutlinedButton'i yakalamiyordu.
bool _acikMi(WidgetTester tester, String etiket) {
  final f = find.ancestor(
    of: find.text(etiket),
    matching: find.bySubtype<ButtonStyleButton>(),
  );
  expect(f, findsWidgets, reason: '"$etiket" dugmesi bulunamadi');
  return tester.widgetList<ButtonStyleButton>(f).first.onPressed != null;
}
