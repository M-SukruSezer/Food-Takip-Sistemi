const express = require('express');
const { queryAll, queryOne, execute, transaction } = require('../db');
const {
  requireAuth, requireRole, resolveStoreScope, storeFilter, allowsStore, MANAGER_ROLES,
} = require('../auth');
const { logActivity } = require('../utils');
const qr = require('../pdks/qr');
const t = require('../pdks/time');
const bal = require('../pdks/balance');

const router = express.Router();

router.use(requireAuth);

// Vardiya tanimlama, atama ve PDKS ayarlari yonetici islerinde.
const requireManager = requireRole(...MANAGER_ROLES);

// ---- Vardiya tanimlari ----

router.get('/shifts', async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;
  const f = storeFilter(scope, 's.store_id');
  // store_id NULL olan vardiya tum magazalarda kullanilabilen sablon; kapsam
  // filtresi onu dislamasin.
  const rows = await queryAll(`
    SELECT s.*, st.name AS store_name
    FROM shifts s LEFT JOIN stores st ON st.id = s.store_id
    WHERE (s.store_id IS NULL ${f.sql}) AND (? = 1 OR s.active = 1)
    ORDER BY s.store_id NULLS FIRST, s.start_time
  `.replace('(s.store_id IS NULL ' + f.sql + ')',
            f.sql ? `(s.store_id IS NULL OR 1=1${f.sql})` : '1=1'),
    ...f.params, req.query.all === '1' ? 1 : 0);
  res.json(rows.map((r) => ({ ...r, active: !!r.active })));
});

/// Vardiya alanlarini dogrular.
function readShift(body, existing) {
  const out = {
    name: body.name !== undefined ? String(body.name).trim() : existing?.name,
    start_time: body.start_time !== undefined ? String(body.start_time).trim() : existing?.start_time,
    end_time: body.end_time !== undefined ? String(body.end_time).trim() : existing?.end_time,
  };
  if (!out.name) return { error: 'Vardiya adı zorunludur' };
  if (t.parseHhmm(out.start_time) === null) return { error: 'Başlangıç saati SS:DD biçiminde olmalıdır' };
  if (t.parseHhmm(out.end_time) === null) return { error: 'Bitiş saati SS:DD biçiminde olmalıdır' };

  const nums = {
    break_duration_minutes: [0, 480, 'Mola süresi'],
    late_tolerance_minutes: [0, 120, 'Geç kalma toleransı'],
    early_leave_tolerance_minutes: [0, 120, 'Erken çıkış toleransı'],
    overtime_starts_after_minutes: [0, 120, 'Fazla mesai eşiği'],
  };
  for (const [key, [min, max, label]] of Object.entries(nums)) {
    const raw = body[key];
    if (raw === undefined) { out[key] = existing ? existing[key] : undefined; continue; }
    const n = Number(raw);
    if (!Number.isInteger(n) || n < min || n > max) {
      return { error: `${label} ${min}-${max} arasında tam sayı olmalıdır` };
    }
    out[key] = n;
  }

  // Calisma suresi molayi karsilamali; aksi halde puantaj eksiye duser.
  const s = t.parseHhmm(out.start_time);
  const e = t.parseHhmm(out.end_time);
  const span = e > s ? e - s : 24 * 60 - s + e;
  const brk = out.break_duration_minutes ?? 0;
  if (brk >= span) {
    return { error: `Mola süresi (${brk} dk) vardiya süresinden (${span} dk) kısa olmalıdır` };
  }
  return { values: out };
}

