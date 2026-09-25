import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/batch.dart';
import '../models/dashboard.dart';
import '../models/product_type.dart';
import '../widgets/dialogs.dart';

/// Donuk depoya yeni parti ekleme.
Future<bool?> showAddBatchDialog(
  BuildContext context, {
  required List<ProductType> types,
  required List<StoreOption> stores,
}) {
  int? typeId = types.isEmpty ? null : types.first.id;
  int? storeId;
  final quantity = TextEditingController(text: '1');
  final code = TextEditingController();
  final notes = TextEditingController();
  final isSuper = session.user?.isSuperAdmin ?? false;

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Yeni Ürün',
      submitLabel: 'Kaydet',
      fields: (context, rebuild) => [
        LabeledField(
          label: 'Ürün Çeşidi',
          child: DropdownButtonFormField<int>(
            initialValue: typeId,
            isExpanded: true,
            items: types
                .map(
                  (t) => DropdownMenuItem(
                    value: t.id,
                    child: Text(
                      '${t.name} (${t.sktDays} gün)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              typeId = v;
              rebuild();
            },
          ),
        ),
        // Kisa alanlar yan yana: cep ekraninda form yuksekligi dususu.
        FormRow(
          left: LabeledField(
            label: 'Adet',
            child: TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          right: LabeledField(
            label: 'Parti Kodu',
            child: TextField(
              controller: code,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
        if (isSuper && stores.isNotEmpty)
          LabeledField(
            label: 'Mağaza',
            hint: 'Boş bırakılırsa çeşidin kendi mağazası kullanılır.',
            child: DropdownButtonFormField<int?>(
              initialValue: storeId,
              isExpanded: true,
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Çeşidin mağazası'),
                ),
                ...stores.map(
                  (s) =>
                      DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
                ),
              ],
              onChanged: (v) {
                storeId = v;
                rebuild();
              },
            ),
          ),
        LabeledField(
          label: 'Not (opsiyonel)',
          child: TextField(
            controller: notes,
            maxLines: 2,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
      onSubmit: () async {
        final qty = int.tryParse(quantity.text.trim());
        if (typeId == null) return 'Ürün çeşidi seçilmelidir';
        if (qty == null || qty < 1) return 'Miktar en az 1 olmalıdır';
        try {
          await repo.createBatch(
            productTypeId: typeId!,
            quantity: qty,
            storeId: storeId,
            batchCode: code.text,
            notes: notes.text,
          );
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Cozulme surecine alma. Kismi alinirsa parti bolunur.
Future<bool?> showThawDialog(BuildContext context, Batch batch) {
  final quantity = TextEditingController(text: '${batch.remaining}');
  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Çözülmeye Al',
      submitLabel: 'Çözülmeye Al',
      fields: (context, rebuild) => [
        Text(
          '${batch.productName} — kalan ${batch.remaining} adet',
          style: TextStyle(color: context.tokens.muted),
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Adet',
          hint: 'Tamamı alınmazsa parti bölünür, kalan donukta durur. Süre +4°C, 8 saat.',
          child: TextField(
            controller: quantity,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
      onSubmit: () async {
        final qty = int.tryParse(quantity.text.trim());
        if (qty == null || qty < 1) return 'Miktar en az 1 olmalıdır';
        if (qty > batch.remaining) {
            return 'Yeterli stok yok. Kalan: ${batch.remaining}';
          }
        try {
          await repo.thaw(batch.id, qty);
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Zayi: adet ve sebep.
Future<bool?> showDiscardDialog(BuildContext context, Batch batch) {
  final quantity = TextEditingController(text: '${batch.remaining}');
  final reason = TextEditingController();
  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Zayi Gir',
      submitLabel: 'Zayi Gir',
      fields: (context, rebuild) => [
        Text(
          '${batch.productName} — kalan ${batch.remaining} adet',
          style: TextStyle(color: context.tokens.muted),
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Adet',
          child: TextField(
            controller: quantity,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 16),
          ),
        ),
        LabeledField(
          label: 'Sebep',
          child: TextField(
            controller: reason,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
      onSubmit: () async {
        final qty = int.tryParse(quantity.text.trim());
        if (qty == null || qty < 1) return 'Miktar en az 1 olmalıdır';
        if (qty > batch.remaining) {
            return 'Yeterli stok yok. Kalan: ${batch.remaining}';
          }
        try {
          await repo.discard(
            batch.id,
            quantity: qty,
            reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
          );
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Donuk stoka adet ekleme.
Future<bool?> showStockAddDialog(BuildContext context, Batch batch) {
  final quantity = TextEditingController(text: '1');
  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Stok Ekle',
      submitLabel: 'Stoka Ekle',
      fields: (context, rebuild) => [
        Text(
          '${batch.productName} — mevcut ${batch.remaining} adet',
          style: TextStyle(color: context.tokens.muted),
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Eklenecek Adet',
          child: TextField(
            controller: quantity,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
      onSubmit: () async {
        final qty = int.tryParse(quantity.text.trim());
        if (qty == null || qty < 1) return 'Miktar en az 1 olmalıdır';
        try {
          await repo.addStock(batch.id, qty);
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Sure dolmadan food dolabina aktarim icin yonetici onayi istegi.
Future<bool?> showEarlyRequestDialog(BuildContext context, Batch batch) {
  final reason = TextEditingController();
  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Erken Aktarım İste',
      submitLabel: 'Onaya Gönder',
      fields: (context, rebuild) => [
        Text(
          '${batch.productName} (${batch.remaining} adet) çözünme süresi dolmadan food dolabına '
          'alınmak isteniyor. Kalan süre: ${formatHours(batch.thawRemainingHours)}.',
          style: TextStyle(color: context.tokens.muted),
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Erken Aktarım Nedeni',
          child: TextField(
            controller: reason,
            maxLines: 3,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              hintText: 'örn: Müşteri siparişi için acil ihtiyaç var',
            ),
          ),
        ),
      ],
      onSubmit: () async {
        if (reason.text.trim().length < 3) {
            return 'Erken aktarım nedeni yazılmalıdır';
          }
        try {
          await repo.requestEarlyTransfer(batch.id, reason.text.trim());
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Ana Yonetici duzeltmesi: tarih/saat ve adetler.
Future<bool?> showAdjustDialog(BuildContext context, Batch batch) {
  DateTime? parse(String? iso) =>
      iso == null ? null : DateTime.tryParse(iso)?.toLocal();

  final quantity = TextEditingController(text: '${batch.quantity}');
  final remaining = TextEditingController(text: '${batch.remaining}');
  var frozenAt = parse(batch.enteredFrozenAt);
  var thawStart = parse(batch.thawingStartedAt);
  var thawFinish = parse(batch.thawingFinishAt);
  var cabinetAt = parse(batch.foodCabinetEnteredAt);
  var sktEnd = parse(batch.sktEnd);

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Kaydı Düzelt — ${batch.productName}',
      submitLabel: 'Düzeltmeyi Kaydet',
      fields: (context, rebuild) => [
        Text(
          'Yanlış girilen tarih/saat ve adetleri düzeltir. Ürünün durumu değişmez ve '
          'yapılan düzeltme hareket kayıtlarına yazılır.',
          style: TextStyle(fontSize: 13, color: context.tokens.muted),
        ),
        const SizedBox(height: 12),
        FormRow(
          left: LabeledField(
            label: 'Toplam Adet',
            child: TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          right: LabeledField(
            label: 'Kalan Adet',
            child: TextField(
              controller: remaining,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Kalan adet toplam adetten büyük olamaz.',
            style: TextStyle(fontSize: 11, color: context.tokens.muted),
          ),
        ),
        LabeledField(
          label: 'Donuk Depoya Giriş',
          child: DateTimeField(
            value: frozenAt,
            onChanged: (v) {
              frozenAt = v;
              rebuild();
            },
          ),
        ),
        if (thawStart != null)
          LabeledField(
            label: 'Çözülme Başlangıcı',
            child: DateTimeField(
              value: thawStart,
              onChanged: (v) {
                thawStart = v;
                rebuild();
              },
            ),
          ),
        if (thawFinish != null)
          LabeledField(
            label: 'Çözülme Bitişi',
            child: DateTimeField(
              value: thawFinish,
              onChanged: (v) {
                thawFinish = v;
                rebuild();
              },
            ),
          ),
        if (cabinetAt != null)
          LabeledField(
            label: 'Food Dolabına Giriş',
            hint: batch.sktDays == null
                ? null
                : 'Bu tarih değişince SKT bitişi ${batch.sktDays} güne göre yeniden hesaplanır.',
            child: DateTimeField(
              value: cabinetAt,
              onChanged: (v) {
                cabinetAt = v;
                // SKT, dugmeye basildigi an degil dolaba giris anina gore hesaplanir.
                if (batch.sktDays != null) {
                  sktEnd = v.add(Duration(days: batch.sktDays!));
                }
                rebuild();
              },
            ),
          ),
        if (sktEnd != null)
          LabeledField(
            label: 'SKT Bitiş',
            child: DateTimeField(
              value: sktEnd,
              onChanged: (v) {
                sktEnd = v;
                rebuild();
              },
            ),
          ),
      ],
      onSubmit: () async {
        final qty = int.tryParse(quantity.text.trim());
        final rem = int.tryParse(remaining.text.trim());
        if (qty == null || qty < 1) return 'Toplam adet en az 1 olmalıdır';
        if (rem == null || rem < 0) {
            return 'Kalan adet 0 veya daha büyük olmalıdır';
          }
        if (rem > qty) {
            return 'Kalan adet toplam adetten büyük olamaz (toplam: $qty)';
          }
        if (frozenAt == null) return 'Donuk depoya giriş tarihi zorunludur';

        String? iso(DateTime? d) => d?.toUtc().toIso8601String();
        try {
          await repo.adjustBatch(batch.id, {
            'quantity': qty,
            'remaining': rem,
            'entered_frozen_at': iso(frozenAt),
            if (thawStart != null) 'thawing_started_at': iso(thawStart),
            if (thawFinish != null) 'thawing_finish_at': iso(thawFinish),
            if (cabinetAt != null) 'food_cabinet_entered_at': iso(cabinetAt),
            if (sktEnd != null) 'skt_end': iso(sktEnd),
          });
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Parti detayi ve satis gecmisi.
Future<void> showBatchDetail(BuildContext context, Batch batch) async {
  List<SaleRecord> sales = const [];
  Batch detail = batch;
  try {
    final (b, s) = await repo.batchDetail(batch.id);
    detail = b;
    sales = s;
  } catch (_) {
    // Bildirim API katmaninda gosterilir; eldeki ozet yine gosterilir.
  }
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final t = ctx.tokens;
      Widget row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 150,
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: t.muted),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
            ),
          ],
        ),
      );

      return AlertDialog(
        title: Text('Ürün Detayı — ${detail.productName}'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                row('Durum', statusLabels[detail.status] ?? detail.status),
                row('Miktar', '${detail.remaining} / ${detail.quantity} adet'),
                row('Donuk Depoya Giriş', fmtDateTime(detail.enteredFrozenAt)),
                if (detail.thawingStartedAt != null)
                  row(
                    'Çözülme Başlangıcı',
                    fmtDateTime(detail.thawingStartedAt),
                  ),
                if (detail.thawingFinishAt != null)
                  row('Çözülme Bitişi', fmtDateTime(detail.thawingFinishAt)),
                if (detail.foodCabinetEnteredAt != null)
                  row(
                    'Food Dolabına Giriş',
                    fmtDateTime(detail.foodCabinetEnteredAt),
                  ),
                if (detail.sktEnd != null)
                  row('SKT Bitiş', fmtDateTime(detail.sktEnd)),
                if (detail.notes != null && detail.notes!.isNotEmpty)
                  row('Not', detail.notes!),
                const SizedBox(height: 12),
                Text(
                  'Satış Geçmişi',
                  style: TextStyle(fontWeight: FontWeight.w700, color: t.ink),
                ),
                const SizedBox(height: 8),
                if (sales.isEmpty)
                  Text(
                    'Henüz satış yok',
                    style: TextStyle(color: t.muted, fontSize: 13),
                  )
                else
                  ...sales.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              fmtDateTime(s.soldAt),
                              style: TextStyle(fontSize: 13, color: t.ink),
                            ),
                          ),
                          Text(
                            '${s.quantity} adet',
                            style: TextStyle(fontSize: 13, color: t.muted),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            s.unitPrice == null ? '-' : fmtMoney(s.unitPrice),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: t.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
        ],
      );
    },
  );
}

/// Cozulmeye alinan adedi duzeltir.
///
/// Kullanici "dogru adet kaci" girer; fark donuk depoya geri doner. 0 girilirse
/// parti cozulmeden tamamen cikar. Fark once ayni partiden bolunmus donuk
/// kardese eklenir, yoksa donma tarihi korunarak yeni donuk parti acilir.
Future<bool?> showCorrectThawDialog(BuildContext context, Batch batch) {
  final quantity = TextEditingController(text: batch.remaining.toString());

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Çözülme Adedini Düzelt',
      submitLabel: 'Düzelt',
      fields: (context, rebuild) {
        final t = context.tokens;
        final entered = int.tryParse(quantity.text.trim());
        final back = entered == null || entered < 0 || entered > batch.remaining
            ? null
            : batch.remaining - entered;
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${batch.productName} — şu anda ${batch.remaining} adet çözülmede.',
              style: TextStyle(fontSize: 13, color: t.muted),
            ),
          ),
          LabeledField(
            label: 'Doğru Adet',
            hint: '0 yazarsanız ürün tamamen donuk depoya döner.',
            child: TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 16),
              onChanged: (_) => rebuild(),
            ),
          ),
          if (back != null && back > 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.primarySoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.ac_unit, size: 18, color: t.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$back adet donuk depoya geri dönecek. '
                      'Dondurucuya giriş tarihi korunur.',
                      style: TextStyle(fontSize: 12, color: t.ink),
                    ),
                  ),
                ],
              ),
            ),
        ];
      },
      onSubmit: () async {
        final n = int.tryParse(quantity.text.trim());
        if (n == null || n < 0) return 'Doğru adet 0 veya daha büyük bir tam sayı olmalıdır';
        if (n > batch.remaining) {
          return 'Doğru adet mevcut adetten (${batch.remaining}) büyük olamaz';
        }
        if (n == batch.remaining) return 'Adet değişmedi';
        try {
          await repo.correctThawQuantity(batch, n);
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

