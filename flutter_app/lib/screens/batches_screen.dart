import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/batch_actions.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../core/responsive.dart';
import '../models/batch.dart';
import '../models/dashboard.dart';
import '../widgets/dialogs.dart';
import '../widgets/panels.dart';
import '../widgets/search_field.dart';
import '../widgets/shell_scope.dart';
import 'batch_dialogs.dart';

/// Ürünler / Stok ekranı.
/// 4 özet gösterge kartı, 4 sekme (Donuk Depo, Çözünme, Satışa Hazır, Geçmiş),
/// arama ve ürün kartları.
class BatchesScreen extends StatefulWidget {
  const BatchesScreen({super.key, this.initialTab});

  /// Ana sayfadaki özet kutularından gelen sekme ('frozen', 'thawing',
  /// 'food_cabinet'). Tanınmayan değer yok sayılır.
  final String? initialTab;

  @override
  State<BatchesScreen> createState() => _BatchesScreenState();
}

class _BatchesScreenState extends State<BatchesScreen> {
  static const _tabs = [
    (id: 'frozen', label: 'Donuk Depo', icon: Icons.ac_unit_rounded),
    (id: 'thawing', label: 'Çözünme', icon: Icons.hourglass_bottom_rounded),
    (id: 'food_cabinet', label: 'Satışa Hazır', icon: Icons.kitchen_outlined),
    (id: 'sold,discarded', label: 'Geçmiş', icon: Icons.history_rounded),
  ];

  final _searchController = TextEditingController();
  int _tab = 0;
  String _search = '';
  List<Batch> _items = const [];
  DashboardCounts? _counts;
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final requested = _tabs.indexWhere((t) => t.id == widget.initialTab);
    if (requested >= 0) _tab = requested;
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final items = await repo.batches(status: _tabs[_tab].id, silent: silent);
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

