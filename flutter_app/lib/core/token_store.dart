import 'package:shared_preferences/shared_preferences.dart';

/// Kimlik jetonunun nerede saklandığını HTTP katmanından ayırır.
abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

final class SharedPreferencesTokenStore implements TokenStore {
  const SharedPreferencesTokenStore({this.key = 'token'});

  final String key;

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(key);
  }

  @override
  Future<void> write(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, value);
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
  }
}
