import 'package:flutter/foundation.dart';

import '../models/user.dart';
import 'auth_repository.dart';
import 'api_client.dart';
import 'push.dart';

/// React tarafindaki AuthProvider'in karsiligi: token + kullanici durumu.
class Session extends ChangeNotifier {
  Session({AuthRepository? authRepository})
    : _authRepository = authRepository ?? RemoteAuthRepository(api);

  final AuthRepository _authRepository;
  AppUser? _user;
  bool _loading = true;

  AppUser? get user => _user;
  bool get loading => _loading;
  bool get signedIn => _user != null;

  /// Uygulama acilisinda kayitli token ile oturumu geri yukler.
  Future<void> restore() async {
    if (!await _authRepository.hasSession()) {
      _loading = false;
      notifyListeners();
      return;
    }
    try {
      // Hata satir ici gosterilmedigi icin bildirim bastirilir.
      _user = await _authRepository.restoreUser();
    } catch (_) {
      await _authRepository.clearSession();
      _user = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String username, String password) async {
    _user = await _authRepository.signIn(username, password);
    notifyListeners();
  }

  Future<void> signOut() async {
    // Jeton SUNUCUDAN once silinir: token gecersiz kilindiktan sonra silme
    // istegi 401 alirdi ve cihaz onceki kullanicinin bildirimlerini almaya
    // devam ederdi.
    await unregisterDeviceToken();
    await _authRepository.clearSession();
    _user = null;
    notifyListeners();
  }

  void updateUser(AppUser next) {
    _user = next;
    notifyListeners();
  }
}

final session = Session();
