const t = require('./time');

// Izin ve avans bakiyesi hesaplari.
//
// Veritabanina dokunmaz: sorgular cagiran katmanda, kural burada. Boylece
// kurallar duvar saatinden ve veriden bagimsiz test edilebiliyor.

/// Hafta tatili gunleri. users.permissions ile ayni desende JSON metin.
/// 0 = Pazar ... 6 = Cumartesi. Bozuk veri gelirse Pazar varsayilir.
function parseWeeklyOff(json) {
  try {
    const v = JSON.parse(json || '[0]');
    if (!Array.isArray(v)) return [0];
    const days = v.map(Number).filter((d) => Number.isInteger(d) && d >= 0 && d <= 6);
    return days.length ? [...new Set(days)] : [0];
  } catch {
    return [0];
  }
}

/// Yillik izin yili.
///
/// 4857 sayili Is Kanunu'nda izin hakki ISE GIRIS tarihine gore yillanir,
/// takvim yilina gore degil. Ise giris bilinmiyorsa takvim yili kullanilir.
/// Gun sayisini ayin son gunune kirpar.
///
/// 29 Subat girisli personelin artik olmayan yildaki yildonumu 29 Subat
/// olarak kurulursa var olmayan bir tarih uretilir ('2026-02-29') ve SQL
/// karsilastirmalari sessizce bozulur. O gun 28 Subat'a kirpilir.
function clampDay(year, month, day) {
  const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const pad = (n) => String(n).padStart(2, '0');
  return `${year}-${pad(month)}-${pad(Math.min(day, lastDay))}`;
}

function leaveYearRange(hiredAt, atIso = new Date().toISOString()) {
  const today = t.localDate(atIso);
  const [y] = today.split('-').map(Number);

  if (!hiredAt || !/^\d{4}-\d{2}-\d{2}$/.test(hiredAt)) {
    return { from: `${y}-01-01`, to: `${y}-12-31`, basis: 'calendar' };
  }

  const [, hm, hd] = hiredAt.split('-').map(Number);
  const anniversaryThisYear = clampDay(y, hm, hd);
  // Yildonumu henuz gelmediyse gecen yilin yildonumunden bu yila.
  const startYear = today >= anniversaryThisYear ? y : y - 1;
  const from = clampDay(startYear, hm, hd);
  // Bir sonraki yildonumunun bir gun oncesi.
  const to = t.shiftDate(clampDay(startYear + 1, hm, hd), -1);
  return { from, to, basis: 'anniversary' };
}

/// Iki tarih arasindaki IZIN GUNU sayisi.
///
/// Hafta tatili gunleri dusulur: yillik izin calisma gunu uzerinden sayilir.
/// Resmi tatiller HESABA KATILMIYOR — tatil takvimi tablosu gerekir, bu
/// surumde yok. Kullaniciya gosterilen metinde belirtilmeli.
function countLeaveDays(from, to, weeklyOffDays = [0]) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to)) return null;
  if (to < from) return null;
  const off = new Set(weeklyOffDays);
  let days = 0;
  let cursor = from;
  // Ust sinir: tek talepte bir yildan uzun izin girilemez.
  for (let guard = 0; guard < 400 && cursor <= to; guard++) {
    const [y, m, d] = cursor.split('-').map(Number);
    const dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
    if (!off.has(dow)) days++;
    cursor = t.shiftDate(cursor, 1);
  }
  return days;
}

/// Saatlik izin suresi. Ayni gun icinde olmali.
function countLeaveHours(startIso, endIso) {
  const a = new Date(startIso).getTime();
  const b = new Date(endIso).getTime();
  if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a) return null;
  const hours = (b - a) / 3600000;
  // Tek seferde 12 saatten uzun "saatlik izin" gunluk izindir.
  if (hours > 12) return null;
  return Math.round(hours * 100) / 100;
}

/// Bulunulan takvim ayi (avans limiti aylik).
function monthRange(atIso = new Date().toISOString()) {
  const today = t.localDate(atIso);
  const [y, m] = today.split('-').map(Number);
  const from = clampDay(y, m, 1);
  const to = t.shiftDate(
    m === 12 ? clampDay(y + 1, 1, 1) : clampDay(y, m + 1, 1), -1
  );
  return { from, to };
}

/// Iki tarih araligi cakisiyor mu? (ikisi de kapali aralik)
function overlaps(aFrom, aTo, bFrom, bTo) {
  return aFrom <= bTo && bFrom <= aTo;
}

/// Bakiye ozeti.
///
/// BEKLEYEN talep de dusulur: aksi halde personel ust uste talep gonderip
/// hakkindan fazlasini onaya dusurebilirdi. Reddedilen geri eklenir.
function summarize({ entitlementDays, usedDays, pendingDays,
                     advanceLimit, usedAdvance, pendingAdvance,
                     usedHours, pendingHours }) {
  const remainingDays = entitlementDays - usedDays - pendingDays;
  const remainingAdvance = advanceLimit - usedAdvance - pendingAdvance;
  return {
    leave: {
      entitlement_days: entitlementDays,
      used_days: usedDays,
      pending_days: pendingDays,
      remaining_days: Math.round(Math.max(0, remainingDays) * 100) / 100,
      // Hakki asan onayli izin varsa eksi bakiye gizlenmemeli.
      over_used: remainingDays < 0,
    },
    hourly_leave: {
      used_hours: Math.round((usedHours || 0) * 100) / 100,
      pending_hours: Math.round((pendingHours || 0) * 100) / 100,
      // Saatlik izin yillik izin gununden DUSULMUYOR: ayri takip ediliyor.
      // Isletme dusulmesini isterse kural burada degisir.
      deducted_from_annual: false,
    },
    advance: {
      monthly_limit: advanceLimit,
      used: Math.round(usedAdvance * 100) / 100,
      pending: Math.round(pendingAdvance * 100) / 100,
      remaining: Math.round(Math.max(0, remainingAdvance) * 100) / 100,
      over_used: remainingAdvance < 0,
    },
  };
}

module.exports = {
  parseWeeklyOff,
  leaveYearRange,
  countLeaveDays,
  countLeaveHours,
  monthRange,
  overlaps,
  summarize,
};