router.post('/shifts', requireManager, async (req, res) => {
  const body = req.body || {};
  const parsed = readShift(body, null);
  if (parsed.error) return res.status(400).json({ error: parsed.error });

  // store_id verilmezse kullanicinin magazasi; NULL istenirse tum magazalar
  // icin sablon olur, bunu yalnizca ana yonetici yapabilir.
  let storeId = body.store_id === undefined ? req.user.store_id : body.store_id;
  if (storeId === null) {
    if (req.user.role !== 'super_admin') {
      return res.status(403).json({ error: 'Tüm mağazalar için vardiya yalnızca Ana Yönetici tanımlar' });
    }
  } else {
    storeId = Number(storeId);
    if (!Number.isInteger(storeId)) return res.status(400).json({ error: 'Mağaza geçersiz' });
    if (!allowsStore(req, storeId)) return res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
  }

  const v = parsed.values;
  const r = await execute(`
    INSERT INTO shifts (store_id, name, start_time, end_time, break_duration_minutes,
      late_tolerance_minutes, early_leave_tolerance_minutes,
      overtime_starts_after_minutes, created_by)
    VALUES (?,?,?,?,?,?,?,?,?) RETURNING id`,
    storeId, v.name, v.start_time, v.end_time,
    v.break_duration_minutes ?? 0, v.late_tolerance_minutes ?? 0,
    v.early_leave_tolerance_minutes ?? 0, v.overtime_starts_after_minutes ?? 15,
    req.user.id);

  await logActivity(req.user, 'VARDIYA_OLUSTUR', 'shift', r.lastInsertRowid,
    `${v.name} (${v.start_time}-${v.end_time})`, storeId);
  res.status(201).json({ id: Number(r.lastInsertRowid) });
});

