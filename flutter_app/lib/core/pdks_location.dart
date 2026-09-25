import 'package:geolocator/geolocator.dart';

/// Giris/cikis icin anlik konum.
///
/// KVKK: konum yalnizca islem aninda aliniyor, arka planda izleme yok. Bu
/// yuzden ACCESS_BACKGROUND_LOCATION istenmiyor.
class PdksPosition {
  const PdksPosition({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.isMocked,
  });

  final double latitude;
  final double longitude;
  final double accuracy;

  /// Android/iOS sahte konum bayragi. Web'de bilinmedigi icin null olabilir.
  final bool? isMocked;
}

/// Konum alinamadiginda kullaniciya gosterilecek sebep.
class LocationDenied implements Exception {
  LocationDenied(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Anlik konumu alir.
///
/// Onbellekteki eski konum KABUL EDILMEZ: giris anindaki konum gerekiyor,
/// yoksa personel isyerinden ayrilirken eski konumla islem yapabilir.
Future<PdksPosition> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw LocationDenied('Konum servisi kapalı. Ayarlardan açıp tekrar deneyin.');
  }

  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.denied) {
    throw LocationDenied('Konum izni verilmedi.');
  }
  if (perm == LocationPermission.deniedForever) {
    throw LocationDenied(
      'Konum izni kalıcı olarak kapatılmış. Uygulama ayarlarından açın.',
    );
  }

  final p = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 20),
    ),
  );
  return PdksPosition(
    latitude: p.latitude,
    longitude: p.longitude,
    accuracy: p.accuracy,
    isMocked: p.isMocked,
  );
}
