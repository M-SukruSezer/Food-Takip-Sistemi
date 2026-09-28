import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/new_theme.dart';
import '../models/activity_log.dart';

IconData logIcon(String action) {
  const map = {
    'GIRIS': Icons.vpn_key_outlined,
    'MAGAZA_OLUSTUR': Icons.store_outlined,
    'MAGAZA_GUNCELLE': Icons.store_outlined,
    'MAGAZA_SIL': Icons.store_outlined,
    'KULLANICI_OLUSTUR': Icons.person_outline,
    'KULLANICI_GUNCELLE': Icons.person_outline,
    'KULLANICI_SIL': Icons.person_outline,
    'SIFRE_SIFIRLA': Icons.lock_outline,
    'SIFRE_DEGISTIR': Icons.lock_outline,
    'CESIT_OLUSTUR': Icons.cake_outlined,
    'CESIT_GUNCELLE': Icons.cake_outlined,
    'CESIT_SIL': Icons.cake_outlined,
    'DONUK_EKLE': Icons.ac_unit,
    'COZULME_BASLA': Icons.hourglass_bottom,
    'FOOD_DOLABI': Icons.kitchen_outlined,
    'FOOD_DOLABI_OTOMATIK': Icons.kitchen_outlined,
    'SATIS': Icons.payments_outlined,
    'IMHA': Icons.delete_outline,
    'STOK_EKLE': Icons.add_box_outlined,
    'PARTI_DUZELT': Icons.edit_calendar_outlined,
    'COZULME_DUZELT': Icons.undo,
    'SATIS_DUZELT': Icons.edit_outlined,
    'SATIS_SIL': Icons.delete_forever_outlined,
    'ZAYI_DUZELT': Icons.edit_outlined,
    'ZAYI_SIL': Icons.delete_forever_outlined,
    'PARTI_SIL': Icons.delete_forever_outlined,
    'TRANSFER_ISTEK': Icons.fact_check_outlined,
    'TRANSFER_ONAY': Icons.check_circle_outline,
    'TRANSFER_RET': Icons.cancel_outlined,
    'TRANSFER_IPTAL': Icons.cancel_outlined,
  };
  return map[action] ?? Icons.receipt_long_outlined;
}

Color getIconBgColor(String action) {
  if (action == 'GIRIS') return NewTokens.secondaryFixed;
  if (action.contains('RAPOR_SIL') || action.contains('SIL')) return NewTokens.errorContainer;
  if (action.contains('RAPOR') || action.contains('SATIS')) return NewTokens.secondaryContainer;
  return NewTokens.surfaceContainerHigh;
}

