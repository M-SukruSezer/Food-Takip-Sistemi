import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/auth_repository.dart';
import 'package:foodtakip/core/session.dart';
import 'package:foodtakip/core/token_store.dart';
import 'package:foodtakip/models/user.dart';
import 'package:foodtakip/navigation/route_access_strategy.dart';

const _barista = AppUser(
  id: 1,
  username: 'barista',
  fullName: 'Test Kullanıcı',
  role: 'barista',
);

void main() {
  group('bağımlılık stratejileri', () {
    test('token deposu sözleşmesi altyapıdan bağımsız çalışır', () async {
      final store = _MemoryTokenStore();
      expect(await store.read(), isNull);

      await store.write('abc');
      expect(await store.read(), 'abc');

      await store.clear();
      expect(await store.read(), isNull);
    });

    test('Session kimlik doğrulama deposuyla enjekte edilir', () async {
      final auth = _FakeAuthRepository();
      final session = Session(authRepository: auth);

      await session.restore();
      expect(session.user, _barista);
      expect(session.signedIn, isTrue);

      await session.signIn('barista', 'secret');
      expect(auth.lastUsername, 'barista');
    });

    test('rol stratejisi erişimi ve açılış rotasını belirler', () {
      const strategy = RoleBasedRouteAccessStrategy();

      expect(strategy.landingPath(_barista), '/pdks');
      expect(strategy.canAccess(_barista, '/pdks'), isTrue);
      expect(strategy.canAccess(_barista, '/users'), isFalse);
    });
  });
}

final class _MemoryTokenStore implements TokenStore {
  String? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

final class _FakeAuthRepository implements AuthRepository {
  String? lastUsername;

  @override
  Future<void> clearSession() async {}

  @override
  Future<bool> hasSession() async => true;

  @override
  Future<AppUser> restoreUser() async => _barista;

  @override
  Future<AppUser> signIn(String username, String password) async {
    lastUsername = username;
    return _barista;
  }
}
