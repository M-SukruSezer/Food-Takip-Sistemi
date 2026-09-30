import '../models/user.dart';
import 'api_client.dart';
import 'opts.dart';

abstract interface class AuthRepository {
  Future<bool> hasSession();
  Future<AppUser> restoreUser();
  Future<AppUser> signIn(String username, String password);
  Future<void> clearSession();
}

final class RemoteAuthRepository implements AuthRepository {
  const RemoteAuthRepository(this._client);

  final ApiClient _client;

  @override
  Future<bool> hasSession() async {
    await _client.loadToken();
    return _client.token != null;
  }

  @override
  Future<AppUser> restoreUser() async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/auth/me',
      options: apiOptions(noToast: true),
    );
    return AppUser.fromJson(response.data!);
  }

  @override
  Future<AppUser> signIn(String username, String password) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'username': username, 'password': password},
      options: apiOptions(noToast: true, busyMessage: 'Giriş yapılıyor...'),
    );
    final data = response.data!;
    await _client.setToken(data['token'] as String);
    return AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  @override
  Future<void> clearSession() => _client.setToken(null);
}
