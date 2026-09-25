import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/tokens.dart';
import '../models/daily_report.dart';
import '../widgets/dialogs.dart';

/// Rapor degerlerini tipine gore bicimler. Payda sifirsa "-" gosterilir.
String formatReportValue(num? value, String type) {
  if (value == null) return '-';
  return switch (type) {
    'money' => fmtMoney(value),
    'percent' => '${(value * 100).toStringAsFixed(2)}%',
    'int' => fmtInt(value),
    _ => value.toStringAsFixed(2),
  };
}

/// Gunluk veri girisi. Yalnizca ham alanlar sorulur; oranlar sunucuda
/// hesaplandigi icin forma konmaz.
Future<bool?> showDailyReportDialog(BuildContext context, {required ReportFields fields}) async {
  if (fields.entry.isEmpty) return null;

  var date = DateTime.now();
  final controllers = {for (final f in fields.entry) f.key: TextEditingController()};
  var loadedFor = '';
  var system = SystemFoodValues.empty;

  String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String textFor(ReportField f, num v) => f.isInt ? v.toInt().toString() : v.toString();

  /// Secilen gun icin formu hazirlar.
  ///
  /// Food alanlari (FOOD USD, FOOD USD ₺, FOOD MO ₺) sistemdeki satis ve imha
  /// kayitlarindan otomatik dolar. Gune ait kayit varsa onceki degerler
  /// kullanilir — kullanici duzeltmisse kaybolmasin.
  Future<void> loadExisting(VoidCallback rebuild) async {
    final key = dayKey(date);
    if (loadedFor == key) return;
    loadedFor = key;
    try {
      final day = await repo.dailyReportFor(key);
      system = day.suggested;
      for (final f in fields.entry) {
        final saved = day.report?.values[f.key];
        if (saved != null) {
          controllers[f.key]!.text = textFor(f, saved);
        } else if (SystemFoodValues.keys.contains(f.key)) {
          controllers[f.key]!.text = textFor(f, system[f.key] ?? 0);
        } else {
          controllers[f.key]!.text = '';
        }
      }
    } catch (_) {
      // Sistem degerleri alinamazsa alanlar bos kalir, elle girilebilir.
    }
    rebuild();
  }

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Günlük Rapor',
      submitLabel: 'Kaydet',
      fields: (context, rebuild) {
        // Ilk acilista ve tarih degisince mevcut kaydi yukle.
        loadExisting(rebuild);
        return [
          LabeledField(
            label: 'Tarih',
            hint: 'Aynı gün için tekrar giriş mevcut kaydı günceller.',
            child: DateTimeField(
              value: date,
              onChanged: (v) {
                date = v;
                rebuild();
              },
            ),
          ),
          ...fields.entry.map((f) {
            final fromSystem = SystemFoodValues.keys.contains(f.key);
            final systemValue = system[f.key];
            return LabeledField(
              label: f.label,
              hint: fromSystem
                  ? 'Sistemdeki satış ve imha kayıtlarından: '
                      '${formatReportValue(systemValue, f.type)}'
                  : null,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controllers[f.key],
                      keyboardType: TextInputType.numberWithOptions(decimal: !f.isInt),
                      style: const TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        suffixText: f.type == 'money' ? 'TL' : null,
                        hintText: f.isInt ? 'adet' : null,
                      ),
                    ),
                  ),
                  // Kullanici elle degistirdiyse sistem degerine donebilsin.
                  if (fromSystem) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Sistemden doldur',
                      onPressed: () {
                        controllers[f.key]!.text = textFor(f, systemValue ?? 0);
                        rebuild();
                      },
                      icon: const Icon(Icons.sync, size: 20),
                    ),
                  ],
                ],
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'FOOD alanları sistemdeki pasta satış ve imha kayıtlarından '
              'otomatik dolar; gerekirse değiştirebilirsiniz. '
              'AT, IPT, FOOD MARKOUT %, FOOD UPH, MODIFIERS % ve APP% '
              'girilen değerlerden otomatik hesaplanır.',
              style: TextStyle(fontSize: 12, color: context.tokens.muted),
            ),
          ),
        ];
      },
      onSubmit: () async {
        final values = <String, num>{};
        for (final f in fields.entry) {
          final raw = controllers[f.key]!.text.trim().replaceAll(',', '.');
          if (raw.isEmpty) return '${f.label} zorunludur';
          final n = num.tryParse(raw);
          if (n == null || n < 0) return '${f.label} 0 veya daha büyük bir sayı olmalıdır';
          if (f.isInt && n != n.roundToDouble()) return '${f.label} tam sayı olmalıdır';
          values[f.key] = f.isInt ? n.toInt() : n;
        }
        try {
          await repo.saveDailyReport(dayKey(date), values);
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Tek gunun tum kalemleri.
Future<void> showDailyReportDetail(
  BuildContext context,
  DailyReport report,
  ReportFields fields,
) {
  final t = context.tokens;
  Widget row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: bold ? t.ink : t.muted)),
            ),
            Text(value,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: bold ? t.primary : t.ink)),
          ],
        ),
      );

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(fmtDate(report.date)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...fields.entry
                  .map((f) => row(f.label, formatReportValue(report.values[f.key], f.type))),
              const Divider(height: 20),
              ...fields.derived.map((f) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      row(f.label, formatReportValue(report.metrics[f.key], f.type), bold: true),
                      if (f.formula != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(f.formula!,
                              style: TextStyle(fontSize: 11, color: t.muted)),
                        ),
                    ],
                  )),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
      ],
    ),
  );
}
