import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../core/new_theme.dart';
import '../models/dashboard.dart';
import '../models/movement.dart';
import '../models/product_type.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/panels.dart';
import 'movement_dialogs.dart';

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

/// Hareket raporu: satis, ikram ve zayi kayitlari tek listede; tarih, urun ve
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
  MovementReport _report = const MovementReport(
    items: [],
    totals: MovementTotals.empty,
  );
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
    final range = DateRange.values.where(
      (r) => r != DateRange.custom && r.name == widget.initialRange,
    );
    if (range.isNotEmpty) _range = range.first;
    if (movementKinds.contains(widget.initialKind)) {
      _kinds
        ..clear()
        ..add(widget.initialKind!);
    }
    _load();
    // Urun filtresi icin cesit listesi; hata verirse filtre gizli kalir.
    repo
        .productTypes(silent: true)
        .then((t) {
          if (mounted) setState(() => _types = t);
        })
        .onError((Object _, StackTrace _) {});
    if (_isSuper) {
      repo
          .stores(silent: true)
          .then((s) {
            if (mounted) setState(() => _stores = s);
          })
          .onError((Object _, StackTrace _) {});
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
        kinds: _kinds.length == movementKinds.length
            ? const []
            : _kinds.toList(),
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

  bool get _canAdjust => session.user?.can('adjust_batches') ?? false;

  Future<void> _correct(Movement m) async {
    final ok = await showMovementCorrectDialog(context, m);
    if (ok == true) await _load(silent: true);
  }

  /// Kayit silinince adedin tamami stoga doner; onay metni bunu yaziyor.
  Future<void> _remove(Movement m) async {
    final ok = await confirmDialog(
      context,
      title: '${m.kindLabel} Kaydını Sil',
      confirmLabel: 'Sil',
      body: Text(
        '${m.productName ?? 'Ürün'} — ${m.quantity} adet\n\n'
        'Kayıt silinecek ve ${m.quantity} adet stoka geri dönecek.',
      ),
    );
    if (ok != true) return;
    try {
      if (m.kind == 'discard') {
        await repo.deleteDiscard(m.id);
      } else {
        await repo.deleteSale(m.id);
      }
    } catch (_) {
      // Bildirim API katmanindan gelir.
    }
    await _load(silent: true);
  }

  Color _kindColor(String kind) => switch (kind) {
    'ikram' => NewTokens.secondaryFixed,
    'discard' => NewTokens.error,
    _ => NewTokens.secondary,
  };

  Widget _buildProgressRow(
    String label,
    String value,
    double percent,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: NewTokens.labelMd.copyWith(color: NewTokens.onSurface),
                ),
              ],
            ),
            Text(
              value,
              style: NewTokens.labelMd.copyWith(
                color: NewTokens.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: NewTokens.surfaceContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: percent / 100,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final totals = _report.totals;

    if (!_loaded) {
      return const Scaffold(
        backgroundColor: NewTokens.surface,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: NewTokens.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                style: NewTokens.bodyMd.copyWith(color: NewTokens.error),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: NewTokens.surface,
      appBar: AppBar(
        backgroundColor: NewTokens.surface.withValues(alpha: 0.85),
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        title: Row(
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
                    const SizedBox(width: 4),
                    Text(
                      'DÜZCE MERKEZ ŞUBE',
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Ana Sayfa',
                  style: NewTokens.headlineSm.copyWith(
                    color: NewTokens.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.notifications,
              color: NewTokens.onSurfaceVariant,
            ),
            onPressed: () {},
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
            child: const Icon(
              Icons.person,
              size: 18,
              color: NewTokens.onPrimary,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Intro
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FİNANS & OPERASYON',
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ciro Forecast & Satış Raporu',
                      style: NewTokens.headlineMd.copyWith(
                        color: NewTokens.onSurface,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: _pickCustomRange,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: NewTokens.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _rangeLabels[_range] ?? 'Tarih',
                          style: NewTokens.labelSm.copyWith(
                            color: NewTokens.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Aylık ciro tahmini, haftalık akış ve şube ürün analitiği',
              style: NewTokens.bodySm.copyWith(
                color: NewTokens.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Exports and toggles
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: NewTokens.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: NewTokens.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check,
                            size: 16,
                            color: NewTokens.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Haftalık Görünüm',
                            style: NewTokens.labelMd.copyWith(
                              color: NewTokens.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: Text(
                          'Aylık Konsolide',
                          style: NewTokens.labelMd.copyWith(
                            color: NewTokens.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.table_view,
                          size: 18,
                          color: NewTokens.tertiary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Excel İndir',
                          style: NewTokens.labelMd.copyWith(
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
                    height: 40,
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.picture_as_pdf,
                          size: 18,
                          color: NewTokens.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'PDF Raporu',
                          style: NewTokens.labelMd.copyWith(
                            color: NewTokens.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Ciro Forecast Hero Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NewTokens.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: NewTokens.secondaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.trending_up,
                              size: 20,
                              color: NewTokens.onSecondaryContainer,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ciro Forecast',
                                style: NewTokens.headlineSm.copyWith(
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
                        Icons.chevron_right,
                        size: 20,
                        color: NewTokens.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
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
                                fmtMoney(totals.revenue),
                                style: NewTokens.headlineMd.copyWith(
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
                          padding: const EdgeInsets.all(12),
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
                                style: NewTokens.headlineMd.copyWith(
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
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: NewTokens.secondaryContainer.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.insights,
                              size: 20,
                              color: NewTokens.secondary,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ay Sonu Ciro Tahmini',
                                  style: NewTokens.labelSm.copyWith(
                                    color: NewTokens.onSecondaryContainer,
                                  ),
                                ),
                                Text(
                                  'Veri Girişi Bekleniyor',
                                  style: NewTokens.labelMd.copyWith(
                                    color: NewTokens.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: NewTokens.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Hedef: 1.5M ₺',
                            style: NewTokens.labelSm.copyWith(
                              color: NewTokens.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Aylık Hedef Gerçekleşmesi',
                        style: NewTokens.labelSm.copyWith(
                          color: NewTokens.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '%0.0',
                        style: NewTokens.labelSm.copyWith(
                          color: NewTokens.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 10,
                        decoration: BoxDecoration(
                          color: NewTokens.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Petty Cash Mini Strip - Son 7 Gunluk Satis
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NewTokens.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            'Günlük adet & ciro (₺) performansı',
                            style: NewTokens.labelSm.copyWith(
                              color: NewTokens.onSurfaceVariant,
                            ),
                          ),
                        ],
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
                                '7 Günlük Toplam Ciro',
                                style: NewTokens.labelSm.copyWith(
                                  color: NewTokens.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                fmtMoney(totals.revenue),
                                style: NewTokens.headlineSm.copyWith(
                                  color: NewTokens.primary,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Toplam ${totals.saleQty} adet satış',
                                style: NewTokens.labelSm.copyWith(
                                  color: NewTokens.onSurfaceVariant,
                                  fontSize: 10,
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
                                'Günlük Ciro Ortalaması',
                                style: NewTokens.labelSm.copyWith(
                                  color: NewTokens.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '5.125,83 ₺',
                                style: NewTokens.headlineSm.copyWith(
                                  color: NewTokens.secondary,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Ort. 27 adet / gün',
                                style: NewTokens.labelSm.copyWith(
                                  color: NewTokens.tertiary,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 6-Metric Executive Operational Grid
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
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
                              'NET SALES',
                              style: NewTokens.labelSm.copyWith(
                                color: NewTokens.onSurfaceVariant,
                              ),
                            ),
                            const Icon(
                              Icons.point_of_sale,
                              size: 18,
                              color: NewTokens.primary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          fmtMoney(totals.revenue),
                          style: NewTokens.headlineSm.copyWith(
                            color: NewTokens.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${totals.count} Adisyon',
                          style: NewTokens.labelSm.copyWith(
                            color: NewTokens.tertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
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
                              'ORTALAMA FİŞ',
                              style: NewTokens.labelSm.copyWith(
                                color: NewTokens.onSurfaceVariant,
                              ),
                            ),
                            const Icon(
                              Icons.receipt_long,
                              size: 18,
                              color: NewTokens.secondary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '305,11 ₺',
                          style: NewTokens.headlineSm.copyWith(
                            color: NewTokens.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'IPT: 0.14',
                          style: NewTokens.labelSm.copyWith(
                            color: NewTokens.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
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
                              'SATILAN ÜRÜN',
                              style: NewTokens.labelSm.copyWith(
                                color: NewTokens.onSurfaceVariant,
                              ),
                            ),
                            const Icon(
                              Icons.inventory,
                              size: 18,
                              color: NewTokens.tertiary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${totals.saleQty} adet',
                          style: NewTokens.headlineSm.copyWith(
                            color: NewTokens.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '30 Adet İçecek',
                          style: NewTokens.labelSm.copyWith(
                            color: NewTokens.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
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
                              'İPTAL/ZAYİ',
                              style: NewTokens.labelSm.copyWith(
                                color: NewTokens.onSurfaceVariant,
                              ),
                            ),
                            const Icon(
                              Icons.delete,
                              size: 18,
                              color: NewTokens.error,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${totals.discardQty} adet',
                          style: NewTokens.headlineSm.copyWith(
                            color: NewTokens.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fmtMoney(totals.discardValue),
                          style: NewTokens.labelSm.copyWith(
                            color: NewTokens.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Inventory Flow Breakdown
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NewTokens.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Durum Dağılımı',
                            style: NewTokens.headlineSm.copyWith(
                              color: NewTokens.onSurface,
                            ),
                          ),
                          Text(
                            'Stok anlık · satış, ikram ve zayi toplamı',
                            style: NewTokens.labelSm.copyWith(
                              color: NewTokens.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const Icon(
                        Icons.donut_large,
                        size: 20,
                        color: NewTokens.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildProgressRow(
                    'Satıldı',
                    totals.saleQty.toString(),
                    35,
                    NewTokens.secondary,
                  ),
                  const SizedBox(height: 8),
                  _buildProgressRow(
                    'Zayi',
                    totals.discardQty.toString(),
                    10,
                    NewTokens.error,
                  ),
                  const SizedBox(height: 8),
                  _buildProgressRow(
                    'İkram',
                    totals.ikramQty.toString(),
                    5,
                    NewTokens.secondaryFixed,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Items list...
            ..._report.items.map(
              (m) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.productName ?? 'Ürün',
                            style: NewTokens.bodyMd.copyWith(
                              color: NewTokens.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _kindColor(m.kind)
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  m.kindLabel,
                                  style: NewTokens.labelSm.copyWith(
                                    color: _kindColor(m.kind),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${m.quantity} adet',
                                style: NewTokens.labelSm.copyWith(
                                  color: NewTokens.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Text(
                      m.total == null ? 'Fiyat yok' : fmtMoney(m.total),
                      style: NewTokens.labelMd.copyWith(
                        color: NewTokens.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
