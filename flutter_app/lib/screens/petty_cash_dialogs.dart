import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/avatar_image.dart';
import '../core/format.dart';
import '../core/image_pick.dart';
import '../core/repository.dart';
import '../core/tokens.dart';
import '../models/petty_cash.dart';
import '../widgets/dialogs.dart';

/// Masraf ekleme penceresi: tutar, aciklama, tarih ve fis fotosu.
Future<bool?> showExpenseDialog(BuildContext context, {PettyCashStatus? status}) {
  final amount = TextEditingController();
  final description = TextEditingController();
  var spentAt = DateTime.now();
  String? receipt;
  Uint8List? preview;
  String? imageError;

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Masraf Ekle',
      submitLabel: 'Kaydet',
      fields: (context, rebuild) {
        final t = context.tokens;

        Future<void> pick({required bool camera}) async {
          imageError = null;
          rebuild();
          try {
            final bytes = await pickImageBytes(fromCamera: camera);
            if (bytes == null) return;
            // Sunucuda en kucuk makul boyutta saklanmasi icin kuculterek
            // gonderilir; ham telefon fotosu 3-5 MB geliyor.
            receipt = encodeReceipt(bytes);
            preview = base64Decode(receipt!.split(',').last);
          } on FormatException catch (e) {
            imageError = e.message;
          } catch (e) {
            imageError = 'Görsel alınamadı: $e';
          }
          rebuild();
        }

        return [
          if (status != null && status.hasLimit)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Bu hafta kalan: ${fmtMoney(status.remaining)}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.muted),
              ),
            ),
          LabeledField(
            label: 'Tutar (TL)',
            child: TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          LabeledField(
            label: 'Açıklama',
            hint: 'Masrafın ne için yapıldığı.',
            child: TextField(
              controller: description,
              maxLines: 2,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          LabeledField(
            label: 'Tarih',
            child: DateTimeField(
              value: spentAt,
              onChanged: (v) {
                spentAt = v;
                rebuild();
              },
            ),
          ),
          LabeledField(
            label: 'Fiş / Fatura',
            hint: 'Görsel otomatik olarak küçültülüp sıkıştırılarak saklanır.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (imageError != null) ...[
                  Text(imageError!, style: TextStyle(color: t.danger, fontSize: 13)),
                  const SizedBox(height: 8),
                ],
                if (preview != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                    child: Image.memory(preview!, height: 140, fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 6),
                  Text('${(receipt!.length / 1024).round()} KB olarak kaydedilecek',
                      style: TextStyle(fontSize: 12, color: t.muted)),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    if (cameraAvailable()) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pick(camera: true),
                          icon: const Icon(Icons.photo_camera_outlined, size: 18),
                          label: const Text('Çek'),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => pick(camera: false),
                        icon: const Icon(Icons.photo_library_outlined, size: 18),
                        label: const Text('Galeri'),
                      ),
                    ),
                    if (preview != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Fişi kaldır',
                        onPressed: () {
                          receipt = null;
                          preview = null;
                          rebuild();
                        },
                        icon: Icon(Icons.close, color: t.danger),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ];
      },
      onSubmit: () async {
        final value = num.tryParse(amount.text.trim().replaceAll(',', '.'));
        if (value == null || value <= 0) return 'Tutar 0’dan büyük bir sayı olmalıdır';
        if (description.text.trim().isEmpty) return 'Açıklama zorunludur';
        if (status != null && status.hasLimit && value > status.remaining) {
          return 'Haftalık limit aşılıyor. Kalan: ${fmtMoney(status.remaining)}';
        }
        try {
          await repo.addPettyCash(
            amount: value,
            description: description.text.trim(),
            receipt: receipt,
            spentAt: spentAt,
          );
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Ana Yonetici: magaza basina haftalik limit belirleme.
Future<bool?> showLimitsDialog(BuildContext context) async {
  List<PettyCashLimit> limits;
  try {
    limits = await repo.pettyCashLimits();
  } catch (e) {
    return null;
  }
  if (!context.mounted) return null;

  final controllers = {
    for (final l in limits) l.storeId: TextEditingController(text: l.weeklyAmount.toString()),
  };

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Haftalık Petty Cash Limitleri',
      submitLabel: 'Kaydet',
      fields: (context, rebuild) => [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Her mağazanın haftalık harcama tavanı. Hafta pazartesi başlar.',
            style: TextStyle(fontSize: 13, color: context.tokens.muted),
          ),
        ),
        ...limits.map((l) => LabeledField(
              label: l.storeName,
              child: TextField(
                controller: controllers[l.storeId],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(suffixText: 'TL'),
              ),
            )),
      ],
      onSubmit: () async {
        for (final l in limits) {
          final raw = controllers[l.storeId]!.text.trim().replaceAll(',', '.');
          final value = num.tryParse(raw.isEmpty ? '0' : raw);
          if (value == null || value < 0) {
            return '${l.storeName}: limit 0 veya daha büyük olmalıdır';
          }
          if (value == l.weeklyAmount) continue;
          try {
            await repo.setPettyCashLimit(l.storeId, value);
          } catch (e) {
            return errorMessage(e);
          }
        }
        return null;
      },
    ),
  );
}
