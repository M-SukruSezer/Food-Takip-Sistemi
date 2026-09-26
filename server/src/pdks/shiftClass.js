// Vardiya siniflandirmasi ve yasal kontroller.
//
// Cizelgede vardiya saatlerinin renklendirilmesi ve yasal sinir uyarilari
// buradan cikar. Veritabanina dokunmaz; kural tek yerde olsun diye ayri
// modul — iki istemci de ayni siniflari ve ayni uyarilari gostersin.
//
// Dayanak 4857 sayili Is Kanunu:
//   m.63  gunluk calisma en fazla 11 saat
//   m.68  ara dinlenmesi: <=4 sa 15 dk, 4-7,5 sa 30 dk, >7,5 sa 60 dk
//   m.69  gece donemi 20:00-06:00; gece calismasi 7,5 saati gecemez

const t = require('./time');
const sheet = require('./timesheet');

/// Gece donemi: 20:00 - 06:00 (m.69).
const GECE_BASI = 20 * 60;
const GECE_SONU = 6 * 60;

/// Gunluk azami calisma (m.63).
const GUNLUK_AZAMI = 11 * 60;

/// Gece calismasi azami (m.69).
const GECE_AZAMI = 7.5 * 60;

/// Vardiyanin gece donemine (20:00-06:00) dusen dakikasi.
///
/// Vardiya gece yarisini gecebilir, bu yuzden mutlak dakika ekseninde
/// calisiliyor: baslangic 0..1439, bitis baslangictan kucukse +1440.
function geceDakikasi(startHhmm, endHhmm) {
  const b = t.parseHhmm(startHhmm);
  const e0 = t.parseHhmm(endHhmm);
  if (b === null || e0 === null) return 0;
  const e = e0 > b ? e0 : e0 + 1440;

  // Gece pencereleri: dun 20:00, bugun 20:00, yarin 20:00 baslangicli
  // 10 saatlik dilimler. Ust uste binme toplanir.
  let toplam = 0;
  for (const kaydir of [-1440, 0, 1440]) {
    const pb = GECE_BASI + kaydir;
    const pe = pb + (24 * 60 - GECE_BASI) + GECE_SONU; // 20:00 -> 06:00 = 600 dk
    toplam += Math.max(0, Math.min(e, pe) - Math.max(b, pb));
  }
  return toplam;
}

/// Vardiya kategorisi. Baslangic saatine gore; cizelgede renk bundan cikar.
///
/// Gece kategorisi baslangica DEGIL gece donemine dusen sureye gore: 16:00
/// baslayip 00:30 biten vardiya aksam gibi gorunur ama 4,5 saati gece
/// donemindedir ve gece calismasi sayilir.
function kategori(startHhmm, endHhmm) {
  const b = t.parseHhmm(startHhmm);
  if (b === null) return 'bilinmiyor';
  const gece = geceDakikasi(startHhmm, endHhmm);
  const sure = sheet.shiftSpanMinutes(startHhmm, endHhmm) ?? 0;
  // Suresinin en az ucte biri gece donemindeyse gece vardiyasi sayilir.
  if (sure > 0 && gece >= sure / 3) return 'gece';
  if (b < 12 * 60) return 'sabah';
  if (b < 16 * 60) return 'gunduz';
  return 'aksam';
}

/// Yasal uyarilar. Renk TEK BASINA bilgi tasimasin diye her uyarinin kisa bir
/// etiketi var; arayuz rengin yanina bunu da yaziyor.
function uyarilar(shift) {
  const { start_time: b, end_time: e } = shift || {};
  const sure = sheet.shiftSpanMinutes(b, e);
  if (sure === null) return [];
  const liste = [];
  if (sure > GUNLUK_AZAMI) {
    liste.push({
      kod: 'GUNLUK_ASIM',
      etiket: '11 sa aşımı',
      aciklama: `Günlük çalışma ${Math.round(sure / 6) / 10} saat; 4857 m.63'e göre en fazla 11 saat.`,
    });
  }
  const gece = geceDakikasi(b, e);
  if (gece > GECE_AZAMI) {
    liste.push({
      kod: 'GECE_ASIM',
      etiket: 'gece 7,5 sa aşımı',
      aciklama: `Gece dönemine düşen süre ${Math.round(gece / 6) / 10} saat; 4857 m.69'a göre en fazla 7,5 saat.`,
    });
  }
  const tanimli = Number(shift.break_duration_minutes) || 0;
  const yasal = sheet.legalBreakMinutes(sure);
  if (tanimli < yasal) {
    liste.push({
      kod: 'MOLA_EKSIK',
      etiket: `mola ${yasal} dk olmalı`,
      aciklama: `${Math.round(sure / 6) / 10} saatlik vardiyada ara dinlenmesi en az ${yasal} dakika (4857 m.68); tanımlı süre ${tanimli} dakika.`,
    });
  }
  return liste;
}

/// Cizelgede gosterilecek NET calisma suresi.
///
/// Planli sureden ara dinlenmesi DUSULUR: mola ucretli calisma suresine
/// dahil degil, dolayisiyla "planlanan calisma saati" molayi icermemeli.
/// Dusulen miktar puantajdaki kuralin AYNISI (tanimli ile yasal asgarinin
/// kucugu) ki plan ile gerceklesen ayni olcekte olsun.
function netDakika(shift) {
  const sure = sheet.shiftSpanMinutes(shift.start_time, shift.end_time);
  if (sure === null) return 0;
  return Math.max(0, sure - sheet.breakToDeduct(sure, shift.break_duration_minutes));
}

module.exports = {
  GECE_BASI, GECE_SONU, GUNLUK_AZAMI, GECE_AZAMI,
  geceDakikasi, kategori, uyarilar, netDakika,
};