    // İstatistik sayılarını güvenli çek; testlerde fakeApi dashboard mocklamamışsa çökmez.
    repo
        .dashboard(silent: true)
        .then((d) {
          if (mounted) {
            setState(() => _counts = d.counts);
          }
        })
        .catchError((_) {});
  }

  List<Batch> get _shown => filterBatches(_items, _search);

  Future<void> _after(Future<bool?> action) async {
    final ok = await action;
    if (ok == true) await _load(silent: true);
  }

  /// Parti silme geri alınamaz: bağlı satış ve zayi kayıtları da gider.
  Future<void> _deleteBatch(Batch b) async {
    final ok = await confirmDialog(
      context,
      title: 'Kaydı Sil',
      confirmLabel: 'Sil',
      body: Text(
        '${b.productName} (${statusLabels[b.status] ?? b.status}, ${b.remaining} adet kalan) '
        'kaydı silinecek.\n\nBu partiye ait satış, ikram ve zayi kayıtları da '
        'silinir. İşlem geri alınamaz.\n\nYalnızca adet yanlışsa silmek yerine '
        '"Tarih / Adet Düzelt" kullanın.',
      ),
    );
    if (ok != true) return;
    try {
      await repo.deleteBatch(b);
    } catch (_) {}
    await _load(silent: true);
  }

  Future<void> _completeThaw(Batch b) async {
    final ok = await confirmDialog(
      context,
      title: 'Food Dolabına Aktar',
      danger: false,
      confirmLabel: 'Aktar',
      body: Text(
        '${b.productName} (${b.remaining} adet) food dolabına aktarılacak. '
        'SKT süresi çözülmenin bittiği andan itibaren işler.',
      ),
    );
    if (ok != true) return;
    try {
      await repo.completeThaw(b);
    } catch (_) {}
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isSuper = session.user?.isSuperAdmin ?? false;
    final mobile = AppShellScope.isMobile(context);
    final sidePadding = context.isNarrowPhone ? 4.0 : 8.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: !_loaded
              ? const SizedBox.shrink()
              : _error != null && _items.isEmpty
              ? Center(
                  child: AppCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppAlert(message: _error!),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => _load(),
                          child: const Text('Tekrar Dene'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(silent: true),
                  child: CustomScrollView(
                    slivers: [
                      // 1. Üst Başlık & İstatistik Özet Kartları & Sekmeler
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            sidePadding,
                            mobile ? 0 : 12,
                            sidePadding,
                            8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!mobile) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Ürünler',
                                        style: TextStyle(
                                          fontSize: AppFontSize.headline,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.4,
                                          color: t.ink,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                              ],

                              // 4 Metrik Gösterge Kartı (2x2 Grid)
                              _StatsGrid(counts: _counts),
                              const SizedBox(height: 14),

                              // 4 Sekme Butonu
                              _TabBar(
                                tabs: _tabs,
                                index: _tab,
                                counts: _counts,
                                onChanged: (i) {
                                  setState(() {
                                    _tab = i;
                                    _loaded = false;
                                    _items = const [];
                                  });
                                  _load();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 2. SABİT Arama Kutusu
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _AramaBasligi(
                          child: ProductSearchField(
                            controller: _searchController,
                            onChanged: (v) => setState(() => _search = v),
                            onClear: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            },
                            filtering: _search.trim().isNotEmpty,
                          ),
                          zemin: t.bg,
                        ),
                      ),

                      // 5. Ürün Kartları Listesi
                      if (_shown.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: sidePadding,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: t.card,
                                border: Border.all(color: t.border),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _items.isEmpty
                                    ? 'Bu sekmede kayıt bulunamadı.'
                                    : '"$_search" ile eşleşen ürün bulunamadı.',
                                style: TextStyle(
                                  color: t.muted,
                                  fontSize: AppFontSize.bodyLarge,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        )
                      else ...[
                        if (context.isCompact)
                          SliverPadding(
                            padding: EdgeInsets.symmetric(
                              horizontal: sidePadding,
                            ),
                            sliver: SliverList.separated(
                              itemCount: _shown.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) => _BatchCard(
                                batch: _shown[i],
                                showStore: isSuper,
                                canAdjust:
                                    session.user?.can('adjust_batches') ??
                                    false,
                                canDiscard:
                                    session.user?.can('discard') ?? false,
                                canDelete: session.user?.isSuperAdmin ?? false,
                                onDetail: () =>
                                    showBatchDetail(context, _shown[i]),
                                onAdjust: () => _after(
                                  showAdjustDialog(context, _shown[i]),
                                ),
                                onThaw: () =>
                                    _after(showThawDialog(context, _shown[i])),
                                onCompleteThaw: () => _completeThaw(_shown[i]),
                                onAddStock: () => _after(
                                  showStockAddDialog(context, _shown[i]),
                                ),
                                onEarlyRequest: () => _after(
                                  showEarlyRequestDialog(context, _shown[i]),
                                ),
                                onDiscard: () => _after(
                                  showDiscardDialog(context, _shown[i]),
                                ),
                                onCorrectThaw: () => _after(
                                  showCorrectThawDialog(context, _shown[i]),
                                ),
                                onDelete: () => _deleteBatch(_shown[i]),
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 460,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    mainAxisExtent: 195,
                                  ),
                              delegate: SliverChildBuilderDelegate(
                                (context, i) => _BatchCard(
                                  batch: _shown[i],
                                  showStore: isSuper,
                                  canAdjust:
                                      session.user?.can('adjust_batches') ??
                                      false,
                                  canDiscard:
                                      session.user?.can('discard') ?? false,
                                  canDelete:
                                      session.user?.isSuperAdmin ?? false,
                                  onDetail: () =>
                                      showBatchDetail(context, _shown[i]),
                                  onAdjust: () => _after(
                                    showAdjustDialog(context, _shown[i]),
                                  ),
                                  onThaw: () => _after(
                                    showThawDialog(context, _shown[i]),
                                  ),
                                  onCompleteThaw: () =>
                                      _completeThaw(_shown[i]),
                                  onAddStock: () => _after(
                                    showStockAddDialog(context, _shown[i]),
                                  ),
                                  onEarlyRequest: () => _after(
                                    showEarlyRequestDialog(context, _shown[i]),
                                  ),
                                  onDiscard: () => _after(
                                    showDiscardDialog(context, _shown[i]),
                                  ),
                                  onCorrectThaw: () => _after(
                                    showCorrectThawDialog(context, _shown[i]),
                                  ),
                                  onDelete: () => _deleteBatch(_shown[i]),
                                ),
                                childCount: _shown.length,
                              ),
                            ),
                          ),
                      ],

                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// 4 Özet Kartı (2x2 Grid telefonda, 4x1 tablette/masaüstünde)
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({this.counts});

  final DashboardCounts? counts;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final frozenQty = counts?.frozenQty ?? (counts?.frozen ?? 0);
    final frozenCount = counts?.frozen ?? 0;
    final thawingQty = counts?.thawingQty ?? (counts?.thawing ?? 0);
    final cabinetQty = counts?.cabinetQty ?? (counts?.cabinet ?? 0);
    final criticalQty = counts?.expiringCount ?? 0;

    return EqualTileGrid(
      maxColumns: 4,
      children: [
        _MetricCard(
          title: 'DONUK DEPO',
          value: '$frozenQty / $frozenCount çeşit',
          footerIcon: Icons.access_time_rounded,
          footerText: 'Anlık depo durumu',
          icon: Icons.ac_unit_rounded,
          iconBg: context.tokens.infoSoft,
          iconColor: context.tokens.info,
          footerColor: context.tokens.muted,
        ),
        _MetricCard(
          title: 'ÇÖZÜNMEDE',
          value: '$thawingQty paket aktif',
          footerIcon: Icons.timer_outlined,
          footerText: 'Aktif çözülenler',
          icon: Icons.hourglass_bottom_rounded,
          iconBg: t.primarySoft,
          iconColor: t.primary,
          footerColor: t.muted,
        ),
        _MetricCard(
          title: 'SATIŞA HAZIR',
          value: '$cabinetQty vitrinde',
          footerIcon: Icons.verified_user_outlined,
          footerText: 'Dolap stoğu',
          icon: Icons.storefront_rounded,
          iconBg: context.tokens.successSoft,
          iconColor: context.tokens.success,
          footerColor: context.tokens.success,
          boldFooter: true,
        ),
        _MetricCard(
          title: 'KRİTİK STOK',
          value: '$criticalQty ürün azaldı',
          footerIcon: Icons.error_outline_rounded,
          footerText: criticalQty > 0 ? '! Sipariş verilmeli' : 'Stok güvenli',
          icon: Icons.warning_amber_rounded,
          iconBg: context.tokens.dangerSoft,
          iconColor: context.tokens.danger,
          footerColor: criticalQty > 0
              ? context.tokens.danger
              : context.tokens.success,
          boldFooter: true,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.footerIcon,
    required this.footerText,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.footerColor,
    this.boldFooter = false,
  });

  final String title;
  final String value;
  final IconData footerIcon;
  final String footerText;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final Color footerColor;
  final bool boldFooter;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm + 2),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: AppFontSize.micro,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: t.muted,
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 14, color: iconColor),
              ),
            ],
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppFontSize.bodyLarge,
              fontWeight: FontWeight.w800,
              color: t.ink,
              letterSpacing: -0.3,
            ),
          ),
          Row(
            children: [
              Icon(footerIcon, size: 12, color: footerColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  footerText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFontSize.micro,
                    fontWeight: boldFooter ? FontWeight.w700 : FontWeight.w500,
                    color: footerColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 4 Sekme Butonu (2x2 Grid telefonda, 4x1 geniş ekranda)
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.tabs,
    required this.index,
    required this.onChanged,
    this.counts,
  });

  final List<({String id, String label, IconData icon})> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  final DashboardCounts? counts;

  int? _badgeCount(int i) {
    if (i == 1) return counts?.thawing;
    if (i == 2) return counts?.cabinet;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final narrow = context.isCompact;
    return GridView.count(
      crossAxisCount: narrow ? 2 : 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: narrow ? 3.4 : 3.8,
      children: List.generate(tabs.length, (i) {
        final active = i == index;
        final badge = _badgeCount(i);

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: active ? t.primary : t.card,
              border: Border.all(
                color: active ? t.primary : t.border,
                width: 1.2,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: t.primary.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  tabs[i].icon,
                  size: 16,
                  color: active ? t.onPrimary : t.muted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    tabs[i].label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active ? t.onPrimary : t.ink,
                    ),
                  ),
                ),
                if (badge != null && badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: active ? t.primaryDark : t.primarySoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$badge',
                      style: TextStyle(
                        fontSize: AppFontSize.micro,
                        fontWeight: FontWeight.w700,
                        color: active ? t.onPrimary : t.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({
    required this.batch,
    required this.showStore,
    required this.canAdjust,
    required this.canDiscard,
    required this.canDelete,
    required this.onDetail,
    required this.onAdjust,
    required this.onThaw,
    required this.onCompleteThaw,
    required this.onAddStock,
    required this.onEarlyRequest,
    required this.onDiscard,
    required this.onCorrectThaw,
    required this.onDelete,
  });

  final Batch batch;
  final bool showStore;
  final bool canAdjust;
  final bool canDiscard;
  final bool canDelete;
  final VoidCallback onDetail;
  final VoidCallback onAdjust;
  final VoidCallback onThaw;
  final VoidCallback onCompleteThaw;
  final VoidCallback onAddStock;
  final VoidCallback onEarlyRequest;
  final VoidCallback onDiscard;
  final VoidCallback onCorrectThaw;
  final VoidCallback onDelete;

  ({String text, Color bg, Color textColor}) _badgeInfo(BuildContext context) {
    final t = context.tokens;
    if (batch.status == 'food_cabinet') {
      return switch (batch.urgency) {
        'expired' => (
          text: 'SKT Geçti',
          bg: t.dangerSoft,
          textColor: t.dangerText,
        ),
        'critical' => (
          text: 'SON GÜN',
          bg: t.dangerSoft,
          textColor: t.dangerText,
        ),
        'warning' => (
          text: 'Son 2 Gün',
          bg: t.warningSoft,
          textColor: t.warningText,
        ),
        _ => (text: 'Food Dolabı', bg: t.successSoft, textColor: t.success),
      };
    }
    return switch (batch.status) {
      'frozen' => (text: 'Donuk Depo', bg: t.infoSoft, textColor: t.info),
      'thawing' => (
        text: 'Çözülmede',
        bg: t.warningSoft,
        textColor: t.warningText,
      ),
      'sold' => (text: 'Satıldı', bg: t.successSoft, textColor: t.success),
      'discarded' => (text: 'Zayi', bg: t.border, textColor: t.muted),
      _ => (text: batch.status, bg: t.border, textColor: t.muted),
    };
  }

  Widget? _primaryWidget(BuildContext context, BatchAction? action) {
    final t = context.tokens;
    return switch (action) {
      BatchAction.thaw => FilledButton.icon(
        onPressed: onThaw,
        icon: const Icon(Icons.ac_unit_rounded, size: 17),
        label: const Text(
          'Çözülmeye Al',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: AppFontSize.body,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: t.primary,
          foregroundColor: t.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      BatchAction.completeThaw => FilledButton.icon(
        onPressed: onCompleteThaw,
        icon: const Icon(Icons.kitchen_outlined, size: 17),
        label: const Text(
          'Food Dolabına Al',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: AppFontSize.body,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: t.primary600,
          foregroundColor: t.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      BatchAction.awaitingApproval => Container(
        height: 42,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: t.warningSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.warning.withValues(alpha: 0.3)),
        ),
        child: Text(
          'Onay Bekliyor',
          style: TextStyle(
            color: t.warningText,
            fontWeight: FontWeight.w700,
            fontSize: AppFontSize.body,
          ),
        ),
      ),
      _ => null,
    };
  }

  _MenuEntry _entry(BatchAction a) => switch (a) {
    BatchAction.detail => (
      label: 'Detay',
      icon: Icons.info_outline_rounded,
      danger: false,
      onTap: onDetail,
    ),
    BatchAction.adjust => (
      label: 'Tarih / Adet Düzelt',
      icon: Icons.edit_outlined,
      danger: false,
      onTap: onAdjust,
    ),
    BatchAction.addStock => (
      label: 'Stok Ekle',
      icon: Icons.add_box_outlined,
      danger: false,
      onTap: onAddStock,
    ),
    BatchAction.earlyRequest => (
      label: 'Erken Aktarım İste (${formatHours(batch.thawRemainingHours)})',
      icon: Icons.hourglass_bottom_rounded,
      danger: false,
      onTap: onEarlyRequest,
    ),
    BatchAction.discard => (
      label: 'Zayi Gir',
      icon: Icons.delete_outline_rounded,
      danger: true,
      onTap: onDiscard,
    ),
    BatchAction.correctThaw => (
      label: 'Çözülme Adedini Düzelt',
      icon: Icons.undo_rounded,
      danger: false,
      onTap: onCorrectThaw,
    ),
    BatchAction.deleteBatch => (
      label: 'Kaydı Sil',
      icon: Icons.delete_forever_outlined,
      danger: true,
      onTap: onDelete,
    ),
    _ => (label: '-', icon: Icons.help_outline, danger: false, onTap: onDetail),
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final badge = _badgeInfo(context);
    final actions = batchActionsFor(
      batch,
      canAdjust: canAdjust,
      canDiscard: canDiscard,
      canDelete: canDelete,
    );
    final primary = _primaryWidget(context, actions.primary);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ürün Başlığı & Durum Rozeti
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  batch.productName.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: AppFontSize.bodyLarge,
                    letterSpacing: 0.2,
                    color: t.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: badge.bg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge.text,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: badge.textColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Meta Bilgileri
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Adet: ',
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        color: t.muted,
                      ),
                    ),
                    TextSpan(
                      text: '${batch.remaining}/${batch.quantity}',
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w800,
                        color: t.primary,
                      ),
                    ),
                  ],
                ),
              ),
              if (batch.status == 'thawing' && !batch.thawReady)
                Text(
                  '· Çözünme: ${formatHours(batch.thawRemainingHours)}',
                  style: TextStyle(fontSize: AppFontSize.label, color: t.muted),
                ),
              if (batch.sktDays != null)
                Text(
                  '· Dolap: ${batch.sktDays} gün',
                  style: TextStyle(fontSize: AppFontSize.label, color: t.muted),
                ),
              if (batch.sktEnd != null)
                Text(
                  '· SKT: ${fmtDateTime(batch.sktEnd)} (${formatHours(batch.remainingHours)})',
                  style: TextStyle(fontSize: AppFontSize.label, color: t.muted),
                ),
              if (showStore && batch.storeName != null)
                Text(
                  '· Mağaza: ${batch.storeName}',
                  style: TextStyle(fontSize: AppFontSize.label, color: t.muted),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Aksiyon Butonları Satırı
          Row(
            children: [
              if (primary != null) Expanded(child: primary),
              if (primary != null) const SizedBox(width: 8),
              if (primary == null) const Spacer(),
              _ActionMenu(items: actions.menu.map(_entry).toList()),
            ],
          ),
        ],
      ),
    );
  }
}

