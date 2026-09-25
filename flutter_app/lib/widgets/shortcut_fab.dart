import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/nav.dart';
import '../core/notify.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/dashboard.dart';
import '../screens/batch_dialogs.dart';
import '../screens/daily_report_dialogs.dart';
import '../screens/petty_cash_dialogs.dart';
import 'scrim.dart';

/// Kisayol tanimi. Rol listesi bos kalirsa dugme hic cizilmez.
class _Shortcut {
  const _Shortcut({
    required this.label,
    required this.icon,
    required this.roles,
    required this.run,
  });

  final String label;
  final IconData icon;
  final List<String> roles;

  /// Kisayolun isi. Bir sey degistiyse true doner, cagiran ekrani yeniler.
  final Future<bool> Function(BuildContext context) run;
}

// Masraf girisi yalnizca magaza kasasini kullanan iki rolde (sunucudaki
// SPENDER_ROLES ile ayni). Ust kademeler modulu gorur ama giris yapmaz.
const _spenderRoles = ['store_manager', 'shift_supervisor'];

final _shortcuts = <_Shortcut>[
  _Shortcut(
    label: 'Donuk Depoya Ürün Ekle',
    icon: Icons.ac_unit,
    roles: allRoles,
    run: (context) async {
      // Cesit ve magaza listesi olmadan form kurulamaz; yukleme katmani
      // gorunurken cekilir.
      final types = await repo.productTypes();
      final stores = (session.user?.isSuperAdmin ?? false)
          ? await repo.stores(silent: true)
          : const <StoreOption>[];
      if (!context.mounted) return false;
      if (types.isEmpty) {
        toast('Önce pasta çeşidi tanımlanmalı', kind: ToastKind.error);
        return false;
      }
      final ok = await showAddBatchDialog(
        context,
        types: types,
        stores: stores,
      );
      return ok == true;
    },
  ),
  _Shortcut(
    label: 'Masraf Gir',
    icon: Icons.receipt_long_outlined,
    roles: _spenderRoles,
    run: (context) async {
      // Limit durumu forma gecirilir ki kalan tutar uyarisi calissin.
      final page = await repo.pettyCash(silent: true);
      if (!context.mounted) return false;
      final ok = await showExpenseDialog(context, status: page.status);
      return ok == true;
    },
  ),
  _Shortcut(
    label: 'Günlük Rapor Gir',
    icon: Icons.assessment_outlined,
    roles: reportPanelRoles,
    run: (context) async {
      final fields = await repo.reportFields(silent: true);
      if (!context.mounted) return false;
      if (fields.entry.isEmpty) return false;
      final ok = await showDailyReportDialog(context, fields: fields);
      return ok == true;
    },
  ),
  _Shortcut(
    label: 'Onaylar',
    icon: Icons.fact_check_outlined,
    roles: managerRoles,
    run: (context) async {
      context.go('/approvals');
      return false;
    },
  ),
];

List<_Shortcut> _shortcutsFor(String? role) => role == null
    ? const []
    : _shortcuts.where((s) => s.roles.contains(role)).toList();

/// Kullanicinin rolunde hic kisayol var mi? Yoksa dugme cizilmez.
bool hasShortcuts(String? role) => _shortcutsFor(role).isNotEmpty;

/// Sag altta duran kisayol dugmesi.
///
/// Dokununca tam ekran perde acilir ve kisayollar dugmenin uzerinde listelenir.
/// Perde yukleme katmaniyla ayni gorunumu paylasiyor ([AppScrim]).
class ShortcutFab extends StatefulWidget {
  const ShortcutFab({super.key, this.bottomInset = 0});

  /// Alt cubugun yuksekligi. Menu ogeleri cubugun uzerinde kalmali.
  final double bottomInset;

  @override
  State<ShortcutFab> createState() => _ShortcutFabState();
}

class _ShortcutFabState extends State<ShortcutFab> {
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final items = _shortcutsFor(session.user?.role);
    if (items.isEmpty) return const SizedBox.shrink();

