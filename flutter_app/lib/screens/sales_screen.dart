import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/dashboard.dart';
import '../models/movement.dart';
import '../models/product_type.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/panels.dart';

/// Hazir tarih araliklari. "Tümü" filtre gondermez, sunucu son 1000 hareketi
/// doner.
enum DateRange { today, week, month, all, custom }

const _rangeLabels = {
  DateRange.today: 'Bugün',
  DateRange.week: 'Son 7 gün',
  DateRange.month: 'Son 30 gün',
  DateRange.all: 'Tümü',
  DateRange.custom: 'Özel aralık',
};

/// Hareket raporu: satis, ikram ve imha kayitlari tek listede; tarih, urun ve
/// tur filtreleriyle suzulur.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key, this.initialRange, this.initialKind});

  /// Ana sayfadaki ozet kutularindan gelen filtreler. Taninmayan degerler
  /// yok sayilir, ekran varsayilanlariyla acilir.
  final String? initialRange;
  final String? initialKind;

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  MovementReport _report = const MovementReport(items: [], totals: MovementTotals.empty);
  List<StoreOption> _stores = const [];
  List<ProductType> _types = const [];

  DateRange _range = DateRange.month;
  DateTimeRange? _custom;
  int? _productTypeId;
  final Set<String> _kinds = {...movementKinds};
  int? _storeId;

  String? _error;
  bool _loaded = false;

  bool get _isSuper => session.user?.isSuperAdmin ?? false;

  @override
  void initState() {
    super.initState();
    final range = DateRange.values
        .where((r) => r != DateRange.custom && r.name == widget.initialRange);
    if (range.isNotEmpty) _range = range.first;
    if (movementKinds.contains(widget.initialKind)) {
      _kinds
        ..clear()
        ..add(widget.initialKind!);
    }
    _load();
    // Urun filtresi icin cesit listesi; hata verirse filtre gizli kalir.
    repo.productTypes(silent: true).then((t) {
      if (mounted) setState(() => _types = t);
    }).onError((Object _, StackTrace _) {});
    if (_isSuper) {
      repo.stores(silent: true).then((s) {
        if (mounted) setState(() => _stores = s);
      }).onError((Object _, StackTrace _) {});
    }
  }

  /// Secili aralik: (baslangic, bitis). Tumu icin ikisi de null.
  (DateTime?, DateTime?) get _bounds {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_range) {
      DateRange.today => (today, today),
      DateRange.week => (today.subtract(const Duration(days: 6)), today),
      DateRange.month => (today.subtract(const Duration(days: 29)), today),
      DateRange.all => (null, null),
      DateRange.custom => (_custom?.start, _custom?.end),
    };
  }

  Future<void> _load({bool silent = false}) async {
    final (from, to) = _bounds;
    try {
      final report = await repo.movements(
        from: from,
        to: to,
        productTypeId: _productTypeId,
        // Hepsi seciliyse parametre gonderilmez.
        kinds: _kinds.length == movementKinds.length ? const [] : _kinds.toList(),
        storeId: _storeId,
        silent: silent,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
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

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _custom,
      locale: const Locale('tr', 'TR'),
    );
    if (picked == null) return;
    setState(() {
      _custom = picked;
      _range = DateRange.custom;
    });
    await _load(silent: true);
  }

  void _toggleKind(String kind, bool on) {
    setState(() {
      if (on) {
        _kinds.add(kind);
      } else {
        // En az bir tur secili kalmali; hepsi kapaliyken liste anlamsiz olur.
        if (_kinds.length > 1) _kinds.remove(kind);
      }
    });
    _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final totals = _report.totals;
    final narrow = MediaQuery.sizeOf(context).width < 641;

    return CrudScaffold(
      title: 'Hareket Raporu',
      loaded: _loaded,
      error: _error,
      onRetry: () => _load(),
      onRefresh: () => _load(silent: true),
      emptyText: 'Seçtiğiniz filtrelerde hareket bulunamadı.',
      banner: Column(
        children: [
          _FilterCard(
            range: _range,
            custom: _custom,
            onRange: (r) {
              if (r == DateRange.custom) {
                _pickCustomRange();
                return;
              }
              setState(() => _range = r);
              _load(silent: true);
            },
            onPickCustom: _pickCustomRange,
            types: _types,
            productTypeId: _productTypeId,
            onProductType: (id) {
              setState(() => _productTypeId = id);
              _load(silent: true);
            },
            kinds: _kinds,
            onKind: _toggleKind,
            stores: _isSuper ? _stores : const [],
            storeId: _storeId,
            onStore: (id) {
              setState(() => _storeId = id);
              _load(silent: true);
            },
          ),
          const SizedBox(height: AppTokens.gap),
          _TotalsGrid(
            narrow: narrow,
            children: [
              StatCard(
                label: 'Satış Adedi',
                value: fmtInt(totals.saleQty),
                sub: '${totals.count} hareket',
              ),
              StatCard(
                label: 'Ciro',
                value: fmtMoney(totals.revenue),
                sub: 'yalnızca satışlar',
              ),
              StatCard(
                label: 'İkram Edilen',
                value: fmtInt(totals.ikramQty),
                sub: 'değeri ${fmtMoney(totals.ikramValue)}',
              ),
              StatCard(
                label: 'İmha Edilen',
                value: fmtInt(totals.discardQty),
                sub: 'değeri ${fmtMoney(totals.discardValue)}',
              ),
            ],
          ),
        ],
      ),
      children: _report.items
          .map((m) => AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(m.productName ?? 'Ürün',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700, color: t.ink)),
                        ),
                        Text(
                          m.total == null ? 'Fiyat yok' : fmtMoney(m.total),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: m.total == null ? t.muted : _kindColor(m.kind, t),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Pill(text: m.kindLabel, color: _kindColor(m.kind, t)),
                        Pill(text: '${m.quantity} adet', color: t.info),
                        if (m.unitPrice != null)
                          Pill(
                            // Imhada fiyat anlik goruntu degil, guncel fiyat.
                            text: m.priceIsCurrent
                                ? 'güncel birim ${fmtMoney(m.unitPrice)}'
                                : 'birim ${fmtMoney(m.unitPrice)}',
                            color: t.warning,
                          ),
                        if (_isSuper && m.storeName != null)
                          Pill(text: m.storeName!, color: t.primary),
                      ],
                    ),
                    if (m.reason?.isNotEmpty == true) ...[
                      const SizedBox(height: 6),
                      Text(m.reason!, style: TextStyle(fontSize: 13, color: t.ink)),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${fmtDateTime(m.at)} · ${m.userName ?? 'bilinmiyor'}',
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Color _kindColor(String kind, AppTokens t) => switch (kind) {
        'ikram' => t.warning,
        'discard' => t.danger,
        _ => t.success,
      };
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.range,
    required this.custom,
    required this.onRange,
    required this.onPickCustom,
    required this.types,
    required this.productTypeId,
    required this.onProductType,
    required this.kinds,
    required this.onKind,
    required this.stores,
    required this.storeId,
    required this.onStore,
  });

  final DateRange range;
  final DateTimeRange? custom;
  final ValueChanged<DateRange> onRange;
  final VoidCallback onPickCustom;
  final List<ProductType> types;
  final int? productTypeId;
  final ValueChanged<int?> onProductType;
  final Set<String> kinds;
  final void Function(String kind, bool on) onKind;
  final List<StoreOption> stores;
  final int? storeId;
  final ValueChanged<int?> onStore;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Tarih', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.ink)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: DateRange.values.map((r) {
              final selected = range == r;
              final label = r == DateRange.custom && custom != null
                  ? '${fmtDate(custom!.start.toIso8601String())} – ${fmtDate(custom!.end.toIso8601String())}'
                  : _rangeLabels[r]!;
              return ChoiceChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) => r == DateRange.custom ? onPickCustom() : onRange(r),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text('Hareket Türü',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.ink)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: movementKinds.map((kind) {
              final selected = kinds.contains(kind);
              return FilterChip(
                label: Text(movementKindLabels[kind]!),
                selected: selected,
                onSelected: (on) => onKind(kind, on),
              );
            }).toList(),
          ),
          if (types.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: productTypeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ürün'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Tüm ürünler')),
                ...types.map((x) => DropdownMenuItem<int?>(value: x.id, child: Text(x.name))),
              ],
              onChanged: onProductType,
            ),
          ],
          if (stores.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: storeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Mağaza'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Tüm Mağazalar')),
                ...stores.map((s) => DropdownMenuItem<int?>(value: s.id, child: Text(s.name))),
              ],
              onChanged: onStore,
            ),
          ],
        ],
      ),
    );
  }
}

/// Dort ozet kutusu: telefonda 2x2, genis ekranda tek sirada dort.
/// IntrinsicHeight ayni satirdaki kutulari esitler, icerik kesilmez.
class _TotalsGrid extends StatelessWidget {
  const _TotalsGrid({required this.narrow, required this.children});

  final bool narrow;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final columns = narrow ? 2 : 4;
    return Column(
      children: [
        for (var start = 0; start < children.length; start += columns) ...[
          if (start > 0) const SizedBox(height: AppTokens.gap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var col = 0; col < columns; col++) ...[
                  if (col > 0) const SizedBox(width: AppTokens.gap),
                  Expanded(
                    child: start + col < children.length
                        ? children[start + col]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
