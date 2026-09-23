import 'dart:async';
import 'package:flutter/foundation.dart';

/// Acik istek sayaci — React tarafindaki busy.js ile ayni davranis.
/// API katmani her istekte artirir, bittiginde azaltir; sifira dusunce
/// yukleme katmani kapanir.
class BusyState extends ChangeNotifier {
  int _count = 0;
  Timer? _hideTimer;
  bool _visible = false;

  bool get visible => _visible;

  void begin() {
    _count += 1;
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!_visible) {
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
