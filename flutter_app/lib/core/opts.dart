import 'package:dio/dio.dart';

/// Istek bazinda katman/bildirim davranisini ayarlar.
Options apiOptions({
  bool silent = false,
  bool noToast = false,
  String? successMessage,
  String? busyMessage,
}) {
  final extra = <String, dynamic>{};
  if (silent) extra['silent'] = true;
  if (noToast) extra['noToast'] = true;
  if (successMessage != null) extra['successMessage'] = successMessage;
  // Yukleme katmaninda genel "Yükleniyor..." yerine yazilacak metin.
  if (busyMessage != null) extra['busyMessage'] = busyMessage;
  return Options(extra: extra);
}
