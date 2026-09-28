import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/new_theme.dart';
import '../models/batch.dart';

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  final _searchController = TextEditingController();
  List<Batch> _items = const [];
  String _search = '';
  String? _error;
  bool _loaded = false;
  String _activeHorizon = 'bugun';
  String _activeCategory = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final items = await repo.recommendations(silent: silent);
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
  }

  List<Batch> get _shown {
    final q = normalizeSearch(_search.trim());
    if (q.isEmpty) return _items;
    return _items
        .where(
          (b) =>
              normalizeSearch(b.productName).contains(q) ||
              normalizeSearch(b.storeName).contains(q),
        )
        .toList();
  }

  int _sum(Iterable<Batch> list) =>
      list.fold<int>(0, (a, b) => a + b.remaining);

  Future<void> _sell(Batch b) async {
    final ok = await _confirm(
      title: 'Satışı Onayla',
      confirmLabel: '1 Adet Sat',
      danger: false,
      body: _sellMessage(b),
    );
    if (ok != true) return;
    try {
      await repo.sellOne(b);
    } catch (_) {}
    await _load(silent: true);
  }

  Future<void> _ikram(Batch b) async {
    final ok = await _confirm(
      title: 'İkramı Onayla',
      confirmLabel: '1 Adet İkram Et',
      danger: false,
      body: _ikramMessage(b),
    );
    if (ok != true) return;
    try {
      await repo.ikramOne(b);
    } catch (_) {}
    await _load(silent: true);
  }

  Future<void> _discard(Batch b) async {
    final ok = await _confirm(
      title: 'Zayi Gir',
      confirmLabel: 'Zayi Gir',
      danger: true,
      body: Text(
        '${b.productName} (${b.remaining} adet) için zayi girilecek. Onaylıyor musunuz?',
      ),
    );
    if (ok != true) return;
    try {
      await repo.discardAll(b);
    } catch (_) {}
    await _load(silent: true);
  }

  Widget _sellMessage(Batch b) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: b.productName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: ' ürününden '),
              const TextSpan(
                text: '1 adet',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text:
                    ' satılacak. Kalan ${b.remaining} adetten ${b.remaining - 1} adede düşecek.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (b.hasPrice)
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Ciroya '),
                TextSpan(
                  text: fmtMoney(b.productUnitPrice),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: ' eklenecek.'),
              ],
            ),
          )
        else
          const Text(
            'Bu çeşit için satış fiyatı tanımlı değil; ciroya 0 TL yazılacak.',
            style: TextStyle(color: NewTokens.error),
          ),
      ],
    );
  }

  Widget _ikramMessage(Batch b) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: b.productName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: ' ürününden '),
              const TextSpan(
                text: '1 adet ikram',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text:
                    ' edilecek. Kalan ${b.remaining} adetten ${b.remaining - 1} adede düşecek.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Ciroya '),
              TextSpan(
                text: 'eklenmez',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: ' ve satış adedine sayılmaz.'),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (b.hasPrice)
          Text(
            'İkram değeri olarak ${fmtMoney(b.productUnitPrice)} kaydedilir.',
            style: const TextStyle(
              color: NewTokens.onSurfaceVariant,
              fontSize: 13,
            ),
          )
        else
          const Text(
            'Bu çeşit için fiyat tanımlı olmadığı için ikram değeri kaydedilemez.',
            style: TextStyle(color: NewTokens.error, fontSize: 13),
          ),
      ],
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String confirmLabel,
    required bool danger,
    required Widget body,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NewTokens.surfaceContainerLowest,
        title: Text(title, style: NewTokens.headlineSm),
        content: body,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: OutlinedButton.styleFrom(
              foregroundColor: NewTokens.onSurface,
              side: const BorderSide(color: NewTokens.outline),
            ),
            child: const Text('Vazgeç', style: NewTokens.labelLg),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: danger ? NewTokens.error : NewTokens.primary,
              foregroundColor: danger ? NewTokens.onError : NewTokens.onPrimary,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel, style: NewTokens.labelLg),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded)
      return const Scaffold(
        backgroundColor: NewTokens.surface,
        body: SizedBox.shrink(),
      );

    if (_error != null && _items.isEmpty) {
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
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _load(),
                style: FilledButton.styleFrom(
                  backgroundColor: NewTokens.primary,
                ),
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    final shown = _shown;

    final expired = shown.where((b) => b.isExpired).toList();
    final today = shown
        .where((b) => b.urgency == 'critical' && !b.isExpired)
        .toList();
    final upcoming = shown
        .where(
          (b) =>
              (b.urgency == 'warning' || b.urgency == 'normal') && !b.isExpired,
        )
        .toList();

    return Scaffold(
      backgroundColor: NewTokens.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
          decoration: BoxDecoration(
            color: NewTokens.surface.withValues(alpha: 0.85),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
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
                          Expanded(
                            child: Text(
                              'Düzce Merkez Şube',
                              style: NewTokens.labelSm.copyWith(
                                color: NewTokens.primary,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        'Öneri / Skt',
                        style: NewTokens.headlineSm,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Muhammed Ş. Sezer · Mağaza Müdürü',
                        style: NewTokens.labelSm.copyWith(
                          color: NewTokens.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.notifications_none,
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
                    const SizedBox(width: 4),
                    Container(
                      width: 32,
                      height: 32,
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
      body: RefreshIndicator(
        onRefresh: () => _load(silent: true),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 8, bottom: 96),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (expired.isNotEmpty) ...[
                      _buildUrgentBanner(expired.length),
                      const SizedBox(height: 16),
                    ],
                    _buildHorizonTabs(
                      _items,
                    ), // Pass all items for total counts
                    const SizedBox(height: 12),
                    _buildSearchAndFilters(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (shown.isEmpty)
                _buildEmptySearch()
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      if (expired.isNotEmpty)
                        _buildSection('skt-gecti', expired),
                      if (today.isNotEmpty) _buildSection('bugun', today),
                      if (upcoming.isNotEmpty)
                        _buildSection('gelecek', upcoming),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUrgentBanner(int count) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NewTokens.errorContainer,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: NewTokens.error,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: NewTokens.onError,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ACİL OPERASYONEL AKSİYON',
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Şimdi',
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.onErrorContainer.withValues(
                          alpha: 0.75,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$count adet ürünün SKT\'si doldu!',
                  style: NewTokens.bodyMd.copyWith(
                    color: NewTokens.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Lütfen vitrinden kaldırarak zayi fişi oluşturun veya satışı durdurun.',
                  style: NewTokens.bodySm.copyWith(
                    color: NewTokens.onErrorContainer.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: NewTokens.error,
                        foregroundColor: NewTokens.onError,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 0,
                        ),
                        minimumSize: const Size(0, 36),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {},
                      icon: const Icon(Icons.delete_sweep, size: 18),
                      label: Text(
                        'Tümünü Zayi Et ($count)',
                        style: NewTokens.labelMd,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: NewTokens.surfaceContainerLowest
                            .withValues(alpha: 0.6),
                        foregroundColor: NewTokens.onErrorContainer,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 0,
                        ),
                        minimumSize: const Size(0, 36),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {},
                      child: const Text('Gizle', style: NewTokens.labelMd),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizonTabs(List<Batch> allItems) {
    final sktCount = allItems.where((b) => b.isExpired).length;
    final bugunCount = allItems
        .where((b) => b.urgency == 'critical' && !b.isExpired)
        .length;
    final gelecekCount = allItems
        .where(
          (b) =>
              (b.urgency == 'warning' || b.urgency == 'normal') && !b.isExpired,
        )
        .length;

    return Row(
      children: [
        Expanded(
          child: _buildHorizonTab(
            'skt-gecti',
            'SKT Geçen',
            sktCount,
            'Acil Zayi',
            NewTokens.error,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildHorizonTab(
            'bugun',
            'Bugün',
            bugunCount,
            '< 24 Saat',
            NewTokens.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildHorizonTab(
            'gelecek',
            '2-3 Gün',
            gelecekCount,
            'İzleme',
            NewTokens.tertiaryContainer,
          ),
        ),
      ],
    );
  }

  Widget _buildHorizonTab(
    String id,
    String label,
    int count,
    String subtitle,
    Color color,
  ) {
    final isActive = _activeHorizon == id;
    return GestureDetector(
      onTap: () => setState(() => _activeHorizon = id),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive
              ? NewTokens.surfaceContainerHigh
              : NewTokens.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: NewTokens.labelSm.copyWith(
                      color: isActive
                          ? NewTokens.onSurface
                          : NewTokens.onSurfaceVariant,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '$count',
              style: NewTokens.numericMetric.copyWith(
                color: isActive
                    ? color
                    : (id == 'gelecek' ? NewTokens.onSurface : color),
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: isActive
                    ? color
                    : NewTokens.onSurfaceVariant.withValues(alpha: 0.75),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Column(
      children: [
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: NewTokens.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _search = v),
            style: NewTokens.bodyMd.copyWith(color: NewTokens.onSurface),
            decoration: InputDecoration(
              hintText: 'Ürün adı veya barkod ara...',
              hintStyle: NewTokens.bodyMd.copyWith(
                color: NewTokens.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: NewTokens.onSurfaceVariant,
                size: 20,
              ),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: NewTokens.onSurfaceVariant,
                        size: 16,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildCategoryChip('all', 'Tümü', Icons.apps, true),
              const SizedBox(width: 8),
              _buildCategoryChip('pasta', 'Pastalar', Icons.cake, false),
              const SizedBox(width: 8),
              _buildCategoryChip(
                'atistirmalik',
                'Atıştırmalık',
                Icons.cookie,
                false,
              ),
              const SizedBox(width: 8),
              _buildCategoryChip(
                'firinci',
                'Unlu Mamul',
                Icons.bakery_dining,
                false,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChip(
    String id,
    String label,
    IconData icon,
    bool active,
  ) {
    return GestureDetector(
      onTap: () => setState(() => _activeCategory = id),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? NewTokens.primary : NewTokens.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          boxShadow: active
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? NewTokens.onPrimary : NewTokens.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: NewTokens.labelSm.copyWith(
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

  Widget _buildEmptySearch() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: NewTokens.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off,
              color: NewTokens.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          const Text('Eşleşen Ürün Bulunamadı', style: NewTokens.headlineSm),
          const SizedBox(height: 4),
          Text(
            'Farklı bir arama terimi deneyebilir veya kategori filtresini temizleyebilirsiniz.',
            style: NewTokens.bodyMd.copyWith(color: NewTokens.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: NewTokens.primary,
              foregroundColor: NewTokens.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              _searchController.clear();
              setState(() {
                _search = '';
                _activeCategory = 'all';
              });
            },
            child: const Text('Filtreleri Sıfırla', style: NewTokens.labelMd),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String id, List<Batch> items) {
    String title;
    IconData icon;
    Color color;
    String badgeText;
    Color badgeColor;
    Color badgeTextColor;

    if (id == 'skt-gecti') {
      title = "SKT'si Dolanlar";
      icon = Icons.error_outline;
      color = NewTokens.error;
      badgeText = '${items.length} SKU Bekliyor';
      badgeColor = NewTokens.errorContainer;
      badgeTextColor = NewTokens.onErrorContainer;
    } else if (id == 'bugun') {
      title = "Bugün SKT Dolanlar";
      icon = Icons.schedule;
      color = NewTokens.primary;
      badgeText = 'Öncelikli Satış';
      badgeColor = NewTokens.surfaceContainer;
      badgeTextColor = NewTokens.primary;
    } else {
      title = "Son 2-3 Gün Kalanlar";
      icon = Icons.event_upcoming;
      color = NewTokens.tertiaryContainer;
      badgeText = 'İkram & Kampanya';
      badgeColor = NewTokens.surfaceContainer;
      badgeTextColor = NewTokens.onSurfaceVariant;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    title,
                    style: NewTokens.headlineSm.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeText,
                  style: NewTokens.labelSm.copyWith(
                    color: badgeTextColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...items.map((b) => _buildProductItem(b, id)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildProductItem(Batch b, String sectionId) {
    bool isExpired = b.isExpired;
    bool isToday = !isExpired && b.urgency == 'critical';

    String statusBadgeText;
    Color statusBadgeColor;
    Color statusBadgeTextColor;
    Color statusBadgeDotColor;

    if (isExpired) {
      statusBadgeText = 'SKT Geçti';
      statusBadgeColor = NewTokens.errorContainer;
      statusBadgeTextColor = NewTokens.onErrorContainer;
      statusBadgeDotColor = NewTokens.error;
    } else if (isToday) {
      statusBadgeText = 'Son Gün';
      statusBadgeColor = NewTokens.secondaryContainer;
      statusBadgeTextColor = NewTokens.onSecondaryContainer;
      statusBadgeDotColor = NewTokens.secondary;
    } else {
      statusBadgeText = '${b.daysLeft ?? 2} Gün Kaldı';
      statusBadgeColor = NewTokens.surfaceContainerHigh;
      statusBadgeTextColor = NewTokens.onSurface;
      statusBadgeDotColor = NewTokens.tertiaryContainer;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.image,
                  color: NewTokens.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.productName,
                      style: NewTokens.headlineSm.copyWith(
                        color: NewTokens.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${b.remaining} adet',
                          style: NewTokens.bodySm.copyWith(
                            color: NewTokens.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          ' · ',
                          style: NewTokens.bodySm.copyWith(
                            color: NewTokens.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          'SKT: ${fmtDateTime(b.sktEnd)}',
                          style: NewTokens.bodySm.copyWith(
                            color: isExpired
                                ? NewTokens.error
                                : (isToday
                                      ? NewTokens.primary
                                      : NewTokens.tertiary),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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
                  color: statusBadgeColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusBadgeDotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusBadgeText,
                      style: NewTokens.labelSm.copyWith(
                        color: statusBadgeTextColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isExpired)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: NewTokens.errorContainer,
                      foregroundColor: NewTokens.onErrorContainer,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => _discard(b),
                    icon: const Icon(Icons.delete_forever, size: 20),
                    label: const Text(
                      'Zayi Et (Fire Kaydı)',
                      style: NewTokens.labelLg,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: NewTokens.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.more_vert,
                      color: NewTokens.onSurfaceVariant,
                    ),
                    onPressed: () {},
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: NewTokens.primary,
                      foregroundColor: NewTokens.onPrimary,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => _sell(b),
                    icon: const Icon(Icons.point_of_sale, size: 18),
                    label: const Text('Satış', style: NewTokens.labelLg),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: NewTokens.surfaceContainerHigh,
                      foregroundColor: NewTokens.onSurface,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => _ikram(b),
                    icon: const Icon(Icons.redeem, size: 18),
                    label: const Text('İkram', style: NewTokens.labelLg),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: isToday
                          ? NewTokens.errorContainer
                          : NewTokens.surfaceContainerLow,
                      foregroundColor: isToday
                          ? NewTokens.error
                          : NewTokens.onSurfaceVariant,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => _discard(b),
                    icon: const Icon(Icons.delete, size: 18),
                    label: const Text('Zayi', style: NewTokens.labelLg),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
