import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/tokens.dart';
import '../models/manager_overview.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/panels.dart';
import '../widgets/search_field.dart';

/// Stok Yeterliligi: urun urun donuk depo stogu ve satis hizina gore kac gun
/// yetecegi. Ana sayfada cok yer kapladigi icin kendi modulu.
class StockCoverageScreen extends StatefulWidget {
  const StockCoverageScreen({super.key});

  @override
  State<StockCoverageScreen> createState() => _StockCoverageScreenState();
}

class _StockCoverageScreenState extends State<StockCoverageScreen> {
  StockCoverage _stock = StockCoverage.empty;
  final _search = TextEditingController();
  int _window = 14;
  String _query = '';
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final o = await repo.managerOverview(days: _window, silent: silent);
      if (!mounted) return;
      setState(() {
        _stock = o.stock;
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
    final t = context.tokens;
    final q = normalizeSearch(_query);
    final items = q.isEmpty
        ? _stock.items
        : _stock.items.where((i) => normalizeSearch(i.name).contains(q)).toList();

    // Satis hizi olanlar once; satmayanlar yeterlilik hesaplanamadigi icin
    // ayri bolumde toplanir.
    final active = items.where((i) => i.daysOfCover != null).toList();
    final idle = items.where((i) => i.daysOfCover == null).toList();

    final critical = _stock.items.where((i) => i.risk == 0 || i.risk == 1).length;

    return CrudScaffold(
      title: 'Stok Yeterliliği',
      loaded: _loaded,
      error: _error,
      onRetry: () => _load(),
      onRefresh: () => _load(silent: true),
      emptyText: 'Bu mağazada aktif stok veya satış kaydı yok.',
      banner: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (critical > 0) ...[
            AppAlert(
              message: '$critical çeşidin donuk deposu 3 günden az yetecek '
                  'veya tükendi. Sipariş verilmesi gerekebilir.',
            ),
            const SizedBox(height: AppTokens.gap),
          ],
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Satış hızı penceresi',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.ink)),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7 gün')),
                    ButtonSegment(value: 14, label: Text('14 gün')),
                    ButtonSegment(value: 30, label: Text('30 gün')),
                  ],
                  selected: {_window},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) {
                    setState(() => _window = v.first);
                    _load(silent: true);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Son ${_stock.windowDays} günün satış adedinden günlük hız '
                  'bulunur, donuk depodaki adet buna bölünür.',
                  style: TextStyle(fontSize: 12, color: t.muted),
                ),
                const SizedBox(height: 10),
                ProductSearchField(
                  controller: _search,
                  filtering: _query.isNotEmpty,
                  onChanged: (v) => setState(() => _query = v),
                  onClear: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      children: [
        ...active.map((i) => _CoverageCard(item: i)),
        if (idle.isNotEmpty) ...[
          const SizedBox(height: 4),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Satış hareketi olmayan ${idle.length} çeşit',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.ink)),
                const SizedBox(height: 4),
                Text('Satış hızı sıfır olduğu için yeterlilik hesaplanamaz.',
                    style: TextStyle(fontSize: 12, color: t.muted)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: idle
                      .map((i) => Pill(
                            text: '${i.name} · ${fmtInt(i.frozenQty)} adet',
                            color: t.muted,
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CoverageCard extends StatelessWidget {
  const _CoverageCard({required this.item});

  final StockCoverageItem item;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cover = item.daysOfCover;
    final color = switch (item.risk) {
      0 || 1 => t.danger,
      2 => t.warning,
      _ => t.success,
    };
    final label = switch (item.risk) {
      0 => 'Stok yok',
      1 => 'Kritik',
      2 => 'Azalıyor',
      _ => 'Yeterli',
    };
    final coverText = cover == null
        ? '-'
        : cover < 1
            ? 'bugün biter'
            : '${cover.toStringAsFixed(cover < 10 ? 1 : 0)} gün';

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.name,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.ink)),
              ),
              const SizedBox(width: 8),
              Pill(text: label, color: color),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Cell(label: 'Donuk depo', value: fmtInt(item.frozenQty), strong: true)),
              Expanded(child: _Cell(label: 'Çözülen', value: fmtInt(item.thawingQty))),
              Expanded(child: _Cell(label: 'Food dolabı', value: fmtInt(item.cabinetQty))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Cell(
                  label: 'Satış hızı',
                  value: '${item.dailyVelocity.toStringAsFixed(2)}/gün',
                ),
              ),
              Expanded(
                child: _Cell(label: 'Yeterlilik', value: coverText, color: color, strong: true),
              ),
              Expanded(
                child: _Cell(
                  label: 'Biteceği gün',
                  value: item.depletionDate == null ? '-' : fmtDate(item.depletionDate),
                ),
              ),
            ],
          ),
          if (item.frozenValue != null) ...[
            const SizedBox(height: 8),
            Text(
              'Donuk depodaki tutar ${fmtMoney(item.frozenValue)} · '
              'son ${item.soldQty} adet satıldı',
              style: TextStyle(fontSize: 11, color: t.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.value,
    this.color,
    this.strong = false,
  });

  final String label;
  final String value;
  final Color? color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: t.muted)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
              fontSize: strong ? 15 : 14,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: color ?? t.ink,
            )),
      ],
    );
  }
}
