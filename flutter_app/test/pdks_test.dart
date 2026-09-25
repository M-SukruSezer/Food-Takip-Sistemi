import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/format.dart';
import 'package:foodtakip/core/nav.dart';
import 'package:foodtakip/models/pdks.dart';
import 'package:foodtakip/screens/pdks_admin_screen.dart';
import 'package:foodtakip/screens/pdks_screen.dart';
import 'package:foodtakip/widgets/crud_scaffold.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:foodtakip/widgets/qr_view.dart';

import 'support/fake_api.dart';

Map<String, Object?> _status({
  bool inside = false,
  bool enabled = true,
  bool hasLocation = true,
  List<Map<String, Object?>>? shifts,
  List<Map<String, Object?>>? logs,
}) => {
      'work_date': '2026-11-02',
      'is_inside': inside,
      'open_since': inside ? '2026-11-02T05:00:00.000Z' : null,
      'store': {
        'id': 1, 'name': 'DÜZCE MERKEZ', 'pdks_enabled': enabled,
        'qr_mode': 'rotating', 'latitude': hasLocation ? 40.8438 : null,
        'longitude': hasLocation ? 31.1565 : null,
        'geofence_radius_m': 100, 'has_location': hasLocation,
      },
      'shifts': shifts ?? [
        {'name': 'Gündüz', 'start_time': '08:00', 'end_time': '17:00',
         'break_duration_minutes': 60, 'late_tolerance_minutes': 10, 'is_day_off': false},
      ],
      'logs': logs ?? [],
    };

final _balance = {
  'leave': {'entitlement_days': 14, 'used_days': 3, 'pending_days': 2,
    'remaining_days': 9, 'over_used': false},
  'hourly_leave': {'used_hours': 4, 'pending_hours': 0, 'deducted_from_annual': false},
  'advance': {'monthly_limit': 3000, 'used': 500, 'pending': 0, 'remaining': 2500,
    'over_used': false},
  'leave_year': {'from': '2026-03-15', 'to': '2027-03-14', 'basis': 'anniversary'},
  'month': {'from': '2026-11-01', 'to': '2026-11-30'},
  'weekly_off_days': [0],
  'notes': ['Yıllık izin hesabında hafta tatili düşülür, resmi tatiller düşülmez.'],
};

Map<String, Object?> _routes({Map<String, Object?>? status}) => {
      'GET /pdks/me': status ?? _status(),
      'GET /pdks/requests/balances': _balance,
      'GET /pdks/requests': const <Object>[],
      'GET /pdks/assignments': const <Object>[],
    };

