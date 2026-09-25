import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/tokens.dart';
import '../models/movement.dart';
import '../widgets/dialogs.dart';

/// Satis, ikram veya zayi kaydinin adedini geriye donuk duzeltir.
///
/// Adet azaltilirsa fark stoga geri doner, artirilirsa stoktan duser. Rapor
/// paneli food rakamlarini bu kayitlardan canli hesapladigi icin duzeltme
/// gecmis gunlerin raporuna da yansir.
Future<bool?> showMovementCorrectDialog(BuildContext context, Movement m) {
  final quantity = TextEditingController(text: m.quantity.toString());
  final reason = TextEditingController(text: m.reason ?? '');
  final isDiscard = m.kind == 'discard';

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: '${m.kindLabel} Adedini Düzelt',
      submitLabel: 'Düzelt',
      fields: (context, rebuild) {
        final t = context.tokens;
        final entered = int.tryParse(quantity.text.trim());
        final delta = entered == null || entered < 1 ? null : m.quantity - entered;
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${m.productName ?? 'Ürün'} — ${fmtDateTime(m.at)}\n'
              'Kayıtlı adet: ${m.quantity}',
              style: TextStyle(fontSize: 13, color: t.muted),
            ),
          ),
          LabeledField(
            label: 'Doğru Adet',
            child: TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 16),
              onChanged: (_) => rebuild(),
            ),
          ),
          if (isDiscard)
            LabeledField(
              label: 'Zayi Sebebi',
              child: TextField(
                controller: reason,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          if (delta != null && delta != 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.primarySoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.border),
              ),
              child: Row(
                children: [
                  Icon(delta > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 18, color: t.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      delta > 0
                          ? '$delta adet stoka geri dönecek.'
                          : '${-delta} adet stoktan düşecek. Yeterli stok yoksa işlem reddedilir.',
                      style: TextStyle(fontSize: 12, color: t.ink),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Rapor panelindeki FOOD rakamları bu kayıtlardan hesaplandığı için '
              'düzeltme o günün raporuna da yansır.',
              style: TextStyle(fontSize: 11, color: t.muted),
            ),
          ),
        ];
      },
      onSubmit: () async {
        final n = int.tryParse(quantity.text.trim());
        if (n == null || n < 1) return 'Adet en az 1 olmalıdır';
        final r = reason.text.trim();
        if (n == m.quantity && (!isDiscard || r == (m.reason ?? ''))) {
          return 'Değişiklik yapılmadı';
        }
        try {
          if (isDiscard) {
            await repo.updateDiscard(m.id, n, r);
          } else {
            await repo.updateSaleQuantity(m.id, n);
          }
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}
