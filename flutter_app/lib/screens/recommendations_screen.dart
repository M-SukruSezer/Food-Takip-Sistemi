import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/batch.dart';
import '../widgets/panels.dart';
import '../widgets/search_field.dart';
import '../widgets/sell_confirm_bottom_sheet.dart';
import 'batch_dialogs.dart';

/// Food dolabındaki tüm ürünler, SKT'si en yakın olan en üstte.
/// Arama listeyi ve kademe sayaçlarını birlikte filtreler (ekranda görünen ile
/// sayılan aynı olsun); SKT uyarısı güvenlik sinyali olduğu için filtreden
/// etkilenmez.
class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  final _searchController = TextEditingController();
  List<Batch> _items = const [];
  String _search = '';
  String _selectedCategory = 'Tümü';
  bool _hideExpiredBanner = false;
  String? _error;
  bool _loaded = false;

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

  String _categorize(Batch b) {
    final n = b.productName.toLowerCase();
    if (n.contains('pasta') ||
        n.contains('kek') ||
        n.contains('cheesecake') ||
        n.contains('brownie') ||
        n.contains('tatlı') ||
        n.contains('tatli')) {
      return 'Pastalar';
    }
    if (n.contains('kahve') ||
        n.contains('çay') ||
        n.contains('cay') ||
        n.contains('latte') ||
        n.contains('içecek') ||
        n.contains('icecek') ||
        n.contains('su')) {
      return 'İçecekler';
    }
    return 'Atıştırmalık';
  }

  Map<String, int> get _categoryCounts {
    final counts = <String, int>{
      'Tümü': _items.length,
      'Pastalar': 0,
      'Atıştırmalık': 0,
      'İçecekler': 0,
    };
    for (final b in _items) {
      final cat = _categorize(b);
      counts[cat] = (counts[cat] ?? 0) + 1;
    }
    return counts;
  }

  List<Batch> get _shown {
    final q = normalizeSearch(_search.trim());
    var list = _items;
    if (_selectedCategory != 'Tümü') {
      list = list.where((b) => _categorize(b) == _selectedCategory).toList();
    }
    if (q.isEmpty) return list;
    return list
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
    final ok = await showSellConfirmBottomSheet(context, b);
    if (ok != true) return;
    try {
      await repo.sellOne(b);
    } catch (_) {
      // Bildirim API katmanında gösterilir.
    }
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
    } catch (_) {
      // Bildirim API katmanında gösterilir.
    }
    await _load(silent: true);
  }

  Future<void> _discard(Batch b) async {
    final ok = await showDiscardDialog(context, b);
    if (ok == true) {
      await _load(silent: true);
    }
  }

  Future<void> _discardAll(List<Batch> expiredList) async {
    final count = _sum(expiredList);
    final ok = await _confirm(
      title: 'Tümünü Zayi Et',
      confirmLabel: 'Tümünü Zayi Et',
      danger: true,
      body: Text(
        '$count adet ürün (${expiredList.length} çeşit) için toplu zayi girilecek. Onaylıyor musunuz?',
      ),
    );
    if (ok != true) return;
    for (final b in expiredList) {
      try {
        await repo.discardAll(b);
      } catch (_) {
        // Bildirim API katmanında gösterilir.
      }
    }
    await _load(silent: true);
  }

  /// İkram stoktan düşer ama satış sayılmaz. Personel ikisini karıştırmasın
  /// diye onay metni bunu açıkça yazar.
  Widget _ikramMessage(Batch b) {
    final t = context.tokens;
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
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Ciroya '),
              const TextSpan(
                text: 'eklenmez',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: ' ve satış adedine sayılmaz.'),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (b.hasPrice)
          Text(
            'İkram değeri olarak ${fmtMoney(b.productUnitPrice)} kaydedilir.',
            style: TextStyle(color: t.muted, fontSize: 13),
          )
        else
          Text(
            'Bu çeşit için fiyat tanımlı olmadığı için ikram değeri kaydedilemez.',
            style: TextStyle(color: t.warning, fontSize: 13),
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
    final t = context.tokens;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: body,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: t.danger)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (!_loaded) return const SizedBox.shrink();
    if (_error != null && _items.isEmpty) {
      return Center(
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppAlert(message: _error!),
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

    final shown = _shown;
    final expired = _items.where((b) => b.isExpired).toList();
    final critical = shown
        .where((b) => b.urgency == 'critical' || b.isExpired)
        .toList();
    final warning = shown.where((b) => b.urgency == 'warning').toList();
    final normal = shown.where((b) => b.urgency == 'normal').toList();
    final filtering = _search.trim().isNotEmpty || _selectedCategory != 'Tümü';

    final shownExpired = shown.where((b) => b.isExpired).toList();
    final shownCritical =
        shown.where((b) => b.urgency == 'critical' && !b.isExpired).toList();
    final shownUpcoming =
        shown.where((b) => !b.isExpired && b.urgency != 'critical').toList();

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          if (expired.isNotEmpty && !_hideExpiredBanner) ...[
            _UrgentExpiredBanner(
              expiredCount: _sum(expired),
              skuCount: expired.length,
              canDiscard: session.user?.can('discard') ?? false,
              onDiscardAll: () => _discardAll(expired),
              onDismiss: () => setState(() => _hideExpiredBanner = true),
            ),
            const SizedBox(height: 8),
          ],
          Container(
            padding: const EdgeInsets.all(10),
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
                _TierRow(
                  critical: _sum(critical),
                  criticalCount: critical.length,
                  warning: _sum(warning),
                  warningCount: warning.length,
                  normal: _sum(normal),
                  normalCount: normal.length,
                ),
                const SizedBox(height: 8),
                ProductSearchField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _search = v),
                  onClear: () {
                    _searchController.clear();
                    setState(() => _search = '');
                  },
                  filtering: _search.trim().isNotEmpty,
                ),
                const SizedBox(height: 8),
                _CategoryChipsRow(
                  selected: _selectedCategory,
                  counts: _categoryCounts,
                  onSelected: (cat) => setState(() => _selectedCategory = cat),
                ),
                if (filtering) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Filtre etkin: ${_items.length} üründen ${shown.length} tanesi listeleniyor.',
                    style: TextStyle(fontSize: 11, color: t.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            AppCard(
              child: Text(
                'Food dolabında satışa hazır ürün bulunmuyor.',
                style: TextStyle(color: t.muted),
              ),
            )
          else if (shown.isEmpty)
            AppCard(
              child: Text(
                '"$_search" ile eşleşen ürün bulunamadı.',
                style: TextStyle(color: t.muted),
              ),
            )
          else ...[
            if (shownCritical.isNotEmpty) ...[
              _SectionHeader(
                title: 'Bugün SKT Dolanlar',
                countLabel: 'Öncelikli Satış',
                icon: Icons.access_time_rounded,
                color: context.tokens.primary,
              ),
              ...shownCritical.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RecommendationCard(
                    batch: b,
                    showStore: session.user?.isSuperAdmin ?? false,
                    onSell: () => _sell(b),
                    onIkram: (session.user?.can('ikram') ?? false)
                        ? () => _ikram(b)
                        : null,
                    onDiscard: (session.user?.can('discard') ?? false)
                        ? () => _discard(b)
                        : null,
                  ),
                ),
              ),
            ],
            if (shownUpcoming.isNotEmpty) ...[
              const _SectionHeader(
                title: 'Son 2–3 Gün Kalanlar',
                countLabel: 'İkram & Kampanya',
                icon: Icons.hourglass_bottom_rounded,
                color: Color(0xFF2563EB),
              ),
              ...shownUpcoming.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RecommendationCard(
                    batch: b,
                    showStore: session.user?.isSuperAdmin ?? false,
                    onSell: () => _sell(b),
                    onIkram: (session.user?.can('ikram') ?? false)
                        ? () => _ikram(b)
                        : null,
                    onDiscard: (session.user?.can('discard') ?? false)
                        ? () => _discard(b)
                        : null,
                  ),
                ),
              ),
            ],
            if (shownExpired.isNotEmpty) ...[
              _SectionHeader(
                title: "SKT'si Dolanlar",
                countLabel: '${shownExpired.length} SKU Bekliyor',
                icon: Icons.error_outline_rounded,
                color: t.danger,
              ),
              ...shownExpired.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RecommendationCard(
                    batch: b,
                    showStore: session.user?.isSuperAdmin ?? false,
                    onSell: () => _sell(b),
                    onIkram: (session.user?.can('ikram') ?? false)
                        ? () => _ikram(b)
                        : null,
                    onDiscard: (session.user?.can('discard') ?? false)
                        ? () => _discard(b)
                        : null,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _UrgentExpiredBanner extends StatelessWidget {
  const _UrgentExpiredBanner({
    required this.expiredCount,
    required this.skuCount,
    required this.canDiscard,
    required this.onDiscardAll,
    required this.onDismiss,
  });

  final int expiredCount;
  final int skuCount;
  final bool canDiscard;
  final VoidCallback onDiscardAll;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.dangerSoft,
        border: Border.all(color: t.danger.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: t.danger,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'ACİL OPERASYONEL',
                          style: TextStyle(
                            color: t.danger,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Şimdi',
                          style: TextStyle(
                            color: t.dangerStrong,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '$expiredCount adet ürünün SKT\'si doldu!',
                      style: TextStyle(
                        color: t.dangerStrong,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Lütfen vitrinden kaldırarak zayi fişi oluşturun veya satışı durdurun.',
            style: TextStyle(
              color: t.dangerStrong,
              fontSize: 11,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (canDiscard) ...[
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.delete_outline_rounded, size: 14),
                    label: Text(
                      'Tümünü Zayi Et ($expiredCount)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: t.dangerStrong,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: const Size(0, 30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: onDiscardAll,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.dangerStrong,
                  side: BorderSide(color: t.danger.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  minimumSize: const Size(0, 30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: onDismiss,
                child: const Text('Gizle',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryChipsRow extends StatelessWidget {
  const _CategoryChipsRow({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final String selected;
  final Map<String, int> counts;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final categories = ['Tümü', 'Pastalar', 'Atıştırmalık', 'İçecekler'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: categories.map((cat) {
          final isSelected = selected == cat;
          final count = counts[cat] ?? 0;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onSelected(cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected
                      ? t.primary
                      : t.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? t.primary
                        : t.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? t.onPrimary : t.ink,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.25)
                            : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.countLabel,
    required this.icon,
    required this.color,
  });

  final String title;
  final String countLabel;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4, left: 2, right: 2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              countLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.critical,
    required this.criticalCount,
    required this.warning,
    required this.warningCount,
    required this.normal,
    required this.normalCount,
  });

  final int critical;
  final int criticalCount;
  final int warning;
  final int warningCount;
  final int normal;
  final int normalCount;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tiles = [
      _Tier(
        color: t.danger,
        label: 'Son Gün',
        value: critical,
        count: criticalCount,
      ),
      _Tier(
        color: t.warning,
        label: '2 Gün',
        value: warning,
        count: warningCount,
      ),
      _Tier(
        color: t.primary,
        label: '3 Gün',
        value: normal,
        count: normalCount,
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

class _Tier extends StatelessWidget {
  const _Tier({
    required this.color,
    required this.label,
    required this.value,
    required this.count,
  });

  final Color color;
  final String label;
  final int value;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
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
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.batch,
    required this.showStore,
    required this.onSell,
    required this.onIkram,
    required this.onDiscard,
  });

  final Batch batch;
  final bool showStore;
  final VoidCallback onSell;

  /// Yetki yoksa null gelir ve düğme çizilmez.
  final VoidCallback? onIkram;
  final VoidCallback? onDiscard;

  ({String text, Color color, Color bg}) _badge(AppTokens t) =>
      switch (batch.urgency) {
        'expired' => (
            text: 'SKT Geçti',
            color: t.danger,
            bg: t.dangerSoft
          ),
        'critical' => (
            text: 'SON GÜN',
            color: t.danger,
            bg: t.dangerSoft
          ),
        'warning' => (
            text: '2 Gün Kaldı',
            color: t.info,
            bg: t.infoSoft
          ),
        _ => (
            text: 'Food Dolabı',
            color: t.primary,
            bg: t.primarySoft
          ),
      };

  Widget _buildProductThumbnail(BuildContext context, Batch batch) {
    final t = context.tokens;
    final name = batch.productName.toLowerCase();
    IconData icon = Icons.restaurant_rounded;
    Color bg = t.bg;
    Color iconColor = t.primary;

    if (name.contains('pasta') ||
        name.contains('kek') ||
        name.contains('cheesecake') ||
        name.contains('brownie') ||
        name.contains('tatlı') ||
        name.contains('tatli')) {
      icon = Icons.cake_outlined;
      bg = t.warningSoft;
      iconColor = t.warning;
    } else if (name.contains('poğaça') ||
        name.contains('pogaca') ||
        name.contains('börek') ||
        name.contains('borek') ||
        name.contains('simit') ||
        name.contains('cookie') ||
        name.contains('kurabiye')) {
      icon = Icons.bakery_dining_outlined;
      bg = t.warningSoft;
      iconColor = t.warningText;
    } else if (name.contains('kahve') ||
        name.contains('çay') ||
        name.contains('cay') ||
        name.contains('latte') ||
        name.contains('içecek') ||
        name.contains('icecek')) {
      icon = Icons.local_cafe_outlined;
      bg = t.infoSoft;
      iconColor = t.info;
    } else if (name.contains('salata') ||
        name.contains('sandviç') ||
        name.contains('sandvic') ||
        name.contains('dürüm')) {
      icon = Icons.lunch_dining_outlined;
      bg = t.successSoft;
      iconColor = t.success;
    }

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: Icon(icon, color: iconColor, size: 26),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final badge = _badge(t);

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProductThumbnail(context, batch),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            batch.productName,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: t.ink,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badge.bg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            badge.text,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: badge.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      children: [
                        Text(
                          '${batch.remaining} adet',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: t.muted,
                          ),
                        ),
                        if (batch.hasPrice) ...[
                          Text('•',
                              style: TextStyle(
                                  color: t.border, fontSize: 12)),
                          Text(
                            fmtMoney(batch.productUnitPrice),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: t.primary,
                            ),
                          ),
                        ],
                        if (showStore && batch.storeName != null) ...[
                          Text('•',
                              style: TextStyle(
                                  color: t.border, fontSize: 12)),
                          Text(
                            batch.storeName!,
                            style: TextStyle(
                              fontSize: 12,
                              color: t.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 13,
                          color: batch.isExpired
                              ? t.danger
                              : (batch.urgency == 'critical'
                                  ? t.warning
                                  : t.muted),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            batch.isExpired
                                ? 'SKT: ${fmtDateTime(batch.sktEnd)} [Süresi doldu]'
                                : (batch.urgency == 'critical'
                                    ? 'SKT: ${fmtDateTime(batch.sktEnd)} [${(batch.remainingHours ?? 0).floor()} sa kaldı]'
                                    : 'SKT: ${fmtDateTime(batch.sktEnd)} [${batch.daysLeft ?? 0} gün kaldı]'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: batch.urgency == 'critical' || batch.isExpired
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                              color: batch.isExpired
                                  ? t.danger
                                  : (batch.urgency == 'critical'
                                      ? t.warning
                                      : t.muted),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!batch.isExpired || onDiscard != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1, color: t.border),
            ),
            Row(
              children: [
                if (!batch.isExpired)
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: t.primary,
                          foregroundColor: t.onPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: onSell,
                        child: const Text(
                          'Satış',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                if (!batch.isExpired && onIkram != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: t.primary,
                          backgroundColor: t.primarySoft,
                          side: BorderSide(color: t.primary.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: onIkram,
                        child: const Text(
                          'İkram',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
                if (onDiscard != null) ...[
                  if (!batch.isExpired) const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: t.danger,
                          backgroundColor: t.dangerSoft,
                          side: BorderSide(color: t.danger.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: onDiscard,
                        child: const Text(
                          'Zayi',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
