import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/dashboard.dart';
import '../widgets/mini_bar_chart.dart';
import '../widgets/panels.dart';
import '../widgets/rank_list.dart';

/// Operasyon ozeti ve raporlar her ekran boyutunda acik. Ozet kutulari
/// tiklanabilir; her biri ilgili ekrani acar.
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

  int? _storeId;
  bool _monthly = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    if (session.user?.isSuperAdmin ?? false) {
      // Magaza listesi kritik degil: gelmezse secici gizli kalir.
      repo.stores(silent: true).then((s) {
        if (mounted) setState(() => _stores = s);
      }).onError((Object _, StackTrace _) {});
    }
    // 60 saniyelik yenileme kullanicinin baslattigi islem degil: katman ve
    // bildirim olmadan doner, yoksa ekran her dakika kilitlenirdi.
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load(silent: true));
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
        if (session.user?.canManage ?? false) repo.pendingApprovalCount(silent: silent),
      ]);
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
      // Engelleyici katmanin kalici kilide donusmemesi icin cikis yolu birakilir.
      setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final data = _data;

    if (data == null) {
      if (_error != null) {
        return Center(
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppAlert(message: _error!),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => _load(), child: const Text('Tekrar Dene')),
              ],
            ),
          ),
        );
      }
      // Yukleme katmanini global BusyOverlay gosterir.
      return const SizedBox.shrink();
    }

    final c = data.counts;

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (c.expiredQty > 0) ...[
            AppAlert(
              message: '${c.expiredQty} adet ürünün SKT\'si doldu! Satışa sunulmamalı, hemen imha edilmeli.',
            ),
            const SizedBox(height: AppTokens.gap),
          ],
          if (_pendingApprovals > 0) ...[
            AppAlert(
              danger: false,
              icon: Icons.fact_check_outlined,
              message: '$_pendingApprovals erken aktarım isteği onayını bekliyor.',
            ),
            const SizedBox(height: AppTokens.gap),
          ],
          if ((session.user?.isSuperAdmin ?? false) && _stores.isNotEmpty) ...[
            _StoreSelector(
              stores: _stores,
              value: _storeId,
              onChanged: (v) {
                setState(() => _storeId = v);
                _load();
              },
            ),
            const SizedBox(height: AppTokens.gap),
          ],
          _StatGrid(counts: c, soldToday: data.soldToday),
          const SizedBox(height: AppTokens.gap),
          if (_summary != null) ...[
            _SummaryBlock(summary: _summary!),
            const SizedBox(height: AppTokens.gap),
          ],
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Son 7 Günlük Satış',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.ink)),
                const SizedBox(height: 14),
                MiniBarChart(
                  label: 'Satış Adedi',
                  values: _sales.map((e) => e.qty as num).toList(),
                  dates: _sales.map((e) => e.date).toList(),
                  barColor: t.primary,
                ),
                const SizedBox(height: 16),
                MiniBarChart(
                  label: 'Ciro (TL)',
                  values: _sales.map((e) => e.revenue).toList(),
                  dates: _sales.map((e) => e.date).toList(),
                  barColor: t.info,
                  showAsMoney: true,
                ),
                const SizedBox(height: 16),
                _StatusBreakdown(slices: _status),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.gap),
          if (_perf != null) _PerformanceBlock(
            perf: _perf!,
            monthly: _monthly,
            onPeriodChanged: (v) => setState(() => _monthly = v),
          ),
        ],
      ),
    );
  }
}

class _StoreSelector extends StatelessWidget {
  const _StoreSelector({required this.stores, required this.value, required this.onChanged});

