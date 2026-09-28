import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/nav.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../core/new_theme.dart';
import '../models/daily_report.dart';
import '../models/dashboard.dart';
import '../models/manager_overview.dart';
import 'manager_overview_block.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardData? _data;
  ReportSummary? _summary;
  List<SalesPoint> _sales = const [];
  List<StatusSlice> _status = const [];
  ProductPerformance? _perf;
  List<StoreOption> _stores = const [];
  int _pendingApprovals = 0;

  ManagerOverview? _overview;
  ReportFields _reportFields = ReportFields.empty;

  int? _storeId;
  bool _monthly = false;
  String? _error;
  Timer? _timer;

  bool get _showOverview => reportPanelRoles.contains(session.user?.role);

  @override
  void initState() {
    super.initState();
    _load();
    if (_showOverview) {
      repo
          .reportFields()
          .then((f) {
            if (mounted) setState(() => _reportFields = f);
          })
          .onError((Object _, StackTrace _) {});
    }
    if (session.user?.isSuperAdmin ?? false) {
      repo
          .stores(silent: true)
          .then((s) {
            if (mounted) setState(() => _stores = s);
          })
          .onError((Object _, StackTrace _) {});
    }
    _timer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final results = await Future.wait([
        repo.dashboard(storeId: _storeId, silent: silent),
        repo.reportSummary(storeId: _storeId, silent: silent),
        repo.sales7(storeId: _storeId, silent: silent),
        repo.statusBreakdown(storeId: _storeId, silent: silent),
        repo.productPerformance(storeId: _storeId, silent: silent),
        if (session.user?.canManage ?? false)
          repo.pendingApprovalCount(silent: silent),
      ]);
      if (_showOverview) {
        repo
            .managerOverview(storeId: _storeId, silent: true)
            .then((o) {
              if (mounted) setState(() => _overview = o);
            })
            .onError((Object _, StackTrace _) {});
      }
      if (!mounted) return;
      setState(() {
        _data = results[0] as DashboardData;
        _summary = results[1] as ReportSummary;
        _sales = results[2] as List<SalesPoint>;
        _status = results[3] as List<StatusSlice>;
        _perf = results[4] as ProductPerformance;
        _pendingApprovals = results.length > 5 ? results[5] as int : 0;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;

    if (data == null) {
      if (_error != null) {
        return Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NewTokens.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  style: NewTokens.bodyMd.copyWith(color: NewTokens.error),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _load(),
                  child: const Text('Tekrar Dene'),
                ),
              ],
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final c = data.counts;
    final soldToday = data.soldToday;

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: Container(
        color: NewTokens.surface,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          children: [
            if (c.expiredQty > 0) ...[
              _UrgentActionBanner(expiredQty: c.expiredQty),
              const SizedBox(height: 16),
            ],

            _FinancialQuickOverview(overview: _overview, fields: _reportFields),
            const SizedBox(height: 16),

            _RealtimeStatusKpiQuad(counts: c),
            const SizedBox(height: 16),

            _MicroOperationalPerformanceRow(
              soldToday: soldToday,
              summary: _summary,
            ),
            const SizedBox(height: 16),

            _SalesAnalyticsCharts(sales: _sales, status: _status),
            const SizedBox(height: 16),

            if (_perf != null)
              _ProductPerformanceList(
                perf: _perf!,
                monthly: _monthly,
                onPeriodChanged: (v) => setState(() => _monthly = v),
              ),
          ],
        ),
      ),
    );
  }
}