void main() {
  setUpAll(initTestFormatting);

  void tall(WidgetTester tester, [double h = 3200]) {
    tester.view.physicalSize = Size(800, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('Süre biçimi', () {
    test('dakika saate çevrilir', () {
      expect(fmtDuration(0), '-');
      expect(fmtDuration(null), '-');
      expect(fmtDuration(45), '45 dk');
      expect(fmtDuration(60), '1s');
      expect(fmtDuration(510), '8s 30dk');
      expect(fmtDuration(-90), '-1s 30dk');
    });

    test('ay adı Türkçe', () {
      expect(fmtMonth('2026-11'), 'Kasım 2026');
      expect(fmtMonth('2026-01'), 'Ocak 2026');
      expect(fmtMonth('bozuk'), 'bozuk');
      expect(fmtMonth('2026-13'), '2026-13');
    });
  });

  group('Modeller', () {
    test('QR sırrı model alanlarında yok', () {
      final s = PdksStore.fromJson(
          (_status()['store'] as Map<String, dynamic>));
      // Sunucu sirri dondurmuyor; model de tasimamali.
      expect(s.toString().contains('secret'), isFalse);
      expect(s.hasLocation, isTrue);
      expect(s.geofenceRadiusM, 100);
    });

    test('gece vardiyası tespiti', () {
      final gece = PdksShift.fromJson(
          {'start_time': '22:00', 'end_time': '06:00', 'name': 'Gece'});
      final gunduz = PdksShift.fromJson(
          {'start_time': '08:00', 'end_time': '17:00', 'name': 'Gündüz'});
      expect(gece.crossesMidnight, isTrue);
      expect(gunduz.crossesMidnight, isFalse);
    });

    test('sabit QR süresi dolmaz', () {
      expect(QrToken.fromJson({'token': 'PDKS1S:1:x', 'mode': 'static'}).isStatic, isTrue);
      expect(QrToken.fromJson({'token': 'PDKS1:1:2:x', 'mode': 'rotating'}).isStatic, isFalse);
    });

    test('bakiye alanları ayrışır', () {
      final b = PdksBalance.fromJson(_balance);
      expect(b.remainingDays, 9);
      expect(b.pendingDays, 2);
      expect(b.advanceRemaining, 2500);
      expect(b.hourlyUsedHours, 4);
      expect(b.notes.length, 1);
    });

    test('anlık durum içeride/dışarıda ayırır', () {
      final p = PresenceSnapshot.fromJson({
        'inside_count': 1,
        'inside': [{'user_id': 1, 'full_name': 'A', 'role': 'barista',
          'last_type': 'GIRIS', 'minutes_since': 95}],
        'outside': [{'user_id': 2, 'full_name': 'B', 'role': 'barista',
          'last_type': 'CIKIS'}],
      });
      expect(p.insideCount, 1);
      expect(p.inside.first.isInside, isTrue);
      expect(p.outside.first.isInside, isFalse);
    });
  });

  group('Personel ekranı', () {
    testWidgets('dışarıdayken giriş düğmesi, içerideyken çıkış', (tester) async {
      tall(tester);
      installFakeApi(_routes());
      signInAs('barista', storeId: 1);

      await tester.pumpWidget(host(const PdksScreen()));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Pill, 'İş yerinde değilsiniz'), findsOneWidget);
      expect(find.text('Konumla İşe Başla'), findsOneWidget);
      expect(find.text('Konumla İşi Bitir'), findsNothing);
      expect(find.text('QR Okut (giriş)'), findsOneWidget);
    });

    testWidgets('içerideyken çıkış düğmesi ve giriş saati', (tester) async {
      tall(tester);
      installFakeApi(_routes(status: _status(inside: true)));
      signInAs('barista', storeId: 1);

      await tester.pumpWidget(host(const PdksScreen()));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Pill, 'İş yerindesiniz'), findsOneWidget);
      expect(find.text('Konumla İşi Bitir'), findsOneWidget);
      expect(find.textContaining('itibarıyla giriş yapıldı'), findsOneWidget);
      expect(find.text('QR Okut (çıkış)'), findsOneWidget);
    });

    testWidgets('KVKK bilgisi gösterilir', (tester) async {
      tall(tester);
      installFakeApi(_routes());
      signInAs('barista', storeId: 1);

      await tester.pumpWidget(host(const PdksScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('yalnızca giriş/çıkış anında alınır'), findsOneWidget);
      expect(find.textContaining('Arka planda konum izlenmez'), findsOneWidget);
      expect(find.textContaining('100 m'), findsOneWidget);
    });

    testWidgets('PDKS kapalıysa uyarı ve düğmeler kapalı', (tester) async {
      tall(tester);
      installFakeApi(_routes(status: _status(enabled: false)));
      signInAs('barista', storeId: 1);

      await tester.pumpWidget(host(const PdksScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('devam takibi henüz açılmamış'), findsOneWidget);
      final btn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Konumla İşe Başla'));
      expect(btn.onPressed, isNull);
    });

    testWidgets('mağaza konumu yoksa konumla giriş kapalı, QR açık', (tester) async {
      tall(tester);
      installFakeApi(_routes(status: _status(hasLocation: false)));
      signInAs('barista', storeId: 1);

      await tester.pumpWidget(host(const PdksScreen()));
      await tester.pumpAndSettle();

      final gps = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Konumla İşe Başla'));
      expect(gps.onPressed, isNull);
      expect(find.textContaining('konumla giriş kapalı'), findsOneWidget);
      // QR yine kullanilabilir.
      final qr = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'QR Okut (giriş)'));
      expect(qr.onPressed, isNotNull);
    });

    testWidgets('bugünün vardiyası ve kayıtları', (tester) async {
      tall(tester);
      installFakeApi(_routes(status: _status(logs: [
        {'id': 1, 'type': 'GIRIS', 'method': 'GPS',
         'occurred_at': '2026-11-02T05:02:00.000Z', 'distance_m': 42},
        {'id': 2, 'type': 'CIKIS', 'method': 'QR',
         'occurred_at': '2026-11-02T14:05:00.000Z'},
      ])));
      signInAs('barista', storeId: 1);

      await tester.pumpWidget(host(const PdksScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Gündüz · 08:00-17:00'), findsOneWidget);
      expect(find.textContaining('10 dk tolerans'), findsOneWidget);
      expect(find.widgetWithText(Pill, 'Giriş'), findsOneWidget);
      expect(find.widgetWithText(Pill, 'Çıkış'), findsOneWidget);
      // GPS kaydinda mesafe, QR'da yok.
      expect(find.textContaining('GPS · 42 m'), findsOneWidget);
      expect(find.text('QR'), findsOneWidget);
    });

    testWidgets('bakiye kartı bekleyeni ayrı gösterir', (tester) async {
      tall(tester);
      installFakeApi(_routes());
      signInAs('barista', storeId: 1);

      await tester.pumpWidget(host(const PdksScreen()));
      await tester.pumpAndSettle();

      expect(find.text('9 gün'), findsOneWidget);   // kalan
      expect(find.text('2 gün'), findsOneWidget);   // bekleyen
      expect(find.text('2.500,00 TL'), findsOneWidget);
      expect(find.textContaining('4 saat saatlik izin'), findsOneWidget);
      expect(find.textContaining('resmi tatiller düşülmez'), findsOneWidget);
    });

    testWidgets('vardiya takvimi Pazartesi ile başlar', (tester) async {
      tall(tester);
      installFakeApi(_routes());
      signInAs('barista', storeId: 1);

      await tester.pumpWidget(host(const PdksScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(ShiftCalendar), findsOneWidget);
      expect(find.text('Pzt'), findsOneWidget);
      expect(find.text('Paz'), findsOneWidget);
      // Pazartesi ilk sirada.
      expect(tester.getTopLeft(find.text('Pzt')).dx,
          lessThan(tester.getTopLeft(find.text('Paz')).dx));
    });
  });

  group('QR gösterici', () {
    testWidgets('zemin her zaman beyaz', (tester) async {
      // Koyu temada koyu zeminde QR okunamaz.
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(body: QrView(data: 'PDKS1:1:2:abc', label: 'test')),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
      final box = tester.widget<Container>(find.ancestor(
        of: find.byType(QrImageView), matching: find.byType(Container)).first);
      final deco = box.decoration as BoxDecoration;
      expect(deco.color, Colors.white);
      expect(find.text('test'), findsOneWidget);
    });
  });

  group('Yönetici ekranı', () {
    Map<String, Object?> adminRoutes() => {
          'GET /pdks/now': {
            'as_of': '2026-11-02T09:00:00.000Z',
            'work_date': '2026-11-02',
            'inside_count': 1,
            'inside': [{'user_id': 3, 'full_name': 'TALAT HAMZA', 'role': 'barista',
              'last_type': 'GIRIS', 'last_method': 'GPS',
              'last_at': '2026-11-02T05:02:00.000Z', 'minutes_since': 95,
              'distance_m': 42}],
            'outside': [{'user_id': 4, 'full_name': 'ALİ CANBULAT',
              'role': 'shift_supervisor', 'last_type': 'CIKIS',
              'last_at': '2026-11-01T14:00:00.000Z'}],
          },
          'GET /pdks/requests': [
            {'id': 7, 'user_id': 3, 'full_name': 'TALAT HAMZA', 'type': 'AVANS',
             'amount': 500, 'reason': 'Acil', 'status': 'PENDING'},
          ],
          'GET /pdks/timesheet': {
            'from': '2026-11-01', 'to': '2026-11-02',
            'items': [{
              'user': {'id': 3, 'full_name': 'TALAT HAMZA'},
              'days': [{'work_date': '2026-11-02', 'presence_minutes': 540,
                'worked_minutes': 480, 'scheduled_minutes': 480,
                'overtime_minutes': 0, 'missing_minutes': 0, 'late_minutes': 0,
                'is_day_off': false, 'on_leave': false, 'statuses': [],
                'shift_names': ['Gündüz']}],
              'summary': {'days': 1, 'worked_days': 1, 'absent_days': 0,
                'leave_days': 0, 'worked_minutes': 480, 'scheduled_minutes': 480,
                'overtime_minutes': 120, 'missing_minutes': 0, 'late_minutes': 30,
                'unscheduled_minutes': 0},
            }],
            'total': {'days': 1, 'worked_minutes': 480, 'overtime_minutes': 120,
              'missing_minutes': 0, 'unscheduled_minutes': 0},
            'notes': ['Mola, İş Kanunu m.68 asgarisi ile...'],
          },
        };

    testWidgets('anlık durum içeridekini süresiyle gösterir', (tester) async {
      tall(tester);
      installFakeApi(adminRoutes());
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(host(const PdksAdminScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Şu an işte: 1 kişi'), findsOneWidget);
      expect(find.text('TALAT HAMZA'), findsOneWidget);
      expect(find.widgetWithText(Pill, '1s 35dk'), findsOneWidget);
      expect(find.textContaining('GPS · 42 m'), findsOneWidget);
      // Disarida olan da listede.
      expect(find.text('ALİ CANBULAT'), findsOneWidget);
    });

    testWidgets('talep sekmesinde onayla/reddet çıkar', (tester) async {
      tall(tester);
      installFakeApi(adminRoutes());
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(host(const PdksAdminScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Talepler'));
      await tester.pumpAndSettle();

      expect(find.text('Onayla'), findsOneWidget);
      expect(find.text('Reddet'), findsOneWidget);
      expect(find.textContaining('Avans · 500,00 TL'), findsOneWidget);
      expect(find.textContaining('vardiya atanmaz'), findsOneWidget);
    });

    testWidgets('puantaj sekmesi özeti gösterir', (tester) async {
      tall(tester);
      installFakeApi(adminRoutes());
      signInAs('store_manager', storeId: 1);

      await tester.pumpWidget(host(const PdksAdminScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Puantaj'));
      await tester.pumpAndSettle();

      expect(find.text('Çalışılan'), findsOneWidget);
      expect(find.text('8s'), findsOneWidget);       // 480 dk
      expect(find.text('2s'), findsOneWidget);       // 120 dk mesai
      expect(find.textContaining('1 gün çalıştı'), findsOneWidget);
      expect(find.textContaining('30 dk geç'), findsOneWidget);
    });
  });

  group('Menü', () {
    test('personel ekranı herkeste, yönetim ekranı yöneticide', () {
      final staff = navItems.firstWhere((i) => i.path == '/pdks');
      expect(staff.label, 'Devam Takibi');
      expect(staff.roles, allRoles);

      final admin = navItems.firstWhere((i) => i.path == '/pdks-admin');
      expect(admin.roles, managerRoles);
      expect(admin.roles, isNot(contains('barista')));
    });

    test('devam takibi Operasyon grubunda', () {
      final op = navGroups.firstWhere((g) => g.title == 'Operasyon');
      expect(op.items.map((i) => i.path), contains('/pdks'));
      final yon = navGroups.firstWhere((g) => g.title == 'Yönetim');
      expect(yon.items.map((i) => i.path), contains('/pdks-admin'));
    });
  });
}