  final List<StoreOption> stores;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.store_outlined, size: 18, color: context.tokens.muted),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                value: value,
                isExpanded: true,
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Tüm Mağazalar')),
                  ...stores.map((s) => DropdownMenuItem<int?>(value: s.id, child: Text(s.name))),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Alti kutucuk tek izgarada: hepsi ayni boyut, aralarindaki bosluk esit.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.counts, required this.soldToday});

  final DashboardCounts counts;
  final SoldToday soldToday;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width < 641 ? 2 : (width < 900 ? 3 : (width < 1200 ? 3 : 6));
    // Her kutu ilgili ekrani acar; stok kutulari Urunler/Stok'un dogru
    // sekmesine, satis kutulari bugune filtreli Hareket Raporu'na gider.
    final cards = <Widget>[
      StatCard(
        label: 'Donuk Depo', value: '${counts.frozenQty}', sub: '${counts.frozen} kayıt',
        icon: Icons.ac_unit, valueColor: t.info,
        onTap: () => context.go('/batches?tab=frozen'),
      ),
      StatCard(
        label: 'Çözülme', value: '${counts.thawingQty}', sub: '${counts.thawing} kayıt',
        icon: Icons.hourglass_bottom, valueColor: t.warning,
        onTap: () => context.go('/batches?tab=thawing'),
      ),
      StatCard(
        label: 'Food Dolabı', value: '${counts.cabinetQty}', sub: '${counts.cabinet} kayıt',
        icon: Icons.kitchen_outlined, valueColor: t.success,
        onTap: () => context.go('/batches?tab=food_cabinet'),
      ),
      StatCard(
        label: 'SKT Geçen', value: '${counts.expiredQty}', sub: 'imha edilmeli',
        icon: Icons.warning_amber_rounded, valueColor: t.danger,
        onTap: () => context.go('/recommendations'),
      ),
      StatCard(
        label: 'Bugün Satılan', value: '${soldToday.qty} adet',
        sub: '${fmtMoney(soldToday.revenue)} ciro', icon: Icons.payments_outlined,
        onTap: () => context.go('/sales?range=today&kind=sale'),
      ),
      StatCard(
        label: 'Bugünkü İşlem', value: '${soldToday.count}', sub: 'satış kaydı',
        icon: Icons.shopping_bag_outlined,
        onTap: () => context.go('/sales?range=today'),
      ),
    ];
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppTokens.gap,
      crossAxisSpacing: AppTokens.gap,
      childAspectRatio: width < 641 ? 1.55 : 1.45,
      children: cards,
    );
  }
}