router.put('/shifts/:id', requireManager, async (req, res) => {
  const row = await queryOne('SELECT * FROM shifts WHERE id = ?', Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Vardiya bulunamadı' });
  if (row.store_id === null && req.user.role !== 'super_admin') {
    return res.status(403).json({ error: 'Tüm mağazalar vardiyasını yalnızca Ana Yönetici düzenler' });
  }
  if (row.store_id !== null && !allowsStore(req, row.store_id)) {
    return res.status(403).json({ error: 'Bu vardiyaya erişim yetkiniz yok' });
  }
  const parsed = readShift(req.body || {}, row);
  if (parsed.error) return res.status(400).json({ error: parsed.error });
  const v = parsed.values;
  const active = req.body.active === undefined ? row.active : (req.body.active ? 1 : 0);

  await execute(`
    UPDATE shifts SET name=?, start_time=?, end_time=?, break_duration_minutes=?,
      late_tolerance_minutes=?, early_leave_tolerance_minutes=?,
      overtime_starts_after_minutes=?, active=? WHERE id=?`,
    v.name, v.start_time, v.end_time, v.break_duration_minutes,
    v.late_tolerance_minutes, v.early_leave_tolerance_minutes,
    v.overtime_starts_after_minutes, active, row.id);

  await logActivity(req.user, 'VARDIYA_GUNCELLE', 'shift', row.id,
    `${v.name} (${v.start_time}-${v.end_time})`, row.store_id);
  res.json({ ok: true });
});

/// Vardiya silme. Atanmis vardiya silinemez: gecmis puantaj o tanima dayanir.
router.delete('/shifts/:id', requireManager, async (req, res) => {
  const row = await queryOne('SELECT * FROM shifts WHERE id = ?', Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Vardiya bulunamadı' });
  if (row.store_id !== null && !allowsStore(req, row.store_id)) {
    return res.status(403).json({ error: 'Bu vardiyaya erişim yetkiniz yok' });
  }
  const used = await queryOne('SELECT COUNT(*) AS c FROM user_shifts WHERE shift_id = ?', row.id);
  if (Number(used.c) > 0) {
    return res.status(400).json({
      error: `Bu vardiya ${used.c} güne atanmış. Silmek yerine pasife alın; `
        + 'geçmiş puantaj bu tanıma dayanıyor.',
    });
  }
  await execute('DELETE FROM shifts WHERE id = ?', row.id);
  await logActivity(req.user, 'VARDIYA_SIL', 'shift', row.id, row.name, row.store_id);
  res.json({ ok: true });
});

// ---- Vardiya atamalari ----

/// Atama listesi. Personel yalnizca kendi atamalarini gorur.
router.get('/assignments', async (req, res) => {
  const from = req.query.from;
  const to = req.query.to;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(from || '') || !/^\d{4}-\d{2}-\d{2}$/.test(to || '')) {
    return res.status(400).json({ error: 'from ve to YYYY-AA-GG biçiminde olmalıdır' });
  }
  const isManager = MANAGER_ROLES.includes(req.user.role);
  const params = [from, to];
  let where = 'us.work_date >= ? AND us.work_date <= ?';

  if (!isManager) {
    where += ' AND us.user_id = ?';
    params.push(req.user.id);
  } else {
    const scope = resolveStoreScope(req, res);
    if (!scope.ok) return undefined;
    const f = storeFilter(scope, 'u.store_id');
    where += f.sql;
    params.push(...f.params);
    if (req.query.userId) { where += ' AND us.user_id = ?'; params.push(Number(req.query.userId)); }
  }

  const rows = await queryAll(`
    SELECT us.id, us.user_id, us.shift_id, us.work_date, us.is_day_off, us.note,
           u.full_name, u.store_id, s.name AS shift_name, s.start_time, s.end_time,
           s.break_duration_minutes, s.late_tolerance_minutes
    FROM user_shifts us
    JOIN users u ON u.id = us.user_id
    LEFT JOIN shifts s ON s.id = us.shift_id
    WHERE ${where}
    ORDER BY us.work_date, u.full_name, s.start_time
  `, ...params);
  res.json(rows.map((r) => ({ ...r, is_day_off: !!r.is_day_off })));
});

/// Toplu atama.
///
/// Bir vardiyayi bir tarih araliginda birden fazla personele atar. Hafta
/// tatili gunleri atlanir (personelin profilindeki gunler), onayli izin gunu
/// varsa o gun atlanir ve cevapta bildirilir — sessizce ustune yazmak izni
/// gorunmez kilardi.
router.post('/assignments', requireManager, async (req, res) => {
  const body = req.body || {};
  const userIds = Array.isArray(body.user_ids) ? body.user_ids.map(Number) : [];
  const from = String(body.from || '');
  const to = String(body.to || '');
  const isDayOff = body.is_day_off === true;
  const shiftId = isDayOff ? null : Number(body.shift_id);

  if (userIds.length === 0 || userIds.some((id) => !Number.isInteger(id))) {
    return res.status(400).json({ error: 'En az bir personel seçilmelidir' });
  }
  if (userIds.length > 200) return res.status(400).json({ error: 'Tek seferde en fazla 200 personel' });
  if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to) || to < from) {
    return res.status(400).json({ error: 'Geçerli bir tarih aralığı verin' });
  }
  // 400 gunluk ust sinir: kisitta da var, once burada anlasilir mesaj verilir.
  const spanDays = bal.countLeaveDays(from, to, []) ?? 0;
  if (spanDays > 366) return res.status(400).json({ error: 'Aralık en fazla 1 yıl olabilir' });

  let shift = null;
  if (!isDayOff) {
    if (!Number.isInteger(shiftId)) return res.status(400).json({ error: 'Vardiya seçilmelidir' });
    shift = await queryOne('SELECT * FROM shifts WHERE id = ? AND active = 1', shiftId);
    if (!shift) return res.status(404).json({ error: 'Vardiya bulunamadı veya pasif' });
    if (shift.store_id !== null && !allowsStore(req, shift.store_id)) {
      return res.status(403).json({ error: 'Bu vardiyaya erişim yetkiniz yok' });
    }
  }

  const users = await queryAll(
    `SELECT u.id, u.full_name, u.store_id, u.active, p.weekly_off_days
     FROM users u LEFT JOIN pdks_profiles p ON p.user_id = u.id
     WHERE u.id IN (${userIds.map(() => '?').join(',')})`, ...userIds);

  const result = { assigned: 0, skipped: [], users: [] };
  for (const u of users) {
    if (!u.active) { result.skipped.push({ user_id: u.id, reason: 'pasif personel' }); continue; }
    if (!allowsStore(req, u.store_id)) {
      result.skipped.push({ user_id: u.id, reason: 'mağaza yetkisi yok' });
      continue;
    }
    if (shift && shift.store_id !== null && Number(shift.store_id) !== Number(u.store_id)) {
      result.skipped.push({ user_id: u.id, full_name: u.full_name, reason: 'vardiya başka mağazaya ait' });
      continue;
    }

    const off = new Set(bal.parseWeeklyOff(u.weekly_off_days));
    // Onayli izinler: o gunlere vardiya yazilmaz.
    const leaves = await queryAll(
      `SELECT start_at, end_at FROM personnel_requests
       WHERE user_id = ? AND type = 'IZIN' AND status = 'APPROVED'
         AND start_at <= ? AND end_at >= ?`, u.id, to, from);

    let count = 0;
    const skippedDates = [];
    await transaction(async (client) => {
      let cursor = from;
      for (let guard = 0; guard < 400 && cursor <= to; guard++) {
        const [y, m, d] = cursor.split('-').map(Number);
        const dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
        const onLeave = leaves.some((l) => cursor >= l.start_at && cursor <= l.end_at);

        if (isDayOff || (!off.has(dow) && !onLeave)) {
          // Ayni gune ayni vardiya varsa tekrar yazilmaz.
          await execute(`
            INSERT INTO user_shifts (user_id, shift_id, work_date, is_day_off, note, assigned_by)
            VALUES (?,?,?,?,?,?)
            ON CONFLICT (user_id, work_date, shift_id) DO NOTHING`,
            [u.id, shiftId, cursor, isDayOff ? 1 : 0, body.note || null, req.user.id], client);
          count++;
        } else if (onLeave) {
          skippedDates.push({ date: cursor, reason: 'onaylı izin' });
        }
        cursor = t.shiftDate(cursor, 1);
      }
    });

    result.assigned += count;
    result.users.push({
      user_id: u.id, full_name: u.full_name, days: count,
      skipped_dates: skippedDates,
    });
  }

  await logActivity(req.user, 'VARDIYA_ATA', 'shift', shiftId,
    `${from} - ${to} arasi ${result.users.length} personele ${result.assigned} gün`
    + (isDayOff ? ' (hafta tatili)' : ''), req.user.store_id);
  res.status(201).json(result);
});

