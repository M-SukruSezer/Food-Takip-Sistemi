import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/notify.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/dashboard.dart';
import '../models/product_type.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/panels.dart';

/// Pasta cesitleri: SKT suresi ve satis fiyati burada tanimlanir.
/// Yazma yetkisi yalnizca Ana Yoneticide.
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

  // Ana Yonetici ya da "Pasta cesidi yonetimi" yetkisi verilmis kullanici.
  bool get _canManage => session.user?.can('manage_product_types') ?? false;

  @override
  void initState() {
    super.initState();
    _load();
    // Magaza listesi yalnizca Ana Yoneticiye acik (sunucu 403 doner); yetkili
    // mudur zaten kendi magazasina yazar, listeye ihtiyaci yok.
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
    final ok = await confirmDialog(
      context,
      title: 'Çeşidi Sil',
      confirmLabel: 'Sil',
      body: Text(
        '${type.name} çeşidi silinecek. Bu çeşide ait ürün kaydı varsa silinemez, '
        'pasife alınabilir.',
      ),
    );
    if (ok != true) return;
    try {
      await repo.deleteProductType(type);
    } catch (_) {
      // Bildirim API katmaninda gosterilir.
    }
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Fiyati tanimsiz aktif cesitler satildiginda ciroya 0 yazar.
    final missingPrice = _items.where((e) => e.active && !e.hasPrice).toList();

    return CrudScaffold(
      title: 'Pasta Çeşitleri ve SKT Süreleri',
      loaded: _loaded,
      error: _error,
      onRetry: () => _load(),
      onRefresh: () => _load(silent: true),
      addLabel: 'Yeni Çeşit',
      onAdd: _canManage ? () => _edit() : null,
      emptyText: 'Henüz ürün çeşidi eklenmemiş.',
      grid: true,
      banner: _canManage && missingPrice.isNotEmpty
          ? AppAlert(
              danger: false,
              icon: Icons.price_change_outlined,
              message:
                  '${missingPrice.length} aktif çeşidin satış fiyatı tanımlı değil. Bu çeşitler '
                  'satıldığında ciroya 0 TL yazılır: '
                  '${missingPrice.take(5).map((e) => e.name).join(', ')}'
                  '${missingPrice.length > 5 ? ' ve ${missingPrice.length - 5} çeşit daha' : ''}.',
            )
          : null,
      children: _items
          .map(
            (type) => AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          type.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: t.ink,
                          ),
                        ),
                      ),
                      if (!type.active) Pill(text: 'pasif', color: t.danger),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    type.description?.isNotEmpty == true
                        ? type.description!
                        : 'Açıklama yok',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: t.muted),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Pill(text: 'SKT: ${type.sktDays} gün', color: t.warning),
                      type.hasPrice
                          ? Pill(
                              text: fmtMoney(type.unitPrice),
                              color: t.success,
                            )
                          : Pill(text: 'Fiyat yok', color: t.danger),
                      if (type.isGlobal)
                        Pill(text: 'Genel', color: t.info)
                      else if (_canManage && type.storeName != null)
                        Pill(text: type.storeName!, color: t.info),
                    ],
                  ),
                  if (_canManage) ...[
                    const SizedBox(height: 10),
                    CardActions(
                      children: [
                        OutlinedButton(
                          onPressed: () => _edit(type),
                          child: const Text('Düzenle'),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: t.danger,
                            side: BorderSide(color: t.danger),
                          ),
                          onPressed: () => _delete(type),
                          child: const Text('Sil'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Cesit ekle/duzenle penceresi.
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
  int? storeId = type?.storeId;
  final isSuper = session.user?.isSuperAdmin ?? false;

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: type == null ? 'Yeni Pasta Çeşidi' : 'Çeşidi Düzenle',
      submitLabel: 'Kaydet',
      fields: (context, rebuild) => [
        LabeledField(
          label: 'Ürün Adı',
          child: TextField(
            controller: name,
            style: const TextStyle(fontSize: 16),
          ),
        ),
        // Kisa sayisal alanlar yan yana.
        FormRow(
          left: LabeledField(
            label: 'SKT Süresi (gün)',
            hint: '1 ile 14 arasında olmalıdır.',
            child: TextField(
              controller: skt,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          right: LabeledField(
            label: 'Satış Fiyatı (TL)',
            hint:
                'Satış yapıldığında ciro bu fiyattan otomatik hesaplanır. '
                'Boş bırakılırsa ciroya 0 TL yazılır.',
            child: TextField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
        LabeledField(
          label: 'Açıklama (opsiyonel)',
          child: TextField(
            controller: description,
            maxLines: 2,
            style: const TextStyle(fontSize: 16),
          ),
        ),
        if (isSuper)
          LabeledField(
            label: 'Mağaza',
            child: DropdownButtonFormField<int?>(
              initialValue: storeId,
              isExpanded: true,
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Genel — tüm mağazalar kullanabilir'),
                ),
                ...stores.map(
                  (s) => DropdownMenuItem<int?>(
                    value: s.id,
                    child: Text('Yalnızca: ${s.name}'),
                  ),
                ),
              ],
              onChanged: (v) {
                storeId = v;
                rebuild();
              },
            ),
          ),
        SwitchListTile(
          value: active,
          onChanged: (v) {
            active = v;
            rebuild();
          },
          title: const Text('Aktif'),
          contentPadding: EdgeInsets.zero,
        ),
      ],
      onSubmit: () async {
        if (name.text.trim().isEmpty) return 'Ürün adı zorunludur';
        final days = int.tryParse(skt.text.trim());
        if (days == null || days < 1 || days > 14) {
          return 'SKT süresi 1-14 gün arasında olmalıdır';
        }
        num? unitPrice;
        final priceText = price.text.trim().replaceAll(',', '.');
        if (priceText.isNotEmpty) {
          unitPrice = num.tryParse(priceText);
          if (unitPrice == null || unitPrice < 0) {
            return 'Satış fiyatı 0 veya daha büyük bir sayı olmalıdır';
          }
        }
        try {
          await repo.saveProductType(
            id: type?.id,
            name: name.text.trim(),
            sktDays: days,
            unitPrice: unitPrice,
            description: description.text.trim().isEmpty
                ? null
                : description.text.trim(),
            active: active,
            storeId: storeId,
            includeStore: isSuper,
          );
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}
