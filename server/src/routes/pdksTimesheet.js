const express = require('express');
const { queryAll, queryOne } = require('../db');
const {
  requireAuth, resolveStoreScope, storeFilter, allowsStore, MANAGER_ROLES,
} = require('../auth');
const bal = require('../pdks/balance');
const sheet = require('../pdks/timesheet');
const t = require('../pdks/time');

const router = express.Router();

router.use(requireAuth);

const isDate = (v) => /^\d{4}-\d{2}-\d{2}$/.test(String(v || ''));

/// Tarih araligindaki tum gunler.
function dateRange(from, to) {
  const out = [];
  let cursor = from;
  for (let guard = 0; guard < 400 && cursor <= to; guard++) {
    out.push(cursor);
    cursor = t.shiftDate(cursor, 1);
  }
  return out;
}

/// Bir veya daha fazla personelin puantaji.
///
/// Sorgular kisi basina degil ARALIK BASINA atilir: 30 gun x 20 personel icin
/// 600 sorgu yerine 4 sorgu.
async function buildTimesheet(userIds, from, to) {
  if (userIds.length === 0) return [];
  const ph = userIds.map(() => '?').join(',');

  const users = await queryAll(
    `SELECT u.id, u.full_name, u.role, u.store_id, s.name AS store_name
     FROM users u LEFT JOIN stores s ON s.id = u.store_id
     WHERE u.id IN (${ph}) ORDER BY u.full_name`, ...userIds);

  // Resmi tatiller: aralik basina tek sorgu, magaza bazinda haritalanir.
  // Tatil gunu planli sureyi dusuruyor; izin hesabinda dusuldugu icin
  // puantajda calisma gunu sayilmasi tutarsiz olurdu.
  const storeIds = [...new Set(users.map((u) => u.store_id).filter((v) => v != null))];
  const holidayRows = storeIds.length === 0
    ? []
    : await queryAll(`
        SELECT holiday_date, name, is_half_day, store_id FROM public_holidays
        WHERE holiday_date >= ? AND holiday_date <= ?
          AND (store_id IS NULL OR store_id IN (${storeIds.map(() => '?').join(',')}))`,
        from, to, ...storeIds);
  const holidaysByStore = new Map();
  for (const sid of storeIds) {
    holidaysByStore.set(sid, bal.holidayMap(
      holidayRows.filter((h) => h.store_id === null || Number(h.store_id) === Number(sid))
    ));
  }

  const assignments = await queryAll(`
    SELECT us.user_id, us.work_date, us.is_day_off,
           s.start_time, s.end_time, s.break_duration_minutes,
           s.late_tolerance_minutes, s.early_leave_tolerance_minutes,
           s.overtime_starts_after_minutes, s.name AS shift_name
    FROM user_shifts us LEFT JOIN shifts s ON s.id = us.shift_id
    WHERE us.user_id IN (${ph}) AND us.work_date >= ? AND us.work_date <= ?`,
    ...userIds, from, to);

  const logs = await queryAll(`
    SELECT user_id, work_date, type, method, occurred_at, is_valid_location
    FROM attendance_logs
    WHERE user_id IN (${ph}) AND work_date >= ? AND work_date <= ?
    ORDER BY occurred_at, id`, ...userIds, from, to);

  // Onayli gunluk izinler: araliga degen tum talepler.
  const leaves = await queryAll(`
    SELECT user_id, start_at, end_at FROM personnel_requests
    WHERE user_id IN (${ph}) AND type = 'IZIN' AND status = 'APPROVED'
      AND start_at <= ? AND end_at >= ?`, ...userIds, to, from);

  // Onayli saatlik izinler: gune gore dakika toplami.
  const hourly = await queryAll(`
    SELECT user_id, substr(start_at, 1, 10) AS d,
           COALESCE(SUM(hours), 0) * 60 AS minutes
    FROM personnel_requests
    WHERE user_id IN (${ph}) AND type = 'SAATLIK_IZIN' AND status = 'APPROVED'
      AND substr(start_at, 1, 10) >= ? AND substr(start_at, 1, 10) <= ?
    GROUP BY user_id, substr(start_at, 1, 10)`, ...userIds, from, to);

  const key = (u, d) => `${u}|${d}`;
  const byAssignment = new Map();
  for (const a of assignments) {
    const k = key(a.user_id, a.work_date);
    if (!byAssignment.has(k)) byAssignment.set(k, []);
    byAssignment.get(k).push({ ...a, is_day_off: !!a.is_day_off });
  }
  const byLog = new Map();
  for (const l of logs) {
    const k = key(l.user_id, l.work_date);
    if (!byLog.has(k)) byLog.set(k, []);
    byLog.get(k).push(l);
  }
  const byHourly = new Map();
  for (const h of hourly) byHourly.set(key(h.user_id, h.d), Number(h.minutes) || 0);

  const dates = dateRange(from, to);
  return users.map((u) => {
    const userLeaves = leaves.filter((l) => Number(l.user_id) === Number(u.id));
    const userHolidays = holidaysByStore.get(u.store_id) || {};
    const days = dates.map((date) => {
      const day = sheet.computeDay({
        workDate: date,
        shifts: byAssignment.get(key(u.id, date)) || [],
        logs: byLog.get(key(u.id, date)) || [],
        leaveDay: userLeaves.some((l) => date >= l.start_at && date <= l.end_at),
        hourlyLeaveMinutes: byHourly.get(key(u.id, date)) || 0,
        holiday: userHolidays[date] || null,
      });
      const names = (byAssignment.get(key(u.id, date)) || [])
        .map((a) => a.shift_name).filter(Boolean);
      return { ...day, shift_names: names };
    });
    return {
      user: {
        id: u.id, full_name: u.full_name, role: u.role,
        store_id: u.store_id, store_name: u.store_name,
      },
      days,
      summary: sheet.summarize(days),
    };
  });
}

