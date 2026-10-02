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

/// Masraf kategorileri. Aciklamanin basina "[Kategori]" olarak yazilir;
/// raporlarda masraflar buna gore ayrisir.
const expenseCategories = [
  'Temizlik & Hijyen',
  'Acil Sarf & Süt',
  'Kırtasiye & Fiş',
  'Ulaşım & Kurye',
  'Teknik Bakım',
  'Diğer Giderler',
];

/// "[Kategori] (eski belge notu) açıklama" -> (kategori, açıklama).
({String? category, String text}) splitExpenseDescription(String raw) {
  final m = RegExp(r'^\[(.+?)\]\s*(?:\([^)]*\)\s*)?(.*)$').firstMatch(raw);
  if (m == null) return (category: null, text: raw);
  final cat = m.group(1)!;
  return (
    category: expenseCategories.contains(cat) ? cat : null,
    text: m.group(2) ?? '',
  );
}

/// Masraf ekleme / düzenleme formu (standart form tasarımı).
///
/// [expense] verilirse kayıt düzenlenir. Haftalık limit durumu formda değil
/// Petty Cash sayfasının üstündeki kartta görünür; limit aşımı yine burada
/// gönderimden önce yakalanır.
Future<bool?> showExpenseDialog(
  BuildContext context, {
  PettyCashStatus? status,
  PettyCashExpense? expense,
}) {
  final editing = expense != null;
  final parsed = editing ? splitExpenseDescription(expense.description) : null;
  final amount = TextEditingController(
    text: editing ? fmtAmountInput(expense.amount) : '',
  );
  final desc = TextEditingController(text: parsed?.text ?? '');
  var category = parsed?.category ?? expenseCategories.first;
  var spentAt = editing
      ? (DateTime.tryParse(expense.spentAt)?.toLocal() ?? DateTime.now())
      : DateTime.now();
  String? receipt;
  Uint8List? preview;
  String? imageError;

  return showAppSheet<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: editing ? 'Masrafı Düzenle' : 'Masraf Ekle',
      headerIcon: Icons.receipt_long_outlined,
      submitLabel: editing ? 'Kaydet' : 'Masrafı Kaydet',
      fields: (context, rebuild) {
        final t = context.tokens;

        void addPreset(int v) {
          final cur =
              num.tryParse(amount.text.trim().replaceAll(',', '.')) ?? 0;
          amount.text = fmtAmountInput(cur + v);
          rebuild();
        }

        Future<void> pick({required bool camera}) async {
          imageError = null;
          try {
            final bytes = await pickImageBytes(fromCamera: camera);
            if (bytes != null) {
              receipt = encodeReceipt(bytes);
              preview = base64Decode(receipt!.split(',').last);
            }
          } on FormatException catch (e) {
            imageError = e.message;
          } catch (e) {
            imageError = 'Görsel alınamadı: $e';
          }
          rebuild();
        }

        return [
          FormRow(
            left: LabeledField(
              label: 'Tutar (₺)',
              child: TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(fontSize: AppFontSize.title),
                decoration: const InputDecoration(
                  hintText: '0,00',
                  suffixText: 'TL',
                ),
              ),
            ),
            right: LabeledField(
              label: 'Tarih',
              child: DateTimeField(
                value: spentAt,
                onChanged: (v) {
                  spentAt = v;
                  rebuild();
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                for (final p in const [50, 100, 250, 500]) ...[
                  if (p != 50) const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => addPreset(p),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 40),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('+$p TL'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          LabeledField(
            label: 'Kategori',
            child: DropdownButtonFormField<String>(
              initialValue: category,
              isExpanded: true,
              items: [
                for (final c in expenseCategories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) {
                category = v ?? category;
                rebuild();
              },
            ),
          ),
          LabeledField(
            label: 'Açıklama',
            child: TextField(
              controller: desc,
              maxLines: 2,
              style: const TextStyle(fontSize: AppFontSize.title),
              decoration: const InputDecoration(hintText: 'Ne için harcandı?'),
            ),
          ),
          LabeledField(
            label: 'Fiş / Fatura Fotoğrafı',
            hint: editing && expense.hasReceipt && preview == null
                ? 'Mevcut fiş korunur; yenisini seçerseniz değiştirilir.'
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (preview != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Image.memory(
                        preview!,
                        height: 160,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => pick(camera: false),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Galeriden'),
                      ),
                    ),
                    if (cameraAvailable()) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pick(camera: true),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Fotoğraf Çek'),
                        ),
                      ),
                    ],
                  ],
                ),
                if (imageError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      imageError!,
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        color: t.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ];
      },
      onSubmit: () async {
        final val = num.tryParse(amount.text.trim().replaceAll(',', '.'));
        if (val == null || val <= 0) {
          return 'Tutar 0’dan büyük bir sayı olmalıdır';
        }
        final text = desc.text.trim();
        if (text.isEmpty) return 'Açıklama zorunludur';
        // Duzenlemede kaydin kendi tutari limite geri eklenir.
        final available = status != null && status.hasLimit
            ? status.remaining + (editing ? expense.amount : 0)
            : null;
        if (available != null && val > available) {
          return 'Haftalık limit aşılıyor. Kalan: ${fmtMoney(available)}';
        }
        final full = '[$category] $text';
        try {
          if (editing) {
            await repo.updatePettyCash(
              expense.id,
              amount: val,
              description: full,
              receipt: receipt,
              spentAt: spentAt,
            );
          } else {
            await repo.addPettyCash(
              amount: val,
              description: full,
              receipt: receipt,
              spentAt: spentAt,
            );
          }
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Tutar alani icin sade gosterim: 150 -> "150", 12.5 -> "12,50".
String fmtAmountInput(num v) => v % 1 == 0
    ? v.toInt().toString()
    : v.toStringAsFixed(2).replaceAll('.', ',');

/// Ana Yönetici: mağaza başına haftalık limit belirleme.
Future<bool?> showLimitsDialog(BuildContext context) async {
  List<PettyCashLimit> limits;
  try {
    limits = await repo.pettyCashLimits();
  } catch (e) {
    return null;
  }
  if (!context.mounted) return null;

  final controllers = {
    for (final l in limits)
      l.storeId: TextEditingController(text: l.weeklyAmount.toString()),
  };

  return showAppSheet<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Haftalık Petty Cash Limitleri',
      submitLabel: 'Kaydet',
      fields: (context, rebuild) => [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Her mağazanın haftalık harcama tavanı. Hafta pazartesi başlar.',
            style: TextStyle(
              fontSize: AppFontSize.body,
              color: context.tokens.muted,
            ),
          ),
        ),
        ...limits.map(
          (l) => LabeledField(
            label: l.storeName,
            child: TextField(
              controller: controllers[l.storeId],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(fontSize: AppFontSize.title),
              decoration: const InputDecoration(suffixText: 'TL'),
            ),
          ),
        ),
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

/// Masraf reddi. Gerekçe zorunlu: masrafı giren kişi neden reddedildiğini
/// görsün, sunucu da boş gerekçeyi kabul etmiyor.
Future<bool?> showPettyCashRejectDialog(
  BuildContext context,
  PettyCashExpense expense,
) {
  final note = TextEditingController();

  return showAppSheet<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Masrafı Reddet',
      submitLabel: 'Reddet',
      fields: (context, rebuild) {
        final t = context.tokens;
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${fmtMoney(expense.amount)} — ${expense.description}\n'
              '${expense.createdByName ?? 'bilinmiyor'} girdi.',
              style: TextStyle(fontSize: AppFontSize.body, color: t.muted),
            ),
          ),
          LabeledField(
            label: 'Ret Gerekçesi',
            hint:
                'Masrafı giren kişi bu gerekçeyi görecek. '
                'Tutar haftalık limite geri eklenir.',
            child: TextField(
              controller: note,
              autofocus: true,
              maxLines: 2,
              style: const TextStyle(fontSize: AppFontSize.title),
            ),
          ),
        ];
      },
      onSubmit: () async {
        final text = note.text.trim();
        if (text.isEmpty) return 'Ret gerekçesi zorunludur';
        try {
          await repo.rejectPettyCash(expense, text);
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}
