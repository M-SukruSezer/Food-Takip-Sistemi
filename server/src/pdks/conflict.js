// Vardiya planlama cakisma kontrolu.
//
// Bir gune vardiya atanirken o gun icin ENGELLEYICI ya da UYARILACAK bir durum
// var mi? Kural burada, veritabani erisimi cagiran katmanda: boylece hem tek
// hucre atamasi hem toplu atama hem de otomatik dongü AYNI kurali kullaniyor
// ve zamanla ayrismiyor.
//
// Onceki surumde kural yalnizca toplu atamanin icinde gomuluydu; tek hucre ucu
// eklendiginde izin kontrolu hic yapilmadi ve izinli personele vardiya
// atanabiliyordu.

const t = require('./time');

/// Engelleyici sebepler: bu gune vardiya YAZILMAMALI.
const BLOCK = 'block';

/// Uyarilacak sebepler: yazilabilir ama yonetici bilmeli.
const WARN = 'warn';

/// Gunluk (yillik) izin bu gunu kapsiyor mu?
///
/// IZIN kayitlarinda start_at/end_at YYYY-MM-DD; kapsama gun bazinda ve
/// iki ucu dahil.
function dailyLeaveHit(leaves, workDate) {
  return leaves.find((l) => l.type === 'IZIN'
    && typeof l.start_at === 'string' && typeof l.end_at === 'string'
    && workDate >= l.start_at.slice(0, 10)
    && workDate <= l.end_at.slice(0, 10));
}

/// Saatlik izinler bu gune dusuyor mu?
///
/// SAATLIK_IZIN kayitlarinda start_at/end_at ISO zaman damgasi (UTC). Gunu
/// YEREL saate gore buluyoruz: 23:00'te baslayan saatlik izin UTC'de ertesi
/// gune duser ve yanlis gune yazilirdi.
function hourlyLeaveHits(leaves, workDate) {
  return leaves.filter((l) => l.type === 'SAATLIK_IZIN'
    && typeof l.start_at === 'string'
    && t.localDate(l.start_at) === workDate);
}

/// Bir gunun cakisma durumu.
///
/// [leaves] o personelin ONAYLI izin kayitlari (IZIN + SAATLIK_IZIN)
/// [holiday] o gunun resmi tatil kaydi ya da null
/// [weeklyOff] o gun hafta tatili mi
///
/// Doner: { blocked, reasons: [{ level, code, label, detail }] }
function checkDay({ workDate, leaves = [], holiday = null, weeklyOff = false }) {
  const reasons = [];

  if (weeklyOff) {
    reasons.push({
      level: BLOCK,
      code: 'HAFTA_TATILI',
      label: 'hafta tatili',
      detail: `${workDate} personelin hafta tatili günü.`,
    });
  }

  const gunluk = dailyLeaveHit(leaves, workDate);
  if (gunluk) {
    reasons.push({
      level: BLOCK,
      code: 'YILLIK_IZIN',
      label: 'onaylı izin',
      detail: `${workDate} onaylı yıllık izin kapsamında`
        + ` (${gunluk.start_at.slice(0, 10)} – ${gunluk.end_at.slice(0, 10)}).`,
    });
  }

  // Tam gun tatilde calisma planlanmaz; yarim tatilde calisilir.
  if (holiday != null && holiday.half !== true) {
    reasons.push({
      level: BLOCK,
      code: 'RESMI_TATIL',
      label: `resmi tatil (${holiday.name})`,
      detail: `${workDate} resmi tatil: ${holiday.name}.`,
    });
  }

  // Saatlik izin gunu KAPATMIYOR: personel gunun bir kisminda calisiyor.
  // Bu yuzden engel degil uyari — yonetici vardiyayi yine atayabilir, planli
  // sure puantajda saatlik izin kadar dusuluyor.
  for (const s of hourlyLeaveHits(leaves, workDate)) {
    const saat = (v) => {
      const d = new Date(v);
      return Number.isNaN(d.getTime()) ? '?' : t.localMinutes(v);
    };
    const bas = saat(s.start_at);
    const bit = saat(s.end_at);
    const hhmm = (m) => typeof m === 'number'
      ? `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`
      : '?';
    reasons.push({
      level: WARN,
      code: 'SAATLIK_IZIN',
      label: 'saatlik izin',
      detail: `${workDate} ${hhmm(bas)}–${hhmm(bit)} arası onaylı saatlik izin`
        + ` (${s.hours ?? '?'} saat). Vardiya atanabilir; planlı süre puantajda düşülür.`,
    });
  }

  if (holiday != null && holiday.half === true) {
    reasons.push({
      level: WARN,
      code: 'YARIM_TATIL',
      label: `yarım gün tatil (${holiday.name})`,
      detail: `${workDate} yarım gün resmi tatil: ${holiday.name}.`,
    });
  }

  return {
    blocked: reasons.some((r) => r.level === BLOCK),
    reasons,
  };
}

/// Engelleyici sebeplerin kisa ozeti; toplu atamanin "atlandi" bildiriminde
/// ve hucre ucunun hata mesajinda kullaniliyor.
function blockLabel(result) {
  return result.reasons
    .filter((r) => r.level === BLOCK)
    .map((r) => r.label)
    .join(' + ');
}

module.exports = { BLOCK, WARN, checkDay, blockLabel, dailyLeaveHit, hourlyLeaveHits };
