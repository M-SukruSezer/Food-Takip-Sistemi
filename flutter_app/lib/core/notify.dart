import 'package:flutter/material.dart';

import 'tokens.dart';

/// Bildirimler API katmanindan da tetiklendigi icin (widget agaci disi)
/// global bir messenger anahtari kullanilir. React tarafindaki ToastHost'un
/// karsiligi.
final messengerKey = GlobalKey<ScaffoldMessengerState>();

enum ToastKind { info, success, warning, error }

void toast(String message, {ToastKind kind = ToastKind.info}) {
  final messenger = messengerKey.currentState;
  if (messenger == null) return;
  final background = switch (kind) {
    ToastKind.success => ToastColors.success,
    ToastKind.warning => ToastColors.warning,
    ToastKind.error => messenger.context.tokens.dangerStrong,
    ToastKind.info => ToastColors.info,
  };
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        // Uyari daha uzun durur: engellenmeyen ama okunmasi gereken bir not.
        duration: Duration(seconds: kind == ToastKind.warning ? 6 : 3),
      ),
    );
}

/// Pencere kapandiktan sonra basari bildirimi. Pencere icindeki cagrilar
/// noToast oldugu icin bildirimi ekran verir.
void toastSaved(String message) => toast(message, kind: ToastKind.success);

/// Hata bildirimi: kirmizi arka plan, 4 saniye gorunur.
void toastError(String message) => toast(message, kind: ToastKind.error);