    // Menu acikken dugme cizilmiyor. Gorunum sebebi degil, olculen sebep:
    // dokunma dalgasi (ink splash) ~450ms animasyon yapiyor ve bulantinin
    // ARKASINDA kaldigi icin her karede tam ekran bulantiyi yeniden
    // hesaplatiyordu. Web tarafi da acikken dugmeyi gizliyor.
    if (_menuOpen) return const SizedBox.shrink();

    return FloatingActionButton(
      onPressed: () async {
        setState(() => _menuOpen = true);
        try {
          await _open(context, items, widget.bottomInset);
        } finally {
          if (mounted) setState(() => _menuOpen = false);
        }
      },
      backgroundColor: t.primary,
      foregroundColor: t.card,
      tooltip: 'Kısayollar',
      child: const Icon(Icons.bolt),
    );
  }
}

Future<void> _open(
  BuildContext context,
  List<_Shortcut> items,
  double bottomInset,
) async {
  final picked = await showGeneralDialog<_Shortcut>(
    context: context,
    // Perdeyi kendimiz ciziyoruz; hazir bariyer kapatilir.
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    barrierLabel: 'Kısayolları kapat',
    // Olculen: 180ms'de son oge yerine oturuyordu ama kareler 640ms devam
    // ediyordu. Sure kisaltildi; asil kazanc bulantiyi animasyon disina
    // cikarmak (asagida).
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (ctx, a1, a2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, _) =>
        _ShortcutSheet(items: items, bottomInset: bottomInset, animation: anim),
  );
  if (picked == null || !context.mounted) return;
  try {
    await picked.run(context);
  } catch (_) {
    // Bildirim API katmanindan gelir.
  }
}

class _ShortcutSheet extends StatelessWidget {
  const _ShortcutSheet({
    required this.items,
    required this.bottomInset,
    required this.animation,
  });

  final List<_Shortcut> items;
  final double bottomInset;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Material(
      type: MaterialType.transparency,
      // Perde animasyonun DISINDA: BackdropFilter fade icinde oldugunda tam
      // ekran bulanti her karede yeniden hesaplaniyor (saveLayer) ve menu
      // oturduktan sonra bile kareler devam ediyordu. Yukleme katmani da
      // solmadan beliriyor; gorunum tutarli kaliyor.
      child: AppScrim(
        absorb: false,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          behavior: HitTestBehavior.opaque,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(right: 16, bottom: bottomInset + 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      // Basamakli giris ayni 120ms penceresinin ICINDE kaliyor:
                      // Interval ile kaydirildigi icin toplam sure uzamiyor.
                      child: _Entry(
                        animation: animation,
                        index: i,
                        count: items.length,
                        child: _ShortcutTile(
                          item: items[i],
                          onTap: () => Navigator.pop(context, items[i]),
                        ),
                      ),
                    ),
                  // Kapatma dugmesi acan dugmenin yerinde duruyor.
                  FloatingActionButton(
                    onPressed: () => Navigator.pop(context),
                    backgroundColor: t.card,
                    foregroundColor: t.ink,
                    tooltip: 'Kapat',
                    child: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tek ogenin girisi: kisa bir kaydirma ve solma.
///
/// Basamak, sureyi uzatmamak icin [Interval] ile ayni pencere icinde veriliyor.
/// Repaint siniri, oge boyanirken perdenin yeniden boyanmasini engelliyor.
class _Entry extends StatelessWidget {
  const _Entry({
    required this.animation,
    required this.index,
    required this.count,
    required this.child,
  });

  final Animation<double> animation;
  final int index;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Alttaki oge ilk girer; en ustteki en son. Pencerenin ilk yarisi
    // basamaklara ayrilir, kalan yarisi harekete.
    final step = count <= 1 ? 0.0 : (count - 1 - index) / count * 0.5;
    final curve = CurvedAnimation(
      parent: animation,
      curve: Interval(step, 1, curve: Curves.easeOutCubic),
    );
    return RepaintBoundary(
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.35),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({required this.item, required this.onTap});

  final _Shortcut item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Etiket perdenin uzerinde okunabilsin diye kart zemininde duruyor.
        Material(
          color: t.card,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 48,
          height: 48,
          child: Material(
            color: t.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(child: Icon(item.icon, size: 22, color: t.card)),
            ),
          ),
        ),
      ],
    );
  }
}
