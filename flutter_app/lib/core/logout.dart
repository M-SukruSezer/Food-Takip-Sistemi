import 'package:flutter/material.dart';

import 'session.dart';
import '../widgets/mobile_sheet.dart';
import 'tokens.dart';

/// Oturumu kapatmadan once onay ister. Uygulamada cikis iki yerden
/// yapilabiliyor (ust bar ve Profil); ikisi de buradan gecer ki uyari metni
/// ve davranis ayni olsun.
Future<void> confirmSignOut(BuildContext context) async {
  final name = session.user?.fullName;
  final t = context.tokens;
  final ok = await showAppSheet<bool>(
    context: context,
    builder: (ctx) => Center(
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        backgroundColor: t.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Çıkış Yap',
                  style: TextStyle(
                    color: t.ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 22),
                Text.rich(
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
                  style: TextStyle(color: t.ink, fontSize: 16, height: 1.6),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: t.bg,
                          foregroundColor: t.ink,
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFC93629),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Çıkış Yap'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  if (ok == true) await session.signOut();
}
