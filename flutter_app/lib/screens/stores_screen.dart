import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/notify.dart';
import '../core/repository.dart';
import '../core/tokens.dart';
import '../models/store.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/panels.dart';

/// Magazalar: yalnizca Ana Yonetici erisir (sunucu tarafinda da zorunlu).
class StoresScreen extends StatefulWidget {
  const StoresScreen({super.key});

  @override
  State<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends State<StoresScreen> {
  List<Store> _items = const [];
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final items = await repo.storeList(silent: silent);
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

  Future<void> _edit([Store? store]) async {
    final ok = await showStoreDialog(context, store: store);
    if (ok == true) {
      toastSaved(store == null ? 'Mağaza eklendi' : 'Mağaza güncellendi');
      await _load(silent: true);
    }
  }

  Future<void> _delete(Store store) async {
    final ok = await confirmDialog(
      context,
      title: 'Mağazayı Sil',
      confirmLabel: 'Sil',
      body: Text('${store.name} silinecek. Bu mağazaya tanımlı ürün çeşitleri de silinir.'),
    );
    if (ok != true) return;
    try {
      await repo.deleteStore(store);
    } catch (_) {
      // Hata bildirimi API katmanindan gelir.
    }
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return CrudScaffold(
      title: 'Mağazalar',
      loaded: _loaded,
      error: _error,
      onRetry: () => _load(),
      onRefresh: () => _load(silent: true),
      addLabel: 'Yeni Mağaza',
      onAdd: () => _edit(),
      emptyText: 'Henüz mağaza eklenmemiş.',
      grid: true,
      children: _items
          .map((store) => AppCardStore(
                store: store,
                onEdit: () => _edit(store),
                onDelete: store.deletable ? () => _delete(store) : null,
                inkColor: t.ink,
              ))
          .toList(),
    );
  }
}

/// Magaza karti. Silme yalnizca bagli kaydi olmayan magazalarda acik.
class AppCardStore extends StatelessWidget {
  const AppCardStore({
    super.key,
    required this.store,
    required this.onEdit,
    required this.onDelete,
    required this.inkColor,
  });

  final Store store;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final Color inkColor;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(store.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: inkColor)),
              ),
              Pill(text: store.active ? 'aktif' : 'pasif', color: store.active ? t.success : t.danger),
            ],
          ),
          const SizedBox(height: 6),
          Text(store.address?.isNotEmpty == true ? store.address! : 'Adres girilmemiş',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: t.muted)),
          Text(store.phone?.isNotEmpty == true ? store.phone! : 'Telefon girilmemiş',
              style: TextStyle(fontSize: 13, color: t.muted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Pill(text: '${store.userCount} personel', color: t.info),
              Pill(text: '${store.activeBatchCount} aktif ürün', color: t.warning),
            ],
          ),
          const SizedBox(height: 10),
          CardActions(children: [
            OutlinedButton(onPressed: onEdit, child: const Text('Düzenle')),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: onDelete == null ? t.muted : t.danger,
                side: BorderSide(color: onDelete == null ? t.border : t.danger),
              ),
              onPressed: onDelete,
              child: const Text('Sil'),
            ),
          ]),
        ],
      ),
    );
  }
}

Future<bool?> showStoreDialog(BuildContext context, {Store? store}) {
  final name = TextEditingController(text: store?.name ?? '');
  final address = TextEditingController(text: store?.address ?? '');
  final phone = TextEditingController(text: store?.phone ?? '');
  var active = store?.active ?? true;

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: store == null ? 'Yeni Mağaza' : 'Mağazayı Düzenle',
      submitLabel: 'Kaydet',
      fields: (context, rebuild) => [
        LabeledField(
          label: 'Mağaza Adı',
          child: TextField(controller: name, style: const TextStyle(fontSize: 16)),
        ),
        LabeledField(
          label: 'Adres (opsiyonel)',
          child: TextField(controller: address, maxLines: 2, style: const TextStyle(fontSize: 16)),
        ),
        LabeledField(
          label: 'Telefon (opsiyonel)',
          child: TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            style: const TextStyle(fontSize: 16),
          ),
        ),
        // Yeni magaza her zaman aktif acilir; sunucu POST'ta active almaz.
        if (store != null)
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
        if (name.text.trim().isEmpty) return 'Mağaza adı zorunludur';
        try {
          await repo.saveStore(
            id: store?.id,
            name: name.text.trim(),
            address: address.text.trim().isEmpty ? null : address.text.trim(),
            phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
            active: active,
          );
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}