router.delete('/assignments/:id', requireManager, async (req, res) => {
  const row = await queryOne(`
    SELECT us.*, u.store_id, u.full_name FROM user_shifts us
    JOIN users u ON u.id = us.user_id WHERE us.id = ?`, Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Atama bulunamadı' });
  if (!allowsStore(req, row.store_id)) {
    return res.status(403).json({ error: 'Bu atamaya erişim yetkiniz yok' });
  }
  // Devam kaydi girilmis gunun atamasi silinemez: puantaj dayanagi kaybolur.
  const logs = await queryOne(
    'SELECT COUNT(*) AS c FROM attendance_logs WHERE user_id = ? AND work_date = ?',
    row.user_id, row.work_date);
  if (Number(logs.c) > 0) {
    return res.status(400).json({
      error: `${row.work_date} gününde ${logs.c} devam kaydı var. `
        + 'Atama silinemez; vardiyayı değiştirmek için yeniden atama yapın.',
    });
  }
  await execute('DELETE FROM user_shifts WHERE id = ?', row.id);
  await logActivity(req.user, 'VARDIYA_ATAMA_SIL', 'shift', row.shift_id,
    `${row.full_name} ${row.work_date}`, row.store_id);
  res.json({ ok: true });
});

// ---- Personel PDKS profili ----

router.get('/profiles', requireManager, async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;
  const f = storeFilter(scope, 'u.store_id');
  const rows = await queryAll(`
    SELECT u.id AS user_id, u.full_name, u.role, u.store_id, s.name AS store_name,
           p.hired_at, p.annual_leave_days, p.monthly_advance_limit, p.weekly_off_days
    FROM users u
    LEFT JOIN pdks_profiles p ON p.user_id = u.id
    LEFT JOIN stores s ON s.id = u.store_id
    WHERE u.active = 1 ${f.sql}
    ORDER BY u.full_name`, ...f.params);
  res.json(rows.map((r) => ({
    ...r,
    // Profil hic olusturulmamissa varsayilanlar gosterilir.
    hired_at: r.hired_at ?? null,
    annual_leave_days: r.annual_leave_days === null ? 14 : Number(r.annual_leave_days),
    monthly_advance_limit: r.monthly_advance_limit === null ? 0 : Number(r.monthly_advance_limit),
    weekly_off_days: bal.parseWeeklyOff(r.weekly_off_days),
    has_profile: r.annual_leave_days !== null,
  })));
});

