import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'busy.dart';
import 'notify.dart';

/// Derleme sirasinda --dart-define=API_URL=... ile degistirilebilir.
const apiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://food-takip-sistemi.vercel.app/api',
);

const _tokenKey = 'token';

/// Istek bazinda ayarlar (Options.extra):
///   silent: true          -> katman ve bildirim yok (arka plan yenilemeleri)
///   noToast: true         -> katman var, bildirim yok (hatayi kendi gosteren ekranlar)
///   successMessage: '...' -> basari bildiriminde genel metin yerine bu kullanilir
class ApiClient {
  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      // Sunucu hata gövdesini kendimiz okuyabilmek icin durum kodunu birakiyoruz.
      validateStatus: (status) => status != null && status < 400,
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onResponse: _onResponse,
      onError: _onError,
    ));
  }

  late final Dio _dio;
  String? _token;

  /// 401 alindiginda oturumu dusurmek icin uygulama tarafindan atanir.
  void Function()? onUnauthorized;

  Dio get dio => _dio;
  String? get token => _token;

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
  }

  Future<void> setToken(String? value) async {
    _token = value;
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, value);
    }
  }

  bool _flag(RequestOptions options, String key) => options.extra[key] == true;

  bool _isMutation(RequestOptions options) {
    final m = options.method.toUpperCase();
    return m == 'POST' || m == 'PUT' || m == 'PATCH' || m == 'DELETE';
  }

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_token != null) {
      options.headers['Authorization'] = 'Bearer $_token';
    }
    if (!_flag(options, 'silent')) {
      options.extra['__busy'] = true;
      busy.begin();
    }
    handler.next(options);
  }

  void _onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    if (options.extra['__busy'] == true) busy.end();
    // Veri okumalarinda basari bildirimi verilmez; her ekran acilisinda
    // bildirim cikmasi gurultu olurdu. Yazma islemlerinde verilir.
    if (!_flag(options, 'silent') && !_flag(options, 'noToast') && _isMutation(options)) {
      final message = options.extra['successMessage'] as String?;
      toast(message ?? 'İşlem başarılı', kind: ToastKind.success);
    }
    handler.next(response);
  }

  void _onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    if (options.extra['__busy'] == true) busy.end();

    final unauthorized = err.response?.statusCode == 401;
    if (!_flag(options, 'silent') && !_flag(options, 'noToast')) {
      toast(errorMessage(err), kind: ToastKind.error);
    }
    if (unauthorized) onUnauthorized?.call();
    handler.next(err);
  }
}

/// Sunucu {"error": "..."} doner; onu kullaniciya gosterilecek metne cevirir.
String errorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return 'Sunucuya ulaşılamıyor. Bağlantınızı kontrol edin.';
    }
  }
  return 'Bir hata oluştu';
}

final api = ApiClient();
