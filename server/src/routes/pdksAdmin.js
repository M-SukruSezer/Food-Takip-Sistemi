const express = require('express');
const { queryAll, queryOne, execute, transaction } = require('../db');
const {
  requireAuth, requireRole, resolveStoreScope, storeFilter, allowsStore, MANAGER_ROLES,
} = require('../auth');
const { logActivity } = require('../utils');
const qr = require('../pdks/qr');
const t = require('../pdks/time');
const bal = require('../pdks/balance');
const pay = require('../pdks/payroll');
const cls = require('../pdks/shiftClass');
const kvkk = require('../pdks/kvkk');

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
    // Resmi tatiller de atlanir. Tatilde acik olan magaza icin yonetici o
    // gunu tek tek atayabilir; toplu atamada varsayilan olarak atlanmasi
    // yanlis planlamayi engelliyor.
    const holidayRows = await queryAll(`
      SELECT holiday_date, name, is_half_day, store_id FROM public_holidays
      WHERE holiday_date >= ? AND holiday_date <= ?
        AND (store_id IS NULL OR store_id = ?)`, from, to, u.store_id);
    const holidays = bal.holidayMap(holidayRows);

    let count = 0;
    const skippedDates = [];
    await transaction(async (client) => {
      let cursor = from;
      for (let guard = 0; guard < 400 && cursor <= to; guard++) {
        const [y, m, d] = cursor.split('-').map(Number);
        const dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
        const onLeave = leaves.some((l) => cursor >= l.start_at && cursor <= l.end_at);
        // Yarim tatilde calisilir; yalnizca tam tatil atlanir.
        const onHoliday = holidays[cursor] != null && holidays[cursor].half !== true;

        if (isDayOff || (!off.has(dow) && !onLeave && !onHoliday)) {
          // Ayni gune ayni vardiya varsa tekrar yazilmaz.
          await execute(`
            INSERT INTO user_shifts (user_id, shift_id, work_date, is_day_off, note, assigned_by)
            VALUES (?,?,?,?,?,?)
            ON CONFLICT (user_id, work_date, shift_id) DO NOTHING`,
            [u.id, shiftId, cursor, isDayOff ? 1 : 0, body.note || null, req.user.id], client);
          count++;
        } else {
          // Atlanan gunun SEBEBI bildirilir. Hafta tatili dali eksikti: gun
          // atlaniyordu ama skipped_dates bos donuyor, yonetici "7 gun
          // istedim, 6 gun yazildi" farkinin sebebini goremiyordu.
          //
          // Birden fazla sebep ust uste gelebilir (Pazar'a denk gelen resmi
          // tatil gibi); hepsi yazilir ki gun tek sebeple aciklanmis
          // gorunmesin.
          const sebepler = [];
          if (off.has(dow)) sebepler.push('hafta tatili');
          if (onLeave) sebepler.push('onaylı izin');
          if (onHoliday) sebepler.push(`resmi tatil (${holidays[cursor].name})`);
          skippedDates.push({ date: cursor, reason: sebepler.join(' + ') });
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

/// Tek hucre ataması: bir personelin BIR gunu.
///
/// Neden ayri uc: cizelgede hucreye tiklayarak plan yapmak "o gunu SU HALE
/// getir" islemi, "ekle" degil. Toplu uc eklemeli calisiyor ve mevcut atamayi
/// birakiyordu; istemcinin once silip sonra eklemesi ise yarim kalabilen iki
/// adim uretiyordu (silindi ama eklenemedi -> gun bosalir).
///
/// Govde: { user_id, work_date, shift_id | null, is_day_off }
///   shift_id verilirse o vardiya atanir
///   is_day_off true ise hafta tatili yazilir
///   ikisi de yoksa gun BOSALTILIR
router.put('/assignments/cell', requireManager, async (req, res) => {
  const body = req.body || {};
  const userId = Number(body.user_id);
  const workDate = String(body.work_date || '');
  const isDayOff = body.is_day_off === true;
  const shiftId = body.shift_id === null || body.shift_id === undefined
    ? null : Number(body.shift_id);

  if (!Number.isInteger(userId)) return res.status(400).json({ error: 'Personel seçilmelidir' });
  if (!/^\d{4}-\d{2}-\d{2}$/.test(workDate)) {
    return res.status(400).json({ error: 'Tarih YYYY-AA-GG biçiminde olmalıdır' });
  }
  if (isDayOff && shiftId !== null) {
    return res.status(400).json({ error: 'Hafta tatili ile vardiya birlikte verilemez' });
  }

  const user = await queryOne(
    'SELECT id, full_name, store_id, active FROM users WHERE id = ?', userId);
  if (!user || !user.active) return res.status(404).json({ error: 'Personel bulunamadı' });
  if (!allowsStore(req, user.store_id)) {
    return res.status(403).json({ error: 'Bu personele erişim yetkiniz yok' });
  }

  let shift = null;
  if (shiftId !== null) {
    shift = await queryOne('SELECT * FROM shifts WHERE id = ? AND active = 1', shiftId);
    if (!shift) return res.status(404).json({ error: 'Vardiya bulunamadı veya pasif' });
    if (shift.store_id !== null && Number(shift.store_id) !== Number(user.store_id)) {
      return res.status(400).json({ error: 'Vardiya bu personelin mağazasına ait değil' });
    }
    if (shift.store_id !== null && !allowsStore(req, shift.store_id)) {
      return res.status(403).json({ error: 'Bu vardiyaya erişim yetkiniz yok' });
    }
  }

  // Devam kaydi girilmis gun degistirilemez: puantaj dayanagi kaybolur.
  // Silme ucuyla ayni kural.
  const logs = await queryOne(
    'SELECT COUNT(*) AS c FROM attendance_logs WHERE user_id = ? AND work_date = ?',
    userId, workDate);
  if (Number(logs.c) > 0) {
    return res.status(400).json({
      error: `${workDate} gününde ${logs.c} devam kaydı var; o günün planı değiştirilemez.`,
    });
  }

  // Tek islem: gunu temizle, sonra istenen hali yaz. Yarim kalmasin diye
  // islem (transaction) icinde.
  await transaction(async (client) => {
    await execute('DELETE FROM user_shifts WHERE user_id = ? AND work_date = ?',
      [userId, workDate], client);
    if (isDayOff) {
      await execute(`INSERT INTO user_shifts (user_id, shift_id, work_date, is_day_off, assigned_by)
        VALUES (?,?,?,1,?)`, [userId, null, workDate, req.user.id], client);
    } else if (shiftId !== null) {
      await execute(`INSERT INTO user_shifts (user_id, shift_id, work_date, is_day_off, assigned_by)
        VALUES (?,?,?,0,?)`, [userId, shiftId, workDate, req.user.id], client);
    }
  });

  const ne = isDayOff ? 'hafta tatili' : shift ? `${shift.name} (${shift.start_time}-${shift.end_time})` : 'boşaltıldı';
  await logActivity(req.user, 'VARDIYA_HUCRE', 'shift', shiftId,
    `${user.full_name} ${workDate}: ${ne}`, user.store_id);

  res.json({
    ok: true,
    user_id: userId,
    work_date: workDate,
    is_day_off: isDayOff,
    shift: shift && {
      id: shift.id, name: shift.name,
      start_time: shift.start_time, end_time: shift.end_time,
      break_duration_minutes: shift.break_duration_minutes,
      category: cls.kategori(shift.start_time, shift.end_time),
      minutes: cls.netDakika(shift),
      warnings: cls.uyarilar(shift),
    },
  });
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
           p.hired_at, p.annual_leave_days, p.monthly_advance_limit, p.weekly_off_days,
           p.monthly_salary, p.hourly_rate, p.meal_daily
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
    // Ucret alanlari NULL kalabiliyor: "tanimli degil" ile "sifir" ayri.
    // Sifir yazmak "ucretsiz calisiyor" anlamina gelirdi.
    monthly_salary: r.monthly_salary === null ? null : Number(r.monthly_salary),
    hourly_rate: r.hourly_rate === null ? null : Number(r.hourly_rate),
    meal_daily: r.meal_daily === null ? null : Number(r.meal_daily),
    effective_hourly_rate: pay.hourlyRateOf(r).rate,
    wage_basis: pay.hourlyRateOf(r).basis,
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
  // Ucret alanlari. Bos metin ve null "tanimi kaldir" demek; sifir gecerli
  // bir deger ("tanimli ama odenmiyor") oldugu icin ikisi ayri tutuluyor.
  const para = (anahtar, etiket) => {
    if (body[anahtar] === undefined) return { yok: true };
    if (body[anahtar] === null || body[anahtar] === '') return { deger: null };
    const n = Number(body[anahtar]);
    if (!Number.isFinite(n) || n < 0) return { hata: `${etiket} 0 veya daha büyük olmalıdır` };
    // Ust sinir: kurus hatasi ya da yanlis birimle girilen deger (orn. kurus
    // cinsinden 4500000) sessizce kaydedilmesin.
    if (n > 10000000) return { hata: `${etiket} çok büyük görünüyor, kontrol edin` };
    return { deger: n };
  };
  const maas = para('monthly_salary', 'Aylık maaş');
  const saatlik = para('hourly_rate', 'Saat ücreti');
  const yemek = para('meal_daily', 'Günlük yemek ücreti');
  for (const v of [maas, saatlik, yemek]) {
    if (v.hata) return res.status(400).json({ error: v.hata });
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
    monthly_salary: maas.yok ? existing?.monthly_salary ?? null : maas.deger,
    hourly_rate: saatlik.yok ? existing?.hourly_rate ?? null : saatlik.deger,
    meal_daily: yemek.yok ? existing?.meal_daily ?? null : yemek.deger,
  };

  await execute(`
    INSERT INTO pdks_profiles (user_id, hired_at, annual_leave_days,
      monthly_advance_limit, weekly_off_days, monthly_salary, hourly_rate,
      meal_daily, updated_by)
    VALUES (?,?,?,?,?,?,?,?,?)
    ON CONFLICT (user_id) DO UPDATE SET
      hired_at = EXCLUDED.hired_at,
      annual_leave_days = EXCLUDED.annual_leave_days,
      monthly_advance_limit = EXCLUDED.monthly_advance_limit,
      weekly_off_days = EXCLUDED.weekly_off_days,
      monthly_salary = EXCLUDED.monthly_salary,
      hourly_rate = EXCLUDED.hourly_rate,
      meal_daily = EXCLUDED.meal_daily,
      updated_by = EXCLUDED.updated_by,
      updated_at = to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')`,
    user.id, next.hired_at, next.annual_leave_days,
    next.monthly_advance_limit, next.weekly_off_days,
    next.monthly_salary, next.hourly_rate, next.meal_daily, req.user.id);

  // Denetim izinde ucret TUTARI yazilmiyor: Hareket Kayitlari ekrani daha
  // geniş bir kitleye acik ve maas bilgisi oraya dusmemeli. Yalnizca hangi
  // alanin degistirildigi kaydediliyor.
  const degisen = [];
  if (!maas.yok) degisen.push('aylık maaş');
  if (!saatlik.yok) degisen.push('saat ücreti');
  if (!yemek.yok) degisen.push('yemek ücreti');
  await logActivity(req.user, 'PDKS_PROFIL', 'user', user.id,
    `${user.full_name}: ${next.annual_leave_days} gün izin, `
    + `${next.monthly_advance_limit} TL avans limiti`
    + (degisen.length ? ` — ${degisen.join(', ')} güncellendi` : ''), user.store_id);
  res.json({
    ok: true, ...next,
    weekly_off_days: bal.parseWeeklyOff(next.weekly_off_days),
    effective_hourly_rate: pay.hourlyRateOf(next).rate,
    wage_basis: pay.hourlyRateOf(next).basis,
  });
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

// ---- Resmi tatiller ----

/// Tatil listesi. Personel de gorur: izin talebi verirken hangi gunun tatil
/// oldugunu bilmesi gerekiyor.
router.get('/holidays', async (req, res) => {
  const from = req.query.from;
  const to = req.query.to;
  const params = [];
  let where = '1 = 1';
  if (/^\d{4}-\d{2}-\d{2}$/.test(from || '')) { where += ' AND h.holiday_date >= ?'; params.push(from); }
  if (/^\d{4}-\d{2}-\d{2}$/.test(to || '')) { where += ' AND h.holiday_date <= ?'; params.push(to); }

  // Kullanicinin magazasina ait olan + tum magazalar icin gecerli olanlar.
  const storeId = req.user.store_id;
  if (storeId) {
    where += ' AND (h.store_id IS NULL OR h.store_id = ?)';
    params.push(storeId);
  }

  const rows = await queryAll(`
    SELECT h.*, s.name AS store_name
    FROM public_holidays h LEFT JOIN stores s ON s.id = h.store_id
    WHERE ${where}
    ORDER BY h.holiday_date`, ...params);
  res.json(rows.map((r) => ({ ...r, is_half_day: r.is_half_day === 1 })));
});

router.post('/holidays', requireManager, async (req, res) => {
  const body = req.body || {};
  const date = String(body.holiday_date || '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return res.status(400).json({ error: 'Tarih YYYY-AA-GG biçiminde olmalıdır' });
  }
  const name = String(body.name || '').trim();
  if (!name) return res.status(400).json({ error: 'Tatil adı zorunludur' });
  const half = body.is_half_day ? 1 : 0;

  // store_id verilmezse kullanicinin magazasi. Tum magazalar icin tatil
  // yalnizca ana yoneticide: ulke capinda gecerli bir kayit.
  let storeId = body.store_id === undefined ? req.user.store_id : body.store_id;
  if (storeId === null) {
    if (req.user.role !== 'super_admin') {
      return res.status(403).json({ error: 'Tüm mağazalar için tatil yalnızca Ana Yönetici tanımlar' });
    }
  } else {
    storeId = Number(storeId);
    if (!Number.isInteger(storeId)) return res.status(400).json({ error: 'Mağaza geçersiz' });
    if (!allowsStore(req, storeId)) return res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
  }

  try {
    const r = await execute(`
      INSERT INTO public_holidays (holiday_date, name, is_half_day, store_id, created_by)
      VALUES (?,?,?,?,?) RETURNING id`, date, name, half, storeId, req.user.id);
    await logActivity(req.user, 'TATIL_EKLE', 'holiday', r.lastInsertRowid,
      `${date} ${name}${half ? ' (yarım gün)' : ''}`, storeId);
    res.status(201).json({ id: Number(r.lastInsertRowid) });
  } catch (e) {
    if (String(e.message).includes('idx_holidays')) {
      return res.status(400).json({ error: 'Bu tarih için zaten bir tatil kayıtlı' });
    }
    throw e;
  }
});

router.delete('/holidays/:id', requireManager, async (req, res) => {
  const row = await queryOne('SELECT * FROM public_holidays WHERE id = ?', Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Tatil bulunamadı' });
  if (row.store_id === null && req.user.role !== 'super_admin') {
    return res.status(403).json({ error: 'Tüm mağazalar tatilini yalnızca Ana Yönetici siler' });
  }
  if (row.store_id !== null && !allowsStore(req, row.store_id)) {
    return res.status(403).json({ error: 'Bu tatile erişim yetkiniz yok' });
  }
  await execute('DELETE FROM public_holidays WHERE id = ?', row.id);
  await logActivity(req.user, 'TATIL_SIL', 'holiday', row.id,
    `${row.holiday_date} ${row.name}`, row.store_id);
  res.json({ ok: true });
});

// Sabit tarihli milli bayramlar. DINI BAYRAMLAR BURADA YOK: tarihleri her yil
// kaydigi icin uydurmak yanlis izin hesabi uretir, elle girilmeleri gerekiyor.
const FIXED_HOLIDAYS = [
  { md: '01-01', name: 'Yılbaşı' },
  { md: '04-23', name: 'Ulusal Egemenlik ve Çocuk Bayramı' },
  { md: '05-01', name: 'Emek ve Dayanışma Günü' },
  { md: '05-19', name: 'Atatürk’ü Anma, Gençlik ve Spor Bayramı' },
  { md: '07-15', name: 'Demokrasi ve Millî Birlik Günü' },
  { md: '08-30', name: 'Zafer Bayramı' },
  { md: '10-29', name: 'Cumhuriyet Bayramı' },
];

/// Bir yilin sabit milli bayramlarini ekler. Var olan kayitlara dokunmaz.
router.post('/holidays/seed', requireRole('super_admin'), async (req, res) => {
  const year = Number(req.query.year || req.body?.year);
  if (!Number.isInteger(year) || year < 2000 || year > 2100) {
    return res.status(400).json({ error: 'Geçerli bir yıl verin' });
  }
  let added = 0;
  for (const h of FIXED_HOLIDAYS) {
    const r = await execute(`
      INSERT INTO public_holidays (holiday_date, name, is_half_day, store_id, created_by)
      VALUES (?,?,0,NULL,?)
      ON CONFLICT DO NOTHING`, `${year}-${h.md}`, h.name, req.user.id);
    if (r.changes > 0) added++;
  }
  await logActivity(req.user, 'TATIL_TOHUM', 'holiday', null,
    `${year} yılı sabit milli bayramları: ${added} kayıt eklendi`, null);
  res.status(201).json({
    year,
    added,
    total: FIXED_HOLIDAYS.length,
    warning: 'Dini bayramlar (Ramazan ve Kurban) her yıl kaydığı için '
      + 'eklenmedi; elle girilmeleri gerekiyor.',
  });
});

// ---- KVKK: ham koordinat saklama suresi ----

router.get('/kvkk/status', requireRole('super_admin'), async (req, res) => {
  res.json(await kvkk.retentionStatus());
});

/// Suresi gecmis koordinatlari bosaltir. Devam kaydi SILINMEZ.
router.post('/kvkk/purge', requireRole('super_admin'), async (req, res) => {
  const days = req.body && req.body.days !== undefined ? Number(req.body.days) : undefined;
  if (days !== undefined && (!Number.isInteger(days) || days < 1 || days > 3650)) {
    return res.status(400).json({ error: 'Saklama süresi 1-3650 gün arasında olmalıdır' });
  }
  const out = await kvkk.purgeCoordinates({ days });
  await logActivity(req.user, 'KVKK_TEMIZLIK', 'attendance_log', null,
    `${out.purged} kaydın ham koordinatı silindi (${out.retention_days} gün)`, null);
  res.json(out);
});

module.exports = router;
