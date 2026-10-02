import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Telefonun kalici kimligi: hesap ilk acildigi telefona eslestirilir ve
/// baska telefondan acilmaya calisilinca sunucu hesabi bloke eder.
///
/// Android'de ANDROID_ID kullanilir (uygulama silinip yeniden kurulsa da
/// ayni kalir; fabrika ayarlarina donunce degisir). Kanal yoksa (iOS,
/// testler) bir kez uretilen rastgele kimlik saklanir. Web'de kimlik
/// gonderilmez: tarayici bir telefon degil.
class DeviceIdentity {
  static const _channel = MethodChannel('foodtakip/device');
  static const _prefKey = 'device_identity';

  String? _id;
  String? _name;

  String? get id => _id;
  String? get name => _name;

  /// Isteklere eklenen basliklar; yuklenmediyse bos.
  Map<String, String> get headers => {
    'X-Device-Id': ?_id,
    'X-Device-Name': ?_name,
  };

  Future<void> load() async {
    if (kIsWeb) return;
    try {
      final info = await _channel.invokeMapMethod<String, String>('info');
      final androidId = info?['id'];
      if (androidId != null && androidId.isNotEmpty) {
        _id = 'a:$androidId';
        _name = _ascii(info?['name']);
        return;
      }
    } catch (_) {
      // Kanal yok: yedek kimlige gecilir.
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      var stored = prefs.getString(_prefKey);
      if (stored == null) {
        final r = Random.secure();
        stored =
            'u:${List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
        await prefs.setString(_prefKey, stored);
      }
      _id = stored;
      _name = _ascii(defaultTargetPlatform.name);
    } catch (_) {
      // Kimlik uretilemezse istekler basliksiz gider.
    }
  }

  /// HTTP basliklari yalnizca ASCII tasir.
  static String? _ascii(String? v) {
    if (v == null) return null;
    final s = v.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    if (s.isEmpty) return null;
    return s.length > 80 ? s.substring(0, 80) : s;
  }
}

final deviceIdentity = DeviceIdentity();
