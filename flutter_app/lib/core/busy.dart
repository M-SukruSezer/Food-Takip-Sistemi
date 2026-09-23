import 'dart:async';
import 'package:flutter/foundation.dart';

/// Acik istek sayaci — React tarafindaki busy.js ile ayni davranis.
/// API katmani her istekte artirir, bittiginde azaltir; sifira dusunce
/// yukleme katmani kapanir.
class BusyState extends ChangeNotifier {
  static const defaultMessage = 'Yükleniyor...';

  int _count = 0;
  Timer? _hideTimer;
  bool _visible = false;
  String? _message;

  bool get visible => _visible;

  /// Katmanda yazan metin. Istek kendi metnini vermediyse genel metin kullanilir.
  String get message => _message ?? defaultMessage;

  void begin({String? message}) {
    _count += 1;
    if (message != null) _message = message;
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!_visible || message != null) {
      _visible = true;
      notifyListeners();
    }
  }

  void end() {
    _count = _count > 0 ? _count - 1 : 0;
    if (_count != 0) return;
    // Zincirlenen istekler arasinda katmanin bir anlik kapanip tekrar acilmasi
    // goz tirmaliyor; kisa gecikme ikisini tek katman gibi gosterir.
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 180), () {
      _hideTimer = null;
      _visible = false;
      // Sonraki istek kendi metnini vermezse genel metne donulsun.
      _message = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }
}

/// API katmani bir widget agaci icinde olmadigi icin tek ortak ornek kullanilir.
final busy = BusyState();