router.put('/profiles/:userId', requireManager, async (req, res) => {
  const user = await queryOne('SELECT id, full_name, store_id FROM users WHERE id = ?', Number(req.params.userId));
  if (!user) return res.status(404).json({ error: 'Personel bulunamadı' });
  if (!allowsStore(req, user.store_id)) {
    return res.status(403).json({ error: 'Bu personele erişim yetkiniz yok' });
  }
  const body = req.body || {};

  const hiredAt = body.hired_at === undefined ? undefined
    : body.hired_at === null || body.hired_at === '' ? null : String(body.hired_at);
  if (hiredAt && !/^\d{4}-\d{2}-\d{2}$/.test(hiredAt)) {
    return res.status(400).json({ error: 'İşe giriş tarihi YYYY-AA-GG biçiminde olmalıdır' });
  }
  const days = body.annual_leave_days === undefined ? undefined : Number(body.annual_leave_days);
  if (days !== undefined && (!Number.isFinite(days) || days < 0 || days > 365)) {
    return res.status(400).json({ error: 'Yıllık izin 0-365 gün arasında olmalıdır' });
  }
  const limit = body.monthly_advance_limit === undefined ? undefined : Number(body.monthly_advance_limit);
  if (limit !== undefined && (!Number.isFinite(limit) || limit < 0)) {
    return res.status(400).json({ error: 'Avans limiti 0 veya daha büyük olmalıdır' });
  }
  let offDays;
  if (body.weekly_off_days !== undefined) {
    const arr = Array.isArray(body.weekly_off_days) ? body.weekly_off_days.map(Number) : null;
    if (!arr || arr.some((d) => !Number.isInteger(d) || d < 0 || d > 6)) {
      return res.status(400).json({ error: 'Hafta tatili günleri 0-6 arasında olmalıdır' });
    }
    if (arr.length > 6) return res.status(400).json({ error: 'En az bir çalışma günü kalmalıdır' });
    offDays = JSON.stringify([...new Set(arr)]);
  }

  const existing = await queryOne('SELECT * FROM pdks_profiles WHERE user_id = ?', user.id);
  const next = {
    hired_at: hiredAt === undefined ? existing?.hired_at ?? null : hiredAt,
    annual_leave_days: days === undefined ? existing?.annual_leave_days ?? 14 : days,
    monthly_advance_limit: limit === undefined ? existing?.monthly_advance_limit ?? 0 : limit,
    weekly_off_days: offDays === undefined ? existing?.weekly_off_days ?? '[0]' : offDays,
  };

  await execute(`
    INSERT INTO pdks_profiles (user_id, hired_at, annual_leave_days,
      monthly_advance_limit, weekly_off_days, updated_by)
    VALUES (?,?,?,?,?,?)
    ON CONFLICT (user_id) DO UPDATE SET
      hired_at = EXCLUDED.hired_at,
      annual_leave_days = EXCLUDED.annual_leave_days,
      monthly_advance_limit = EXCLUDED.monthly_advance_limit,
      weekly_off_days = EXCLUDED.weekly_off_days,
      updated_by = EXCLUDED.updated_by,
      updated_at = to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')`,
    user.id, next.hired_at, next.annual_leave_days,
    next.monthly_advance_limit, next.weekly_off_days, req.user.id);

  await logActivity(req.user, 'PDKS_PROFIL', 'user', user.id,
    `${user.full_name}: ${next.annual_leave_days} gün izin, `
    + `${next.monthly_advance_limit} TL avans limiti`, user.store_id);
  res.json({ ok: true, ...next, weekly_off_days: bal.parseWeeklyOff(next.weekly_off_days) });
});

// ---- Magaza PDKS ayarlari ----

router.get('/settings', requireManager, async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;
  const f = storeFilter(scope, 'id');
  const rows = await queryAll(`
    SELECT id, name, latitude, longitude, geofence_radius_m, qr_mode, pdks_enabled,
           (qr_secret IS NOT NULL) AS has_secret
    FROM stores WHERE active = 1 ${f.sql} ORDER BY name`, ...f.params);
  // Sir ASLA doner degil; yalnizca tanimli olup olmadigi bildirilir.
  res.json(rows.map((r) => ({
    ...r, pdks_enabled: !!r.pdks_enabled, has_secret: !!r.has_secret,
  })));
});

