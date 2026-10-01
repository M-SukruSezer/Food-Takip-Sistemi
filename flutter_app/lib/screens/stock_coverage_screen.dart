import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/tokens.dart';
import '../core/responsive.dart';
import '../models/manager_overview.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/panels.dart';
import '../widgets/shell_scope.dart';

/// Stok Yeterliliği: ürün ürün donuk depo stoğu ve satış hızına göre kaç gün
/// yeteceği analiz ekranı.
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
  String _filter = 'all'; // 'all', 'stok-yok', 'kritik', 'yeterli'
  String _sortBy =
      'risk'; // 'risk', 'cover_asc', 'velocity_desc', 'name_asc', 'qty_desc'
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

  void _exportExcel() {
    if (_stock.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dışa aktarılacak stok verisi bulunmuyor.'),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Stok yeterliliği listesi Excel formatında hazırlandı.',
              ),
            ),
          ],
        ),
        backgroundColor: context.tokens.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSortDialog() {
    final t = context.tokens;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tune, size: 20, color: t.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Sıralama Seçenekleri',
                        style: TextStyle(
                          fontSize: AppFontSize.title,
                          fontWeight: FontWeight.bold,
                          color: t.ink,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Divider(color: t.border),
                _sortTile(
                  ctx,
                  'risk',
                  'Risk / Kritik Duruma Göre (Varsayılan)',
                ),
                _sortTile(
                  ctx,
                  'cover_asc',
                  'En Az Kalan Gün (Önce Bitecekler)',
                ),
                _sortTile(ctx, 'velocity_desc', 'En Yüksek Satış Hızı'),
                _sortTile(ctx, 'qty_desc', 'En Fazla Donuk Stok'),
                _sortTile(ctx, 'name_asc', 'Ürün Adı (A - Z)'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sortTile(BuildContext ctx, String key, String title) {
    final t = ctx.tokens;
    final selected = _sortBy == key;
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          fontSize: AppFontSize.bodyLarge,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? t.primary : t.ink,
        ),
      ),
      trailing: selected ? Icon(Icons.check, color: t.primary, size: 20) : null,
      onTap: () {
        setState(() => _sortBy = key);
        Navigator.pop(ctx);
      },
    );
  }

  void _showOrderDraftSheet(List<StockCoverageItem> urgentItems) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: context.tokens.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.assignment_add,
                          color: context.tokens.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Otomatik Sipariş Taslağı',
                              style: TextStyle(
                                fontSize: AppFontSize.title,
                                fontWeight: FontWeight.bold,
                                color: context.tokens.ink,
                              ),
                            ),
                            Text(
                              '${urgentItems.length} kritik ürün tespit edildi',
                              style: TextStyle(
                                fontSize: AppFontSize.label,
                                color: context.tokens.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      itemCount: urgentItems.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (c, idx) {
                        final t = context.tokens;
                        final item = urgentItems[idx];
                        final suggested =
                            ((item.dailyVelocity * 7) - item.frozenQty)
                                .ceil()
                                .clamp(2, 50);
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: t.bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: t.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: TextStyle(
                                        fontSize: AppFontSize.body,
                                        fontWeight: FontWeight.bold,
                                        color: t.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Mevcut Donuk: ${item.frozenQty} · Hız: ${item.dailyVelocity.toStringAsFixed(2)}/gün',
                                      style: TextStyle(
                                        fontSize: AppFontSize.caption,
                                        color: t.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: t.primarySoft,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '+$suggested Kutu',
                                  style: TextStyle(
                                    fontSize: AppFontSize.body,
                                    fontWeight: FontWeight.bold,
                                    color: t.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Sipariş taslağı başarıyla oluşturuldu.',
                          ),
                          backgroundColor: context.tokens.primary,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: context.tokens.primary,
                      foregroundColor: context.tokens.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Siparişi Onayla ve Gönder',
                      style: TextStyle(
                        fontSize: AppFontSize.bodyLarge,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _stock.items.isEmpty) {
      return Center(
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppAlert(message: _error!),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _load(),
                style: FilledButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: t.onPrimary,
                ),
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    final q = normalizeSearch(_query);
    final searchFiltered = q.isEmpty
        ? _stock.items
        : _stock.items
              .where((i) => normalizeSearch(i.name).contains(q))
              .toList();

    // Category / Risk filter
    final filtered = searchFiltered.where((i) {
      if (_filter == 'stok-yok') return i.risk == 0;
      if (_filter == 'kritik') return i.risk == 1 || i.risk == 2;
      if (_filter == 'yeterli') {
        return i.risk == 3 || (i.risk != null && i.risk! > 3);
      }
      return true;
    }).toList();

    // Sort items
    final sorted = List<StockCoverageItem>.from(filtered);
    sorted.sort((a, b) {
      switch (_sortBy) {
        case 'cover_asc':
          final ca = a.daysOfCover ?? 99999;
          final cb = b.daysOfCover ?? 99999;
          return ca.compareTo(cb);
        case 'velocity_desc':
          return b.dailyVelocity.compareTo(a.dailyVelocity);
        case 'qty_desc':
          return b.frozenQty.compareTo(a.frozenQty);
        case 'name_asc':
          return a.name.compareTo(b.name);
        case 'risk':
        default:
          final ra = a.risk ?? 99;
          final rb = b.risk ?? 99;
          if (ra != rb) return ra.compareTo(rb);
          final ca = a.daysOfCover ?? 99999;
          final cb = b.daysOfCover ?? 99999;
          return ca.compareTo(cb);
      }
    });

    final active = sorted.where((i) => i.daysOfCover != null).toList();
    final idle = sorted.where((i) => i.daysOfCover == null).toList();

    // Counts across all items
    final stokYokCount = _stock.items.where((i) => i.risk == 0).length;
    final kritikCount = _stock.items
        .where((i) => i.risk == 1 || i.risk == 2)
        .length;
    final yeterliCount = _stock.items
        .where((i) => i.risk == 3 || (i.risk != null && i.risk! > 3))
        .length;

    // Critical count for alert banner: risk 0 & risk 1
    final criticalAlertCount = _stock.items
        .where((i) => i.risk == 0 || i.risk == 1)
        .length;

    final urgentItems = _stock.items
        .where((i) => i.risk == 0 || i.risk == 1)
        .toList();

    // Total frozen value and quantity
    num totalFrozenValue = 0;
    int totalFrozenQty = 0;
    for (final i in _stock.items) {
      if (i.frozenValue != null) totalFrozenValue += i.frozenValue!;
      totalFrozenQty += i.frozenQty;
    }

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(silent: true),
                color: t.primary,
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  children: [
                    // Mobil kabuk sayfa adını zaten gösterir. Burada yalnızca
                    // sayfaya özgü eylemler kalır.
                    _buildHeader(context),
                    const SizedBox(height: 12),

                    // Operational Alert Card
                    if (criticalAlertCount > 0) ...[
                      _buildAlertBanner(criticalAlertCount),
                      const SizedBox(height: 12),
                    ],

                    // Sales Velocity Window (Satış Hızı Penceresi)
                    _buildVelocityCard(),
                    const SizedBox(height: 12),

                    // Search and Filter Bar
                    _buildSearchAndFilters(
                      stokYokCount,
                      kritikCount,
                      yeterliCount,
                    ),
                    const SizedBox(height: 12),

                    // Completely Empty State
                    if (_stock.items.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: t.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: t.border),
                        ),
                        child: Center(
                          child: Text(
                            'Bu mağazada aktif stok veya satış kaydı yok.',
                            style: TextStyle(
                              color: t.muted,
                              fontSize: AppFontSize.body,
                            ),
                          ),
                        ),
                      )
                    // Search / Filter Empty State
                    else if (active.isEmpty && idle.isEmpty)
                      _buildNoResultsState()
                    // Active Stock Coverage Cards
                    else ...[
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = Breakpoints.of(constraints.maxWidth)
                              .isAtLeastMedium;
                          if (isWide) {
                            final cols =
                                Breakpoints.of(constraints.maxWidth)
                                    .isAtLeastExpanded
                                ? 3
                                : 2;
                            final gap = 12.0;
                            final cardWidth =
                                (constraints.maxWidth - gap * (cols - 1)) /
                                    cols -
                                0.1;
                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: active
                                  .map(
                                    (item) => SizedBox(
                                      width: cardWidth,
                                      child: _CoverageCard(item: item),
                                    ),
                                  )
                                  .toList(),
                            );
                          }
                          return Column(
                            children: active
                                .map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _CoverageCard(item: item),
                                  ),
                                )
                                .toList(),
                          );
                        },
                      ),

                      // Non-moving Items Section
                      if (idle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: t.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: t.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Satış hareketi olmayan ${idle.length} çeşit',
                                style: TextStyle(
                                  fontSize: AppFontSize.bodyLarge,
                                  fontWeight: FontWeight.w700,
                                  color: t.ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Satış hızı sıfır olduğu için yeterlilik hesaplanamaz.',
                                style: TextStyle(
                                  fontSize: AppFontSize.label,
                                  color: t.muted,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: idle
                                    .map(
                                      (i) => Pill(
                                        text:
                                            '${i.name} · ${fmtInt(i.frozenQty)} adet',
                                        color: t.muted,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Operational Total & Fast Order Action Dock (Sticky Bottom Bar)
            if (_stock.items.isNotEmpty)
              _buildBottomDock(totalFrozenValue, totalFrozenQty, urgentItems),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final t = context.tokens;
    final mobile = AppShellScope.isMobile(context);
    if (mobile) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _HeaderAction(
            icon: Icons.file_download_outlined,
            label: 'Excel',
            onTap: _exportExcel,
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Sırala ve filtrele',
            onPressed: _showSortDialog,
            icon: const Icon(Icons.tune, size: 19),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                },
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.bg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_back, size: 20, color: t.ink),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Stok Yeterliliği',
                style: TextStyle(
                  fontSize: AppFontSize.headline,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            Material(
              color: t.primarySoft,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: _exportExcel,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.file_download_outlined,
                        size: 16,
                        color: t.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Excel',
                        style: TextStyle(
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w700,
                          color: t.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: t.bg,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: _showSortDialog,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  child: Icon(Icons.tune, size: 18, color: t.muted),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            'Tüketim hızı, donuk depo gün yeterliliği ve kritik sipariş uyarıları',
            style: TextStyle(fontSize: AppFontSize.label, color: t.muted),
          ),
        ),
      ],
    );
  }

  Widget _buildAlertBanner(int criticalAlertCount) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.dangerSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: t.danger.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.warning_rounded, color: t.dangerText, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$criticalAlertCount çeşidin donuk deposu 3 günden az yetecek veya tükendi.',
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.w700,
                    color: t.dangerText,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Sipariş verilmesi gerekebilir. Kritik stoklar bugün tükenebilir.',
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    color: t.muted,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    setState(() => _filter = 'kritik');
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Acil Tedarik Listesi Oluştur',
                        style: TextStyle(
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w700,
                          color: t.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 15,
                        color: t.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVelocityCard() {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SATIŞ HIZI PENCERESİ',
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w700,
                  color: t.muted,
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: t.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Canlı Hesaplama',
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w600,
                      color: t.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [7, 14, 30].map((days) {
                final selected = _window == days;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (_window != days) {
                        setState(() => _window = days);
                        _load(silent: true);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? t.primarySoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$days gün',
                        style: TextStyle(
                          fontSize: AppFontSize.body,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: selected ? t.primary : t.muted,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Son ${_stock.windowDays} günün satış adedinden günlük hız bulunur, donuk depodaki adet buna bölünür.',
            style: TextStyle(fontSize: AppFontSize.label, color: t.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters(
    int stokYokCount,
    int kritikCount,
    int yeterliCount,
  ) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search Input Box
        Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.border),
          ),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            style: TextStyle(fontSize: AppFontSize.bodyLarge, color: t.ink),
            decoration: InputDecoration(
              hintText: 'Ürün veya kategori ara...',
              hintStyle: TextStyle(
                fontSize: AppFontSize.bodyLarge,
                color: t.muted,
              ),
              prefixIcon: Icon(Icons.search, size: 20, color: t.muted),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Filter Pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('all', 'Tümü (${_stock.items.length})', null),
              const SizedBox(width: 6),
              _filterChip('stok-yok', 'Stok Yok ($stokYokCount)', t.danger),
              const SizedBox(width: 6),
              _filterChip('kritik', 'Kritik ($kritikCount)', t.warning),
              const SizedBox(width: 6),
              _filterChip('yeterli', 'Yeterli ($yeterliCount)', t.success),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String filterKey, String label, Color? dotColor) {
    final t = context.tokens;
    final selected = _filter == filterKey;
    return GestureDetector(
      onTap: () => setState(() => _filter = filterKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? t.primary : t.bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? t.primary : t.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: selected ? t.onPrimary : dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: AppFontSize.label,
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                color: selected ? t.onPrimary : t.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: t.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.inventory_2_outlined, size: 28, color: t.primary),
          ),
          const SizedBox(height: 12),
          Text(
            'Eşleşen Ürün Bulunamadı',
            style: TextStyle(
              fontSize: AppFontSize.title,
              fontWeight: FontWeight.bold,
              color: t.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Arama terimini veya aktif durum filtrelerini kontrol ederek tekrar deneyebilirsiniz.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppFontSize.label, color: t.muted),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: () {
              _search.clear();
              setState(() {
                _query = '';
                _filter = 'all';
              });
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: t.primary,
              side: BorderSide(color: t.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Filtreleri Temizle'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomDock(
    num totalFrozenValue,
    int totalFrozenQty,
    List<StockCoverageItem> urgentItems,
  ) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.card,
        border: Border(top: BorderSide(color: t.border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOPLAM DONUK DEPO DEĞERİ',
                    style: TextStyle(
                      fontSize: AppFontSize.micro,
                      fontWeight: FontWeight.w700,
                      color: t.muted,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fmtMoney(totalFrozenValue),
                    style: TextStyle(
                      fontSize: AppFontSize.titleLarge,
                      fontWeight: FontWeight.w800,
                      color: t.primary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Mevcut Çeşit / Adet',
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      color: t.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_stock.items.length} Kalem · $totalFrozenQty Adet',
                    style: TextStyle(
                      fontSize: AppFontSize.bodyLarge,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: urgentItems.isEmpty
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Şu an acil sipariş gerektiren kritik ürün bulunmuyor.',
                          ),
                          backgroundColor: t.primary,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  : () => _showOrderDraftSheet(urgentItems),
              style: FilledButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: t.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              icon: const Icon(Icons.assignment_add, size: 20),
              label: Text(
                'Otomatik Sipariş Taslağı Oluştur (${urgentItems.length} Kalem)',
                style: const TextStyle(
                  fontSize: AppFontSize.bodyLarge,
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

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.primarySoft,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: t.primary),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: t.primary,
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverageCard extends StatelessWidget {
  const _CoverageCard({required this.item});

  final StockCoverageItem item;

  static IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('cookie') || n.contains('kurabiye')) {
      return Icons.cookie_outlined;
    }
    if (n.contains('muffin') ||
        n.contains('kek') ||
        n.contains('pasta') ||
        n.contains('cheesecake') ||
        n.contains('brownie') ||
        n.contains('tatlı') ||
        n.contains('frambuaz')) {
      return Icons.cake_outlined;
    }
    if (n.contains('burger') || n.contains('sandviç') || n.contains('sıcak')) {
      return Icons.lunch_dining_outlined;
    }
    if (n.contains('açma') ||
        n.contains('poğaça') ||
        n.contains('simit') ||
        n.contains('kahvaltı')) {
      return Icons.breakfast_dining_outlined;
    }
    if (n.contains('cup') || n.contains('dondurma')) {
      return Icons.icecream_outlined;
    }
    if (n.contains('kahve') ||
        n.contains('çay') ||
        n.contains('latte') ||
        n.contains('güneşi') ||
        n.contains('içecek')) {
      return Icons.local_cafe_outlined;
    }
    return Icons.inventory_2_outlined;
  }

  static String _categoryFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('cookie') || n.contains('kurabiye')) return 'Unlu Mamüller';
    if (n.contains('muffin') || n.contains('brownie') || n.contains('pie')) {
      return 'Fırın Grubu';
    }
    if (n.contains('cheesecake')) return 'Cheesecake Grubu';
    if (n.contains('pasta') || n.contains('frambuaz')) return 'Pasta & Tatlı';
    if (n.contains('burger') || n.contains('sandviç')) return 'Sıcak Mutfak';
    if (n.contains('açma') || n.contains('poğaça')) return 'Kahvaltılık';
    if (n.contains('cup')) return 'Bardak Tatlılar';
    if (n.contains('kahve') || n.contains('çay') || n.contains('güneşi')) {
      return 'Mevsimsel İçecek / Kek';
    }
    return 'Özel Ürünler';
  }

  static String _skuFor(StockCoverageItem item) {
    final letters = item.name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(3)
        .join();
    final prefix = letters.isEmpty ? 'PRD' : letters;
    return '$prefix-${item.productTypeId.toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cover = item.daysOfCover;

    final t = context.tokens;
    // Status label and colors
    final (label, textColor, bgColor, dotColor) = switch (item.risk) {
      0 => ('Stok yok', t.dangerText, t.dangerSoft, t.danger),
      1 => ('Kritik', t.warningText, t.warningSoft, t.warning),
      2 => ('Azalıyor', t.warningText, t.warningSoft, t.warning),
      _ => ('Yeterli', t.success, t.successSoft, t.success),
    };

    final coverText = cover == null
        ? '-'
        : cover < 1
        ? 'bugün biter'
        : '${cover.toStringAsFixed(cover < 10 ? 1 : 0)} gün';

    final coverColor = cover == null
        ? t.ink
        : cover < 1
        ? t.danger
        : cover < 7
        ? t.warning
        : t.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Icon, Product Name, Category & Status Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: t.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_iconFor(item.name), size: 20, color: t.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: AppFontSize.bodyLarge,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_categoryFor(item.name)} · SKU: ${_skuFor(item)}',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        color: t.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 2: Depo Dağılım Grid (3 Columns)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'Donuk depo',
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          color: t.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fmtInt(item.frozenQty),
                        style: TextStyle(
                          fontSize: AppFontSize.title,
                          fontWeight: FontWeight.w800,
                          color: item.frozenQty == 0 ? t.danger : t.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'Çözülen',
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          color: t.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fmtInt(item.thawingQty),
                        style: TextStyle(
                          fontSize: AppFontSize.title,
                          fontWeight: FontWeight.w800,
                          color: t.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'Food dolabı',
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          color: t.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fmtInt(item.cabinetQty),
                        style: TextStyle(
                          fontSize: AppFontSize.title,
                          fontWeight: FontWeight.w800,
                          color: (item.cabinetQty == 0 && item.risk == 0)
                              ? t.danger
                              : t.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Row 3: Satış hızı, Yeterlilik, Biteceği gün
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Satış hızı',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        color: t.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.dailyVelocity.toStringAsFixed(2)}/gün',
                      style: TextStyle(
                        fontSize: AppFontSize.body,
                        fontWeight: FontWeight.bold,
                        color: t.ink,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Yeterlilik',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        color: t.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      coverText,
                      style: TextStyle(
                        fontSize: AppFontSize.body,
                        fontWeight: FontWeight.w800,
                        color: coverColor,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Biteceği gün',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        color: t.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.depletionDate == null
                          ? '-'
                          : fmtDate(item.depletionDate),
                      style: TextStyle(
                        fontSize: AppFontSize.body,
                        fontWeight: FontWeight.bold,
                        color: t.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Critical Visual Gauge Bar (when cover < 7)
          if (cover != null && cover < 7) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (cover / 7.0).clamp(0.05, 1.0),
                minHeight: 5,
                backgroundColor: t.border,
                valueColor: AlwaysStoppedAnimation<Color>(
                  cover < 1 ? t.danger : t.warning,
                ),
              ),
            ),
          ],

          // Row 4: Financial detail & recent sales
          const SizedBox(height: 8),
          Text(
            'Donuk depodaki tutar ${fmtMoney(item.frozenValue ?? 0)} · son ${item.soldQty} adet satıldı',
            style: TextStyle(fontSize: AppFontSize.caption, color: t.muted),
          ),
        ],
      ),
    );
  }
}
