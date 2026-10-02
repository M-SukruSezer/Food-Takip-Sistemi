import 'dart:typed_data';

import 'package:flutter/painting.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../models/pdks.dart';
import 'format.dart';
import 'pdf_font.dart';
import 'tokens.dart';
import 'report_export.dart' show sharePdksFile;

// PDKS ciktilari: haftalik vardiya plani (PDF) ve aylik puantaj (Excel + PDF).
//
// Tablolar tek yerde kuruluyor ki Excel ile PDF birbirinden sapmasin — rapor
// panelindeki _Table deseniyle ayni gerekce.

const _gunKisa = ['Paz', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt'];
const _gunUzun = [
  'PAZAR',
  'PAZARTESİ',
  'SALI',
  'ÇARŞAMBA',
  'PERŞEMBE',
  'CUMA',
  'CUMARTESİ',
];

String _gunAdi(String tarih, {bool uzun = false}) {
  final d = DateTime.tryParse('${tarih}T00:00:00Z');
  if (d == null) return '';
  return (uzun ? _gunUzun : _gunKisa)[d.toUtc().weekday % 7];
}

/// Hucrenin metin karsiligi. Ekran ve PDF ayni gosterimi kullansin diye tek
/// fonksiyon.
String rosterCellText(List<RosterCell> hucreler, PublicHoliday? tatil) {
  if (tatil != null && !tatil.isHalfDay) return 'RT';
  if (hucreler.isEmpty) return '-';
  if (hucreler.any((c) => c.isDayOff)) return 'OFF';
  return hucreler.map((c) => c.saatAraligi).join(' / ');
}

/// Cizelgedeki rol etiketi. Ekran ve PDF ayni metni gostersin diye burada.
String rosterRoleLabel(String role) => switch (role.toLowerCase()) {
  'store_manager' => 'Müdür',
  'shift_supervisor' || 'supervisor' => 'Supervisor',
  'senior_barista' => 'Kıdemli Barista',
  'barista' => 'Barista',
  'kitchen' => 'Mutfak',
  'service' => 'Servis',
  '' => 'Personel',
  _ => role[0].toUpperCase() + role.substring(1).toLowerCase(),
};

/// Kadro gucu etiketi (gunluk calisan sayisina gore). Ekran ve PDF ortak.
String rosterStaffingLabel(int working) => working >= 4
    ? 'Yeterli'
    : working >= 3
    ? 'Min. Kadro'
    : 'Dengeli';

/// Ekrandaki (acik tema) renk -> PDF rengi.
PdfColor _pdf(Color c) => PdfColor.fromInt(c.toARGB32());

/// Haftalik vardiya plani PDF'i — ekrandaki "Haftalik Personel Matrisi" ile
/// AYNI duzen ve renkler: Personel & Rol, gun sutunlari (saat + kategori),
/// OFF / RAPOR / RT hucreleri, Planli toplam ve Kadro Gucu satiri. Haftanin
/// plan notlari tablonun altina eklenir.
Future<void> exportRosterPdf(Roster r, {List<String> notes = const []}) async {
  await sharePdksFile(
    await buildRosterPdf(r, notes: notes),
    'vardiya-plani-${r.from}.pdf',
    'application/pdf',
  );
}

/// [exportRosterPdf]'in PDF baytlari (paylasimdan ayri; test edilebilir).
Future<Uint8List> buildRosterPdf(
  Roster r, {
  List<String> notes = const [],
}) async {
  final doc = pw.Document(theme: await pdfTurkishTheme());
  // Kagida basildigi icin her zaman acik tema renkleri.
  const t = AppTokens.light;
  final kenar = pw.BorderSide(width: 0.5, color: _pdf(t.border));

  pw.Widget yazi(
    String s, {
    double size = 7,
    PdfColor? color,
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.center,
  }) => pw.Text(
    s,
    textAlign: align,
    style: pw.TextStyle(
      fontSize: size,
      color: color ?? _pdf(t.ink),
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    ),
  );

  /// Ekrandaki hucre rozeti: renkli kutu + iki satir.
  pw.Widget rozet(String ust, String alt, PdfColor zemin, PdfColor metin) =>
      pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 1),
        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: pw.BoxDecoration(
          color: zemin,
          borderRadius: pw.BorderRadius.circular(3),
        ),
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            yazi(ust, color: metin, bold: true),
            if (alt.isNotEmpty) yazi(alt, size: 6, color: metin),
          ],
        ),
      );

  pw.Widget hucre(List<RosterCell> cells, PublicHoliday? tatil) {
    if (tatil != null && !tatil.isHalfDay) {
      return rozet('RT', 'Tatil', _pdf(t.dangerSoft), _pdf(t.danger));
    }
    if (cells.isEmpty) {
      return pw.Center(child: yazi('-', color: _pdf(t.borderStrong)));
    }
    if (cells.any((c) => c.isDayOff)) {
      final rapor = cells.any((c) => c.isRapor);
      return rozet(
        rapor ? 'RAPOR' : 'OFF',
        rapor ? 'Raporlu' : 'Hafta Tatili',
        _pdf(t.dangerSoft),
        _pdf(t.dangerText),
      );
    }
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        for (final c in cells)
          () {
            final (zemin, metin, etiket) = switch (c.category) {
              ShiftCategory.sabah => (t.infoSoft, t.infoText, 'Sabah'),
              ShiftCategory.gunduz => (t.successSoft, t.okText, 'Gündüz'),
              ShiftCategory.aksam => (t.warningSoft, t.warningText, 'Akşam'),
              ShiftCategory.kapanis => (t.ink, t.card, 'Kapanış'),
              ShiftCategory.bilinmiyor => (t.bg, t.ink, ''),
            };
            // Gece yarisini gecen vardiya ekrandaki gibi koyu zeminde.
            return c.crossesMidnight
                ? rozet(c.saatAraligi, etiket, _pdf(t.ink), _pdf(t.card))
                : rozet(c.saatAraligi, etiket, _pdf(zemin), _pdf(metin));
          }(),
      ],
    );
  }

  pw.Widget pad(pw.Widget child, {double v = 4}) => pw.Padding(
    padding: pw.EdgeInsets.symmetric(vertical: v, horizontal: 3),
    child: child,
  );

  final rows = <pw.TableRow>[
    // Baslik satiri.
    pw.TableRow(
      decoration: pw.BoxDecoration(color: _pdf(t.bg)),
      children: [
        pad(
          yazi('Personel & Rol', size: 8, bold: true, align: pw.TextAlign.left),
          v: 6,
        ),
        for (final d in r.dates)
          pw.Container(
            color: r.holidays[d] != null ? _pdf(t.dangerSoft) : null,
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Column(
              children: [
                yazi(
                  _gunAdi(d),
                  size: 8,
                  bold: true,
                  color: r.holidays[d] != null ? _pdf(t.danger) : null,
                ),
                yazi(
                  '${d.substring(8)}.${d.substring(5, 7)}',
                  color: _pdf(t.muted),
                ),
              ],
            ),
          ),
        pad(yazi('Planlı', size: 8, bold: true, color: _pdf(t.muted)), v: 6),
      ],
    ),
    // Personel satirlari (zebra).
    for (var i = 0; i < r.people.length; i++)
      pw.TableRow(
        decoration: pw.BoxDecoration(color: i.isOdd ? _pdf(t.bg) : null),
        verticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: [
          pad(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                yazi(
                  r.people[i].fullName,
                  size: 8,
                  bold: true,
                  align: pw.TextAlign.left,
                ),
                yazi(
                  rosterRoleLabel(r.people[i].role),
                  size: 6.5,
                  color: _pdf(t.muted),
                  align: pw.TextAlign.left,
                ),
              ],
            ),
          ),
          for (final d in r.dates)
            pad(hucre(r.people[i].gun(d), r.holidays[d]), v: 2),
          pad(
            yazi(fmtDuration(r.people[i].plannedMinutes), size: 8, bold: true),
          ),
        ],
      ),
    // Kadro gucu satiri.
    pw.TableRow(
      decoration: pw.BoxDecoration(
        color: _pdf(t.border.withValues(alpha: 0.6)),
      ),
      verticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pad(
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              yazi('Kadro Gücü', size: 8, bold: true, align: pw.TextAlign.left),
              yazi(
                'Çalışan sayısı',
                size: 6.5,
                color: _pdf(t.primary),
                align: pw.TextAlign.left,
              ),
            ],
          ),
        ),
        for (final d in r.dates)
          pad(
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              decoration: pw.BoxDecoration(
                color: _pdf(t.card),
                borderRadius: pw.BorderRadius.circular(3),
              ),
              child: pw.Column(
                children: [
                  yazi(
                    '${r.gunToplam(d).working} Kişi',
                    bold: true,
                    color: _pdf(t.primary),
                  ),
                  yazi(
                    rosterStaffingLabel(r.gunToplam(d).working),
                    size: 6,
                    color: _pdf(t.okText),
                  ),
                ],
              ),
            ),
            v: 3,
          ),
        pad(
          yazi(
            fmtDuration(r.totalPlannedMinutes),
            size: 8,
            bold: true,
            color: _pdf(t.primary),
          ),
        ),
      ],
    ),
  ];

  doc.addPage(
    pw.MultiPage(
      // 7 gun + isim dikey sayfaya sigmiyor.
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Haftalık Vardiya Planı',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: _pdf(t.ink),
                    ),
                  ),
                  pw.Text(
                    '${r.storeName != null ? '${r.storeName} · ' : ''}'
                    '${fmtDate(r.from)} – ${fmtDate(r.to)}',
                    style: pw.TextStyle(fontSize: 10, color: _pdf(t.muted)),
                  ),
                ],
              ),
            ),
            pw.Text(
              '${r.people.length} personel',
              style: pw.TextStyle(fontSize: 9, color: _pdf(t.muted)),
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _pdf(t.border), width: 0.8),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Table(
            border: pw.TableBorder(horizontalInside: kenar),
            columnWidths: {
              0: const pw.FixedColumnWidth(120),
              for (var i = 1; i <= r.dates.length; i++)
                i: const pw.FlexColumnWidth(),
              r.dates.length + 1: const pw.FixedColumnWidth(48),
            },
            children: rows,
          ),
        ),
        if (notes.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text(
            'Plan Notları',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: _pdf(t.ink),
            ),
          ),
          pw.SizedBox(height: 4),
          for (final n in notes)
            pw.Bullet(
              text: n,
              style: pw.TextStyle(fontSize: 9, color: _pdf(t.ink)),
            ),
        ],
        pw.SizedBox(height: 10),
        pw.Text(
          'Planlı süreler NET çalışmadır: ara dinlenmesi (4857 m.68) '
          'düşülmüştür.',
          style: pw.TextStyle(fontSize: 7, color: _pdf(t.muted)),
        ),
      ],
    ),
  );

  return doc.save();
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
