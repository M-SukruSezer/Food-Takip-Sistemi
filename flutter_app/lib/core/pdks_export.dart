import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../models/pdks.dart';
import 'format.dart';
import 'pdf_font.dart';
import 'report_export.dart' show sharePdksFile;

// PDKS ciktilari: haftalik vardiya plani (PDF) ve aylik puantaj (Excel + PDF).
//
// Tablolar tek yerde kuruluyor ki Excel ile PDF birbirinden sapmasin — rapor
// panelindeki _Table deseniyle ayni gerekce.

const _gunKisa = ['Paz', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt'];

String _gunAdi(String tarih) {
  final d = DateTime.tryParse('${tarih}T00:00:00Z');
  return d == null ? '' : _gunKisa[d.toUtc().weekday % 7];
}

/// Hucrenin metin karsiligi. Ekran ve PDF ayni gosterimi kullansin diye tek
/// fonksiyon.
String rosterCellText(List<RosterCell> hucreler, PublicHoliday? tatil) {
  if (tatil != null && !tatil.isHalfDay) return 'RT';
  if (hucreler.isEmpty) return '-';
  if (hucreler.any((c) => c.isDayOff)) return 'HT';
  return hucreler
      .map((c) => '${c.saatAraligi}${c.crossesMidnight ? ')' : ''}')
      .join(' / ');
}

