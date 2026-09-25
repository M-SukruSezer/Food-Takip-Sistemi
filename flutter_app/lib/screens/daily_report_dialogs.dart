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

  String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Secilen gunde kayit varsa alanlar onunla dolar; tekrar giris gunceller.
  Future<void> loadExisting(VoidCallback rebuild) async {
    final key = dayKey(date);
    if (loadedFor == key) return;
    loadedFor = key;
    try {
      final existing = await repo.dailyReportFor(key);
      for (final f in fields.entry) {
        final v = existing?.values[f.key];
        controllers[f.key]!.text = v == null ? '' : (f.isInt ? v.toInt().toString() : v.toString());
      }
    } catch (_) {
      // Kayit yoksa alanlar bos kalir.
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
          ...fields.entry.map((f) => LabeledField(
                label: f.label,
                child: TextField(
                  controller: controllers[f.key],
                  keyboardType: TextInputType.numberWithOptions(decimal: !f.isInt),
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    suffixText: f.type == 'money' ? 'TL' : null,
                    hintText: f.isInt ? 'adet' : null,
                  ),
                ),
              )),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'AT, IPT, FOOD MARKOUT %, FOOD UPH, MODIFIERS % ve APP% '
              'bu değerlerden otomatik hesaplanır.',
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
