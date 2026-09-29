import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'opts.dart';
import 'avatar_image.dart';

final loginArtwork = ValueNotifier<String?>(null);

Future<void> loadLoginArtwork() async {
  final r = await api.dio.get<Map<String, dynamic>>(
    '/branding/login',
    options: apiOptions(silent: true),
  );
  final value = r.data?['image'];
  loginArtwork.value =
      value is String && value.startsWith('data:image/jpeg;base64,')
      ? value
      : null;
}

String encodeLoginArtwork(Uint8List bytes) {
  if (bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('Lütfen 20 MB altında bir görsel seçin.');
  }
  final image = encodeReceipt(bytes, maxSide: 1280, quality: 82);
  if (image.length > receiptMaxChars) {
    throw const FormatException(
      'Görsel çok büyük. Daha küçük bir görsel seçin.',
    );
  }
  return image;
}

Future<void> saveLoginArtwork(String? image) async {
  final r = await api.dio.put<Map<String, dynamic>>(
    '/branding/login',
    data: {'image': image},
    options: apiOptions(noToast: true),
  );
  loginArtwork.value = r.data?['image'] as String?;
}
