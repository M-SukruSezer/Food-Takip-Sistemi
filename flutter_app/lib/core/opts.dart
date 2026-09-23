import 'package:dio/dio.dart';

/// Istek bazinda katman/bildirim davranisini ayarlar.
Options apiOptions({bool silent = false, bool noToast = false, String? successMessage}) {
  final extra = <String, dynamic>{};
  if (silent) extra['silent'] = true;
  if (noToast) extra['noToast'] = true;
  if (successMessage != null) extra['successMessage'] = successMessage;
  return Options(extra: extra);
}