class _UrgentActionBanner extends StatelessWidget {
  final int expiredQty;
  const _UrgentActionBanner({required this.expiredQty});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NewTokens.errorContainer,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: NewTokens.error.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warning, color: NewTokens.error, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACİL İŞLEM GEREKİYOR',
                  style: NewTokens.labelSm.copyWith(
                    color: NewTokens.error,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$expiredQty adet ürünün SKT\'si doldu!',
                  style: NewTokens.bodyMd.copyWith(
                    color: NewTokens.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tezgaha sunulmamalı, hemen imha & zayi kaydı girilmeli.',
                  style: NewTokens.bodySm.copyWith(
                    color: NewTokens.onErrorContainer.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Align(
            alignment: Alignment.center,
            child: InkWell(
              onTap: () => context.go('/recommendations'),
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: NewTokens.surfaceContainerLowest,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x0D000000), blurRadius: 4),
                  ],
                ),
                child: const Icon(
                  Icons.chevron_right,
                  color: NewTokens.error,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinancialQuickOverview extends StatelessWidget {
  final ManagerOverview? overview;
  final ReportFields fields;

  const _FinancialQuickOverview({this.overview, required this.fields});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Ciro Forecast Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NewTokens.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 4,
                offset: Offset(0, 1),
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
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: NewTokens.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.query_stats,
                          color: NewTokens.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ciro Forecast',
                            style: NewTokens.labelLg.copyWith(
                              color: NewTokens.onSurface,
                            ),
                          ),
                          Text(
                            'Ay başından bugüne 0 gün girildi · 27 gün eksik',
                            style: NewTokens.labelSm.copyWith(
                              color: NewTokens.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: NewTokens.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: NewTokens.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ay Başından Bu Yana',
                            style: NewTokens.labelSm.copyWith(
                              color: NewTokens.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '0,00 ₺',
                            style: NewTokens.headlineSm.copyWith(
                              color: NewTokens.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: NewTokens.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Günlük Ortalama',
                            style: NewTokens.labelSm.copyWith(
                              color: NewTokens.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '—',
                            style: NewTokens.headlineSm.copyWith(
                              color: NewTokens.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: NewTokens.secondaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.trending_up,
                          color: NewTokens.tertiary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Ay Sonu Tahmini',
                          style: NewTokens.labelMd.copyWith(
                            color: NewTokens.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Veri girişi bekleniyor',
                      style: NewTokens.labelMd.copyWith(
                        color: NewTokens.tertiary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Petty Cash Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NewTokens.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 4,
                offset: Offset(0, 1),
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
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: NewTokens.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet,
                          color: NewTokens.onSecondaryContainer,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Petty Cash (Kasa)',
                            style: NewTokens.labelLg.copyWith(
                              color: NewTokens.onSurface,
                            ),
                          ),
                          Text(
                            'Haftalık bütçe limiti · 0 masraf kaydı',
                            style: NewTokens.labelSm.copyWith(
                              color: NewTokens.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.add,
                          color: NewTokens.primary,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Masraf',
                          style: NewTokens.labelSm.copyWith(
                            color: NewTokens.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kalan Bütçe',
                        style: NewTokens.labelSm.copyWith(
                          color: NewTokens.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '10.000,00 ₺',
                        style: NewTokens.numericMetric.copyWith(
                          color: NewTokens.primary,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Limit',
                        style: NewTokens.labelSm.copyWith(
                          color: NewTokens.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '10.000,00 ₺',
                        style: NewTokens.bodyMd.copyWith(
                          color: NewTokens.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  Container(
                    width: double.infinity,
                    height: 8,
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: 0.02,
                      child: Container(
                        decoration: BoxDecoration(
                          color: NewTokens.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '%0 harcandı',
                        style: NewTokens.labelSm.copyWith(
                          color: NewTokens.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        'Harcanan: 0,00 ₺',
                        style: NewTokens.labelSm.copyWith(
                          color: NewTokens.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RealtimeStatusKpiQuad extends StatelessWidget {
  final DashboardCounts counts;

  const _RealtimeStatusKpiQuad({required this.counts});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _KpiCard(
                title: 'Donuk Depo',
                icon: Icons.ac_unit,
                iconBg: NewTokens.surfaceContainer,
                iconColor: NewTokens.primary,
                value: '${counts.frozenQty}',
                subtitle: '${counts.frozen} ürün çeşidi',
                valueColor: NewTokens.primary,
                onTap: () => context.go('/batches?tab=frozen'),
              ),
              const SizedBox(height: 12),
              _KpiCard(
                title: 'Food Dolabı',
                icon: Icons.kitchen,
                iconBg: NewTokens.secondaryContainer,
                iconColor: NewTokens.tertiary,
                value: '${counts.cabinetQty}',
                subtitle: '${counts.cabinet} çeşit tezgahta',
                valueColor: NewTokens.tertiary,
                onTap: () => context.go('/batches?tab=food_cabinet'),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              _KpiCard(
                title: 'Çözülmede',
                icon: Icons.hourglass_top,
                iconBg: NewTokens.surfaceContainerHigh,
                iconColor: NewTokens.secondary,
                value: '${counts.thawingQty}',
                subtitle: '${counts.thawing} kayıt',
                valueColor: NewTokens.onSurface,
                onTap: () => context.go('/batches?tab=thawing'),
              ),
              const SizedBox(height: 12),
              _KpiCard(
                title: 'SKT Geçen',
                icon: Icons.emergency,
                iconBg: NewTokens.errorContainer,
                iconColor: NewTokens.error,
                value: '${counts.expiredQty}',
                subtitle: 'Zayi verilmeli',
                valueColor: NewTokens.error,
                subtitleColor: NewTokens.error,
                onTap: () => context.go('/recommendations'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String value;
  final String subtitle;
  final Color valueColor;
  final Color? subtitleColor;
  final VoidCallback onTap;

  const _KpiCard({
    required this.title,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.value,
    required this.subtitle,
    required this.valueColor,
    this.subtitleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NewTokens.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: NewTokens.labelMd.copyWith(
                    color: title == 'SKT Geçen'
                        ? NewTokens.error
                        : NewTokens.onSurfaceVariant,
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: iconBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: NewTokens.numericMetric.copyWith(color: valueColor),
            ),
            Text(
              subtitle,
              style: NewTokens.labelSm.copyWith(
                color: subtitleColor ?? NewTokens.onSurfaceVariant,
                fontWeight: subtitleColor != null
                    ? FontWeight.w600
                    : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MicroOperationalPerformanceRow extends StatelessWidget {
  final SoldToday soldToday;
  final ReportSummary? summary;

  const _MicroOperationalPerformanceRow({
    required this.soldToday,
    this.summary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MicroCard(
                icon: Icons.point_of_sale,
                title: 'Bugün Satılan',
                value: '${soldToday.qty}',
                unit: 'adet',
                subtitle: '${fmtMoney(soldToday.revenue)} ciro',
                color: NewTokens.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MicroCard(
                icon: Icons.receipt_long,
                title: 'Bugünkü İşlem',
                value: '${soldToday.count}',
                unit: 'fiş',
                subtitle: soldToday.count > 0
                    ? 'Satış kaydı var'
                    : 'Satış kaydı yok',
                color: NewTokens.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MicroCard(
                icon: Icons.storefront,
                title: summary?.storeName ?? 'Mağaza',
                value: '${summary?.soldQty ?? 0}',
                unit: 'adet',
                subtitle: fmtMoney(summary?.revenue ?? 0),
                color: NewTokens.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MicroCard(
                icon: Icons.delete_sweep,
                title: 'Toplam Zayi',
                value: '${summary?.discardedQty ?? 0}',
                unit: 'adet',
                subtitle: 'Seçili dönem',
                color: NewTokens.error,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MicroCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String unit;
  final String subtitle;
  final Color color;

  const _MicroCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.unit,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: NewTokens.labelSm.copyWith(
                    color: color == NewTokens.error
                        ? NewTokens.error
                        : NewTokens.onSurfaceVariant,
                    fontWeight: color == NewTokens.error
                        ? FontWeight.w600
                        : FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: NewTokens.headlineSm.copyWith(
                  color: color == NewTokens.error
                      ? NewTokens.error
                      : NewTokens.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: NewTokens.bodySm.copyWith(
                  color: color == NewTokens.error
                      ? NewTokens.error.withValues(alpha: 0.8)
                      : NewTokens.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Text(
            subtitle,
            style: NewTokens.labelSm.copyWith(
              color: color == NewTokens.error
                  ? NewTokens.error.withValues(alpha: 0.7)
                  : NewTokens.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesAnalyticsCharts extends StatelessWidget {
  final List<SalesPoint> sales;
  final List<StatusSlice> status;

  const _SalesAnalyticsCharts({required this.sales, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Son 7 Günlük Satış',
                    style: NewTokens.headlineSm.copyWith(
                      color: NewTokens.onSurface,
                    ),
                  ),
                  Text(
                    'Adet ve ciro dağılım grafiği',
                    style: NewTokens.labelSm.copyWith(
                      color: NewTokens.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Son 7 Gün',
                  style: NewTokens.labelSm.copyWith(color: NewTokens.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Satış Adedi (Adet)',
            style: NewTokens.labelSm.copyWith(
              color: NewTokens.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: sales.map((s) {
              return Column(
                children: [
                  Text(
                    '${s.qty}',
                    style: NewTokens.labelSm.copyWith(
                      fontSize: 10,
                      color: NewTokens.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 24,
                    height: (s.qty.toDouble() / 50.0).clamp(0.0, 1.0) * 80 + 4,
                    decoration: const BoxDecoration(
                      color: NewTokens.tertiaryContainer,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.date,
                    style: NewTokens.labelSm.copyWith(
                      fontSize: 10,
                      color: NewTokens.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text(
            'Günlük Ciro (₺)',
            style: NewTokens.labelSm.copyWith(
              color: NewTokens.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: sales.map((s) {
              return Column(
                children: [
                  Text(
                    '${(s.revenue / 1000).toStringAsFixed(1)}k',
                    style: NewTokens.labelSm.copyWith(
                      fontSize: 9,
                      color: NewTokens.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 24,
                    height: (s.revenue / 10000).clamp(0.0, 1.0) * 80 + 4,
                    decoration: const BoxDecoration(
                      color: NewTokens.primaryContainer,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.date,
                    style: NewTokens.labelSm.copyWith(
                      fontSize: 10,
                      color: NewTokens.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Durum Dağılımı',
                style: NewTokens.labelMd.copyWith(color: NewTokens.onSurface),
              ),
              Text(
                'Stok, satış & fire',
                style: NewTokens.labelSm.copyWith(
                  color: NewTokens.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...status.map((s) {
            Color barColor = NewTokens.primary;
            if (s.status == 'sold') barColor = NewTokens.tertiary;
            if (s.status == 'discarded') barColor = NewTokens.error;
            if (s.status == 'ikram')
              barColor = NewTokens.onSecondaryFixedVariant;
            if (s.status == 'food_cabinet') barColor = NewTokens.secondary;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        s.status,
                        style: NewTokens.bodySm.copyWith(
                          color: s.status == 'discarded'
                              ? NewTokens.error
                              : NewTokens.onSurface,
                          fontWeight: s.status == 'discarded'
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                      Text(
                        '${s.quantity} adet',
                        style: NewTokens.bodySm.copyWith(
                          color: s.status == 'discarded'
                              ? NewTokens.error
                              : NewTokens.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    height: 8,
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: (s.quantity / 2000).clamp(0.02, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ProductPerformanceList extends StatelessWidget {
  final ProductPerformance perf;
  final bool monthly;
  final ValueChanged<bool> onPeriodChanged;

  const _ProductPerformanceList({
    required this.perf,
    required this.monthly,
    required this.onPeriodChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = monthly ? perf.month : perf.week;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ürün Performansı',
                    style: NewTokens.headlineSm.copyWith(
                      color: NewTokens.onSurface,
                    ),
                  ),
                  Text(
                    'Son ${monthly ? '30' : '7'} günlük mağaza analizi',
                    style: NewTokens.labelSm.copyWith(
                      color: NewTokens.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => onPeriodChanged(false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: !monthly
                              ? NewTokens.surfaceContainerLowest
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: !monthly
                              ? const [
                                  BoxShadow(
                                    color: Color(0x0A000000),
                                    blurRadius: 2,
                                    offset: Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          'Hafta',
                          style: NewTokens.labelSm.copyWith(
                            color: !monthly
                                ? NewTokens.primary
                                : NewTokens.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => onPeriodChanged(true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: monthly
                              ? NewTokens.surfaceContainerLowest
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: monthly
                              ? const [
                                  BoxShadow(
                                    color: Color(0x0A000000),
                                    blurRadius: 2,
                                    offset: Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          'Ay',
                          style: NewTokens.labelSm.copyWith(
                            color: monthly
                                ? NewTokens.primary
                                : NewTokens.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _buildListSection(
            'En Çok Satanlar',
            Icons.verified,
            NewTokens.tertiary,
            p.best,
            NewTokens.tertiary,
          ),
          const SizedBox(height: 16),
          _buildListSection(
            'En Az Satanlar',
            Icons.trending_down,
            NewTokens.onSecondaryFixedVariant,
            p.worst,
            NewTokens.secondary,
          ),
          const SizedBox(height: 16),
          _buildListSection(
            'En Çok Zayi (Fire)',
            Icons.delete,
            NewTokens.error,
            p.topWasted,
            NewTokens.error,
          ),

          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NewTokens.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.info, color: NewTokens.primary, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Dönemde ${p.kinds} çeşit üründen toplam ${p.soldTotal} adet satış yapıldı, ${p.wastedTotal} adet zayi kaydı gerçekleştirildi.',
                    style: NewTokens.labelSm.copyWith(
                      color: NewTokens.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListSection(
    String title,
    IconData icon,
    Color titleColor,
    List<ProductRank> items,
    Color barColor,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, color: titleColor, size: 18),
            const SizedBox(width: 6),
            Text(
              title.toUpperCase(),
              style: NewTokens.labelMd.copyWith(
                color: titleColor,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...items.take(5).map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    e.productName,
                    style: NewTokens.bodySm.copyWith(
                      color: NewTokens.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 80,
                      height: 8,
                      decoration: BoxDecoration(
                        color: NewTokens.surfaceContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (e.qty / 50).clamp(0.1, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${e.qty}',
                        style: NewTokens.bodySm.copyWith(
                          color: titleColor == NewTokens.error
                              ? NewTokens.error
                              : NewTokens.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Bu dönemde kayıt yok',
              style: NewTokens.bodySm.copyWith(
                color: NewTokens.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
