// PDKS zaman yardimcilari.
//
// Veritabani zaman damgalarini UTC ISO metni olarak tutuyor. Ama "bugun"
// personel icin YEREL gundur: UTC tarihi kullanmak vardiyayi gece 03:00'te
// (TR saatiyle) yeni gune atlatirdi.
//
// Turkiye 2016'dan beri kalici UTC+3 (yaz saati uygulamasi yok). Bu yuzden
// sabit ofset yeterli; birden fazla ulkeye acilirsa ofset magaza ayari olmali.
const TZ_OFFSET_MINUTES = 180;

/// ISO damgadan yerel takvim gunu (YYYY-MM-DD).
function localDate(iso = new Date().toISOString()) {
  const t = new Date(iso).getTime() + TZ_OFFSET_MINUTES * 60000;
  return new Date(t).toISOString().slice(0, 10);
}

/// ISO damgadan yerel duvar saati, gun basindan itibaren dakika.
/// 08:30 -> 510. Vardiya saatleriyle karsilastirmak icin.
function localMinutes(iso = new Date().toISOString()) {
  const t = new Date(iso).getTime() + TZ_OFFSET_MINUTES * 60000;
  const d = new Date(t);
  return d.getUTCHours() * 60 + d.getUTCMinutes();
}

/// 'HH:MM' -> gun basindan dakika.
function parseHhmm(value) {
  const m = /^([01][0-9]|2[0-3]):([0-5][0-9])$/.exec(String(value || ''));
  if (!m) return null;
  return Number(m[1]) * 60 + Number(m[2]);
}

/// Yerel gunun (YYYY-MM-DD) ve duvar saatinin (dakika) UTC ISO karsiligi.
/// Vardiya saatini mutlak zamana cevirmek icin.
function localToIso(date, minutes) {
  const [y, mo, d] = String(date).split('-').map(Number);
  const utcMs = Date.UTC(y, mo - 1, d, 0, 0, 0) + (minutes - TZ_OFFSET_MINUTES) * 60000;
  return new Date(utcMs).toISOString().replace('Z', 'Z');
}

/// Gun ekler/cikarir (YYYY-MM-DD).
function shiftDate(date, days) {
  const [y, mo, d] = String(date).split('-').map(Number);
  return new Date(Date.UTC(y, mo - 1, d + days)).toISOString().slice(0, 10);
}

/// Vardiya gece yarisini geciyor mu? (22:00 -> 06:00)
function crossesMidnight(startHhmm, endHhmm) {
  const s = parseHhmm(startHhmm);
  const e = parseHhmm(endHhmm);
  if (s === null || e === null) return false;
  return e <= s;
}

module.exports = {
  TZ_OFFSET_MINUTES,
  localDate,
  localMinutes,
  parseHhmm,
  localToIso,
  shiftDate,
  crossesMidnight,
};
