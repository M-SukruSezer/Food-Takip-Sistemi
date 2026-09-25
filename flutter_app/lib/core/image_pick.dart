import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// image_picker'in Linux ve Windows karsiligi yok; oralarda cagri
/// MissingPluginException atardi. Masaustunde dosya secici kullanilir.
bool usesFileSelector(TargetPlatform platform, {bool isWeb = false}) {
  if (isWeb) return false;
  return platform == TargetPlatform.linux ||
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.macOS;
}

const _imageTypes = XTypeGroup(
  label: 'Görseller',
  extensions: ['png', 'jpg', 'jpeg', 'webp'],
  mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
);

/// Kullaniciya gorsel sectirir; iptal ederse null doner.
///
/// [fromCamera] yalnizca telefonda anlamli; masaustunde kamera yok, dosya
/// secici acilir.
Future<Uint8List?> pickImageBytes({bool fromCamera = false}) async {
  if (usesFileSelector(defaultTargetPlatform, isWeb: kIsWeb)) {
    final file = await openFile(acceptedTypeGroups: const [_imageTypes]);
    return file == null ? null : await file.readAsBytes();
  }
  final picked = await ImagePicker().pickImage(
    // Telefonda galeri arayuzu daha tanidik; fis icin kamera da gerekiyor.
    source: fromCamera ? ImageSource.camera : ImageSource.gallery,
  );
  return picked == null ? null : await picked.readAsBytes();
}

/// Masaustunde kamera yok; arayuz "Fotoğraf Çek" dugmesini gizler.
bool cameraAvailable() => !usesFileSelector(defaultTargetPlatform, isWeb: kIsWeb);
