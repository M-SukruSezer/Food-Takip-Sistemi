import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/tokens.dart';
import '../models/manager_overview.dart';
import '../core/new_theme.dart';

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
  String _filter = 'all'; // 'all', 'stok-yok', 'kritik', 'yeterli'

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

  String _getCategory(StockCoverageItem item) {
    final risk = item.risk;
    if (risk == 0) return 'stok-yok';
    if (risk == 1) return 'kritik';
    if (risk == 2) return 'yeterli'; // Using yeterli for 'azaliyor' for now as per HTML? The HTML just has Stok Yok, Kritik, Yeterli.
    return 'yeterli';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded && _error == null) {
      return const Scaffold(
        backgroundColor: NewTokens.surface,
        body: Center(
          child: CircularProgressIndicator(color: NewTokens.primary),
        ),
      );
    }

    final q = normalizeSearch(_query);
    final allItems = _stock.items;

    final filteredBySearch = q.isEmpty
        ? allItems
        : allItems.where((i) => normalizeSearch(i.name).contains(q)).toList();

    final items = _filter == 'all'
        ? filteredBySearch
        : filteredBySearch.where((i) => _getCategory(i) == _filter).toList();

    final criticalCount = allItems
        .where((i) => i.risk == 0 || i.risk == 1)
        .length;
    final stokYokCount = allItems.where((i) => i.risk == 0).length;
    final kritikCount = allItems.where((i) => i.risk == 1).length;
    final yeterliCount = allItems.where((i) => i.risk > 1).length;

    return Scaffold(
      backgroundColor: NewTokens.surface,
      body: Stack(
        children: [
          // Main content
          CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 80,
                ),
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header Title & Context Actions
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        icon: const Icon(
                                          Icons.arrow_back,
                                          color: NewTokens.onSurface,
                                          size: 22,
                                        ),
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          hoverColor:
                                              NewTokens.surfaceContainerHigh,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'Stok Yeterliliği',
                                        style: TextStyle(
                                          fontFamily: 'Plus Jakarta Sans',
                                          fontSize: 20,
                                          height: 28 / 20,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.01 * 20,
                                          color: NewTokens.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        height: 32,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: NewTokens.surfaceContainerLow,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x0D000000),
                                              blurRadius: 2,
                                              offset: Offset(0, 1),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.file_download,
                                              color: NewTokens.primary,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Excel',
                                              style: NewTokens.labelSm.copyWith(
                                                color: NewTokens.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: NewTokens.surfaceContainerLow,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.tune,
                                          color: NewTokens.onSurfaceVariant,
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  'Tüketim hızı, donuk depo gün yeterliliği ve kritik sipariş uyarıları',
                                  style: NewTokens.bodySm.copyWith(
                                    color: NewTokens.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Operational Alert Card
                        if (criticalCount > 0)
                          Container(
                            margin: const EdgeInsets.only(
                              left: 16,
                              right: 16,
                              bottom: 16,
                            ),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: NewTokens.errorContainer.withValues(
                                alpha: 0.4,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0D000000),
                                  blurRadius: 2,
                                  offset: Offset(0, 1),
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
                                    color: NewTokens.errorContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.warning,
                                    color: NewTokens.error,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$criticalCount çeşidin donuk deposu 3 günden az yetecek veya tükendi.',
                                        style: NewTokens.labelMd.copyWith(
                                          color: NewTokens.onErrorContainer,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Sipariş verilmesi gerekebilir. Kritik stoklar bugün tükenebilir.',
                                        style: NewTokens.bodySm.copyWith(
                                          color: NewTokens.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Text(
                                            'Acil Tedarik Listesi Oluştur',
                                            style: NewTokens.labelMd.copyWith(
                                              color: NewTokens.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.arrow_forward,
                                            color: NewTokens.primary,
                                            size: 16,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Sales Velocity Window
                        Container(
                          margin: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            bottom: 8,
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: NewTokens.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0D000000),
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'SATIŞ HIZI PENCERESİ',
                                    style: NewTokens.labelSm.copyWith(
                                      color: NewTokens.onSurfaceVariant,
                                      letterSpacing: 0.05,
                                    ),
                                  ),
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
                                      const SizedBox(width: 4),
                                      Text(
                                        'Canlı Hesaplama',
                                        style: NewTokens.labelSm.copyWith(
                                          color: NewTokens.primary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: NewTokens.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    _buildVelocityButton(7),
                                    _buildVelocityButton(14),
                                    _buildVelocityButton(30),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Son $_window günün satış adedinden günlük hız bulunur, donuk depodaki adet buna bölünür.',
                                style: NewTokens.bodySm.copyWith(
                                  color: NewTokens.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Search & Filters
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            children: [
                              Container(
                                height: 44,
                                decoration: BoxDecoration(
                                  color: NewTokens.surfaceContainerLowest,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x0D000000),
                                      blurRadius: 2,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: TextField(
                                  controller: _search,
                                  onChanged: (v) => setState(() => _query = v),
                                  style: NewTokens.bodyMd.copyWith(
                                    color: NewTokens.onSurface,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Ürün veya kategori ara...',
                                    hintStyle: NewTokens.bodyMd.copyWith(
                                      color: NewTokens.outline,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      color: NewTokens.outline,
                                      size: 20,
                                    ),
                                    suffixIcon: _query.isNotEmpty
                                        ? IconButton(
                                            icon: Container(
                                              width: 24,
                                              height: 24,
                                              decoration: const BoxDecoration(
                                                color:
                                                    NewTokens.surfaceContainer,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.close,
                                                color:
                                                    NewTokens.onSurfaceVariant,
                                                size: 14,
                                              ),
                                            ),
                                            onPressed: () {
                                              _search.clear();
                                              setState(() => _query = '');
                                            },
                                          )
                                        : null,
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _buildFilterPill(
                                      'all',
                                      'Tümü',
                                      allItems.length,
                                      null,
                                      null,
                                    ),
                                    const SizedBox(width: 6),
                                    _buildFilterPill(
                                      'stok-yok',
                                      'Stok Yok',
                                      stokYokCount,
                                      NewTokens.error,
                                      NewTokens.errorContainer,
                                    ),
                                    const SizedBox(width: 6),
                                    _buildFilterPill(
                                      'kritik',
                                      'Kritik',
                                      kritikCount,
                                      Colors.amber[500]!,
                                      NewTokens.surfaceContainerHigh,
                                    ),
                                    const SizedBox(width: 6),
                                    _buildFilterPill(
                                      'yeterli',
                                      'Yeterli',
                                      yeterliCount,
                                      NewTokens.primaryContainer,
                                      NewTokens.surfaceContainerLow,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // List
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: NewTokens.error),
                            ),
                          )
                        else if (items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Sonuç bulunamadı.',
                              style: TextStyle(
                                color: NewTokens.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              children: items
                                  .map((i) => _buildStockCard(i))
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Header (fixed top-0)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  color: NewTokens.surface.withValues(alpha: 0.85),
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top,
                  ),
                  child: Container(
                    height: 80,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: const BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x08000000),
                          blurRadius: 8,
                          offset: Offset(0, 1),
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
                                    'DÜZCE MERKEZ ŞUBE',
                                    style: NewTokens.labelSm.copyWith(
                                      color: NewTokens.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Ana Sayfa',
                                style: NewTokens.headlineSm.copyWith(
                                  color: NewTokens.onSurface,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.02 * 18,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Muhammed Ş. Sezer · Mağaza Müdürü',
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
                                  icon: const Icon(
                                    Icons.notifications,
                                    color: NewTokens.onSurfaceVariant,
                                    size: 24,
                                  ),
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
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.power_settings_new,
                                color: NewTokens.onSurfaceVariant,
                                size: 24,
                              ),
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
                              child: const Icon(
                                Icons.person,
                                color: NewTokens.onPrimary,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVelocityButton(int days) {
    final isSelected = _window == days;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _window = days);
          _load(silent: true);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? NewTokens.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isSelected
                ? const [
                    BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            '$days gün',
            style: NewTokens.labelMd.copyWith(
              color: isSelected
                  ? NewTokens.onSecondaryContainer
                  : NewTokens.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPill(
    String value,
    String label,
    int count,
    Color? dotColor,
    Color? bgColor,
  ) {
    final isSelected = _filter == value;
    final backgroundColor = isSelected
        ? NewTokens.primary
        : (bgColor ?? NewTokens.surfaceContainerLowest);
    final textColor = isSelected
        ? NewTokens.onPrimary
        : (dotColor == NewTokens.error
              ? NewTokens.onErrorContainer
              : (dotColor == Colors.amber[500]
                    ? NewTokens.onSurfaceVariant
                    : NewTokens.secondary));

    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            if (dotColor != null && !isSelected) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              '$label ($count)',
              style: NewTokens.labelSm.copyWith(
                color: textColor,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockCard(StockCoverageItem item) {
    final risk = item.risk;
    final isStokYok = risk == 0;
    final isKritik = risk == 1;
    final isAzaliyor = risk == 2;

    final badgeBg = isStokYok
        ? NewTokens.errorContainer
        : (isKritik ? Colors.amber[100]! : NewTokens.secondaryContainer);
    final badgeText = isStokYok
        ? NewTokens.onErrorContainer
        : (isKritik ? Colors.amber[900]! : NewTokens.onSecondaryContainer);
    final badgeDot = isStokYok
        ? NewTokens.error
        : (isKritik ? Colors.amber[500]! : NewTokens.tertiaryContainer);
    final badgeLabel = isStokYok
        ? 'Stok yok'
        : (isKritik ? 'Kritik' : (isAzaliyor ? 'Azalıyor' : 'Yeterli'));

    final cover = item.daysOfCover;
    final coverText = cover == null
        ? '-'
        : cover < 1
        ? 'bugün biter'
        : '${cover.toStringAsFixed(cover < 10 ? 1 : 0)} gün';

    final coverColor = isStokYok
        ? NewTokens.error
        : (isKritik ? Colors.amber[700]! : NewTokens.tertiaryContainer);

    // Icon selection logic based on HTML examples
    IconData cardIcon = Icons.inventory;
    if (item.name.toLowerCase().contains('cookie') ||
        item.name.toLowerCase().contains('açma')) {
      cardIcon = Icons.bakery_dining;
    } else if (item.name.toLowerCase().contains('pasta') ||
        item.name.toLowerCase().contains('muffin') ||
        item.name.toLowerCase().contains('cheesecake')) {
      cardIcon = Icons.cake;
    } else if (item.name.toLowerCase().contains('burger')) {
      cardIcon = Icons.lunch_dining;
    } else if (item.name.toLowerCase().contains('içecek') ||
        item.name.toLowerCase().contains('portakal')) {
      cardIcon = Icons.local_cafe;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(cardIcon, color: NewTokens.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name.toUpperCase(),
                      style: NewTokens.headlineSm.copyWith(
                        color: NewTokens.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'SKU: ${item.name.substring(0, 3).toUpperCase()}-000', // Mock SKU
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: badgeDot,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      badgeLabel,
                      style: NewTokens.labelSm.copyWith(
                        color: badgeText,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: NewTokens.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'Donuk depo',
                        style: NewTokens.labelSm.copyWith(
                          color: NewTokens.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        fmtInt(item.frozenQty),
                        style: NewTokens.numericMetric.copyWith(
                          color: isStokYok
                              ? NewTokens.error
                              : (isKritik
                                    ? Colors.amber[700]!
                                    : NewTokens.primary),
                          fontSize: 20,
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
                        style: NewTokens.labelSm.copyWith(
                          color: NewTokens.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        fmtInt(item.thawingQty),
                        style: NewTokens.numericMetric.copyWith(
                          color: NewTokens.onSurface,
                          fontSize: 20,
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
                        style: NewTokens.labelSm.copyWith(
                          color: NewTokens.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        fmtInt(item.cabinetQty),
                        style: NewTokens.numericMetric.copyWith(
                          color: isStokYok
                              ? NewTokens.error
                              : NewTokens.onSurface,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Satış hızı',
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${item.dailyVelocity.toStringAsFixed(2)}/gün',
                      style: NewTokens.labelLg.copyWith(
                        color: NewTokens.onSurface,
                        fontWeight: FontWeight.bold,
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
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      coverText,
                      style: NewTokens.labelLg.copyWith(
                        color: coverColor,
                        fontWeight: FontWeight.w800,
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
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      item.depletionDate == null
                          ? '-'
                          : fmtDate(item.depletionDate),
                      style: NewTokens.labelLg.copyWith(
                        color: NewTokens.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isKritik && cover != null && cover > 0) ...[
            const SizedBox(height: 8),
            Container(
              height: 6,
              width: double.infinity,
              decoration: BoxDecoration(
                color: NewTokens.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (cover / 3).clamp(
                  0.0,
                  1.0,
                ), // 3 days is critical threshold
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.amber[500]!,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ],
          if (item.frozenValue != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Donuk depodaki tutar ${fmtMoney(item.frozenValue)} · son ${item.soldQty} adet satıldı',
                    style: NewTokens.labelSm.copyWith(
                      color: NewTokens.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isStokYok)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: NewTokens.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.add_shopping_cart,
                          color: NewTokens.onPrimary,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '+15 Adet',
                          style: NewTokens.labelSm.copyWith(
                            color: NewTokens.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
