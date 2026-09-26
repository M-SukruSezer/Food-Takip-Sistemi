// Vardiya dongüsü (rotation) motoru.
//
// "2 hafta gunduz, 1 hafta gece" gibi bir kurali alip verilen tarih araligi
// icin gun gun hangi personele hangi vardiyanin dusecegini HESAPLAR.
//
// Veritabanina dokunmaz ve tarih "bugun"e bakmaz: tum girdiler disaridan
// geliyor. Boylece uretilen plan zamandan bagimsiz test edilebiliyor — bir
// planlama motorunun en kolay bozulan yani "calistirildigi ana gore farkli
// sonuc uretmesi"dir.

const t = require('./time');

/// Bir dongü adimi: kac HAFTA hangi vardiya.
///
/// { shift_id, weeks } — weeks >= 1
///
/// Ornek: [{shift_id: 3, weeks: 2}, {shift_id: 5, weeks: 1}]
///   iki hafta 3 numarali vardiya, bir hafta 5 numarali vardiya, sonra basa.

/// Kurali dogrular. Gecerliyse null, degilse hata metni doner.
function validatePattern(pattern) {
  if (!Array.isArray(pattern) || pattern.length === 0) {
    return 'En az bir döngü adımı gerekir';
  }
  if (pattern.length > 12) return 'Döngü en fazla 12 adım olabilir';
  for (const [i, adim] of pattern.entries()) {
    const w = Number(adim && adim.weeks);
    if (!Number.isInteger(w) || w < 1 || w > 8) {
      return `${i + 1}. adımda hafta sayısı 1-8 arasında bir tam sayı olmalıdır`;
    }
    // shift_id null olabilir: "o hafta komple hafta tatili" anlamina gelir.
    if (adim.shift_id !== null && !Number.isInteger(Number(adim.shift_id))) {
      return `${i + 1}. adımda geçerli bir vardiya seçilmelidir`;
    }
  }
  const toplam = pattern.reduce((a, x) => a + Number(x.weeks), 0);
  if (toplam > 52) return 'Döngü toplamı 52 haftayı aşamaz';
  return null;
}

/// Dongünün toplam hafta uzunlugu.
function patternWeeks(pattern) {
  return pattern.reduce((a, x) => a + Number(x.weeks), 0);
}

/// Verilen hafta indeksinde (0 tabanli) dongünün hangi adimda oldugu.
///
/// Negatif indeks de dogru calisir: cizelge geriye dogru uretilirse
/// (gecmis bir haftayi doldurmak) kalinti negatife dusmemeli.
function stepAt(pattern, weekIndex) {
  const toplam = patternWeeks(pattern);
  let k = weekIndex % toplam;
  if (k < 0) k += toplam;
  for (const adim of pattern) {
    if (k < Number(adim.weeks)) return adim;
    k -= Number(adim.weeks);
  }
  // patternWeeks ile tutarli oldugu icin buraya dusulmez.
  return pattern[pattern.length - 1];
}

/// Iki tarih arasindaki TAM hafta farki (pazartesi baslangicli).
///
/// Referans ve hedef ayni haftadaysa 0 doner.
function weekDiff(anchorMonday, date) {
  const a = Date.UTC(...anchorMonday.split('-').map((v, i) => (i === 1 ? Number(v) - 1 : Number(v))));
  const b = Date.UTC(...date.split('-').map((v, i) => (i === 1 ? Number(v) - 1 : Number(v))));
  return Math.floor((b - a) / (7 * 86400000));
}

/// Tarihin icinde bulundugu haftanin PAZARTESI'si.
/// Turkiye'de is haftasi pazartesi basliyor.
function mondayOf(date) {
  const [y, m, d] = date.split('-').map(Number);
  const g = new Date(Date.UTC(y, m - 1, d));
  const dow = g.getUTCDay();            // 0 = pazar
  const geri = dow === 0 ? 6 : dow - 1;
  return t.shiftDate(date, -geri);
}

/// Dongüden gun gun plan uretir.
///
/// [anchor]  dongünün BASLADIGI tarih; o tarihin haftasi 1. adimdir
/// [from]/[to] uretilecek aralik (dahil)
/// [weeklyOff] personelin hafta tatili gunleri (0 = pazar)
///
/// Doner: [{ work_date, shift_id, is_day_off }]
///   shift_id null + is_day_off true  -> hafta tatili
///   Hafta tatili gunleri dongüden BAGIMSIZ: kisinin sabit tatil gunu
///   hangi haftada olursa olsun tatildir.
function generate({ pattern, anchor, from, to, weeklyOff = [0] }) {
  const hata = validatePattern(pattern);
  if (hata) throw new Error(hata);
  if (!t.isDate?.(from) && !/^\d{4}-\d{2}-\d{2}$/.test(from)) {
    throw new Error('Başlangıç tarihi YYYY-AA-GG biçiminde olmalıdır');
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(to)) {
    throw new Error('Bitiş tarihi YYYY-AA-GG biçiminde olmalıdır');
  }
  if (to < from) throw new Error('Bitiş tarihi başlangıçtan önce olamaz');

  const anchorMonday = mondayOf(anchor);
  const off = new Set((weeklyOff || []).map(Number));
  const plan = [];
  let cursor = from;
  // 400 gunluk ust sinir: sonsuz dongüye karsi emniyet.
  for (let guard = 0; guard < 400 && cursor <= to; guard++) {
    const [y, m, d] = cursor.split('-').map(Number);
    const dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
    if (off.has(dow)) {
      plan.push({ work_date: cursor, shift_id: null, is_day_off: true });
    } else {
      const adim = stepAt(pattern, weekDiff(anchorMonday, mondayOf(cursor)));
      if (adim.shift_id === null) {
        // Komple tatil haftasi.
        plan.push({ work_date: cursor, shift_id: null, is_day_off: true });
      } else {
        plan.push({
          work_date: cursor,
          shift_id: Number(adim.shift_id),
          is_day_off: false,
        });
      }
    }
    cursor = t.shiftDate(cursor, 1);
  }
  return plan;
}

module.exports = {
  validatePattern, patternWeeks, stepAt, weekDiff, mondayOf, generate,
};
