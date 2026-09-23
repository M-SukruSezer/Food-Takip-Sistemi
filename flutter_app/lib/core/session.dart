import 'package:flutter/foundation.dart';

import '../models/user.dart';
import 'api_client.dart';
import 'opts.dart';

/// React tarafindaki AuthProvider'in karsiligi: token + kullanici durumu.
class Session extends ChangeNotifier {
  AppUser? _user;
  bool _loading = true;

  AppUser? get user => _user;
  bool get loading => _loading;
  bool get signedIn => _user != null;

  /// Uygulama acilisinda kayitli token ile oturumu geri yukler.
  Future<void> restore() async {
    await api.loadToken();
    if (api.token == null) {
      _loading = false;
      notifyListeners();
      return;
    }
    try {
      // Hata satir ici gosterilmedigi icin bildirim bastirilir.
      final r = await api.dio.get<Map<String, dynamic>>(
        '/auth/me',
        options: apiOptions(noToast: true),
      );
      _user = AppUser.fromJson(r.data!);
    } catch (_) {
      await api.setToken(null);
      _user = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String username, String password) async {
    final r = await api.dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'username': username, 'password': password},
      // Giris hatasi formun icinde gosterilir; ayrica bildirim verilmez.
      options: apiOptions(noToast: true),
    );
    final data = r.data!;
    await api.setToken(data['token'] as String);
    _user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    notifyListeners();
  }

  Future<void> signOut() async {
    await api.setToken(null);
    _user = null;
    notifyListeners();
  }

  void updateUser(AppUser next) {
    _user = next;
    notifyListeners();
  }
}

final session = Session();