typedef _MenuEntry = ({
  String label,
  IconData icon,
  bool danger,
  VoidCallback onTap,
});

class _ActionMenu extends StatelessWidget {
  const _ActionMenu({required this.items});

  final List<_MenuEntry> items;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PopupMenuButton<int>(
      tooltip: 'Diğer işlemler',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 210),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (i) => items[i].onTap(),
      itemBuilder: (context) => [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: 44,
            child: Row(
              children: [
                Icon(
                  items[i].icon,
                  size: 18,
                  color: items[i].danger ? t.danger : t.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    items[i].label,
                    style: TextStyle(
                      fontSize: AppFontSize.body,
                      fontWeight: FontWeight.w600,
                      color: items[i].danger ? t.danger : t.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.card,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.more_vert_rounded, size: 20, color: t.muted),
      ),
    );
  }
}

/// Listenin üstünde SABİT kalan arama başlığı.
class _AramaBasligi extends SliverPersistentHeaderDelegate {
  _AramaBasligi({required this.child, required this.zemin});

  final Widget child;
  final Color zemin;

  static const double _yukseklik = 64;

  @override
  double get minExtent => _yukseklik;

  @override
  double get maxExtent => _yukseklik;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox(
      height: _yukseklik,
      child: Container(
        color: zemin,
        padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(_AramaBasligi eski) =>
      eski.child != child || eski.zemin != zemin;
}