/// Haftalik vardiya plani PDF'i.
Future<void> exportRosterPdf(Roster r) async {
  final doc = pw.Document(theme: await pdfTurkishTheme());
  final basliklar = <String>[
    'Personel',
    ...r.dates.map(
      (d) => '${_gunAdi(d)}\n${d.substring(8)}.${d.substring(5, 7)}',
    ),
    'Planlı',
  ];
  final satirlar = r.people
      .map(
        (p) => <String>[
          p.fullName,
          ...r.dates.map((d) => rosterCellText(p.gun(d), r.holidays[d])),
          fmtDuration(p.plannedMinutes),
        ],
      )
      .toList();
  final toplam = <String>[
    'TOPLAM',
    ...r.dates.map((d) => '${r.gunToplam(d).working} kişi'),
    fmtDuration(r.totalPlannedMinutes),
  ];

  doc.addPage(
    pw.MultiPage(
      // 7 gun + isim dikey sayfaya sigmiyor.
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Haftalık Vardiya Planı',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              '${r.storeName != null ? '${r.storeName} · ' : ''}'
              '${fmtDate(r.from)} – ${fmtDate(r.to)}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          headers: basliklar,
          data: [...satirlar, toplam],
          headerStyle: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignment: pw.Alignment.center,
          cellAlignments: {0: pw.Alignment.centerLeft},
          columnWidths: {0: const pw.FixedColumnWidth(110)},
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Hafta tatili "HT", resmi tatil "RT" olarak işaretlenir. '
          'Gece vardiyası saatin yanında ")" ile gösterilir.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ),
  );

  await sharePdksFile(
    await doc.save(),
    'vardiya-plani-${r.from}.pdf',
    'application/pdf',
  );
}

/// Puantaj tablosu. Excel ve PDF ayni veriyi kullanir.
class _PuantajTablo {
  _PuantajTablo(this.headers, this.rows, this.total, this.wages);

  final List<String> headers;
  final List<List<String>> rows;
  final List<String> total;
  final bool wages;
}

String _p(double? v) => v == null ? '' : v.toStringAsFixed(2);

_PuantajTablo _puantajTablo(TimesheetReport r) {
  final w = r.wagesIncluded;
  final headers = <String>[
    'Personel',
    'Mağaza',
    'Çalışılan (dk)',
    'Planlı (dk)',
    'Fazla mesai (dk)',
    'Eksik (dk)',
    'Mola (dk)',
    'Çalışılan gün',
    'İzin günü',
    'Devamsız gün',
    if (w) ...[
      'Saat ücreti',
      'Normal',
      'Fazla mesai',
      'İzin',
      'Yemek',
      'Brüt toplam',
    ],
  ];
  final rows = r.items.map((it) {
    final s = it.summary;
    final g = it.wage;
    return <String>[
      it.fullName,
      it.storeName ?? '',
      '${s.workedMinutes}',
      '${s.scheduledMinutes}',
      '${s.overtimeMinutes}',
      '${s.missingMinutes}',
      '${s.deductedBreakMinutes}',
      '${s.workedDays}',
      '${s.leaveDays}',
      '${s.absentDays}',
      if (w) ...[
        _p(g?.hourlyRate),
        _p(g?.normalPay),
        _p(g?.overtimePay),
        _p(g?.leavePay),
        _p(g?.mealPay),
        _p(g?.grossTotal),
      ],
    ];
  }).toList();
  final t = r.total;
  final wt = r.wageTotal;
  final total = <String>[
    'TOPLAM',
    '',
    '${t.workedMinutes}',
    '${t.scheduledMinutes}',
    '${t.overtimeMinutes}',
    '${t.missingMinutes}',
    '${t.deductedBreakMinutes}',
    '${t.workedDays}',
    '${t.leaveDays}',
    '${t.absentDays}',
    if (w) ...[
      '',
      _p(wt?.normalPay),
      _p(wt?.overtimePay),
      _p(wt?.leavePay),
      _p(wt?.mealPay),
      _p(wt?.grossTotal),
    ],
  ];
  return _PuantajTablo(headers, rows, total, w);
}

/// Aylik puantaj Excel'i. Bordro programina girdi olacagi icin sayilar metin
/// degil SAYI olarak yaziliyor.
Future<void> exportTimesheetExcel(TimesheetReport r) async {
  final workbook = xlsio.Workbook();
  try {
    final sheet = workbook.worksheets[0];
    sheet.name = 'Puantaj';
    sheet.getRangeByIndex(1, 1).setText('Puantaj ${r.from} – ${r.to}');
    final tablo = _puantajTablo(r);
    for (var c = 0; c < tablo.headers.length; c++) {
      sheet.getRangeByIndex(3, c + 1).setText(tablo.headers[c]);
    }
    void yaz(int satir, List<String> degerler) {
      for (var c = 0; c < degerler.length; c++) {
        final v = degerler[c];
        final n = double.tryParse(v);
        final hucre = sheet.getRangeByIndex(satir, c + 1);
        // Ilk iki kolon metin; gerisi sayiysa sayi olarak yazilir ki
        // Excel'de toplanabilsin.
        if (c >= 2 && n != null) {
          hucre.setNumber(n);
        } else {
          hucre.setText(v);
        }
      }
    }

    for (var i = 0; i < tablo.rows.length; i++) {
      yaz(4 + i, tablo.rows[i]);
    }
    yaz(4 + tablo.rows.length, tablo.total);
    await sharePdksFile(
      Uint8List.fromList(workbook.saveAsStream()),
      'puantaj-${r.from}_${r.to}.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  } finally {
    // Syncfusion calisma kitabini elle serbest birakmayi bekliyor.
    workbook.dispose();
  }
}

/// Aylik puantaj PDF'i.
Future<void> exportTimesheetPdf(TimesheetReport r) async {
  final doc = pw.Document(theme: await pdfTurkishTheme());
  final tablo = _puantajTablo(r);
  doc.addPage(
    pw.MultiPage(
      // 16 kolon dikey sayfaya sigmiyor.
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(20),
      header: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Aylık Puantaj',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              '${fmtDate(r.from)} – ${fmtDate(r.to)}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          headers: tablo.headers,
          data: [...tablo.rows, tablo.total],
          headerStyle: pw.TextStyle(
            fontSize: 6.5,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 6.5),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignment: pw.Alignment.centerRight,
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
          },
        ),
        pw.SizedBox(height: 10),
        for (final n in r.notes)
          pw.Text(
            '• $n',
            style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
          ),
        if (tablo.wages) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            'Tutarlar brüt hak ediştir; bordro değildir.',
            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ],
    ),
  );
  await sharePdksFile(
    await doc.save(),
    'puantaj-${r.from}_${r.to}.pdf',
    'application/pdf',
  );
}
