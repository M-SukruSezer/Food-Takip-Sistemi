import 'package:flutter/material.dart';

/// Bildirimler API katmanindan da tetiklendigi icin (widget agaci disi)
/// global bir messenger anahtari kullanilir. React tarafindaki ToastHost'un
/// karsiligi.
final messengerKey = GlobalKey<ScaffoldMessengerState>();

enum ToastKind { info, success, error }

void toast(String message, {ToastKind kind = ToastKind.info}) {
  final messenger = messengerKey.currentState;
  if (messenger == null) return;
  final scheme = Theme.of(messenger.context).colorScheme;
  final background = switch (kind) {
    ToastKind.success => const Color(0xFF166534),
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
        duration: const Duration(seconds: 3),
      ),
    );
}

/// Pencere kapandiktan sonra basari bildirimi. Pencere icindeki cagrilar
/// noToast oldugu icin bildirimi ekran verir.
void toastSaved(String message) => toast(message, kind: ToastKind.success);
