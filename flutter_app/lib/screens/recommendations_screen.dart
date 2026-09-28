import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/batch.dart';
import '../widgets/panels.dart';
import '../widgets/search_field.dart';

/// Food dolabindaki tum urunler, SKT'si en yakin olan en ustte.
/// Arama listeyi ve kademe sayaclarini birlikte filtreler (ekranda gorunen ile
/// sayilan ayni olsun); SKT uyarisi guvenlik sinyali oldugu icin filtreden
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
    } catch (_) {
      // Bildirim API katmaninda gosterilir.
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
      // Bildirim API katmaninda gosterilir.
    }
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
    } catch (_) {
      // Bildirim API katmaninda gosterilir.
    }
    await _load(silent: true);
  }

  Widget _sellMessage(Batch b) {
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
          Text(
            'Bu çeşit için satış fiyatı tanımlı değil; ciroya 0 TL yazılacak.',
            style: TextStyle(color: t.warning),
          ),
      ],
    );
  }

  /// Ikram stoktan duser ama satis sayilmaz. Personel ikisini karistirmasin
  /// diye onay metni bunu acikca yazar.
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
    final filtering = _search.trim().isNotEmpty;

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (expired.isNotEmpty) ...[
            AppAlert(
              message:
                  '${_sum(expired)} adet ürünün SKT\'si doldu. Lütfen zayi girin veya satışı durdurun.',
            ),
            const SizedBox(height: AppTokens.gap),
          ],
          AppCard(
            child: Column(
              children: [
                _TierRow(
                  critical: _sum(critical),
                  criticalCount: critical.length,
                  warning: _sum(warning),
                  warningCount: warning.length,
                  normal: _sum(normal),
                  normalCount: normal.length,
                ),
                const SizedBox(height: AppTokens.gap),
                ProductSearchField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _search = v),
                  onClear: () {
                    _searchController.clear();
                    setState(() => _search = '');
                  },
                  filtering: filtering,
                ),
                if (filtering) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Arama etkin: ${_items.length} üründen ${shown.length} tanesi gösteriliyor. '
                      'Kademe sayıları da bu sonuca göre.',
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppTokens.gap),
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
          else
            ...shown.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.gap),
                child: _RecommendationCard(
                  batch: b,
                  showStore: session.user?.isSuperAdmin ?? false,
                  onSell: () => _sell(b),
                  // Yetkisi olmayan kullanicida dugme hic cizilmez.
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
        color: t.success,
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
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppTokens.radius),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  // React tarafinda 10px'ti ve okunmuyordu; 11px taban.
                  style: TextStyle(
                    fontSize: 11,
                    color: t.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
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

  /// Yetki yoksa null gelir ve dugme cizilmez.
  final VoidCallback? onIkram;
  final VoidCallback? onDiscard;

  ({String text, Color color}) _badge(AppTokens t) => switch (batch.urgency) {
    'expired' => (text: 'SKT Geçti', color: t.danger),
    'critical' => (text: 'SON GÜN', color: t.danger),
    'warning' => (text: 'Son 2 Gün', color: t.warning),
    _ => (text: 'Food Dolabı', color: t.success),
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final badge = _badge(t);
    // Soldaki aciliyet seridi kenarlik olarak verilemez: Flutter yuvarlatilmis
    // kosede tek kenari farkli renkte cizemiyor ("borderRadius can only be
    // given on borders with uniform colors") ve boyama hata veriyor. Serit
    // ayri bir cocuk olarak cizilir, kart kenarligi duz kalir.
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppTokens.radius),
      ),
      // IntrinsicHeight olmadan stretch, kaydirilabilir listede sonsuz yukseklik
      // istiyor; serit yuksekligini govdeden almali.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: badge.color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          batch.productName,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: t.ink,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: badge.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge.text,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: badge.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Text(
                          '${batch.remaining} adet',
                          style: TextStyle(fontSize: 12, color: t.muted),
                        ),
                        Text(
                          'SKT: ${fmtDateTime(batch.sktEnd)}',
                          style: TextStyle(fontSize: 12, color: t.muted),
                        ),
                        Text(
                          '${batch.daysLeft ?? 0} gün (${(batch.remainingHours ?? 0).floor()} sa)',
                          style: TextStyle(
                            fontSize: 12,
                            color: t.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (showStore && batch.storeName != null)
                          Text(
                            batch.storeName!,
                            style: TextStyle(fontSize: 12, color: t.muted),
                          ),
                      ],
                    ),
                    // SKT'si gecmis urun + zayi yetkisi yok: hic dugme kalmaz,
                    // bosluk da cizilmez.
                    if (!batch.isExpired || onDiscard != null)
                      const SizedBox(height: 10),
                    // Uc dugme telefonda da yan yana sigiyor (390px'de ~112px her biri).
                    // SKT'si gecen urunde satis/ikram yok; yetkisi olmayan
                    // kullanicida ilgili dugme hic cizilmedigi icin kalanlar
                    // genisligi paylasir.
                    Row(
                      children: [
                        if (!batch.isExpired)
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: t.success,
                              ),
                              onPressed: onSell,
                              child: const Text('Satış'),
                            ),
                          ),
                        if (!batch.isExpired && onIkram != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onIkram,
                              child: const Text('İkram'),
                            ),
                          ),
                        ],
                        if (onDiscard != null) ...[
                          if (!batch.isExpired) const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: t.danger,
                                side: BorderSide(color: t.danger),
                              ),
                              onPressed: onDiscard,
                              child: const Text('Zayi'),
                            ),
                          ),
                        ],
                      ],
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
