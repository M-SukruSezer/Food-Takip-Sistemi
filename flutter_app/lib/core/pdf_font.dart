import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

// PDF ciktilarinda Turkce karakterler.
//
// SORUN (olculdu): Dart pdf paketinin varsayilan Helvetica yazi tipi
// /WinAnsiEncoding kullaniyor ve cp1252 kumesi s, g, i, I, S, G
// karakterlerini ICERMIYOR. Uretilen PDF'i Poppler ile okudugumuzda:
//   MUHAMMED SUKRU SEZER   -> MUHAMMED ^UKRU SEZER
//   Pazartesi Carsamba     -> Pazartesi Car_amba
//   IZMIT DOLPHIN COLOMBIA -> 0ZM0T DOLPH0N COLOMB0A
// c, o, u, C, O, U cp1252'de oldugu icin kurtuluyor; Turkce'ye ozgu alti
// karakter bozuluyor. Duvara asilacak bir vardiya cizelgesinde ya da bordro
// girdisi olacak bir puantajda personel adinin bozulmasi kabul edilemez.
//
// COZUM: Noto Sans (OFL-1.1) varliklardan yukleniyor. Dart pdf paketi
// kullanilan glifleri kendisi altkumeye aliyor, bu yuzden cikti sismiyor.

/// Ayni oturumda ikinci disa aktarmada tekrar okunmasin.
pw.ThemeData? _onbellek;

/// Turkce destekli PDF temasi.
///
/// Varlik okunamazsa null doner ve cagiran katman varsayilan yazi tipiyle
/// devam eder: bozuk karakterli bir cikti, hic cikti olmamasindan iyidir.
Future<pw.ThemeData?> pdfTurkishTheme() async {
  if (_onbellek != null) return _onbellek;
  try {
    final normal = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    _onbellek = pw.ThemeData.withFont(
      base: pw.Font.ttf(normal),
      bold: pw.Font.ttf(bold),
    );
    return _onbellek;
  } catch (_) {
    return null;
  }
}
