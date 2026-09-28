import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/notify.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/petty_cash.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/dialogs.dart';
import 'petty_cash_dialogs.dart';
import '../widgets/panels.dart';
import '../core/new_theme.dart';

class PettyCashScreen extends StatefulWidget {
  const PettyCashScreen({super.key});

  @override
  State<PettyCashScreen> createState() => _PettyCashScreenState();
}

class _PettyCashScreenState extends State<PettyCashScreen> {
  PettyCashPage _page = const PettyCashPage(items: []);
  String? _error;
  bool _loaded = false;
  String _activeTab = 'petty'; // 'finans' or 'petty'

  static const _spenderRoles = ['store_manager', 'shift_supervisor'];

  bool get _canSpend => _spenderRoles.contains(session.user?.role);
  bool get _isSuper => session.user?.isSuperAdmin ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final page = await repo.pettyCash(silent: silent);
      if (!mounted) return;
      setState(() {
        _page = page;
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

  Future<void> _add() async {
    final ok = await showExpenseDialog(context, status: _page.status);
    if (ok == true) {
      toastSaved('Masraf kaydedildi');
      await _load(silent: true);
    }
  }

  Future<void> _approve(PettyCashExpense e) async {
    final ok = await confirmDialog(
      context,
      title: 'Masrafı Onayla',
      danger: false,
      confirmLabel: 'Onayla',
      body: Text(
        '${fmtMoney(e.amount)} — ${e.description}\n'
        '${e.createdByName ?? 'bilinmiyor'} girdi.'
        '${e.hasReceipt ? '' : '\n\nBu masrafta fiş görseli yok.'}',
      ),
    );
    if (ok != true) return;
    try {
      await repo.approvePettyCash(e);
    } catch (_) {}
    await _load(silent: true);
  }

  Future<void> _reject(PettyCashExpense e) async {
    final ok = await showPettyCashRejectDialog(context, e);
    if (ok == true) await _load(silent: true);
  }

  Future<void> _delete(PettyCashExpense e) async {
    final ok = await confirmDialog(
      context,
      title: 'Masrafı Sil',
      confirmLabel: 'Sil',
      body: Text(
        '${fmtMoney(e.amount)} — ${e.description}\n\nBu kayıt silinecek.',
      ),
    );
    if (ok != true) return;
    try {
      await repo.deletePettyCash(e);
    } catch (_) {}
    await _load(silent: true);
  }

  Future<void> _showReceipt(PettyCashExpense e) async {
    String? data;
    try {
      data = await repo.pettyCashReceipt(e.id);
    } catch (_) {
      return;
    }
    if (!mounted || data == null) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                '${fmtMoney(e.amount)} — ${e.description}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: InteractiveViewer(child: Image.memory(_decode(data!))),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Kapat'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Uint8List _decode(String dataUrl) =>
      base64Decode(dataUrl.split(',').last);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NewTokens.surface,
      appBar: _buildAppBar(),
      body: _loaded
          ? RefreshIndicator(
              onRefresh: () => _load(silent: true),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 100, top: 16),
                children: [
                  if (_error != null) _buildError(),
                  _buildTopControls(),
                  _buildDateRange(),
                  _buildPettyCashBanner(),
                  _buildDonemOzeti(),
                  _buildGununRaporu(),
                  _buildHareketRaporu(),
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator()),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: NewTokens.primary,
        foregroundColor: NewTokens.onPrimary,
        shape: const CircleBorder(),
        child: const Icon(Icons.qr_code_scanner, size: 28),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: NewTokens.surface.withValues(alpha: 0.85),
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(color: Colors.transparent),
        ),
      ),
      title: Column(
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
              const Text(
                'DÜZCE MERKEZ ŞUBE',
                style: TextStyle(
                  color: NewTokens.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const Text(
            'Ana Sayfa',
            style: TextStyle(
              color: NewTokens.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'Muhammed Ş. Sezer · Mağaza Müdürü',
            style: TextStyle(color: NewTokens.onSurfaceVariant, fontSize: 11),
          ),
        ],
      ),
      actions: [
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_outlined,
                color: NewTokens.onSurfaceVariant,
              ),
              onPressed: () {},
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: NewTokens.error,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: const Text(
                  '7',
                  style: TextStyle(
                    color: NewTokens.onError,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(
            Icons.power_settings_new,
            color: NewTokens.onSurfaceVariant,
          ),
          onPressed: () {},
        ),
        Container(
          margin: const EdgeInsets.only(right: 16, left: 4),
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: NewTokens.primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person, color: NewTokens.onPrimary, size: 18),
        ),
      ],
    );
  }

