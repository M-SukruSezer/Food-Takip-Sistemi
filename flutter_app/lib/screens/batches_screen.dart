import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/batch_actions.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/batch.dart';
import '../models/dashboard.dart';
import '../models/product_type.dart';
import '../widgets/dialogs.dart';
import '../widgets/panels.dart';
import '../widgets/search_field.dart';
import 'batch_dialogs.dart';

/// Urunler / Stok. Dort sekme, satir basina bir ana islem + tasma menusu.
/// Satis bu ekrandan kaldirildi: satis Oneri Satis Listesi uzerinden yapiliyor.
class BatchesScreen extends StatefulWidget {
  const BatchesScreen({super.key, this.initialTab});

  /// Ana sayfadaki ozet kutularindan gelen sekme ('frozen', 'thawing',
  /// 'food_cabinet'). Taninmayan deger yok sayilir.
  final String? initialTab;

  @override
  State<BatchesScreen> createState() => _BatchesScreenState();
}

class _BatchesScreenState extends State<BatchesScreen> {
  static const _tabs = [
    (id: 'frozen', label: 'Donuk Depo', icon: Icons.ac_unit),
    (id: 'thawing', label: 'Çözünme', icon: Icons.hourglass_bottom),
    (id: 'food_cabinet', label: 'Satışa Hazır', icon: Icons.kitchen_outlined),
    (id: 'sold,discarded', label: 'Geçmiş', icon: Icons.history),
  ];

