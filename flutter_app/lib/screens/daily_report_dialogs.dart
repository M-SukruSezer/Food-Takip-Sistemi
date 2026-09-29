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

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

/// Gunluk veri girisi ve duzenlemesi.
///
/// Formda yalnizca elle girilen alanlar var. Food alanlari sistemdeki pasta
/// satis ve zayi kayitlarindan hesaplandigi icin girilmez; okunur bilgi
/// olarak gosterilir. Oranlar da sunucuda hesaplanir.
///
/// [existing] verilirse kayitli gun duzenlenir ve tarih degistirilemez —
/// tarihi degistirmek ayni gune ikinci kayit cakismasi olusturuyor. Gun
/// degisecekse kayit silinip yeniden girilir.
Future<bool?> showDailyReportDialog(
  BuildContext context, {
  required ReportFields fields,
  DailyReport? existing,
}) async {
  if (fields.entry.isEmpty) return null;

  final editing = existing != null;
  var date = editing ? DateTime.parse(existing.date) : DateTime.now();
  final controllers = {
    for (final f in fields.entry) f.key: TextEditingController(),
  };
  var loadedFor = '';
  var system = SystemFoodValues.empty;

  String textFor(ReportField f, num v) =>
      f.isInt ? v.toInt().toString() : v.toString();

  if (editing) {
    for (final f in fields.entry) {
      controllers[f.key]!.text = textFor(f, existing.values[f.key] ?? 0);
    }
  }

  /// Secilen gun icin kayitli degerleri ve sistemin food rakamlarini yukler.
  Future<void> loadDay(VoidCallback rebuild) async {
    final key = dayKey(date);
    if (loadedFor == key) return;
    loadedFor = key;
    try {
      final day = await repo.dailyReportFor(key);
      system = day.suggested;
      // Duzenlemede alanlar zaten dolu; ustune yazilmaz.
      if (!editing) {
        for (final f in fields.entry) {
          final saved = day.report?.values[f.key];
          controllers[f.key]!.text = saved == null ? '' : textFor(f, saved);
        }
      }
    } catch (_) {
      // Sistem rakamlari alinamazsa form calismaya devam eder; food degerleri
      // kaydederken sunucu tarafinda yine hesaplanir.
    }
    rebuild();
  }

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: editing ? 'Günlük Raporu Düzenle' : 'Günlük Rapor',
      headerIcon: Icons.receipt_long_rounded,
      subtitle: '• Kasa Kapanış & Vardiya Girişi',
      submitLabel: editing ? 'Güncelle' : 'Kaydet',
      submitColor: const Color(0xFF0F766E),
      fields: (context, rebuild) {
        loadDay(rebuild);
        final t = context.tokens;
        return [
          LabeledField(
            label: 'Tarih',
            hint: editing
                ? 'Tarih değiştirilemez. Farklı bir gün için kaydı silip yeniden girin.'
                : 'Aynı gün için tekrar giriş mevcut kaydı otomatik günceller.',
            child: editing
                ? InputDecorator(
                    decoration: const InputDecoration(),
                    child: Text(
                      fmtDate(existing.date),
                      style: const TextStyle(fontSize: 16),
                    ),
                  )
                : DateTimeField(
                    value: date,
                    onChanged: (v) {
                      date = v;
                      rebuild();
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'MANUEL KASA GİRİŞLERİ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: t.muted,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCCFBF1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '• Birimler senkronize',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Sayisal alanlar kisa; ikili satirlarda form yuksekligi yariya iner.
          ...pairFields(
            fields.entry
                .map<Widget>(
                  (f) => LabeledField(
                    label: f.label,
                    child: TextField(
                      controller: controllers[f.key],
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: !f.isInt,
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        suffixText: f.type == 'money' ? '₺' : null,
                        hintText: f.isInt ? 'adet' : null,
                        isDense: true,
                        filled: true,
                        fillColor: t.card,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: t.border.withValues(alpha: 0.7),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: t.border.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          // Sistemden gelen food alanlari: okunur, girilmez.
          if (fields.system.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 13,
                        color: Color(0xFF0F766E),
                      ),
                      const SizedBox(width: 5),
                      const Expanded(
                        child: Text(
                          'Sistemden gelen değerler',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '• Canlı POS',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF065F46),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: fields.system.map((f) {
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: t.muted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatReportValue(system[f.key], f.type),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: t.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.calculate_outlined,
                          size: 13,
                          color: Color(0xFF0F766E),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'FOOD alanları o günün pasta satış ve zayi kayıtlarından hesaplanır, elle girilmez. AT, IPT, FOOD MARKOUT %, FOOD UPH, MODIFIERS % ve APP% girilen değerlerden otomatik hesaplanır.',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: t.muted,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
          if (n == null || n < 0) {
              return '${f.label} 0 veya daha büyük bir sayı olmalıdır';
            }
          if (f.isInt && n != n.roundToDouble()) {
              return '${f.label} tam sayı olmalıdır';
            }
          values[f.key] = f.isInt ? n.toInt() : n;
        }
        try {
          if (editing) {
            await repo.updateDailyReport(existing, values);
          } else {
            await repo.saveDailyReport(dayKey(date), values);
          }
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Tek gunun tum kalemleri: elle girilenler, sistemden gelenler ve turetilenler.
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
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: bold ? t.ink : t.muted),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: bold ? t.primary : t.ink,
          ),
        ),
      ],
    ),
  );

  Widget heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 2),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: t.muted,
        letterSpacing: .4,
      ),
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
              ...fields.entry.map(
                (f) => row(
                  f.label,
                  formatReportValue(report.values[f.key], f.type),
                ),
              ),
              if (fields.system.isNotEmpty) ...[
                heading('SİSTEMDEN'),
                ...fields.system.map(
                  (f) => row(
                    f.label,
                    formatReportValue(report.values[f.key], f.type),
                  ),
                ),
              ],
              const Divider(height: 20),
              ...fields.derived.map(
                (f) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    row(
                      f.label,
                      formatReportValue(report.metrics[f.key], f.type),
                      bold: true,
                    ),
                    if (f.formula != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          f.formula!,
                          style: TextStyle(fontSize: 11, color: t.muted),
                        ),
                      ),
                  ],
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
    ),
  );
}
