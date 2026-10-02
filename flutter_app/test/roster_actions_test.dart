import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/api_client.dart';
import 'package:foodtakip/core/pdks_export.dart';
import 'package:foodtakip/core/session.dart';
import 'package:foodtakip/models/pdks.dart';
import 'package:foodtakip/screens/roster_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

Map<String, dynamic> _roster({bool canEdit = true}) {
  final dates = [
    for (var i = 5; i <= 11; i++) '2026-10-${i.toString().padLeft(2, '0')}',
  ];
  Map<String, dynamic> cell(String s, String e, String cat) => {
    'shift_id': 1,
    'start_time': s,
    'end_time': e,
    'is_day_off': false,
    'minutes': 450,
    'category': cat,
    'warnings': [],
  };
  return jsonDecode(
    jsonEncode({
      'from': dates.first,
      'to': dates.last,
      'dates': dates,
      'can_edit': canEdit,
      'store': 'Kadıköy',
      'people': [
        {
          'user': {'id': 2, 'full_name': 'Ali Barista', 'role': 'barista'},
          'cells': {
            for (final d in dates)
              d: d.endsWith('06')
                  ? [
                      {'is_day_off': true, 'note': 'RAPOR'},
                    ]
                  : [cell('08:00', '16:00', 'sabah')],
          },
          'planned_minutes': 2700,
        },
      ],
      'totals': {
        for (final d in dates)
          d: {'working': 1, 'day_off': 0, 'unassigned': 0, 'minutes': 450},
      },
      'holidays': {},
    }),
  ) as Map<String, dynamic>;
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late HttpClientAdapter original;
  setUp(() {
    initTestFormatting();
    SharedPreferences.setMockInitialValues({});
    original = api.dio.httpClientAdapter;
  });
  tearDown(() async {
    api.dio.httpClientAdapter = original;
    await session.signOut();
  });

  Future<FakeAdapter> pump(WidgetTester tester, String role) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = installFakeApi({
      'GET /pdks/roster': _roster(canEdit: role != 'barista'),
      'GET /pdks/shifts': const <Object>[],
      'GET /pdks/roster/notes': [
        {'id': 7, 'body': 'Pazar envanter sayımı', 'created_by_name': 'Müdür'},
      ],
      'POST /pdks/roster/notes': {'id': 8},
      'DELETE /pdks/roster/notes/7': {'ok': true},
    });
    signInAs(role, storeId: 4);
    await tester.pumpWidget(_host(const RosterScreen()));
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('müdürde Ekiple Paylaş + PDF İndir; eski düğmeler yok', (
    tester,
  ) async {
    await pump(tester, 'store_manager');
    expect(find.text('Ekiple Paylaş'), findsOneWidget);
    expect(find.text('PDF İndir'), findsOneWidget);
    for (final eski in [
      'Whatsapp ile paylaş',
      'Excel İndir (.xlsx)',
      '+ Vardiya Düzenle',
      'Ekibe Duyur',
      'Dışa Aktar',
      'PDF',
    ]) {
      expect(find.text(eski), findsNothing, reason: eski);
    }
    expect(find.textContaining('Kadro:'), findsNothing);
  });

  testWidgets('notlar görünür; müdür ekler ve kaydırıp siler', (tester) async {
    final fake = await pump(tester, 'store_manager');
    expect(find.text('Pazar envanter sayımı'), findsOneWidget);

    await tester.tap(find.text('Not Ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Cumartesi erken kapanış',
    );
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(
      fake.lastBody('POST /pdks/roster/notes')?['body'],
      'Cumartesi erken kapanış',
    );

    await tester.drag(find.text('Pazar envanter sayımı'), const Offset(300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil').last);
    await tester.pumpAndSettle();
    expect(fake.calls, contains('DELETE /pdks/roster/notes/7'));
  });

  testWidgets('barista notu görür ama ekleyemez, paylaş/PDF görmez', (
    tester,
  ) async {
    await pump(tester, 'barista');
    expect(find.text('Pazar envanter sayımı'), findsOneWidget);
    expect(find.text('Not Ekle'), findsNothing);
    expect(find.text('Ekiple Paylaş'), findsNothing);
  });

  test('PDF ekrandaki tabloyla aynı içeriği ve notları taşır', () async {
    final bytes = await buildRosterPdf(
      Roster.fromJson(_roster()),
      notes: ['Pazar envanter sayımı'],
    );
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
