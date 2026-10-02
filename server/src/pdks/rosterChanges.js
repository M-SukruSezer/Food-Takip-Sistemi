/// Onaylanan personel taleplerinin haftalik vardiya cizelgesine yansimasi.
///
/// Hepsi cagiranin transaction istemcisiyle calisir: talep onayi ile cizelge
/// degisikligi ayni islemde yazilir, yari yolda kalan durum olusmaz.
const { queryAll, queryOne, execute } = require('../db');

/// Rapor gunlerinde cizelgeye yazilan tatil satirinin notu.
const RAPOR_NOTU = 'RAPOR';

/// Satirin "ne oldugu": vardiya kimligi ya da tatil.
const anahtar = (r) => (r.shift_id == null ? 'OFF' : `S${r.shift_id}`);

/// Iki personelin ayni gundeki satirlarindan yer degistirecek olanlar.
///
/// Iki tarafta da bulunan ayni vardiya (ya da ikisinin de tatil olmasi)
/// yerinde kalir: takasla degisen bir sey yok, tasimak da benzersizlik
/// kisitina takilir.
function takasSatirlari(rows, aId, bId) {
  const a = rows.filter((r) => Number(r.user_id) === Number(aId));
  const b = rows.filter((r) => Number(r.user_id) === Number(bId));
  const ortak = new Set(a.map(anahtar).filter((k) => b.some((r) => anahtar(r) === k)));
  return [...a, ...b].filter((r) => !ortak.has(anahtar(r))).map((r) => Number(r.id));
}

/// Takas: verilen her gunde iki personelin cizelge satirlari yer degistirir.
///
/// Tek tarih: o gunun vardiyalari degisir. Iki tarih (Pazartesi benim,
/// Sali onun): iki gunde de yer degisir; tatil satirlari da tasindigi icin
/// A Sali'ya, B Pazartesi'ye gecer.
async function vardiyaTakas(client, { aId, bId, dates }) {
  for (const d of [...new Set(dates.filter(Boolean))]) {
    const rows = await queryAll(`
      SELECT id, user_id, shift_id FROM user_shifts
      WHERE work_date = ? AND user_id IN (?, ?)`, d, aId, bId, client);
    const ids = takasSatirlari(rows, aId, bId);
    if (ids.length === 0) continue;
    await execute(`
      UPDATE user_shifts
      SET user_id = CASE WHEN user_id = ?::bigint THEN ?::bigint ELSE ?::bigint END
      WHERE id = ANY(?::bigint[])`, aId, bId, aId, ids, client);
  }
}

/// Haftalik OFF: personelin `offDate` gunu tatil olur.
///
/// `swapDate` verilmisse (ayni haftadaki mevcut OFF gunu) iki gun yer
/// degistirir: offDate'in vardiyasi swapDate'e gecer. Verilmemisse offDate'in
/// vardiyalari silinip yerine tatil yazilir.
async function haftalikOff(client, { userId, offDate, swapDate, assignedBy }) {
  if (swapDate) {
    await execute(`
      UPDATE user_shifts
      SET work_date = CASE WHEN work_date = ? THEN ? ELSE ? END, note = NULL
      WHERE user_id = ? AND work_date IN (?, ?)`,
    offDate, swapDate, offDate, userId, offDate, swapDate, client);
    return;
  }
  await tatilYaz(client, { userId, date: offDate, note: null, assignedBy });
}

/// Rapor: araliktaki her gun tatil (not: RAPOR) olarak isaretlenir.
async function raporIsle(client, { userId, from, to, assignedBy }) {
  for (const d of gunler(from, to)) {
    await tatilYaz(client, { userId, date: d, note: RAPOR_NOTU, assignedBy });
  }
}

/// Bir gunun tum satirlarini silip tek tatil satiri yazar.
async function tatilYaz(client, { userId, date, note, assignedBy }) {
  await execute('DELETE FROM user_shifts WHERE user_id = ? AND work_date = ?',
    userId, date, client);
  await execute(`
    INSERT INTO user_shifts (user_id, shift_id, work_date, is_day_off, note, assigned_by)
    VALUES (?, NULL, ?, 1, ?, ?)`, userId, date, note, assignedBy, client);
}

/// [from, to] arasindaki YYYY-MM-DD gunleri (ikisi dahil).
function gunler(from, to) {
  const out = [];
  const d = new Date(`${from}T00:00:00Z`);
  const end = new Date(`${to}T00:00:00Z`);
  if (Number.isNaN(d.getTime()) || Number.isNaN(end.getTime())) return out;
  while (d <= end && out.length < 366) {
    out.push(d.toISOString().slice(0, 10));
    d.setUTCDate(d.getUTCDate() + 1);
  }
  return out;
}

/// ISO haftasinin pazartesisi (YYYY-MM-DD).
function haftaBasi(date) {
  const d = new Date(`${date}T00:00:00Z`);
  const gun = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - gun);
  return d.toISOString().slice(0, 10);
}

/// Personelin o gundeki satirlari.
async function gunSatirlari(userId, date) {
  return queryAll(
    'SELECT id, shift_id, is_day_off, note FROM user_shifts WHERE user_id = ? AND work_date = ?',
    userId, date);
}

async function vardiyasiVar(userId, date) {
  return !!(await queryOne(`
    SELECT id FROM user_shifts
    WHERE user_id = ? AND work_date = ? AND shift_id IS NOT NULL LIMIT 1`, userId, date));
}

module.exports = {
  RAPOR_NOTU,
  takasSatirlari,
  vardiyaTakas,
  haftalikOff,
  raporIsle,
  gunler,
  haftaBasi,
  gunSatirlari,
  vardiyasiVar,
};