class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (!summary.isMulti) {
      final width = MediaQuery.sizeOf(context).width;
      return GridView.count(
        crossAxisCount: width < 641 ? 2 : 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppTokens.gap,
        crossAxisSpacing: AppTokens.gap,
        childAspectRatio: width < 641 ? 1.55 : 1.8,
        children: [
          StatCard(
            label: summary.storeName ?? 'Mağaza', value: '${summary.soldQty} adet',
            sub: '${fmtMoney(summary.revenue)} ciro', icon: Icons.payments_outlined,
            onTap: () => context.go('/sales?kind=sale'),
          ),
          StatCard(
            label: 'İmha', value: '${summary.discardedQty}', sub: 'adet',
            icon: Icons.delete_outline, valueColor: t.danger,
            onTap: () => context.go('/sales?kind=discard'),
          ),
        ],
      );
    }
    // Coklu magaza tablosu genis ekranda yatay kaydirilabilir.
    return AppCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Mağaza')),
            DataColumn(label: Text('Donuk')),
            DataColumn(label: Text('Çözülme')),
            DataColumn(label: Text('Food Dolabı')),
            DataColumn(label: Text('Satılan')),
            DataColumn(label: Text('Ciro')),
            DataColumn(label: Text('İmha')),
          ],
          rows: summary.stores
              .map((s) => DataRow(cells: [
                    DataCell(Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                    DataCell(Text('${s.frozenQty}')),
                    DataCell(Text('${s.thawingQty}')),
                    DataCell(Text('${s.cabinetQty}')),
                    DataCell(Text('${s.soldQty} (${s.soldCount})')),
                    DataCell(Text(fmtMoney(s.revenue))),
                    DataCell(Text('${s.discardedQty}')),
                  ]))
              .toList(),
        ),
      ),
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.slices});

  final List<StatusSlice> slices;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (slices.isEmpty) {
      return Text('Veri bulunamadı', style: TextStyle(color: t.muted, fontSize: 13));
    }
    final max = slices.map((s) => s.quantity).reduce((a, b) => a > b ? a : b);
    const labels = {
      'frozen': 'Donuk Depo',
      'thawing': 'Çözülme',
      'food_cabinet': 'Food Dolabı',
      'sold': 'Satıldı',
      'ikram': 'İkram',
      'discarded': 'İmha',
    };
    // Cubuk rengi kalemi ayirt ettirir: aktif stok marka rengi, satis yesil,
    // ikram turuncu, imha kirmizi.
    Color toneFor(String status) => switch (status) {
          'sold' => t.success,
          'ikram' => t.warning,
          'discarded' => t.danger,
          _ => t.primary,
        };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Durum Dağılımı',
            style: TextStyle(color: t.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        // Donuk/cozulme/dolap anlik stok; satis, ikram ve imha ise toplam.
        Text('stok anlık · satış, ikram ve imha toplam',
            style: TextStyle(color: t.muted, fontSize: 11)),
        const SizedBox(height: 8),
        ...slices.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(labels[s.status] ?? s.status,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: t.ink)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: max == 0 ? 0 : (s.quantity / max).clamp(0.04, 1).toDouble(),
                        minHeight: 7,
                        backgroundColor: t.bg,
                        valueColor: AlwaysStoppedAnimation<Color>(toneFor(s.status)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${s.quantity}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.ink)),
                ],
              ),
            )),
      ],
    );
  }
}

class _PerformanceBlock extends StatelessWidget {
  const _PerformanceBlock({
    required this.perf,
    required this.monthly,
    required this.onPeriodChanged,
  });

  final ProductPerformance perf;
  final bool monthly;
  final ValueChanged<bool> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final width = MediaQuery.sizeOf(context).width;
    final p = monthly ? perf.month : perf.week;
    final lists = [
      RankList(title: 'En Çok Satan', icon: Icons.emoji_events_outlined, rows: p.best, tone: RankTone.up, emptyText: 'Bu dönemde satış yok'),
      RankList(title: 'En Az Satan', icon: Icons.trending_down, rows: p.worst, tone: RankTone.down, emptyText: 'Bu dönemde satış yok'),
      RankList(title: 'En Çok Zayi', icon: Icons.delete_outline, rows: p.topWasted, tone: RankTone.waste, emptyText: 'Bu dönemde zayi yok'),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  monthly ? 'Ürün Performansı — Son 30 Gün' : 'Ürün Performansı — Son 7 Gün',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.ink),
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(value: false, label: Text('Hafta')),
                  ButtonSegment<bool>(value: true, label: Text('Ay')),
                ],
                selected: {monthly},
                onSelectionChanged: (s) => onPeriodChanged(s.first),
                showSelectedIcon: false,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (width < 900)
            Column(
              children: [
                for (var i = 0; i < lists.length; i++) ...[
                  if (i > 0) const SizedBox(height: 18),
                  lists[i],
                ],
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < lists.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(child: lists[i]),
                ],
              ],
            ),
          const SizedBox(height: 12),
          Text(
            'Dönemde ${p.kinds} çeşitten toplam ${p.soldTotal} adet satıldı, ${p.wastedTotal} adet zayi verildi.'
            '${p.kinds > 0 && p.kinds <= 5 ? ' Satılan çeşit sayısı 5 veya altında olduğu için en çok ve en az satan listeleri aynı ürünleri içerir.' : ''}',
            style: TextStyle(fontSize: 12, color: t.muted),
          ),
        ],
      ),
    );
  }
}