  Widget _buildTopControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: NewTokens.surfaceContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                _buildTabButton(
                  'finans',
                  'Finans & Satış',
                  Icons.analytics_outlined,
                ),
                _buildTabButton('petty', 'Petty Cash', Icons.payments_outlined),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _canSpend ? _add : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: NewTokens.primaryContainer,
              foregroundColor: NewTokens.onPrimaryContainer,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              minimumSize: const Size(0, 40),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: Text(
              _activeTab == 'petty' ? 'Masraf Ekle' : 'Gün Ekle',
              style: NewTokens.labelMd,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String id, String label, IconData icon) {
    final active = _activeTab == id;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? NewTokens.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? NewTokens.onPrimary : NewTokens.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: NewTokens.labelMd.copyWith(
                color: active
                    ? NewTokens.onPrimary
                    : NewTokens.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRange() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: NewTokens.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildDateChip('Bugün', false),
                  const SizedBox(width: 6),
                  _buildDateChip(
                    'Haftalık (21-27 Eyl)',
                    true,
                    icon: Icons.check_circle,
                    iconColor: NewTokens.tertiary,
                  ),
                  const SizedBox(width: 6),
                  _buildDateChip('Aylık', false),
                  const SizedBox(width: 6),
                  _buildDateChip('Özel', false, icon: Icons.date_range),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.event_available,
                      size: 16,
                      color: NewTokens.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '21.09.2026 – 27.09.2026 (7 Gün)',
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _buildExportBtn(
                      'Excel',
                      Icons.table_view,
                      NewTokens.tertiary,
                    ),
                    const SizedBox(width: 6),
                    _buildExportBtn(
                      'PDF',
                      Icons.picture_as_pdf,
                      NewTokens.error,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateChip(
    String label,
    bool active, {
    IconData? icon,
    Color? iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? NewTokens.secondaryContainer
            : NewTokens.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
        boxShadow: active
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                ),
              ]
            : [],
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 16,
              color: iconColor ?? NewTokens.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: NewTokens.labelMd.copyWith(
              color: active
                  ? NewTokens.onSecondaryContainer
                  : NewTokens.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportBtn(String label, IconData icon, Color iconColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: NewTokens.labelSm.copyWith(color: NewTokens.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _buildPettyCashBanner() {
    final status = _page.status;
    if (status == null) return const SizedBox.shrink();

    final tight = status.usedRatio >= 0.85;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NewTokens.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
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
                        const SizedBox(width: 6),
                        Text(
                          'ŞUBE KASASI / PETTY CASH',
                          style: NewTokens.labelSm.copyWith(
                            color: NewTokens.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Kalan: ${fmtMoney(status.remaining)}',
                      style: NewTokens.headlineMd.copyWith(
                        color: tight ? NewTokens.error : NewTokens.onSurface,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: NewTokens.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock,
                        size: 14,
                        color: NewTokens.onSecondaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Aktif Dönem',
                        style: NewTokens.labelSm.copyWith(
                          color: NewTokens.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: status.usedRatio,
                minHeight: 8,
                backgroundColor: NewTokens.surfaceContainer,
                valueColor: AlwaysStoppedAnimation<Color>(
                  tight ? NewTokens.error : NewTokens.primaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RichText(
                  text: TextSpan(
                    style: NewTokens.labelSm.copyWith(
                      color: NewTokens.onSurfaceVariant,
                    ),
                    children: [
                      const TextSpan(text: 'Harcama: '),
                      TextSpan(
                        text: fmtMoney(status.spentThisWeek),
                        style: const TextStyle(
                          color: NewTokens.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextSpan(text: ' / ${fmtMoney(status.weeklyLimit)}'),
                    ],
                  ),
                ),
                Text(
                  tight ? 'Limit Kritik' : 'Bütçe Hazır',
                  style: NewTokens.labelSm.copyWith(
                    color: tight ? NewTokens.error : NewTokens.tertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.schedule,
                      size: 15,
                      color: NewTokens.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Dönem Başı: ${fmtDate(status.weekStart)}',
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (_canSpend)
                  ElevatedButton.icon(
                    onPressed: _add,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NewTokens.tertiary,
                      foregroundColor: NewTokens.onTertiary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 0,
                      ),
                      minimumSize: const Size(0, 32),
                    ),
                    icon: const Icon(Icons.receipt_long, size: 16),
                    label: Text('Masraf Gir', style: NewTokens.labelSm),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDonemOzeti() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Opacity(
        opacity: _activeTab == 'petty' ? 0.4 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NewTokens.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.query_stats,
                        color: NewTokens.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Dönem Özeti',
                        style: NewTokens.headlineSm.copyWith(
                          color: NewTokens.onSurface,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Konsolide',
                    style: NewTokens.labelSm.copyWith(color: NewTokens.primary),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Oranlar günlük aritmetik ortalama değil, 7 günlük fiş verisinin konsolide toplamından hesaplanır.',
                style: NewTokens.bodySm.copyWith(
                  color: NewTokens.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NET SALES (TOPLAM CİRO)',
                          style: NewTokens.labelSm.copyWith(
                            color: NewTokens.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '51.258,00 ₺',
                          style: NewTokens.numericMetric.copyWith(
                            color: NewTokens.primary,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: NewTokens.primaryFixed.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.point_of_sale,
                        color: NewTokens.primary,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Dummy stat grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.8,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  _buildStatCard(
                    'ADT (Fiş Adedi)',
                    Icons.receipt,
                    NewTokens.tertiary,
                    '168',
                    'fiş',
                  ),
                  _buildStatCard(
                    'Product Qty',
                    Icons.inventory_2,
                    NewTokens.primary,
                    '25',
                    'adet',
                  ),
                  _buildStatCard(
                    'Satılan İçecek',
                    Icons.local_cafe,
                    NewTokens.tertiary,
                    '30',
                    'adet',
                  ),
                  _buildStatCard(
                    'Modifiers',
                    Icons.tune,
                    NewTokens.secondary,
                    '2',
                    'şurup/süt',
                  ),
                  _buildStatCard(
                    'Mobil App Satışı',
                    Icons.smartphone,
                    NewTokens.primary,
                    '2.563,00 ₺',
                    '%5.00 Ciro Payı',
                    smallSub: true,
                    subColor: NewTokens.tertiary,
                  ),
                  _buildStatCard(
                    'Food Değeri',
                    Icons.lunch_dining,
                    NewTokens.onSurfaceVariant,
                    '0,00 ₺',
                    '0 USD / 0 MO',
                    smallSub: true,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildPill(
                    'AT: 305,11 ₺',
                    Icons.shopping_basket,
                    NewTokens.secondaryContainer,
                    NewTokens.onSecondaryContainer,
                  ),
                  _buildPill(
                    'IPT: 0.14',
                    Icons.pin,
                    NewTokens.surfaceContainer,
                    NewTokens.onSurfaceVariant,
                  ),
                  _buildPill(
                    'MODIFIERS: %6.67',
                    Icons.percent,
                    NewTokens.surfaceContainer,
                    NewTokens.onSurfaceVariant,
                  ),
                  _buildPill(
                    'FOOD UPH: 0.00',
                    Icons.speed,
                    NewTokens.surfaceContainer,
                    NewTokens.onSurfaceVariant,
                  ),
                  _buildPill(
                    'MARKOUT: -',
                    null,
                    NewTokens.surfaceContainer,
                    NewTokens.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    IconData icon,
    Color iconColor,
    String val,
    String sub, {
    bool smallSub = false,
    Color? subColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: NewTokens.labelSm.copyWith(
                    color: NewTokens.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, size: 16, color: iconColor),
            ],
          ),
          RichText(
            text: TextSpan(
              style: NewTokens.headlineSm.copyWith(color: NewTokens.onSurface),
              children: [
                TextSpan(text: '$val '),
                if (!smallSub)
                  TextSpan(
                    text: sub,
                    style: NewTokens.labelSm.copyWith(
                      color: NewTokens.onSurfaceVariant,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
              ],
            ),
          ),
          if (smallSub)
            Text(
              sub,
              style: NewTokens.labelSm.copyWith(
                color: subColor ?? NewTokens.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPill(String label, IconData? icon, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: NewTokens.labelSm.copyWith(color: fg)),
        ],
      ),
    );
  }

  Widget _buildGununRaporu() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NewTokens.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: NewTokens.tertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '27.09.2026 · Bugün',
                      style: NewTokens.headlineSm.copyWith(
                        color: NewTokens.onSurface,
                      ),
                    ),
                  ],
                ),
                Text(
                  '51.258,00 ₺',
                  style: NewTokens.numericMetric.copyWith(
                    fontSize: 20,
                    color: NewTokens.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildSmallPill(
                  'AT: 305,11 ₺',
                  NewTokens.surfaceContainer,
                  NewTokens.primary,
                ),
                _buildSmallPill(
                  'IPT: 0.14',
                  NewTokens.surfaceContainer,
                  NewTokens.primary,
                ),
                _buildSmallPill(
                  'MODIFIERS: %6.67',
                  NewTokens.secondaryContainer,
                  NewTokens.onSecondaryContainer,
                ),
                _buildSmallPill(
                  'APP: %5.00',
                  NewTokens.surfaceContainer,
                  NewTokens.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '168 fiş · 25 ürün satışı',
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Muhammed Şükrü Sezer (Müdür)',
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.onSurface,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NewTokens.tertiaryContainer,
                    foregroundColor: NewTokens.onTertiary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.verified, size: 18),
                  label: Text('Günlük Rapor', style: NewTokens.labelMd),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallPill(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: NewTokens.labelSm.copyWith(color: fg)),
    );
  }

  Widget _buildHareketRaporu() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.receipt_long,
                    size: 20,
                    color: NewTokens.onSurface,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Hareket Raporu',
                    style: NewTokens.headlineSm.copyWith(
                      color: NewTokens.onSurface,
                    ),
                  ),
                ],
              ),
              Text(
                'Toplam ${_page.items.length} Kayıt',
                style: NewTokens.labelSm.copyWith(
                  color: NewTokens.onSurfaceVariant,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildFilterCard(
                  'Satış',
                  NewTokens.tertiary,
                  '162',
                  '30.755 ₺',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildFilterCard(
                  'İkram',
                  NewTokens.secondary,
                  '7',
                  '1.350 ₺',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildFilterCard(
                  'Zayi',
                  NewTokens.error,
                  '19',
                  '3.780 ₺',
                  isError: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_page.items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Text(
                  'Bu hafta masraf kaydı yok.',
                  style: NewTokens.bodyMd.copyWith(
                    color: NewTokens.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ..._page.items.map((e) => _buildTransactionItem(e)),
          if (_page.items.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: () {},
                style: TextButton.styleFrom(
                  backgroundColor: NewTokens.surfaceContainer,
                  foregroundColor: NewTokens.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Text(
                  'Tüm İşlemleri Görüntüle',
                  style: NewTokens.labelMd,
                ),
                label: const Icon(Icons.expand_more, size: 18),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterCard(
    String title,
    Color color,
    String count,
    String amount, {
    bool isError = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(
                title,
                style: NewTokens.labelSm.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: NewTokens.onSurface,
              ),
              children: [
                TextSpan(text: count),
                TextSpan(
                  text: ' adet',
                  style: NewTokens.labelSm.copyWith(
                    color: NewTokens.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: NewTokens.labelSm.copyWith(
              color: NewTokens.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(PettyCashExpense e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: NewTokens.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.receipt, color: NewTokens.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        e.description,
                        style: NewTokens.labelLg.copyWith(
                          color: NewTokens.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      fmtMoney(e.amount),
                      style: NewTokens.labelLg.copyWith(
                        color: NewTokens.tertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    _buildSmallPill(
                      e.statusLabel,
                      e.isPending
                          ? Colors.orange.withValues(alpha: 0.2)
                          : e.isRejected
                          ? NewTokens.errorContainer
                          : NewTokens.secondaryContainer,
                      e.isPending
                          ? Colors.orange
                          : e.isRejected
                          ? NewTokens.onErrorContainer
                          : NewTokens.onSecondaryContainer,
                    ),
                    if (e.hasReceipt)
                      _buildSmallPill(
                        'Fişli',
                        NewTokens.surfaceContainer,
                        NewTokens.onSurface,
                      )
                    else
                      _buildSmallPill(
                        'Fiş Yok',
                        NewTokens.surfaceContainer,
                        NewTokens.onSurfaceVariant,
                      ),
                    Text(
                      '${fmtDateTime(e.spentAt)} · ${e.createdByName ?? 'bilinmiyor'}',
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                if (e.isRejected && e.decisionNote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Ret: ${e.decisionNote}',
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.error,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (e.hasReceipt)
                IconButton(
                  icon: const Icon(
                    Icons.image_outlined,
                    size: 16,
                    color: NewTokens.onSurfaceVariant,
                  ),
                  onPressed: () => _showReceipt(e),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              if (e.isPending && (_page.status?.canApprove ?? false))
                IconButton(
                  icon: const Icon(
                    Icons.check,
                    size: 16,
                    color: NewTokens.primary,
                  ),
                  onPressed: () => _approve(e),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              if (e.isPending && (_page.status?.canApprove ?? false))
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 16,
                    color: NewTokens.error,
                  ),
                  onPressed: () => _reject(e),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: NewTokens.error,
                ),
                onPressed: () => _delete(e),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      color: NewTokens.errorContainer,
      child: Text(
        _error!,
        style: const TextStyle(color: NewTokens.onErrorContainer),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: NewTokens.surface.withValues(alpha: 0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem('Ana Sayfa', Icons.dashboard, false),
          _buildNavItem('Ürünler', Icons.inventory_2, false),
          _buildNavItem('Öneri / SKT', Icons.timer, false, badge: '72'),
          _buildNavItem('Rapor', Icons.monitoring, true),
          _buildNavItem('Menü', Icons.widgets, false),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    String label,
    IconData icon,
    bool active, {
    String? badge,
  }) {
    return Expanded(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: active ? NewTokens.primary : NewTokens.onSurfaceVariant,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: NewTokens.labelSm.copyWith(
                  color: active
                      ? NewTokens.primary
                      : NewTokens.onSurfaceVariant,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          if (badge != null)
            Positioned(
              top: 8,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: NewTokens.error,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: NewTokens.onError,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
