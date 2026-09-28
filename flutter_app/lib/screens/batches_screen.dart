import 'package:flutter/material.dart';
import '../core/new_theme.dart';

import '../core/api_client.dart';
import '../core/batch_actions.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/batch.dart';
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
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final requested = _tabs.indexWhere((t) => t.id == widget.initialTab);
    if (requested >= 0) _tab = requested;
    _load();
    // Cesit ve magaza listesi ONCEDEN CEKILMIYOR: "Yeni Ürün" islemi artik
    // yuzen dugmede ve o kisayol veriyi kendisi, yukleme katmani gorunurken
    // cekiyor. Her ekran acilisinda iki istek atmanin gerekcesi kalmadi.
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
    final isSuper = session.user?.isSuperAdmin ?? false;

    return Scaffold(
      backgroundColor: NewTokens.surface,
      body: !_loaded
          ? const Center(child: CircularProgressIndicator(color: NewTokens.primary))
          : _error != null && _items.isEmpty
              ? Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: NewTokens.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 1))],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: NewTokens.bodyMd.copyWith(color: NewTokens.error)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => _load(),
                          style: ElevatedButton.styleFrom(backgroundColor: NewTokens.primary),
                          child: Text('Tekrar Dene', style: NewTokens.labelLg.copyWith(color: NewTokens.onPrimary)),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(silent: true),
                  color: NewTokens.primary,
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.only(top: 16, bottom: 8, left: 16, right: 16),
                        sliver: SliverToBoxAdapter(child: _buildHeader()),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.only(top: 4, bottom: 16, left: 16, right: 16),
                        sliver: SliverToBoxAdapter(child: _buildSegmentedTabs()),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _SearchHeaderDelegate(
                          child: _buildSearchInput(),
                        ),
                      ),
                      SliverToBoxAdapter(child: _buildFilterChips()),
                      SliverPadding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8, left: 16, right: 16),
                        sliver: SliverToBoxAdapter(child: _buildInfoBanner()),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.only(top: 8, bottom: 40, left: 16, right: 16),
                        sliver: _shown.isEmpty
                            ? SliverToBoxAdapter(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: NewTokens.surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 1))],
                                  ),
                                  child: Text(
                                    _items.isEmpty
                                        ? 'Bu sekmede kayıt bulunamadı.'
                                        : '"$_search" ile eşleşen ürün bulunamadı.',
                                    style: NewTokens.bodyMd.copyWith(color: NewTokens.onSurfaceVariant),
                                  ),
                                ),
                              )
                            : SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final batch = _shown[index];
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _buildProductCard(
                                        batch: batch,
                                        isSuper: isSuper,
                                        canAdjust: session.user?.can('adjust_batches') ?? false,
                                        canDiscard: session.user?.can('discard') ?? false,
                                        canDelete: session.user?.isSuperAdmin ?? false,
                                      ),
                                    );
                                  },
                                  childCount: _shown.length,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ürünler & Stok Yönetimi', style: NewTokens.headlineMd.copyWith(color: NewTokens.onSurface)),
                  Text('Donuk depo sayımı, çözünme süreci ve vitrin hazırlığı', style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: () {
                // + Giriş Button (handled in batch dialogs / external)
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: NewTokens.primary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1))],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.add_box, size: 18, color: NewTokens.onPrimary),
                    const SizedBox(width: 6),
                    Text('+ Giriş', style: NewTokens.labelMd.copyWith(color: NewTokens.onPrimary)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                title: 'Donuk Depo',
                icon: Icons.ac_unit,
                iconColor: NewTokens.primary,
                value: '1.147',
                suffix: '/ 47 çeşit',
                bottomIcon: Icons.check_circle,
                bottomText: 'Son sayım: 08:30',
                bottomColor: NewTokens.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildKpiCard(
                title: 'Çözünmede',
                icon: Icons.hourglass_top,
                iconColor: NewTokens.secondary,
                value: '14',
                suffix: 'paket aktif',
                bottomIcon: Icons.schedule,
                bottomText: 'En erken: 45 dk',
                bottomColor: NewTokens.onSurfaceVariant,
                valueColor: NewTokens.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                title: 'Satışa Hazır',
                icon: Icons.storefront,
                iconColor: NewTokens.tertiary,
                value: '72',
                suffix: 'vitrinde',
                bottomIcon: Icons.verified,
                bottomText: 'SKT Güvenli',
                bottomColor: NewTokens.tertiary,
                valueColor: NewTokens.tertiary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildKpiCard(
                title: 'Kritik Stok',
                icon: Icons.warning,
                iconColor: NewTokens.error,
                value: '4',
                suffix: 'ürün azaldı',
                bottomIcon: Icons.priority_high,
                bottomText: 'Sipariş verilmeli',
                bottomColor: NewTokens.error,
                valueColor: NewTokens.error,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String value,
    required String suffix,
    required IconData bottomIcon,
    required String bottomText,
    required Color bottomColor,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title.toUpperCase(), style: NewTokens.labelSm.copyWith(color: NewTokens.onSurfaceVariant, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
              Icon(icon, size: 18, color: iconColor),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: NewTokens.numericMetric.copyWith(color: valueColor ?? NewTokens.onSurface, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Expanded(child: Text(suffix, style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant, fontWeight: FontWeight.w500))),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(bottomIcon, size: 13, color: bottomColor),
              const SizedBox(width: 4),
              Expanded(child: Text(bottomText, style: NewTokens.labelSm.copyWith(color: bottomColor, fontWeight: FontWeight.w600))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedTabs() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 3.5,
        children: List.generate(_tabs.length, (i) {
          final active = i == _tab;
          final tab = _tabs[i];
          
          Widget? badge;
          if (tab.id == 'thawing') {
            badge = Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: NewTokens.secondary, borderRadius: BorderRadius.circular(999)),
              child: Text('14', style: NewTokens.labelSm.copyWith(color: NewTokens.onSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
            );
          } else if (tab.id == 'food_cabinet') {
            badge = Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: NewTokens.surfaceContainer, borderRadius: BorderRadius.circular(999)),
              child: Text('72', style: NewTokens.labelSm.copyWith(color: NewTokens.primary, fontSize: 10, fontWeight: FontWeight.bold)),
            );
          }

          return InkWell(
            onTap: () {
              setState(() {
                _tab = i;
                _loaded = false;
                _items = const [];
              });
              _load();
            },
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? NewTokens.primary : NewTokens.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                boxShadow: active ? const [BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1))] : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(tab.icon, size: 20, color: active ? NewTokens.onPrimary : NewTokens.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(tab.label, style: NewTokens.headlineSm.copyWith(fontSize: 14, color: active ? NewTokens.onPrimary : NewTokens.onSurface, fontWeight: active ? FontWeight.bold : FontWeight.w600)),
                  ?badge,
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSearchInput() {
    return Container(
      color: NewTokens.surface,
      padding: const EdgeInsets.only(top: 8, bottom: 8, left: 16, right: 16),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _search = v),
        style: NewTokens.bodyMd.copyWith(color: NewTokens.onSurface),
        decoration: InputDecoration(
          hintText: 'Ürün adı, barkod veya kod ile ara...',
          hintStyle: NewTokens.bodyMd.copyWith(color: NewTokens.outline),
          prefixIcon: const Icon(Icons.search, size: 20, color: NewTokens.onSurfaceVariant),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: NewTokens.surfaceContainer,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 16, color: NewTokens.onSurfaceVariant),
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _search = '');
                  },
                )
              : null,
          filled: true,
          fillColor: NewTokens.surfaceContainerLowest,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildChip('Tümü (47)', true),
          const SizedBox(width: 8),
          _buildChip('Kruvasan & Açma (8)', false),
          const SizedBox(width: 8),
          _buildChip('Cheesecake (9)', false),
          const SizedBox(width: 8),
          _buildChip('Pastalar (18)', false),
          const SizedBox(width: 8),
          _buildChip('Brownie & Bar (12)', false),
        ],
      ),
    );
  }

  Widget _buildChip(String label, bool active) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? NewTokens.primary : NewTokens.surfaceContainer,
          borderRadius: BorderRadius.circular(999),
          boxShadow: active ? const [BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1))] : null,
        ),
        child: Text(
          label,
          style: NewTokens.labelMd.copyWith(
            color: active ? NewTokens.onPrimary : NewTokens.onSurfaceVariant,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.info, size: 20, color: NewTokens.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Otomatik Çözünme Protokolü', style: NewTokens.labelSm.copyWith(color: NewTokens.primary, fontWeight: FontWeight.bold)),
                Text('"Çözülmeye Al" işlemiyle seçilen adet Donuk Depo'dan düşülür, 72 saatlik geri sayım sayacı başlar.', style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant, fontSize: 11, height: 1.2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard({
    required Batch batch,
    required bool isSuper,
    required bool canAdjust,
    required bool canDiscard,
    required bool canDelete,
  }) {
    final actions = batchActionsFor(
      batch,
      canAdjust: canAdjust,
      canDiscard: canDiscard,
      canDelete: canDelete,
    );

    String badgeText = '';
    Color badgeColor = NewTokens.primary;
    Color badgeBg = NewTokens.surfaceContainer;

    if (batch.status == 'food_cabinet') {
      badgeText = 'Food Dolabı';
      badgeColor = NewTokens.tertiary;
      if (batch.urgency == 'expired' || batch.urgency == 'critical') {
        badgeText = batch.urgency == 'expired' ? 'SKT Geçti' : 'SON GÜN';
        badgeColor = NewTokens.error;
        badgeBg = NewTokens.errorContainer;
      } else if (batch.urgency == 'warning') {
        badgeText = 'Son 2 Gün';
        badgeColor = NewTokens.primary; // fallback warning since tokens don't have explicit warning
      }
    } else {
      switch (batch.status) {
        case 'frozen':
          badgeText = 'Donuk Depo';
          badgeColor = NewTokens.primary;
          break;
        case 'thawing':
          badgeText = 'Çözülme';
          badgeColor = NewTokens.secondary;
          break;
        case 'sold':
          badgeText = 'Satıldı';
          badgeColor = NewTokens.tertiary;
          break;
        case 'discarded':
          badgeText = 'Zayi';
          badgeColor = NewTokens.onSurfaceVariant;
          break;
        default:
          badgeText = batch.status;
          badgeColor = NewTokens.onSurfaceVariant;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NewTokens.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(batch.productName.toUpperCase(), style: NewTokens.headlineSm.copyWith(color: NewTokens.onSurface, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(text: 'Adet: ', style: NewTokens.labelMd.copyWith(color: NewTokens.onSurface, fontWeight: FontWeight.w600)),
                              TextSpan(text: '${batch.remaining}/${batch.quantity}', style: NewTokens.labelMd.copyWith(color: NewTokens.primary, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Container(
                          width: 4,
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: const BoxDecoration(color: NewTokens.outlineVariant, shape: BoxShape.circle),
                        ),
                        Expanded(
                          child: Text(
                            batch.sktEnd != null 
                                ? 'SKT: ${fmtDateTime(batch.sktEnd)} · ${formatHours(batch.remainingHours)}' 
                                : 'Çözünme: ${batch.thawRemainingHours != null ? formatHours(batch.thawRemainingHours) : "-"}',
                            style: NewTokens.bodySm.copyWith(color: NewTokens.onSurfaceVariant, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeText,
                  style: NewTokens.labelSm.copyWith(color: badgeColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (actions.primary != null)
                Expanded(
                  child: actions.primary == BatchAction.thaw
                      ? ElevatedButton.icon(
                          onPressed: () => _after(showThawDialog(context, batch)),
                          icon: const Icon(Icons.ac_unit, size: 20),
                          label: const Text('Çözülmeye Al'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: NewTokens.primary,
                            foregroundColor: NewTokens.onPrimary,
                            textStyle: NewTokens.labelLg.copyWith(fontWeight: FontWeight.bold),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 1,
                          ),
                        )
                      : actions.primary == BatchAction.completeThaw
                          ? ElevatedButton.icon(
                              onPressed: () => _completeThaw(batch),
                              icon: const Icon(Icons.kitchen, size: 20),
                              label: const Text('Food Dolabına Al'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: NewTokens.tertiary,
                                foregroundColor: NewTokens.onTertiary,
                                textStyle: NewTokens.labelLg.copyWith(fontWeight: FontWeight.bold),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 1,
                              ),
                            )
                          : Container(
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: NewTokens.surfaceContainerLow, // Fallback
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('Onay Bekliyor', style: NewTokens.labelLg.copyWith(color: NewTokens.onSurfaceVariant, fontWeight: FontWeight.bold)),
                            ),
                ),
              if (actions.primary != null) const SizedBox(width: 8),
              if (actions.primary == null) const Spacer(),
              _buildActionMenu(actions.menu, batch),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionMenu(List<BatchAction> items, Batch batch) {
    return PopupMenuButton<BatchAction>(
      tooltip: 'İşlem Menüsü',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: NewTokens.surfaceContainerLowest,
      onSelected: (action) {
        switch (action) {
          case BatchAction.detail: showBatchDetail(context, batch); break;
          case BatchAction.adjust: _after(showAdjustDialog(context, batch)); break;
          case BatchAction.addStock: _after(showStockAddDialog(context, batch)); break;
          case BatchAction.earlyRequest: _after(showEarlyRequestDialog(context, batch)); break;
          case BatchAction.discard: _after(showDiscardDialog(context, batch)); break;
          case BatchAction.correctThaw: _after(showCorrectThawDialog(context, batch)); break;
          case BatchAction.deleteBatch: _deleteBatch(batch); break;
          default: showBatchDetail(context, batch); break;
        }
      },
      itemBuilder: (context) {
        return items.map((a) {
          IconData icon = Icons.help_outline;
          String label = '-';
          bool danger = false;
          
          switch (a) {
            case BatchAction.detail: icon = Icons.info_outline; label = 'Detay'; break;
            case BatchAction.adjust: icon = Icons.edit_outlined; label = 'Tarih / Adet Düzelt'; break;
            case BatchAction.addStock: icon = Icons.add_box_outlined; label = 'Stok Ekle'; break;
            case BatchAction.earlyRequest: icon = Icons.hourglass_bottom; label = 'Erken Aktarım İste'; break;
            case BatchAction.discard: icon = Icons.delete_outline; label = 'Zayi Gir'; danger = true; break;
            case BatchAction.correctThaw: icon = Icons.undo; label = 'Çözülme Adedini Düzelt'; break;
            case BatchAction.deleteBatch: icon = Icons.delete_forever_outlined; label = 'Kaydı Sil'; danger = true; break;
            default: break;
          }
          
          return PopupMenuItem<BatchAction>(
            value: a,
            child: Row(
              children: [
                Icon(icon, size: 20, color: danger ? NewTokens.error : NewTokens.onSurfaceVariant),
                const SizedBox(width: 12),
                Text(label, style: NewTokens.labelLg.copyWith(color: danger ? NewTokens.error : NewTokens.onSurface)),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: NewTokens.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.more_vert, size: 20, color: NewTokens.onSurfaceVariant),
      ),
    );
  }
}
