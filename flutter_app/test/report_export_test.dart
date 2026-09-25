import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/models/daily_report.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:foodtakip/core/format.dart';
import 'package:intl/date_symbol_data_local.dart';

void initTestFormattingForExport() => initializeDateFormatting('tr_TR');

/// Dosya uretimi platform kanali gerektirmiyor (iki paket de saf Dart), bu
/// yuzden ciktinin icerigi burada dogrulanabiliyor. report_export.dart'taki
/// paylasim adimi test edilemedigi icin tablo kurulumu ayni sekilde
/// tekrarlanip icerigi olculuyor.
String _fmt(num? v, String type) {
  if (v == null) return '-';
  return switch (type) {
    'money' => fmtMoney(v),
    'percent' => '${(v * 100).toStringAsFixed(2)}%',
    'int' => fmtInt(v),
    _ => v.toStringAsFixed(2),
  };
}

void main() {
  setUp(initTestFormattingForExport);

  final entry = [
    const ReportField(key: 'net_sales', label: 'NET SALES', type: 'money'),
    const ReportField(key: 'adt', label: 'ADT', type: 'int'),
  ];
  final derived = [
    const ReportField(key: 'at', label: 'AT', type: 'money'),
    const ReportField(key: 'app_pct', label: 'APP%', type: 'percent'),
  ];

  test('Excel dosyasi uretilir ve degerler hucrelere yazilir', () {
    final workbook = xlsio.Workbook();
    try {
      final sheet = workbook.worksheets[0];
      final headers = ['Tarih', ...entry.map((f) => f.label), ...derived.map((f) => f.label)];
      for (var c = 0; c < headers.length; c++) {
        sheet.getRangeByIndex(1, c + 1).setText(headers[c]);
      }
      sheet.getRangeByIndex(2, 1).setText('22.09.2026');
      sheet.getRangeByIndex(2, 2).setText(_fmt(10000, 'money'));
      sheet.getRangeByIndex(2, 3).setText(_fmt(200, 'int'));
      sheet.getRangeByIndex(2, 4).setText(_fmt(50, 'money'));
      sheet.getRangeByIndex(2, 5).setText(_fmt(0.15, 'percent'));

      final bytes = Uint8List.fromList(workbook.saveAsStream());
      // xlsx bir zip: PK imzasiyla baslar.
      expect(bytes.length, greaterThan(1000));
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
      expect(sheet.getRangeByIndex(2, 2).text, '10.000,00 TL');
      expect(sheet.getRangeByIndex(2, 5).text, '15.00%');
    } finally {
      workbook.dispose();
    }
  });

  test('PDF dosyasi uretilir', () async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (c) => [
        pw.TableHelper.fromTextArray(
          headers: const ['Tarih', 'NET SALES', 'AT'],
          data: const [
            ['22.09.2026', '10.000,00 TL', '50,00 TL'],
            ['TOPLAM (2 gün)', '20.000,00 TL', '66,67 TL'],
          ],
        ),
      ],
    ));
    final bytes = await doc.save();
    // PDF imzasi: %PDF
    expect(bytes.length, greaterThan(500));
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
  });

  test('bicimleme Excel ve PDF icin ayni', () {
    expect(_fmt(66.6667, 'money'), '66,67 TL');
    expect(_fmt(0.05, 'percent'), '5.00%');
    expect(_fmt(null, 'money'), '-');
  });
}