  final _searchController = TextEditingController();
  int _tab = 0;
  String _search = '';
  List<Batch> _items = const [];
  List<ProductType> _types = const [];
  List<StoreOption> _stores = const [];
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final requested = _tabs.indexWhere((t) => t.id == widget.initialTab);
    if (requested >= 0) _tab = requested;
    _load();
    repo
        .productTypes(silent: true)
        .then((list) {
          if (mounted) {
              setState(() => _types = list.where((t) => t.active).toList());
            }
        })
        .onError((Object _, StackTrace _) {});
    if (session.user?.isSuperAdmin ?? false) {
      repo
          .stores(silent: true)
          .then((list) {
            if (mounted) setState(() => _stores = list);
          })
          .onError((Object _, StackTrace _) {});
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final items = await repo.batches(status: _tabs[_tab].id, silent: silent);
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

  List<Batch> get _shown => filterBatches(_items, _search);

  Future<void> _after(Future<bool?> action) async {
    final ok = await action;
    if (ok == true) await _load(silent: true);
  }

  /// Parti silme geri alinamaz: bagli satis ve zayi kayitlari da gider.
  /// Bu yuzden onay metninde ne silinecegi acikca yaziliyor.
  Future<void> _deleteBatch(Batch b) async {
    final ok = await confirmDialog(
      context,
      title: 'Kaydı Sil',
      confirmLabel: 'Sil',
      body: Text(
        '${b.productName} (${statusLabels[b.status] ?? b.status}, ${b.remaining} adet kalan) '
        'kaydı silinecek.\n\nBu partiye ait satış, ikram ve zayi kayıtları da '
        'silinir. İşlem geri alınamaz.\n\nYalnızca adet yanlışsa silmek yerine '
        '"Tarih / Adet Düzelt" kullanın.',
      ),
    );
    if (ok != true) return;
    try {
      await repo.deleteBatch(b);
    } catch (_) {
      // Bildirim API katmanindan gelir.
    }
    await _load(silent: true);
  }

  Future<void> _completeThaw(Batch b) async {
    final ok = await confirmDialog(
      context,
      title: 'Food Dolabına Aktar',
      danger: false,
      confirmLabel: 'Aktar',
      body: Text(
        '${b.productName} (${b.remaining} adet) food dolabına aktarılacak. '
        'SKT süresi çözülmenin bittiği andan itibaren işler.',
      ),
    );
    if (ok != true) return;
    try {
      await repo.completeThaw(b);
    } catch (_) {
      // Bildirim API katmaninda gosterilir.
    }
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isSuper = session.user?.isSuperAdmin ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ürünler',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _types.isEmpty
                        ? null
                        : () => _after(
                            showAddBatchDialog(
                              context,
                              types: _types,
                              stores: _stores,
                            ),
                          ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Yeni Ürün'),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.gap),
              _TabBar(
                tabs: _tabs.map((e) => (label: e.label, icon: e.icon)).toList(),
                index: _tab,
                onChanged: (i) {
                  setState(() {
                    _tab = i;
                    _loaded = false;
                    _items = const [];
                  });
                  _load();
                },
              ),
              const SizedBox(height: AppTokens.gap),
              ProductSearchField(
                controller: _searchController,
                onChanged: (v) => setState(() => _search = v),
                onClear: () {
                  _searchController.clear();
                  setState(() => _search = '');
                },
                filtering: _search.trim().isNotEmpty,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.gap),
        Expanded(
          child: !_loaded
              ? const SizedBox.shrink()
              : _error != null && _items.isEmpty
              ? Center(
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
                )
              : RefreshIndicator(
                  onRefresh: () => _load(silent: true),
                  child: _shown.isEmpty
                      ? ListView(
                          children: [
                            AppCard(
                              child: Text(
                                _items.isEmpty
                                    ? 'Bu sekmede kayıt bulunamadı.'
                                    : '"$_search" ile eşleşen ürün bulunamadı.',
                                style: TextStyle(color: t.muted),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: _shown.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppTokens.gap),
                          itemBuilder: (context, i) => _BatchCard(
                            batch: _shown[i],
                            showStore: isSuper,
                            canAdjust:
                                session.user?.can('adjust_batches') ?? false,
                            canDiscard: session.user?.can('discard') ?? false,
                            canDelete: session.user?.isSuperAdmin ?? false,
                            onDetail: () => showBatchDetail(context, _shown[i]),
                            onAdjust: () =>
                                _after(showAdjustDialog(context, _shown[i])),
                            onThaw: () =>
                                _after(showThawDialog(context, _shown[i])),
                            onCompleteThaw: () => _completeThaw(_shown[i]),
                            onAddStock: () =>
                                _after(showStockAddDialog(context, _shown[i])),
                            onEarlyRequest: () => _after(
                              showEarlyRequestDialog(context, _shown[i]),
                            ),
                            onDiscard: () =>
                                _after(showDiscardDialog(context, _shown[i])),
                            onCorrectThaw: () => _after(
                              showCorrectThawDialog(context, _shown[i]),
                            ),
                            onDelete: () => _deleteBatch(_shown[i]),
                          ),
                        ),
                ),
        ),
      ],
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.tabs,
    required this.index,
    required this.onChanged,
  });

  final List<({String label, IconData icon})> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final narrow = MediaQuery.sizeOf(context).width < 641;
    // Telefonda dort sekme 2x2 izgaraya oturur; yatay kaydirma gerekmez.
    return GridView.count(
      crossAxisCount: narrow ? 2 : 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: narrow ? 3.4 : 3.8,
      children: List.generate(tabs.length, (i) {
        final active = i == index;
        return InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          onTap: () => onChanged(i),
          child: Container(
            constraints: const BoxConstraints(minHeight: AppTokens.tap),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? t.primary : t.card,
              border: Border.all(color: active ? t.primary : t.borderStrong),
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  tabs[i].icon,
                  size: 15,
                  color: active ? Colors.white : t.ink,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    tabs[i].label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: narrow ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : t.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({
    required this.batch,
    required this.showStore,
    required this.canAdjust,
    required this.canDiscard,
    required this.canDelete,
    required this.onDetail,
    required this.onAdjust,
    required this.onThaw,
    required this.onCompleteThaw,
    required this.onAddStock,
    required this.onEarlyRequest,
    required this.onDiscard,
    required this.onCorrectThaw,
    required this.onDelete,
  });

  final Batch batch;
  final bool showStore;
  final bool canAdjust;
  final bool canDiscard;

  /// Parti silme yalnizca ana yoneticide; geri alinamaz.
  final bool canDelete;
  final VoidCallback onDetail;
  final VoidCallback onAdjust;
  final VoidCallback onThaw;
  final VoidCallback onCompleteThaw;
  final VoidCallback onAddStock;
  final VoidCallback onEarlyRequest;
  final VoidCallback onDiscard;
  final VoidCallback onCorrectThaw;
  final VoidCallback onDelete;

  ({String text, Color color}) _badge(AppTokens t) {
    if (batch.status == 'food_cabinet') {
      return switch (batch.urgency) {
        'expired' => (text: 'SKT Geçti', color: t.danger),
        'critical' => (text: 'SON GÜN', color: t.danger),
        'warning' => (text: 'Son 2 Gün', color: t.warning),
        _ => (text: 'Food Dolabı', color: t.success),
      };
    }
    return switch (batch.status) {
      'frozen' => (text: 'Donuk Depo', color: t.info),
      'thawing' => (text: 'Çözülme', color: t.warning),
      'sold' => (text: 'Satıldı', color: t.success),
      'discarded' => (text: 'Zayi', color: t.muted),
      _ => (text: batch.status, color: t.muted),
    };
  }

  /// Satirda yalnizca o an anlamli olan ana islem durur; gerisi menude.
  /// Karar batch_actions.dart icindeki saf fonksiyondan gelir.
  Widget? _primaryWidget(AppTokens t, BatchAction? action) => switch (action) {
    BatchAction.thaw => FilledButton(
      onPressed: onThaw,
      child: const Text('Çözülmeye Al'),
    ),
    BatchAction.completeThaw => FilledButton(
      style: FilledButton.styleFrom(backgroundColor: t.success),
      onPressed: onCompleteThaw,
      child: const Text('Food Dolabına Al'),
    ),
    BatchAction.awaitingApproval => Container(
      constraints: const BoxConstraints(minHeight: AppTokens.tap),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Text(
        'Onay Bekliyor',
        style: TextStyle(
          color: t.warning,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    ),
    _ => null,
  };

  _MenuEntry _entry(BatchAction a) => switch (a) {
    BatchAction.detail => (
      label: 'Detay',
      icon: Icons.info_outline,
      danger: false,
      onTap: onDetail,
    ),
    BatchAction.adjust => (
      label: 'Tarih / Adet Düzelt',
      icon: Icons.edit_outlined,
      danger: false,
      onTap: onAdjust,
    ),
    BatchAction.addStock => (
      label: 'Stok Ekle',
      icon: Icons.add_box_outlined,
      danger: false,
      onTap: onAddStock,
    ),
    BatchAction.earlyRequest => (
      label: 'Erken Aktarım İste (${formatHours(batch.thawRemainingHours)})',
      icon: Icons.hourglass_bottom,
      danger: false,
      onTap: onEarlyRequest,
    ),
    BatchAction.discard => (
      label: 'Zayi Gir',
      icon: Icons.delete_outline,
      danger: true,
      onTap: onDiscard,
    ),
    BatchAction.correctThaw => (
      label: 'Çözülme Adedini Düzelt',
      icon: Icons.undo,
      danger: false,
      onTap: onCorrectThaw,
    ),
    BatchAction.deleteBatch => (
      label: 'Kaydı Sil',
      icon: Icons.delete_forever_outlined,
      danger: true,
      onTap: onDelete,
    ),
    _ => (label: '-', icon: Icons.help_outline, danger: false, onTap: onDetail),
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final badge = _badge(t);
    final actions = batchActionsFor(
      batch,
      canAdjust: canAdjust,
      canDiscard: canDiscard,
      canDelete: canDelete,
    );
    final primary = _primaryWidget(t, actions.primary);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppTokens.radius),
      ),
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
                    fontSize: 15,
                    color: t.ink,
                  ),
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
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _meta(t, 'Adet', '${batch.remaining}/${batch.quantity}'),
              if (showStore && batch.storeName != null)
                _meta(t, 'Mağaza', batch.storeName!),
              if (batch.sktEnd != null)
                _meta(
                  t,
                  'SKT',
                  '${fmtDateTime(batch.sktEnd)} · ${formatHours(batch.remainingHours)}',
                ),
              if (batch.status == 'thawing' && !batch.thawReady)
                _meta(t, 'Çözülmeye', formatHours(batch.thawRemainingHours)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (primary != null) Expanded(child: primary),
              if (primary != null) const SizedBox(width: 8),
              if (primary == null) const Spacer(),
              _ActionMenu(items: actions.menu.map(_entry).toList()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(AppTokens t, String label, String value) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$label: ',
          style: TextStyle(fontSize: 12, color: t.muted),
        ),
        TextSpan(
          text: value,
          style: TextStyle(
            fontSize: 12,
            color: t.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

typedef _MenuEntry = ({
  String label,
  IconData icon,
  bool danger,
  VoidCallback onTap,
});

class _ActionMenu extends StatelessWidget {
  const _ActionMenu({required this.items});

  final List<_MenuEntry> items;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PopupMenuButton<int>(
      tooltip: 'Diğer işlemler',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 200),
      onSelected: (i) => items[i].onTap(),
      itemBuilder: (context) => [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: AppTokens.tap,
            child: Row(
              children: [
                Icon(
                  items[i].icon,
                  size: 18,
                  color: items[i].danger ? t.danger : t.ink,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    items[i].label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: items[i].danger ? t.danger : t.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        width: AppTokens.tap,
        height: AppTokens.tap,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: t.borderStrong),
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
        child: Icon(Icons.more_vert, size: 18, color: t.ink),
      ),
    );
  }
}
