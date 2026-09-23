import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Sunucunun kabul ettigi ust sinir (auth.js: AVATAR_MAX_CHARS).
const avatarMaxChars = 400000;

/// Sunucu sadece data URL bekler; kare kirpma ve kucultme istemcide yapilir.
/// Telefon fotolari 3-5 MB geliyor, ham hali sinirin cok ustunde kaliyor.
///
/// React tarafinda ayni is canvas ile yapiliyor; burada `image` paketiyle
/// yapildigi icin ayni sonuc tum platformlarda (Windows/Linux dahil) cikar.
String encodeAvatar(Uint8List bytes, {int side = 256, int quality = 82}) {
  // Bozuk ya da gorsel olmayan dosyada decodeImage null donmek yerine
  // RangeError atabiliyor; profil ekrani mesaj gosterebilsin diye tek bir
  // hata tipine cevrilir.
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) {
    throw const FormatException('Görsel açılamadı');
  }
  // Kareye ortalanarak kirpilir, sonra hedef boyuta indirilir.
  final crop = decoded.width < decoded.height ? decoded.width : decoded.height;
  final square = img.copyCrop(
    decoded,
    x: ((decoded.width - crop) / 2).round(),
    y: ((decoded.height - crop) / 2).round(),
    width: crop,
    height: crop,
  );
  final resized = img.copyResize(square, width: side, height: side);

  var q = quality;
  // Nadiren de olsa desenli fotolar 82 kalitede sinirin ustunde kalabiliyor;
  // sunucudan 400 almak yerine kalite kademeli dusurulur.
  while (true) {
    final jpeg = img.encodeJpg(resized, quality: q);
    final url = 'data:image/jpeg;base64,${base64Encode(jpeg)}';
    if (url.length <= avatarMaxChars || q <= 40) return url;
    q -= 12;
  }
}
