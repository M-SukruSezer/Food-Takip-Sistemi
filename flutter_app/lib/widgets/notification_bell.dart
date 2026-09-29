import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/push.dart';
import '../core/repository.dart';
import '../core/tokens.dart';
import 'mobile_sheet.dart';

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
  await showAppSheet<void>(
    context: context,
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
  bool _marking = false;
  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final v = await repo.pdksNotifications(limit: 50);
      if (mounted) {
        setState(() {
          _veri = v;
          _hata = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _hata = 'Bildirimler yüklenemedi');
    }
  }

  Future<void> _tumunuOku() async {
    setState(() => _marking = true);
    try {
      await repo.pdksMarkAllNotificationsRead();
      await _yukle();
    } catch (_) {
      if (mounted) {
        setState(() => _hata = 'Bildirimler güncellenemedi. Tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = _veri;
    return Material(
      color: t.card,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SizedBox(
          width: double.infinity,
          height: MediaQuery.sizeOf(context).height * .8,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                  child: Wrap(
                    alignment: WrapAlignment.start,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Bildirimler',
                            style: TextStyle(
                              color: t.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                            ),
                          ),
                          if (v != null && v.unread > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: t.primarySoft,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: t.primary.withValues(alpha: .25),
                                ),
                              ),
                              child: Text(
                                '${v.unread} Yeni',
                                style: TextStyle(
                                  color: t.primary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (v != null && v.unread > 0)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 44),
                          ),
                          onPressed: _marking ? null : _tumunuOku,
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(
                            _marking
                                ? 'İşaretleniyor...'
                                : 'Tümünü okundu işaretle',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: t.border.withValues(alpha: .5)),
                if (_hata != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(_hata!, style: TextStyle(color: t.danger)),
                        TextButton(
                          onPressed: _yukle,
                          child: const Text('Tekrar dene'),
                        ),
                      ],
                    ),
                  ),
                if (v == null && _hata == null)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (v != null && v.items.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        'Henüz bildiriminiz yok.',
                        style: TextStyle(color: t.muted),
                      ),
                    ),
                  )
                else if (v != null)
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: v.items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final n = v.items[i];
                        final actor = RegExp(r' (Paylaşan|Değiştiren): (.+)$')
                            .firstMatch(n.body);
                        final body = actor == null
                            ? n.body
                            : n.body.substring(0, actor.start);
                        final icon = n.title.contains('paylaşıldı')
                            ? Icons.calendar_today_outlined
                            : n.title.contains('güncellendi')
                            ? Icons.sync
                            : Icons.schedule;
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: n.read
                                ? t.card
                                : t.primarySoft.withValues(alpha: .4),
                            border: Border.all(
                              color: n.read
                                  ? t.border
                                  : const Color(0xFF2AC69B),
                              width: n.read ? 1 : 1.5,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: n.read
                                      ? t.bg
                                      : const Color(0xFF059669),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  icon,
                                  size: 23,
                                  color: n.read ? t.muted : Colors.white,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            n.title,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: t.ink,
                                            ),
                                          ),
                                        ),
                                        if (!n.read)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 6,
                                              top: 4,
                                            ),
                                            child: Icon(
                                              Icons.circle,
                                              size: 8,
                                              color: t.primary,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      body,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.45,
                                        color: n.read ? t.muted : t.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Divider(
                                      height: 1,
                                      color: t.border.withValues(alpha: .6),
                                    ),
                                    const SizedBox(height: 10),
                                    if (actor != null)
                                      Text(
                                        actor
                                            .group(0)!
                                            .trim()
                                            .replaceFirst(RegExp(r'\.$'), ''),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: t.ink,
                                        ),
                                      ),
                                    const SizedBox(height: 3),
                                    Text(
                                      fmtDateTime(n.createdAt),
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: n.read
                                            ? FontWeight.w400
                                            : FontWeight.w700,
                                        color: n.read ? t.muted : t.primaryDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
