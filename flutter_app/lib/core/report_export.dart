import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../models/daily_report.dart';
import 'format.dart';
import 'pdf_font.dart';

/// Rapor tablosunun ortak iskeleti: basliklar ve satirlar hem Excel hem PDF
/// icin tek yerden uretilir, iki cikti birbirinden sapmaz.
class _Table {
  _Table(this.headers, this.rows, this.summaryRow);

  final List<String> headers;
  final List<List<String>> rows;
  final List<String> summaryRow;
}

String _formatValue(num? value, String type) {
  if (value == null) return '-';
  return switch (type) {
    'money' => fmtMoney(value),
    'percent' => '${(value * 100).toStringAsFixed(2)}%',
    'int' => fmtInt(value),
    _ => value.toStringAsFixed(2),
  };
}

_Table _build(
  DailyReportPage page,
  ReportFields fields, {
  bool showStore = false,
}) {
  final headers = <String>[
    'Tarih',
    if (showStore) 'Mağaza',
    ...fields.entry.map((f) => f.label),
    ...fields.system.map((f) => f.label),
    ...fields.derived.map((f) => f.label),
  ];

  final rows = page.items.map((item) {
    return <String>[
      fmtDate(item.date),
      if (showStore) item.storeName ?? '-',
      ...fields.entry.map((f) => _formatValue(item.values[f.key], f.type)),
      ...fields.system.map((f) => _formatValue(item.values[f.key], f.type)),
      ...fields.derived.map((f) => _formatValue(item.metrics[f.key], f.type)),
    ];
  }).toList();

  // Ozet satiri: ham alanlar toplanir, oranlar toplamlardan hesaplanir.
  final summary = <String>[
    'TOPLAM (${page.summary.days} gün)',
    if (showStore) '',
    ...fields.entry.map(
      (f) => _formatValue(page.summary.totals[f.key], f.type),
    ),
    ...fields.system.map(
      (f) => _formatValue(page.summary.totals[f.key], f.type),
    ),
    ...fields.derived.map(
      (f) => _formatValue(page.summary.metrics[f.key], f.type),
    ),
  ];

  return _Table(headers, rows, summary);
}

String _fileName(DailyReportPage page, String extension) {
  final label = page.period == 'month' ? 'aylik' : 'haftalik';
  return 'operasyon-raporu-$label-${page.from}_${page.to}.$extension';
}

/// Excel (.xlsx) uretir ve paylasim/kaydetme penceresini acar.
Future<void> exportReportExcel(
  DailyReportPage page,
  ReportFields fields, {
  bool showStore = false,
}) async {
  final table = _build(page, fields, showStore: showStore);

  final workbook = xlsio.Workbook();
  try {
    final sheet = workbook.worksheets[0];
    sheet.name = 'Operasyon Raporu';

    for (var c = 0; c < table.headers.length; c++) {
      final cell = sheet.getRangeByIndex(1, c + 1);
      cell.setText(table.headers[c]);
      cell.cellStyle.bold = true;
    }
    for (var r = 0; r < table.rows.length; r++) {
      for (var c = 0; c < table.rows[r].length; c++) {
        sheet.getRangeByIndex(r + 2, c + 1).setText(table.rows[r][c]);
      }
    }
    final summaryRow = table.rows.length + 2;
    for (var c = 0; c < table.summaryRow.length; c++) {
      final cell = sheet.getRangeByIndex(summaryRow, c + 1);
      cell.setText(table.summaryRow[c]);
      cell.cellStyle.bold = true;
    }
    for (var c = 1; c <= table.headers.length; c++) {
      sheet.autoFitColumn(c);
    }

    final bytes = Uint8List.fromList(workbook.saveAsStream());
    await sharePdksFile(
      bytes,
      _fileName(page, 'xlsx'),
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  } finally {
    // Syncfusion calisma kitabini elle serbest birakmayi bekliyor.
    workbook.dispose();
  }
}

/// PDF uretir ve paylasim/kaydetme penceresini acar.
Future<void> exportReportPdf(
  DailyReportPage page,
  ReportFields fields, {
  bool showStore = false,
}) async {
  final table = _build(page, fields, showStore: showStore);
  // Turkce karakterler icin gomulu yazi tipi; okunamazsa varsayilanla devam.
  final doc = pw.Document(theme: await pdfTurkishTheme());
  final title = page.period == 'month'
      ? 'Aylık Operasyon Raporu'
      : 'Haftalık Operasyon Raporu';

  doc.addPage(
    pw.MultiPage(
      // 15 kolon dikey sayfaya sigmiyor.
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              '${fmtDate(page.from)} – ${fmtDate(page.to)}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          headers: table.headers,
          data: [...table.rows, table.summaryRow],
          headerStyle: pw.TextStyle(
            fontSize: 7,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 7),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignment: pw.Alignment.centerRight,
          cellAlignments: {0: pw.Alignment.centerLeft},
        ),
      ],
    ),
  );

  await sharePdksFile(
    await doc.save(),
    _fileName(page, 'pdf'),
    'application/pdf',
  );
}

/// Dosyayi paylasim/kaydetme penceresine verir; PDKS ciktilari da kullaniyor. share_plus bes platformda da
/// calisiyor; ayri bir "indirilenler" yolu yonetmeye gerek kalmiyor.
Future<void> sharePdksFile(Uint8List bytes, String name, String mime) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, name: name, mimeType: mime)],
      fileNameOverrides: [name],
    ),
  );
}