router.put('/settings/:storeId', requireManager, async (req, res) => {
  const storeId = Number(req.params.storeId);
  const store = await queryOne('SELECT * FROM stores WHERE id = ?', storeId);
  if (!store) return res.status(404).json({ error: 'Mağaza bulunamadı' });
  if (!allowsStore(req, storeId)) {
    return res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
  }
  const body = req.body || {};

  let lat = store.latitude;
  let lon = store.longitude;
  if (body.latitude !== undefined || body.longitude !== undefined) {
    lat = body.latitude === null ? null : Number(body.latitude);
    lon = body.longitude === null ? null : Number(body.longitude);
    const bothNull = lat === null && lon === null;
    if (!bothNull) {
      const geo = require('../pdks/geo');
      if (!geo.isValidCoordinate(lat, lon)) {
        return res.status(400).json({ error: 'Geçerli bir konum girin' });
      }
    }
  }
  let radius = store.geofence_radius_m;
  if (body.geofence_radius_m !== undefined) {
    radius = Number(body.geofence_radius_m);
    if (!Number.isInteger(radius) || radius < 20 || radius > 5000) {
      return res.status(400).json({ error: 'Yarıçap 20-5000 metre arasında olmalıdır' });
    }
  }
  let mode = store.qr_mode;
  if (body.qr_mode !== undefined) {
    mode = String(body.qr_mode);
    if (!['rotating', 'static'].includes(mode)) {
      return res.status(400).json({ error: 'QR kipi rotating veya static olmalıdır' });
    }
  }
  let enabled = store.pdks_enabled;
  if (body.pdks_enabled !== undefined) enabled = body.pdks_enabled ? 1 : 0;

  // PDKS acilirken sir ve konum hazir olmali: aksi halde personel giris
  // yapmaya calisip anlamsiz hata aliyor.
  let secret = store.qr_secret;
  if (enabled && !secret) secret = qr.generateSecret();
  if (enabled && (lat === null || lon === null)) {
    return res.status(400).json({
      error: 'PDKS açılmadan önce mağaza konumu tanımlanmalıdır '
        + '(GPS doğrulaması buna dayanıyor)',
    });
  }
  // Sabit kod konum dogrulamasi gerektiriyor; konumsuz sabit kip calismaz.
  if (enabled && mode === 'static' && (lat === null || lon === null)) {
    return res.status(400).json({ error: 'Sabit QR kod için mağaza konumu zorunludur' });
  }

  await execute(`
    UPDATE stores SET latitude=?, longitude=?, geofence_radius_m=?, qr_mode=?,
      pdks_enabled=?, qr_secret=? WHERE id=?`,
    lat, lon, radius, mode, enabled, secret, storeId);

  await logActivity(req.user, 'PDKS_AYAR', 'store', storeId,
    `PDKS ${enabled ? 'açık' : 'kapalı'}, ${radius} m yarıçap, ${mode} QR`, storeId);
  res.json({
    ok: true, latitude: lat, longitude: lon, geofence_radius_m: radius,
    qr_mode: mode, pdks_enabled: !!enabled, has_secret: !!secret,
  });
});

/// Sirri yeniler: basili kodlar ve acik kiosk ekranlari gecersiz olur.
router.post('/settings/:storeId/rotate-secret', requireRole('super_admin'), async (req, res) => {
  const storeId = Number(req.params.storeId);
  const store = await queryOne('SELECT id, name FROM stores WHERE id = ?', storeId);
  if (!store) return res.status(404).json({ error: 'Mağaza bulunamadı' });
  await execute('UPDATE stores SET qr_secret = ? WHERE id = ?', qr.generateSecret(), storeId);
  await logActivity(req.user, 'PDKS_SIR_YENILE', 'store', storeId,
    'QR sırrı yenilendi, eski kodlar geçersiz', storeId);
  res.json({ ok: true, warning: 'Basılı QR kodların yeniden basılması gerekiyor' });
});

module.exports = router;
