import 'package:shared_preferences/shared_preferences.dart';

/// "Beni hatirla": yalnizca kullanici adi cihazda saklanir. Sifre hicbir
/// zaman saklanmaz. React istemcisi ayni ismi localStorage'da tutuyor.
const _key = 'rememberedUser';

Future<String?> rememberedUsername() async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getString(_key);
  return (value == null || value.isEmpty) ? null : value;
}

Future<void> setRememberedUsername(String? username) async {
  final prefs = await SharedPreferences.getInstance();
  if (username == null || username.isEmpty) {
    await prefs.remove(_key);
  } else {
    await prefs.setString(_key, username);
  }
}
