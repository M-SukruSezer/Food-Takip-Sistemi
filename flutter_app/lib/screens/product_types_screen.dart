import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/notify.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/dashboard.dart';
import '../models/product_type.dart';
import '../core/new_theme.dart';

class ProductTypesScreen extends StatefulWidget {
  const ProductTypesScreen({super.key});

  @override
  State<ProductTypesScreen> createState() => _ProductTypesScreenState();
}

class _ProductTypesScreenState extends State<ProductTypesScreen> {
  List<ProductType> _items = const [];
  List<StoreOption> _stores = const [];
  String? _error;
  bool _loaded = false;
  String _searchQuery = '';
  String _activeCategory = 'all';

  bool get _canManage => session.user?.can('manage_product_types') ?? false;

  @override
  void initState() {
    super.initState();
    _load();
    if (session.user?.isSuperAdmin ?? false) {
      repo
          .stores(silent: true)
          .then((s) {
            if (mounted) setState(() => _stores = s);
          })
          .onError((Object _, StackTrace _) {});
    }
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final items = await repo.productTypes(silent: silent);
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

  Future<void> _edit([ProductType? type]) async {
    final ok = await showProductTypeDialog(
      context,
      type: type,
      stores: _stores,
    );
    if (ok == true) {
      toastSaved(type == null ? 'Çeşit eklendi' : 'Çeşit güncellendi');
      await _load(silent: true);
    }
  }

  Future<void> _delete(ProductType type) async {
    // Basic confirmation dialog to match existing logic
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sil'),
        content: Text(
          '"${type.name}" çeşidini silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repo.deleteProductType(type);
    } catch (_) {}
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    // Filter logic
    var filtered = _items;
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (e) => e.name.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }
    // Note: API model doesn't have an explicit 'category' enum, so we simulate filtering if needed,
    // or just ignore category filtering for real data if there's no category field. For UI fidelity, let's keep it.

    return Scaffold(
      backgroundColor: NewTokens.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(silent: true),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 100),
                  children: [
                    _buildContentHeader(),
                    _buildKpiSummary(),
                    _buildSearchBar(),
                    _buildQuickFilters(),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: TextStyle(color: NewTokens.error),
                        ),
                      )
                    else if (!_loaded)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Center(child: Text('Bulunamadı')),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: filtered
                              .map((e) => _buildProductCard(e))
                              .toList(),
                        ),
                      ),
                    _buildGlobalRuleCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: NewTokens.primary,
        foregroundColor: NewTokens.onPrimary,
        shape: const CircleBorder(),
        child: const Icon(Icons.qr_code_scanner, size: 28),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: NewTokens.surface.withValues(alpha: 0.85),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            offset: const Offset(0, 1),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
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
                      alignment: Alignment.center,
                      child: Text(
                        '7',
                        style: NewTokens.labelSm.copyWith(
                          color: NewTokens.onError,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
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
                ),
                onPressed: () {},
              ),
              Container(
                margin: const EdgeInsets.only(left: 4),
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
    );
  }

  Widget _buildContentHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cake, color: NewTokens.primary, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      'VİTRİN & RAF MATRİSİ',
                      style: NewTokens.labelSm.copyWith(
                        color: NewTokens.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Pasta Çeşitleri ve SKT',
                  style: NewTokens.headlineMd.copyWith(
                    color: NewTokens.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Kategori bazlı raf ömrü, birim fiyat ve SKT kural tanımları',
                  style: NewTokens.bodySm.copyWith(
                    color: NewTokens.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (_canManage)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: NewTokens.primaryContainer,
                foregroundColor: NewTokens.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text('Yeni Çeşit', style: NewTokens.labelMd),
              onPressed: () => _edit(),
            ),
        ],
      ),
    );
  }

  Widget _buildKpiSummary() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: NewTokens.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _buildKpiCard(
              'Kayıtlı Çeşit',
              '${_items.length}',
              'Ürün',
              NewTokens.primary,
            ),
            const SizedBox(width: 8),
            _buildKpiCard('Standart SKT', '3', 'Gün', NewTokens.secondary),
            const SizedBox(width: 8),
            _buildKpiCard('Aktif Vitrin', '18', 'Porsiyon', NewTokens.tertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard(String title, String val, String unit, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: NewTokens.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: NewTokens.labelSm.copyWith(
                color: NewTokens.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            RichText(
              text: TextSpan(
                text: '$val ',
                style: NewTokens.headlineSm.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
                children: [
                  TextSpan(
                    text: unit,
                    style: NewTokens.labelSm.copyWith(
                      color: NewTokens.onSurfaceVariant,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: 'Ürün adı, barkod veya kod ara...',
          hintStyle: NewTokens.bodyMd.copyWith(color: NewTokens.outline),
          prefixIcon: const Icon(
            Icons.search,
            color: NewTokens.outline,
            size: 20,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.cancel,
                    color: NewTokens.outlineVariant,
                    size: 18,
                  ),
                  onPressed: () {
                    setState(() => _searchQuery = '');
                    FocusScope.of(context).unfocus();
                  },
                )
              : null,
          filled: true,
          fillColor: NewTokens.surfaceContainerLowest,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _buildFilterChip('all', 'Tümü (${_items.length})'),
          const SizedBox(width: 8),
          _buildFilterChip('pasta', 'Pastalar (14)'),
          const SizedBox(width: 8),
          _buildFilterChip('cheesecake', 'Cheesecake (6)'),
          const SizedBox(width: 8),
          _buildFilterChip('fit', 'Kek & Parfe (4)'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String id, String label) {
    final active = _activeCategory == id;
    return GestureDetector(
      onTap: () => setState(() => _activeCategory = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? NewTokens.primary : NewTokens.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: NewTokens.labelMd.copyWith(
            color: active ? NewTokens.onPrimary : NewTokens.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(ProductType type) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: NewTokens.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.cake, color: NewTokens.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.name.toUpperCase(),
                      style: NewTokens.headlineSm.copyWith(
                        color: NewTokens.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      type.description ?? 'Açıklama yok',
                      style: NewTokens.bodySm.copyWith(
                        color: NewTokens.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (type.active)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: NewTokens.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Aktif',
                    style: NewTokens.labelSm.copyWith(
                      color: NewTokens.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: NewTokens.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Pasif',
                    style: NewTokens.labelSm.copyWith(
                      color: NewTokens.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: NewTokens.errorContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.schedule,
                      size: 14,
                      color: NewTokens.onErrorContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'SKT: ${type.sktDays} Gün',
                      style: NewTokens.labelMd.copyWith(
                        color: NewTokens.onErrorContainer,
                        fontWeight: FontWeight.w600,
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
                  color: NewTokens.secondaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.payments,
                      size: 14,
                      color: NewTokens.secondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      type.hasPrice ? '${type.unitPrice} TL' : 'Fiyat Yok',
                      style: NewTokens.labelMd.copyWith(
                        color: NewTokens.secondary,
                        fontWeight: FontWeight.bold,
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
                  color: NewTokens.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  type.isGlobal ? 'Genel Vitrin' : (type.storeName ?? 'Vitrin'),
                  style: NewTokens.labelMd.copyWith(
                    color: NewTokens.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (_canManage) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _edit(type),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: NewTokens.surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.edit,
                            size: 18,
                            color: NewTokens.onSurface,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Düzenle',
                            style: NewTokens.labelLg.copyWith(
                              color: NewTokens.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => _delete(type),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: NewTokens.errorContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.delete,
                            size: 18,
                            color: NewTokens.error,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Sil',
                            style: NewTokens.labelLg.copyWith(
                              color: NewTokens.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGlobalRuleCard() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NewTokens.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: NewTokens.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.ac_unit,
                    color: NewTokens.onPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Standart Çözünme & Dolap Ömrü Kuralı',
                        style: NewTokens.labelLg.copyWith(
                          color: NewTokens.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Otomatik vitrin sayacı politikası',
                        style: NewTokens.labelSm.copyWith(
                          color: NewTokens.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RichText(
              text: TextSpan(
                style: NewTokens.bodySm.copyWith(
                  color: NewTokens.onSurfaceVariant,
                ),
                children: [
                  const TextSpan(
                    text: 'Vitrine çıkarılan donuk pastalar için otomatik SKT sayacı çözünme anından itibaren ',
                  ),
                  TextSpan(
                    text: '72 saat (3 gün)',
                    style: NewTokens.bodySm.copyWith(
                      color: NewTokens.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const TextSpan(
                    text: ' olarak işletilir. Isı kontrolü dışına çıkan ürünler için erken imha protokolü uygulanır.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 44,
              decoration: BoxDecoration(
                color: NewTokens.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextButton.icon(
                onPressed: () {},
                icon: const Icon(
                  Icons.tune,
                  size: 18,
                  color: NewTokens.primary,
                ),
                label: Text(
                  'Varsayılan Raf Ömrü Kurallarını Güncelle',
                  style: NewTokens.labelMd.copyWith(
                    color: NewTokens.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      height: 64 + MediaQuery.of(context).padding.bottom,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: NewTokens.surface.withValues(alpha: 0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            offset: const Offset(0, -2),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(Icons.dashboard, 'Ana Sayfa', false),
          _buildNavItem(
            Icons.inventory_2,
            'Ürünler',
            true,
          ), // Assuming active on some screen
          _buildNavItem(Icons.timer, 'Öneri / SKT', false, badge: '72'),
          _buildNavItem(Icons.monitoring, 'Rapor', false),
          _buildNavItem(Icons.widgets, 'Menü', false),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    IconData icon,
    String label,
    bool active, {
    String? badge,
  }) {
    final color = active ? NewTokens.primary : NewTokens.onSurfaceVariant;
    return Expanded(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                style: NewTokens.labelSm.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          if (badge != null)
            Positioned(
              top: 8,
              right: 18,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: NewTokens.error,
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                alignment: Alignment.center,
                child: Text(
                  badge,
                  style: NewTokens.labelSm.copyWith(
                    color: NewTokens.onError,
                    fontSize: 9,
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

// Dialog implementation
Future<bool?> showProductTypeDialog(
  BuildContext context, {
  ProductType? type,
  required List<StoreOption> stores,
}) {
  final name = TextEditingController(text: type?.name ?? '');
  final skt = TextEditingController(text: '${type?.sktDays ?? 3}');
  final price = TextEditingController(
    text: type?.unitPrice == null ? '' : type!.unitPrice!.toString(),
  );
  final description = TextEditingController(text: type?.description ?? '');
  var active = type?.active ?? true;
  String category = 'cheesecake';
  final isSuper = session.user?.isSuperAdmin ?? false;
  int? storeId = type?.storeId;

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) {
          final bottomInsets = MediaQuery.of(context).viewInsets.bottom;
          return Container(
            margin: EdgeInsets.only(bottom: bottomInsets),
            decoration: const BoxDecoration(
              color: NewTokens.surfaceContainerLowest,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: NewTokens.secondaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.bakery_dining,
                          color: NewTokens.onSecondaryContainer,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              type == null
                                  ? 'Yeni Pasta Çeşidi'
                                  : 'Çeşidi Düzenle',
                              style: NewTokens.headlineSm.copyWith(
                                color: NewTokens.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Raf ömrü ve fiyat matris tanımı',
                              style: NewTokens.labelSm.copyWith(
                                color: NewTokens.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: NewTokens.outline),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                // Body
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Çeşit / Ürün Adı'),
                        _buildTextField(name, 'Örn: San Sebastian Cheesecake'),
                        const SizedBox(height: 12),
                        _buildLabel('Kısa Açıklama & Dolgu'),
                        _buildTextField(
                          description,
                          'Örn: Karamel soslu akışkan dokulu',
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('SKT Süresi (Gün)'),
                                  _buildTextField(
                                    skt,
                                    '3',
                                    suffix: 'Gün',
                                    isNumber: true,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('Birim Satış Fiyatı'),
                                  _buildTextField(
                                    price,
                                    '250',
                                    suffix: '₺',
                                    isNumber: true,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildLabel('Kategori Seçimi'),
                        Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: NewTokens.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: category,
                              isExpanded: true,
                              icon: const Icon(
                                Icons.arrow_drop_down,
                                color: NewTokens.onSurfaceVariant,
                              ),
                              style: NewTokens.bodyMd.copyWith(
                                color: NewTokens.onSurface,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'cheesecake',
                                  child: Text('Cheesecake Serisi'),
                                ),
                                DropdownMenuItem(
                                  value: 'pasta',
                                  child: Text('Katlı Pasta & Yaş Pasta'),
                                ),
                                DropdownMenuItem(
                                  value: 'fit',
                                  child: Text('Kek, Parfe & Sağlıklı'),
                                ),
                              ],
                              onChanged: (v) => setState(() => category = v!),
                            ),
                          ),
                        ),
                        if (isSuper) ...[
                          const SizedBox(height: 12),
                          _buildLabel('Mağaza'),
                          Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: NewTokens.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int?>(
                                value: storeId,
                                isExpanded: true,
                                icon: const Icon(
                                  Icons.arrow_drop_down,
                                  color: NewTokens.onSurfaceVariant,
                                ),
                                style: NewTokens.bodyMd.copyWith(
                                  color: NewTokens.onSurface,
                                ),
                                items: [
                                  const DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text(
                                      'Genel — tüm mağazalar kullanabilir',
                                    ),
                                  ),
                                  ...stores.map(
                                    (s) => DropdownMenuItem<int?>(
                                      value: s.id,
                                      child: Text('Yalnızca: ${s.name}'),
                                    ),
                                  ),
                                ],
                                onChanged: (v) => setState(() => storeId = v),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SwitchListTile(
                          value: active,
                          onChanged: (v) => setState(() => active = v),
                          title: Text(
                            'Aktif',
                            style: NewTokens.labelMd.copyWith(
                              color: NewTokens.onSurface,
                            ),
                          ),
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: NewTokens.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                // Footer
                Container(
                  padding: const EdgeInsets.all(16),
                  color: NewTokens.surfaceContainerLow,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'Vazgeç',
                          style: NewTokens.labelLg.copyWith(
                            color: NewTokens.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NewTokens.primary,
                          foregroundColor: NewTokens.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.check, size: 18),
                        label: Text(
                          'Kaydet',
                          style: NewTokens.labelLg.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () async {
                          if (name.text.trim().isEmpty)
                            return; // Simple validation for now
                          final days = int.tryParse(skt.text.trim());
                          num? unitPrice;
                          final priceText = price.text.trim().replaceAll(
                            ',',
                            '.',
                          );
                          if (priceText.isNotEmpty) {
                            unitPrice = num.tryParse(priceText);
                          }
                          try {
                            await repo.saveProductType(
                              id: type?.id,
                              name: name.text.trim(),
                              sktDays: days ?? 3,
                              unitPrice: unitPrice,
                              description: description.text.trim().isEmpty
                                  ? null
                                  : description.text.trim(),
                              active: active,
                              storeId: storeId,
                              includeStore: isSuper,
                            );
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            // ignore
                          }
                        },
                      ),
                    ],
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

Widget _buildLabel(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: NewTokens.labelMd.copyWith(
        color: NewTokens.onSurface,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

Widget _buildTextField(
  TextEditingController controller,
  String hint, {
  String? suffix,
  bool isNumber = false,
}) {
  return Container(
    height: 44,
    decoration: BoxDecoration(
      color: NewTokens.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
    ),
    child: TextField(
      controller: controller,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      style: NewTokens.bodyMd.copyWith(color: NewTokens.onSurface),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: NewTokens.bodyMd.copyWith(color: NewTokens.outline),
        suffixText: suffix,
        suffixStyle: NewTokens.labelMd.copyWith(color: NewTokens.outline),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        border: InputBorder.none,
      ),
    ),
  );
}
