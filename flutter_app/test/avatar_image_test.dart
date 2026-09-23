import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/avatar_image.dart';
import 'package:image/image.dart' as img;

/// Sunucunun kabul ettigi bicim (auth.js AVATAR_PATTERN).
final _serverPattern = RegExp(r'^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$');

List<int> base64Body(String dataUrl) => base64Decode(dataUrl.split(',').last);

Uint8List _photo(int width, int height) {
  final image = img.Image(width: width, height: height);
  // Duz renk cok iyi sikistigi icin gurultu konur: gercek fotoya yakin boyut.
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, (x * 7) % 256, (y * 13) % 256, (x * y) % 256);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('buyuk foto sunucu sinirinin altina iner', () {
    final url = encodeAvatar(_photo(2000, 1500));
    expect(_serverPattern.hasMatch(url), isTrue);
    expect(url.length, lessThanOrEqualTo(avatarMaxChars));
  });

  test('dikdortgen foto kareye kirpilir', () {
    final url = encodeAvatar(_photo(800, 400));
    final decoded = img.decodeJpg(Uint8List.fromList(
      // data URL onekinden sonrasi base64 govde.
      base64Body(url),
    ))!;
    expect(decoded.width, 256);
    expect(decoded.height, 256);
  });

  test('gecersiz veri anlasilir hata verir', () {
    expect(
      () => encodeAvatar(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(isA<FormatException>()),
    );
  });
}
