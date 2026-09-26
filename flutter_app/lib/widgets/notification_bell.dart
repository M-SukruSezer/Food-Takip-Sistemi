import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/push.dart';
import '../core/repository.dart';
import '../core/tokens.dart';

/// Ust cubuktaki bildirim zili ve listesi.
///
/// Zil rozeti [okunmamis] degerini dinliyor; sayiyi yoklayici (PushPoller)
/// guncelliyor. Boylece zil kendi basina istek atmiyor, yoklayicinin
/// zaten yaptigi istegin sonucunu kullaniyor.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, required this.okunmamis});

  final ValueListenable<int> okunmamis;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ValueListenableBuilder<int>(
      valueListenable: okunmamis,
      builder: (context, adet, _) => IconButton(
        tooltip: adet > 0 ? '$adet okunmamış bildirim' : 'Bildirimler',
        onPressed: () => showNotificationSheet(context),
        style: IconButton.styleFrom(
          minimumSize: const Size(AppTokens.tap, AppTokens.tap),
        ),
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.notifications_none, color: t.ink),
            if (adet > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: t.danger,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  constraints: const BoxConstraints(minWidth: 16),
                  child: Text(
                    adet > 99 ? '99+' : '$adet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: t.onPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bildirim listesini alttan acilan panelde gosterir.
Future<void> showNotificationSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _NotificationSheet(),
  );
}

class _NotificationSheet extends StatefulWidget {
  const _NotificationSheet();

  @override
  State<_NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<_NotificationSheet> {
  NotificationList? _veri;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final v = await repo.pdksNotifications(limit: 50);
      if (mounted) setState(() => _veri = v);
    } catch (e) {
      if (mounted) setState(() => _hata = 'Bildirimler yüklenemedi');
    }
  }

  Future<void> _tumunuOku() async {
    await repo.pdksMarkAllNotificationsRead();
    await _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = _veri;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Bildirimler',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: t.ink,
                      ),
                    ),
                  ),
                  if (v != null && v.unread > 0)
                    TextButton(
                      onPressed: _tumunuOku,
                      child: const Text('Tümünü okundu işaretle'),
                    ),
                ],
              ),
            ),
            if (_hata != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_hata!, style: TextStyle(color: t.danger)),
              )
            else if (v == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (v.items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Henüz bildiriminiz yok.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.muted),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: v.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final n = v.items[i];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        // Okunmamis olan vurgulu: listede hangisinin yeni
                        // oldugu bir bakista gorunmeli.
                        color: n.read ? t.card : t.primarySoft,
                        border: Border.all(
                          color: n.read ? t.border : t.primary600,
                        ),
                        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: t.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            n.body,
                            style: TextStyle(fontSize: 13, color: t.ink),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            fmtDateTime(n.createdAt),
                            style: TextStyle(fontSize: 11, color: t.muted),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
