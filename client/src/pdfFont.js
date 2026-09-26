// PDF ciktilarinda Turkce karakterler.
//
// SORUN (olculdu): jsPDF'in gomulu Helvetica yazi tipi /WinAnsiEncoding
// kullaniyor ve cp1252 kumesi s, g, i, I, S, G karakterlerini ICERMIYOR.
// Uretilen PDF'i Poppler ile okudugumuzda:
//   MUHAMMED SUKRU SEZER  -> MUHAMMED ^UKRU SEZER
//   Pazartesi Carsamba    -> Pazartesi Car_amba
//   IZMIT DOLPHIN COLOMBIA -> 0ZM0T DOLPH0N COLOMB0A
// c, o, u, C, O, U cp1252'de oldugu icin kurtuluyor; Turkce'ye ozgu alti
// karakter bozuluyor. Duvara asilacak bir vardiya cizelgesinde personel
// adinin bozulmasi kabul edilemez.
//
// COZUM: Noto Sans (OFL-1.1) gomuluyor. Yazi tipi JS paketine DEGIL
// public/fonts altina konuldu ve yalnizca disa aktarma aninda indiriliyor;
// normal kullanimda 1 MB'lik yuk olusmuyor.

const DOSYA = {
  normal: '/fonts/NotoSans-Regular.ttf',
  bold: '/fonts/NotoSans-Bold.ttf',
};

export const PDF_FONT = 'NotoSans';

// Ayni oturumda ikinci disa aktarmada tekrar indirilmesin.
let onbellek = null;

async function base64Al(yol) {
  const r = await fetch(yol);
  if (!r.ok) throw new Error(`Yazı tipi yüklenemedi: ${yol}`);
  const buf = await r.arrayBuffer();
  // btoa binary string bekliyor; buyuk dosyada tek seferde spread etmek
  // yigin tasmasi (call stack) uretiyor, bu yuzden parca parca.
  const bytes = new Uint8Array(buf);
  let s = '';
  const ADIM = 0x8000;
  for (let i = 0; i < bytes.length; i += ADIM) {
    s += String.fromCharCode.apply(null, bytes.subarray(i, i + ADIM));
  }
  return btoa(s);
}

/// Yazi tipini dokumana kaydeder ve etkin hale getirir.
///
/// Indirme basarisiz olursa SESSIZCE Helvetica ile devam ediliyor: bozuk
/// karakterli bir cikti, hic cikti olmamasindan iyidir. Cagiran katman
/// donen degere bakip kullaniciyi uyarabilir.
export async function pdfFontKur(doc) {
  try {
    if (!onbellek) {
      const [normal, bold] = await Promise.all([
        base64Al(DOSYA.normal), base64Al(DOSYA.bold),
      ]);
      onbellek = { normal, bold };
    }
    doc.addFileToVFS('NotoSans-Regular.ttf', onbellek.normal);
    doc.addFont('NotoSans-Regular.ttf', PDF_FONT, 'normal');
    doc.addFileToVFS('NotoSans-Bold.ttf', onbellek.bold);
    doc.addFont('NotoSans-Bold.ttf', PDF_FONT, 'bold');
    doc.setFont(PDF_FONT, 'normal');
    return true;
  } catch (e) {
    return false;
  }
}
