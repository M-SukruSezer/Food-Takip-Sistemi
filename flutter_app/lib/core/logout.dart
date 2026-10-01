import 'package:flutter/material.dart';

import 'session.dart';
import '../widgets/dialogs.dart';

/// Oturumu kapatmadan once onay ister. Uygulamada cikis iki yerden
/// yapilabiliyor (ust bar ve Profil); ikisi de buradan gecer ki uyari metni
/// ve davranis ayni olsun.
Future<void> confirmSignOut(BuildContext context) async {
  final name = session.user?.fullName;
  final ok = await confirmDialog(
    context,
    title: 'Çıkış Yap',
    icon: Icons.logout_rounded,
    confirmLabel: 'Çıkış Yap',
    body: Text.rich(
      TextSpan(
        children: [
          if (name != null)
            TextSpan(
              text: name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          TextSpan(
            text: name == null
                ? 'Oturumunuz kapatılacak. Devam etmek istiyor musunuz?'
                : ' oturumu kapatılacak. Devam etmek istiyor musunuz?',
          ),
        ],
      ),
    ),
  );
  if (ok == true) await session.signOut();
}
