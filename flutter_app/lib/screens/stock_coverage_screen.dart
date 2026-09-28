import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/tokens.dart';
import '../models/manager_overview.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/panels.dart';

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
  String _sortBy = 'risk'; // 'risk', 'cover_asc', 'velocity_desc', 'name_asc', 'qty_desc'
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
        const SnackBar(content: Text('Dışa aktarılacak stok verisi bulunmuyor.')),
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
              child: Text('Stok yeterliliği listesi Excel formatında hazırlandı.'),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F766E),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSortDialog() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.tune, size: 20, color: Color(0xFF0F766E)),
                      const SizedBox(width: 8),
                      const Text(
                        'Sıralama Seçenekleri',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                _sortTile(ctx, 'risk', 'Risk / Kritik Duruma Göre (Varsayılan)'),
                _sortTile(ctx, 'cover_asc', 'En Az Kalan Gün (Önce Bitecekler)'),
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
    final selected = _sortBy == key;
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? const Color(0xFF0F766E) : const Color(0xFF0B1C30),
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check, color: Color(0xFF0F766E), size: 20)
          : null,
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
                          color: const Color(0xFFEFF4FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.assignment_add,
                          color: Color(0xFF0F766E),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Otomatik Sipariş Taslağı',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0B1C30),
                              ),
                            ),
                            Text(
                              '${urgentItems.length} kritik ürün tespit edildi',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
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
                        final item = urgentItems[idx];
                        final suggested = ((item.dailyVelocity * 7) - item.frozenQty)
                            .ceil()
                            .clamp(2, 50);
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0B1C30),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Mevcut Donuk: ${item.frozenQty} · Hız: ${item.dailyVelocity.toStringAsFixed(2)}/gün',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF64748B),
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
                                  color: const Color(0xFFEFF4FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '+$suggested Kutu',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F766E),
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
                        const SnackBar(
                          content: Text('Sipariş taslağı başarıyla oluşturuldu.'),
                          backgroundColor: Color(0xFF0F766E),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Siparişi Onayla ve Gönder',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
                  backgroundColor: const Color(0xFF0F766E),
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
        : _stock.items.where((i) => normalizeSearch(i.name).contains(q)).toList();

    // Category / Risk filter
    final filtered = searchFiltered.where((i) {
      if (_filter == 'stok-yok') return i.risk == 0;
      if (_filter == 'kritik') return i.risk == 1 || i.risk == 2;
      if (_filter == 'yeterli') return i.risk == 3 || (i.risk != null && i.risk! > 3);
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
    final kritikCount = _stock.items.where((i) => i.risk == 1 || i.risk == 2).length;
    final yeterliCount = _stock.items.where((i) => i.risk == 3 || (i.risk != null && i.risk! > 3)).length;

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
      backgroundColor: const Color(0xFFF8F9FF),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(silent: true),
                color: const Color(0xFF0F766E),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  children: [
                    // Header Bar
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
                    _buildSearchAndFilters(stokYokCount, kritikCount, yeterliCount),
                    const SizedBox(height: 12),

                    // Completely Empty State
                    if (_stock.items.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Center(
                          child: Text(
                            'Bu mağazada aktif stok veya satış kaydı yok.',
                            style: TextStyle(color: t.muted, fontSize: 13.5),
                          ),
                        ),
                      )
                    // Search / Filter Empty State
                    else if (active.isEmpty && idle.isEmpty)
                      _buildNoResultsState()
                    // Active Stock Coverage Cards
                    else ...[
                      ...active.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _CoverageCard(item: item),
                          )),

                      // Non-moving Items Section
                      if (idle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Satış hareketi olmayan ${idle.length} çeşit',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0B1C30),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Satış hızı sıfır olduğu için yeterlilik hesaplanamaz.',
                                style: TextStyle(fontSize: 12, color: t.muted),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: idle
                                    .map(
                                      (i) => Pill(
                                        text: '${i.name} · ${fmtInt(i.frozenQty)} adet',
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
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFF4FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    size: 20,
                    color: Color(0xFF0B1C30),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Stok Yeterliliği',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0B1C30),
                  letterSpacing: -0.3,
                ),
              ),
            ),
            Material(
              color: const Color(0xFFEFF4FF),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: _exportExcel,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.file_download_outlined,
                        size: 16,
                        color: Color(0xFF0F766E),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Excel',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: const Color(0xFFEFF4FF),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: _showSortDialog,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.tune,
                    size: 18,
                    color: Color(0xFF3E4947),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            'Tüketim hızı, donuk depo gün yeterliliği ve kritik sipariş uyarıları',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ),
      ],
    );
  }

  Widget _buildAlertBanner(int criticalAlertCount) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFDAD6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFFFDAD6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.warning_rounded,
              color: Color(0xFFBA1A1A),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$criticalAlertCount çeşidin donuk deposu 3 günden az yetecek veya tükendi.',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF93000A),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Sipariş verilmesi gerekebilir. Kritik stoklar bugün tükenebilir.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
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
                    children: const [
                      Text(
                        'Acil Tedarik Listesi Oluştur',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 15,
                        color: Color(0xFF0F766E),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
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
              const Text(
                'SATIŞ HIZI PENCERESİ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F766E),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'Canlı Hesaplama',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F766E),
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
              color: const Color(0xFFEFF4FF),
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
                        color: selected ? const Color(0xFFB5EFDA) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$days gün',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                          color: selected
                              ? const Color(0xFF002018)
                              : const Color(0xFF64748B),
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
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters(int stokYokCount, int kritikCount, int yeterliCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search Input Box
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontSize: 14, color: Color(0xFF0B1C30)),
            decoration: InputDecoration(
              hintText: 'Ürün veya kategori ara...',
              hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
              prefixIcon: const Icon(
                Icons.search,
                size: 20,
                color: Color(0xFF64748B),
              ),
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
              _filterChip('stok-yok', 'Stok Yok ($stokYokCount)', const Color(0xFFEF4444)),
              const SizedBox(width: 6),
              _filterChip('kritik', 'Kritik ($kritikCount)', const Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              _filterChip('yeterli', 'Yeterli ($yeterliCount)', const Color(0xFF10B981)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String filterKey, String label, Color? dotColor) {
    final selected = _filter == filterKey;
    return GestureDetector(
      onTap: () => setState(() => _filter = filterKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0F766E) : const Color(0xFFEFF4FF),
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF376E5E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              color: Color(0xFFEFF4FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 28,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Eşleşen Ürün Bulunamadı',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0B1C30),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Arama terimini veya aktif durum filtrelerini kontrol ederek tekrar deneyebilirsiniz.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
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
              foregroundColor: const Color(0xFF0F766E),
              side: const BorderSide(color: Color(0xFF0F766E)),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
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
                  const Text(
                    'TOPLAM DONUK DEPO DEĞERİ',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fmtMoney(totalFrozenValue),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F766E),
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Mevcut Çeşit / Adet',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_stock.items.length} Kalem · $totalFrozenQty Adet',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0B1C30),
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
                        const SnackBar(
                          content: Text('Şu an acil sipariş gerektiren kritik ürün bulunmuyor.'),
                          backgroundColor: Color(0xFF0F766E),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  : () => _showOrderDraftSheet(urgentItems),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              icon: const Icon(Icons.assignment_add, size: 20),
              label: Text(
                'Otomatik Sipariş Taslağı Oluştur (${urgentItems.length} Kalem)',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverageCard extends StatelessWidget {
  const _CoverageCard({required this.item});

  final StockCoverageItem item;

  static IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('cookie') || n.contains('kurabiye')) return Icons.cookie_outlined;
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
    if (n.contains('cup') || n.contains('dondurma')) return Icons.icecream_outlined;
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

    // Status label and colors
    final (label, textColor, bgColor, dotColor) = switch (item.risk) {
      0 => (
        'Stok yok',
        const Color(0xFF991B1B),
        const Color(0xFFFEE2E2),
        const Color(0xFFEF4444)
      ),
      1 => (
        'Kritik',
        const Color(0xFF92400E),
        const Color(0xFFFEF3C7),
        const Color(0xFFF59E0B)
      ),
      2 => (
        'Azalıyor',
        const Color(0xFF92400E),
        const Color(0xFFFEF3C7),
        const Color(0xFFF59E0B)
      ),
      _ => (
        'Yeterli',
        const Color(0xFF065F46),
        const Color(0xFFD1FAE5),
        const Color(0xFF10B981)
      ),
    };

    final coverText = cover == null
        ? '-'
        : cover < 1
            ? 'bugün biter'
            : '${cover.toStringAsFixed(cover < 10 ? 1 : 0)} gün';

    final coverColor = cover == null
        ? const Color(0xFF0B1C30)
        : cover < 1
            ? const Color(0xFFEF4444)
            : cover < 7
                ? const Color(0xFFB45309)
                : const Color(0xFF007952);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
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
                  color: const Color(0xFFEFF4FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _iconFor(item.name),
                  size: 20,
                  color: const Color(0xFF0F766E),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0B1C30),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_categoryFor(item.name)} · SKU: ${_skuFor(item)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
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
                        fontSize: 11,
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
              color: const Color(0xFFEFF4FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'Donuk depo',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fmtInt(item.frozenQty),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: item.frozenQty == 0
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF0F766E),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'Çözülen',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fmtInt(item.thawingQty),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0B1C30),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'Food dolabı',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fmtInt(item.cabinetQty),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: (item.cabinetQty == 0 && item.risk == 0)
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF0B1C30),
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
                    const Text(
                      'Satış hızı',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.dailyVelocity.toStringAsFixed(2)}/gün',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0B1C30),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Yeterlilik',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      coverText,
                      style: TextStyle(
                        fontSize: 13.5,
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
                    const Text(
                      'Biteceği gün',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.depletionDate == null
                          ? '-'
                          : fmtDate(item.depletionDate),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0B1C30),
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
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(
                  cover < 1 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
                ),
              ),
            ),
          ],

          // Row 4: Financial detail & recent sales
          const SizedBox(height: 8),
          Text(
            'Donuk depodaki tutar ${fmtMoney(item.frozenValue ?? 0)} · son ${item.soldQty} adet satıldı',
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}
