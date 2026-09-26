import 'package:flutter/material.dart';

/// Bildirimler API katmanindan da tetiklendigi icin (widget agaci disi)
/// global bir messenger anahtari kullanilir. React tarafindaki ToastHost'un
/// karsiligi.
final messengerKey = GlobalKey<ScaffoldMessengerState>();

enum ToastKind { info, success, warning, error }

void toast(String message, {ToastKind kind = ToastKind.info}) {
  final messenger = messengerKey.currentState;
  if (messenger == null) return;
  final scheme = Theme.of(messenger.context).colorScheme;
  final background = switch (kind) {
    ToastKind.success => const Color(0xFF166534),
    // Amber 800: beyaz yazi ile 7.09 kontrast (olculdu; AA siniri 4.5).
    // Daha acik amber tonlari bu esigin altina duser.
    ToastKind.warning => const Color(0xFF92400E),
    ToastKind.error => scheme.error,
    ToastKind.info => const Color(0xFF111827),
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
