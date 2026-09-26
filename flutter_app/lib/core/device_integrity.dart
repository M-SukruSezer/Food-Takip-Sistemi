import 'package:flutter/foundation.dart';
import 'package:safe_device/safe_device.dart';
import 'package:safe_device/safe_device_config.dart';

/// Cihaz butunluk raporu. Giris/cikis aninda toplanip sunucuya gonderilir.
///
/// NE OLDUGU: caydirici ve denetim sinyali. KANIT DEGIL — kurcalanmis bir
/// istemci bu alanlarin hepsini "temiz" gonderebilir. Gercek dogrulama
/// sunucuda: donen QR imzasi, geofence mesafesi ve onceki kayitla arasindaki
/// hiz. Bu rapor onlarin uzerine biner.
class DeviceIntegrity {
  const DeviceIntegrity({
    this.rooted,
    this.emulator,
    this.devMode,
    this.usbDebug,
    this.externalStorage,
    required this.checked,
  });

  /// Root (Android) / jailbreak (iOS).
  final bool? rooted;

  /// Emulator ya da gercek olmayan cihaz.
  final bool? emulator;

  /// Gelistirici secenekleri acik. Yalnizca Android.
  final bool? devMode;

  /// USB hata ayiklama acik. Yalnizca Android.
  final bool? usbDebug;

  /// Uygulama harici depolamada. Yalnizca Android.
  final bool? externalStorage;

  /// Kontroller tamamlandi mi. false ise sunucu kaydi "unverified"
  /// bayragiyla isaretler: kutuphane hata durumunda false donduruyor, o
  /// sessizligin "temiz" sayilmamasi gerekiyor.
  final bool checked;

  /// Hicbir kontrolun yapilamadigi durum (web, zaman asimi, kanal hatasi).
  static const DeviceIntegrity unknown = DeviceIntegrity(checked: false);

  /// Sunucunun bekledigi govde. Null alanlar HIC gonderilmez: sunucu
  /// "bilinmiyor" ile "false" arasinda ayrim yapiyor.
  Map<String, dynamic> toJson() => {
    if (rooted != null) 'rooted': rooted,
    if (emulator != null) 'emulator': emulator,
    if (devMode != null) 'dev_mode': devMode,
    if (usbDebug != null) 'usb_debug': usbDebug,
    if (externalStorage != null) 'external_storage': externalStorage,
    'checked': checked,
  };

  /// Kullaniciya gosterilecek uyarilar. Bu bayraklar islemi engellemiyor;
  /// engelleyenler (sahte konum, emulator) sunucudan hata olarak donuyor.
  List<String> get warnings => [
    if (rooted == true) 'Cihaz rootlu / jailbreak',
    if (devMode == true) 'Geliştirici seçenekleri açık',
    if (usbDebug == true) 'USB hata ayıklama açık',
    if (externalStorage == true) 'Uygulama harici depolamada',
    if (!checked) 'Cihaz güvenlik kontrolü yapılamadı',
  ];
}

bool _initiated = false;

/// safe_device'i konum kontrolu KAPALI baslatir.
///
/// NEDEN KAPALI: paketin Android kaynagina bakildiginda `isMockLocation`
/// cagrisi kendi SUREKLI konum akisini baslatiyor (startLocationUpdates).
/// Iki sorun:
///   1. KVKK — konumu yalnizca islem aninda aliyoruz, arka planda izleme yok.
///      Paketin kendi akisi bu taahhudu bozardi.
///   2. Ilk cagri, akistan henuz konum gelmediginden bayrak ne olursa olsun
///      false donuyor; yanlis bir guvence uretirdi.
/// Sahte konum bayragi bunun yerine geolocator'dan, KULLANDIGIMIZ olcumun
/// kendisinden okunuyor (Android: Location.isFromMockProvider).
void _ensureInit() {
  if (_initiated) return;
  SafeDevice.init(const SafeDeviceConfig(mockLocationCheckEnabled: false));
  _initiated = true;
}

/// Cihaz butunlugunu toplar.
///
/// [timeout] tamaminin ust siniri: platform kanali takilirsa personel mesaiye
/// giremeyecek hale gelmesin. Zaman asiminda checked=false doner.
Future<DeviceIntegrity> readDeviceIntegrity({
  Duration timeout = const Duration(seconds: 4),
}) async {
  // Web'de bu kontrollerin hicbiri yok; false gondermek yanlis guvence olur.
  if (kIsWeb) return DeviceIntegrity.unknown;
  final platform = defaultTargetPlatform;
  final android = platform == TargetPlatform.android;
  final ios = platform == TargetPlatform.iOS;
  if (!android && !ios) return DeviceIntegrity.unknown;

  try {
    _ensureInit();
    return await _collect(android).timeout(timeout);
  } catch (_) {
    // Hata yutulur ama "temiz" sayilmaz: checked=false ile bildirilir.
    return DeviceIntegrity.unknown;
  }
}

Future<DeviceIntegrity> _collect(bool android) async {
  final rooted = await SafeDevice.isJailBroken;
  final real = await SafeDevice.isRealDevice;
  // Android'e ozgu kontroller iOS'ta anlamsiz; false degil NULL gonderilir.
  final devMode = android ? await SafeDevice.isDevelopmentModeEnable : null;
  final usb = android ? await SafeDevice.isUsbDebuggingEnabled : null;
  final ext = android ? await SafeDevice.isOnExternalStorage : null;
  return DeviceIntegrity(
    rooted: rooted,
    emulator: !real,
    devMode: devMode,
    usbDebug: usb,
    externalStorage: ext,
    checked: true,
  );
}