/// Puantaj.
///
/// Personel yalnizca kendi puantajini gorur. Yonetici magazasinin tum
/// personelini gorur; userId ile tek kisiye daraltabilir.
router.get('/timesheet', async (req, res) => {
  const from = req.query.from;
  const to = req.query.to;
  if (!isDate(from) || !isDate(to)) {
    return res.status(400).json({ error: 'from ve to YYYY-AA-GG biçiminde olmalıdır' });
  }
  if (to < from) return res.status(400).json({ error: 'Bitiş tarihi başlangıçtan önce olamaz' });
  // 400 gunluk ust sinir: dateRange guard ile ayni; once anlasilir mesaj.
  if (dateRange(from, to).length > 366) {
    return res.status(400).json({ error: 'Aralık en fazla 1 yıl olabilir' });
  }

  const isManager = MANAGER_ROLES.includes(req.user.role);
  let userIds;

  if (!isManager) {
    userIds = [req.user.id];
  } else if (req.query.userId) {
    const id = Number(req.query.userId);
    const u = await queryOne('SELECT id, store_id FROM users WHERE id = ?', id);
    if (!u) return res.status(404).json({ error: 'Personel bulunamadı' });
    if (!allowsStore(req, u.store_id)) {
      return res.status(403).json({ error: 'Bu personele erişim yetkiniz yok' });
    }
    userIds = [id];
  } else {
    const scope = resolveStoreScope(req, res);
    if (!scope.ok) return undefined;
    const f = storeFilter(scope, 'store_id');
    const rows = await queryAll(
      `SELECT id FROM users WHERE active = 1 ${f.sql} ORDER BY full_name`, ...f.params);
    userIds = rows.map((r) => r.id);
    // Cok personel x uzun aralik cevabi sisirir; sinirlanir.
    if (userIds.length * dateRange(from, to).length > 6000) {
      return res.status(400).json({
        error: 'Aralık çok geniş. Daha kısa bir dönem seçin ya da tek personel filtreleyin.',
      });
    }
  }

  const items = await buildTimesheet(userIds, from, to);
  res.json({
    from, to, items,
    // Tum personelin toplami: aylik ozet tablosu icin.
    total: sheet.summarize(items.flatMap((i) => i.days)),
    notes: [
      'Mola, İş Kanunu m.68 asgarisi ile vardiyada tanımlı molanın küçüğü kadar düşülür.',
      'Geç kalma ve erken çıkış eksik sürenin parçasıdır, üstüne eklenmez.',
      'Vardiya atanmamış günlerin çalışması sınıflandırılmaz, ayrıca bildirilir.',
      'Resmi tatilde planlı süre sıfırdır; o gün çalışma tamamen fazla mesai sayılır.',
    ],
  });
});

/// Su an iste olanlar. Yonetici ekraninin "anlik durum" listesi.
router.get('/now', async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;
  const isManager = MANAGER_ROLES.includes(req.user.role);
  if (!isManager) return res.status(403).json({ error: 'Bu listeyi görme yetkiniz yok' });

  const f = storeFilter(scope, 'u.store_id');
  // Her personelin SON kaydi: giris ise iceride.
  const rows = await queryAll(`
    SELECT u.id, u.full_name, u.role, u.store_id, s.name AS store_name,
           l.type, l.method, l.occurred_at, l.work_date, l.distance_m, l.is_valid_location
    FROM users u
    LEFT JOIN stores s ON s.id = u.store_id
    LEFT JOIN LATERAL (
      SELECT type, method, occurred_at, work_date, distance_m, is_valid_location
      FROM attendance_logs al WHERE al.user_id = u.id
      ORDER BY al.occurred_at DESC, al.id DESC LIMIT 1
    ) l ON true
    WHERE u.active = 1 ${f.sql}
    ORDER BY u.full_name`, ...f.params);

  const today = t.localDate();
  const inside = [];
  const outside = [];
  for (const r of rows) {
    const item = {
      user_id: r.id, full_name: r.full_name, role: r.role,
      store_id: r.store_id, store_name: r.store_name,
      last_type: r.type, last_method: r.method, last_at: r.occurred_at,
      work_date: r.work_date, distance_m: r.distance_m,
      is_valid_location: r.is_valid_location,
      // Iceridekinin ne kadar suredir oldugu.
      minutes_since: r.occurred_at
        ? Math.round((Date.now() - new Date(r.occurred_at).getTime()) / 60000)
        : null,
    };
    if (r.type === 'GIRIS') inside.push(item); else outside.push(item);
  }

  res.json({
    as_of: new Date().toISOString(),
    work_date: today,
    inside_count: inside.length,
    inside,
    outside,
  });
});

module.exports = router;