Color getIconColor(String action) {
  if (action == 'GIRIS') return NewTokens.onSecondaryFixedVariant;
  if (action.contains('RAPOR_SIL') || action.contains('SIL')) return NewTokens.error;
  if (action.contains('RAPOR') || action.contains('SATIS')) return NewTokens.secondary;
  return NewTokens.primary;
}

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  List<ActivityLog> _items = const [];
  String? _filter;
  String? _error;
  bool _loaded = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final items = await repo.logs(silent: silent);
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(e);
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuper = session.user?.isSuperAdmin ?? false;
    final actions = _items.map((l) => l.action).toSet().toList()..sort();
    
    var shown = _items;
    if (_filter != null) {
      shown = shown.where((l) => l.action == _filter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      shown = shown.where((l) => 
        l.action.toLowerCase().contains(q) || 
        (l.details?.toLowerCase().contains(q) ?? false) ||
        (l.username?.toLowerCase().contains(q) ?? false)
      ).toList();
    }

    final todayCount = _items.where((l) => l.createdAt.year == DateTime.now().year && l.createdAt.month == DateTime.now().month && l.createdAt.day == DateTime.now().day).length;

    return Scaffold(
      backgroundColor: NewTokens.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Custom Header matching HTML
            Container(
              height: 80,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                color: NewTokens.surface, 
                boxShadow: [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.03),
                    offset: Offset(0, 1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: NewTokens.tertiaryContainer,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Düzce Merkez Şube',
                              style: NewTokens.labelSm.copyWith(
                                color: NewTokens.primary,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        Text(
                          'Ana Sayfa',
                          style: NewTokens.headlineSm.copyWith(
                            color: NewTokens.onSurface,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${session.user?.name ?? "Muhammed Ş. Sezer"} · Mağaza Müdürü',
                          style: NewTokens.labelSm.copyWith(
                            color: NewTokens.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Stack(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.notifications, color: NewTokens.onSurfaceVariant),
                            onPressed: () {},
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: NewTokens.error,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              child: Center(
                                child: Text(
                                  '7',
                                  style: NewTokens.labelSm.copyWith(
                                    color: NewTokens.onError,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.power_settings_new, color: NewTokens.onSurfaceVariant),
                        onPressed: () {},
                      ),
                      Container(
                        width: 32,
                        height: 32,
                        margin: const EdgeInsets.only(left: 4),
                        decoration: const BoxDecoration(
                          color: NewTokens.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person, color: NewTokens.onPrimary, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: !_loaded 
                  ? const Center(child: CircularProgressIndicator(color: NewTokens.primary))
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: NewTokens.error)))
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 96),
                          children: [
                            // Top Title Context & Global Actions Strip
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  width: 6,
                                                  height: 6,
                                                  decoration: const BoxDecoration(
                                                    color: NewTokens.primary,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'DENETİM & GÜVENLİK',
                                                  style: NewTokens.labelSm.copyWith(
                                                    color: NewTokens.primary,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Text(
                                              'Hareket Kayıtları',
                                              style: NewTokens.headlineMd.copyWith(
                                                color: NewTokens.onSurface,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              'Sistem içi operasyonel hareketler, vardiya ve denetim logları',
                                              style: NewTokens.bodySm.copyWith(
                                                color: NewTokens.onSurfaceVariant,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Container(
                                            height: 36,
                                            padding: const EdgeInsets.symmetric(horizontal: 12),
                                            decoration: BoxDecoration(
                                              color: NewTokens.surfaceContainerHigh,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.tune, size: 18, color: NewTokens.primary),
                                                const SizedBox(width: 6),
                                                Text('Filtre', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurface, fontWeight: FontWeight.w600)),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            height: 36,
                                            padding: const EdgeInsets.symmetric(horizontal: 12),
                                            decoration: BoxDecoration(
                                              color: NewTokens.surfaceContainer,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.download, size: 18, color: NewTokens.onSecondaryContainer),
                                                const SizedBox(width: 6),
                                                Text('CSV', style: NewTokens.labelMd.copyWith(color: NewTokens.onSecondaryContainer, fontWeight: FontWeight.w600)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Quick Audit Stats Summary Row
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: NewTokens.surfaceContainerLowest,
                                            borderRadius: BorderRadius.circular(12),
                                            boxShadow: const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.04), blurRadius: 3, offset: Offset(0, 1))],
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text('TOPLAM', style: NewTokens.labelSm.copyWith(fontSize: 10, color: NewTokens.onSurfaceVariant)),
                                                  const Icon(Icons.database, size: 16, color: NewTokens.primary),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text('${_items.length}', style: NewTokens.numericMetric.copyWith(fontSize: 18, color: NewTokens.onSurface)),
                                              Text('Sistem Logu', style: NewTokens.labelSm.copyWith(fontSize: 10, color: NewTokens.onSurfaceVariant)),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: NewTokens.surfaceContainerLowest,
                                            borderRadius: BorderRadius.circular(12),
                                            boxShadow: const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.04), blurRadius: 3, offset: Offset(0, 1))],
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text('BUGÜN', style: NewTokens.labelSm.copyWith(fontSize: 10, color: NewTokens.onSurfaceVariant)),
                                                  const Icon(Icons.today, size: 16, color: NewTokens.tertiary),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text('$todayCount İşlem', style: NewTokens.numericMetric.copyWith(fontSize: 18, color: NewTokens.tertiary)),
                                              Text('Merkez Şube', style: NewTokens.labelSm.copyWith(fontSize: 10, color: NewTokens.onSurfaceVariant)),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: NewTokens.surfaceContainerLowest,
                                            borderRadius: BorderRadius.circular(12),
                                            boxShadow: const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.04), blurRadius: 3, offset: Offset(0, 1))],
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text('EŞİTLEME', style: NewTokens.labelSm.copyWith(fontSize: 10, color: NewTokens.onSurfaceVariant)),
                                                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: NewTokens.tertiary, shape: BoxShape.circle)),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text('Canlı', style: NewTokens.numericMetric.copyWith(fontSize: 15, color: NewTokens.onSurface)),
                                              Text('04:37 Senkron', style: NewTokens.labelSm.copyWith(fontSize: 10, color: NewTokens.onSurfaceVariant)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Search & Primary Filter Bar
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Column(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      showModalBottomSheet(
                                        context: context,
                                        backgroundColor: NewTokens.surfaceContainerLowest,
                                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                                        builder: (ctx) {
                                          return SafeArea(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ListTile(
                                                  title: Text('Tüm İşlemler (${_items.length})', style: NewTokens.labelMd.copyWith(color: _filter == null ? NewTokens.primary : NewTokens.onSurface)),
                                                  trailing: _filter == null ? const Icon(Icons.check, color: NewTokens.primary) : null,
                                                  onTap: () {
                                                    setState(() => _filter = null);
                                                    Navigator.pop(ctx);
                                                  },
                                                ),
                                                ...actions.map((a) {
                                                  final count = _items.where((l) => l.action == a).length;
                                                  return ListTile(
                                                    title: Text('$a ($count)', style: NewTokens.labelMd.copyWith(color: _filter == a ? NewTokens.primary : NewTokens.onSurface)),
                                                    trailing: _filter == a ? const Icon(Icons.check, color: NewTokens.primary) : null,
                                                    onTap: () {
                                                      setState(() => _filter = a);
                                                      Navigator.pop(ctx);
                                                    },
                                                  );
                                                }),
                                              ],
                                            ),
                                          );
                                        },
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: NewTokens.surfaceContainerLowest,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.05), blurRadius: 3, offset: Offset(0, 1))],
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('İŞLEM TÜRÜ', style: NewTokens.labelSm.copyWith(fontSize: 10, color: NewTokens.onSurfaceVariant)),
                                              const SizedBox(height: 4),
                                              Text(_filter ?? 'Tüm İşlemler (${_items.length})', style: NewTokens.headlineSm.copyWith(fontSize: 15, color: NewTokens.onSurface)),
                                            ],
                                          ),
                                          const Icon(Icons.expand_more, color: NewTokens.onSurfaceVariant),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          height: 40,
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          decoration: BoxDecoration(
                                            color: NewTokens.surfaceContainerLowest,
                                            borderRadius: BorderRadius.circular(12),
                                            boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.03), blurRadius: 2, offset: Offset(0, 1))],
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.search, size: 18, color: NewTokens.onSurfaceVariant),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: TextField(
                                                  onChanged: (val) => setState(() => _searchQuery = val),
                                                  style: NewTokens.bodySm.copyWith(color: NewTokens.onSurface),
                                                  decoration: InputDecoration(
                                                    hintText: 'Kayıt veya personel ara...',
                                                    hintStyle: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant),
                                                    border: InputBorder.none,
                                                    isDense: true,
                                                    contentPadding: EdgeInsets.zero,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        height: 40,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: NewTokens.surfaceContainerLowest,
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.03), blurRadius: 2, offset: Offset(0, 1))],
                                        ),
                                        child: Text('Bugün', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        height: 40,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: NewTokens.surfaceContainerLowest,
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.03), blurRadius: 2, offset: Offset(0, 1))],
                                        ),
                                        child: Text('7 Gün', style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Log Items
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Column(
                                children: shown.map((log) {
                                  final iconBg = getIconBgColor(log.action);
                                  final iconFg = getIconColor(log.action);

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: NewTokens.surfaceContainerLowest,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.04), blurRadius: 3, offset: Offset(0, 1))],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 28,
                                                    height: 28,
                                                    decoration: BoxDecoration(
                                                      color: iconBg,
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Icon(logIcon(log.action), size: 18, color: iconFg),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      log.action,
                                                      style: NewTokens.labelLg.copyWith(fontSize: 13, color: NewTokens.onSurface),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: iconBg,
                                                borderRadius: BorderRadius.circular(999),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (log.action.contains('SIL') || log.action == 'GIRIS')
                                                    Container(
                                                      width: 6,
                                                      height: 6,
                                                      margin: const EdgeInsets.only(right: 4),
                                                      decoration: BoxDecoration(
                                                        color: iconFg,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                  Text(
                                                    log.action.contains('VARDIYA') ? 'Vardiya' : (log.action == 'GIRIS' ? 'Güvenlik' : 'İşlem'),
                                                    style: NewTokens.labelSm.copyWith(fontSize: 10, color: iconFg),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Padding(
                                          padding: const EdgeInsets.only(left: 36, right: 4),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                log.details ?? '-',
                                                style: NewTokens.bodyMd.copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: NewTokens.onSurface),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  const Icon(Icons.schedule, size: 13, color: NewTokens.onSurfaceVariant),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    fmtDateTime(log.createdAt),
                                                    style: NewTokens.labelSm.copyWith(fontSize: 11, color: NewTokens.onSurfaceVariant),
                                                  ),
                                                  Text(' · ', style: NewTokens.labelSm.copyWith(fontSize: 11, color: NewTokens.onSurfaceVariant)),
                                                  Expanded(
                                                    child: Text(
                                                      log.username ?? 'sistem',
                                                      style: NewTokens.labelSm.copyWith(fontSize: 11, color: NewTokens.primary),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            // Load More Action Strip
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: 48,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: NewTokens.surfaceContainerLowest,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: const [BoxShadow(color: Color.fromRGBO(15, 23, 42, 0.05), blurRadius: 3, offset: Offset(0, 1))],
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.sync, size: 20, color: NewTokens.primary),
                                        const SizedBox(width: 8),
                                        Text('Daha Fazla Kayıt Yükle', style: NewTokens.labelMd.copyWith(color: NewTokens.primary)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.lock, size: 14, color: NewTokens.tertiary),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          'KVKK & Operasyonel Denetim Standartlarına Uygun Kayıtlanmıştır',
                                          style: NewTokens.labelSm.copyWith(fontSize: 10, color: NewTokens.onSurfaceVariant),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: NewTokens.primary,
        child: const Icon(Icons.qr_code_scanner, color: NewTokens.onPrimary),
      ),
      bottomNavigationBar: Container(
        height: 64,
        decoration: const BoxDecoration(
          color: NewTokens.surface,
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.04),
              offset: Offset(0, -2),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.dashboard, 'Ana Sayfa', false),
            _buildNavItem(Icons.inventory_2, 'Ürünler', false),
            _buildNavItem(Icons.timer, 'Öneri / SKT', false, badge: '72'),
            _buildNavItem(Icons.monitoring, 'Rapor', false),
            _buildNavItem(Icons.widgets, 'Menü', true),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive, {String? badge}) {
    final color = isActive ? NewTokens.primary : NewTokens.onSurfaceVariant;
    return Expanded(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                style: NewTokens.labelSm.copyWith(color: color, fontWeight: isActive ? FontWeight.bold : FontWeight.w600),
              ),
            ],
          ),
          if (badge != null)
            Positioned(
              top: 8,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: NewTokens.error,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: NewTokens.labelSm.copyWith(fontSize: 9, color: NewTokens.onError),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
