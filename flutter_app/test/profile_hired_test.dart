import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/api_client.dart';
import 'package:foodtakip/core/format.dart';
import 'package:foodtakip/core/session.dart';
import 'package:foodtakip/screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

/// Profil açılınca kullanıcı bilgisi sunucudan tazelenir: oturum açıldıktan
/// sonra girilen işe giriş tarihi de görünür.
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

  testWidgets('işe giriş tarihi /auth/me ile tazelenip gösterilir', (tester) async {
    installFakeApi({
      'GET /auth/me': {
        'id': 1,
        'username': 'test',
        'full_name': 'Test Kullanici',
        'role': 'store_manager',
        'store_id': 4,
        'hired_at': '2025-06-14',
      },
    });
    signInAs('store_manager', storeId: 4);
    expect(session.user?.hiredAt, isNull);

    await tester.pumpWidget(host(const ProfileScreen()));
    await tester.pumpAndSettle();

    expect(session.user?.hiredAt, '2025-06-14');
    expect(find.text(fmtDate('2025-06-14')), findsOneWidget);
    expect(find.text('Tanımlı değil'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });
}
