const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const {
  requireAuth, requireRole, resolveStoreScope, storeFilter, allowsStore, MANAGER_ROLES,
} = require('../auth');
const { logActivity } = require('../utils');
const bal = require('../pdks/balance');
const t = require('../pdks/time');

const router = express.Router();

router.use(requireAuth);

const requireManager = requireRole(...MANAGER_ROLES);
const TYPES = ['IZIN', 'SAATLIK_IZIN', 'AVANS'];

/// Bir tarih araligindaki resmi tatiller.
///
/// Magazaya ozel tatil genel takvimi gecersiz kilabilir; holidayMap bu onceligi
/// uyguluyor.
async function holidaysFor(storeId, from, to) {
  const rows = await queryAll(`
    SELECT holiday_date, name, is_half_day, store_id FROM public_holidays
    WHERE holiday_date >= ? AND holiday_date <= ?
      AND (store_id IS NULL OR store_id = ?)`, from, to, storeId);
  return bal.holidayMap(rows);
}

/// Personelin profili; kayit yoksa varsayilanlar.
async function profileOf(userId) {
  const p = await queryOne('SELECT * FROM pdks_profiles WHERE user_id = ?', userId);
  return {
    hired_at: p?.hired_at ?? null,
    annual_leave_days: p ? Number(p.annual_leave_days) : 14,
    monthly_advance_limit: p ? Number(p.monthly_advance_limit) : 0,
    weekly_off_days: bal.parseWeeklyOff(p?.weekly_off_days),
  };
}

/// Bakiye: hak, kullanilan, bekleyen, kalan.
///
/// BEKLEYEN talep de dusulur; aksi halde personel ust uste talep gonderip
/// hakkindan fazlasini onaya dusurebilir.
async function balancesOf(userId, atIso = new Date().toISOString()) {
  const profile = await profileOf(userId);
  const year = bal.leaveYearRange(profile.hired_at, atIso);
  const month = bal.monthRange(atIso);

  // Izin yili icinde kalan gunler. start_at araliga giren talepler sayilir.
  const leave = await queryOne(`
    SELECT
      COALESCE(SUM(CASE WHEN status='APPROVED' THEN days ELSE 0 END),0) AS used,
      COALESCE(SUM(CASE WHEN status='PENDING'  THEN days ELSE 0 END),0) AS pending
    FROM personnel_requests
    WHERE user_id = ? AND type = 'IZIN' AND status <> 'REJECTED' AND status <> 'CANCELLED'
      AND start_at >= ? AND start_at <= ?`, userId, year.from, year.to);

  const hourly = await queryOne(`
    SELECT
      COALESCE(SUM(CASE WHEN status='APPROVED' THEN hours ELSE 0 END),0) AS used,
      COALESCE(SUM(CASE WHEN status='PENDING'  THEN hours ELSE 0 END),0) AS pending
    FROM personnel_requests
    WHERE user_id = ? AND type = 'SAATLIK_IZIN' AND status IN ('APPROVED','PENDING')
      AND substr(start_at, 1, 10) >= ? AND substr(start_at, 1, 10) <= ?`,
    userId, month.from, month.to);

  const advance = await queryOne(`
    SELECT
      COALESCE(SUM(CASE WHEN status='APPROVED' THEN amount ELSE 0 END),0) AS used,
      COALESCE(SUM(CASE WHEN status='PENDING'  THEN amount ELSE 0 END),0) AS pending
    FROM personnel_requests
    WHERE user_id = ? AND type = 'AVANS' AND status IN ('APPROVED','PENDING')
      AND substr(created_at, 1, 10) >= ? AND substr(created_at, 1, 10) <= ?`,
    userId, month.from, month.to);

  const summary = bal.summarize({
    entitlementDays: profile.annual_leave_days,
    usedDays: Number(leave.used) || 0,
    pendingDays: Number(leave.pending) || 0,
    advanceLimit: profile.monthly_advance_limit,
    usedAdvance: Number(advance.used) || 0,
    pendingAdvance: Number(advance.pending) || 0,
    usedHours: Number(hourly.used) || 0,
    pendingHours: Number(hourly.pending) || 0,
  });
  return {
    ...summary,
    leave_year: year,
    month,
    weekly_off_days: profile.weekly_off_days,
    hired_at: profile.hired_at,
    notes: [
      'Yıllık izin hesabında hafta tatili ve resmi tatil günleri düşülür; '
        + 'arife gibi yarım tatiller 0,5 gün sayılır.',
      'Dini bayram tarihleri her yıl kaydığı için yöneticinin tatil '
        + 'takvimine eklemesi gerekir.',
    ],
  };
}

router.get('/requests/balances', async (req, res) => {
  const userId = req.query.userId ? Number(req.query.userId) : req.user.id;
  if (userId !== req.user.id) {
    if (!MANAGER_ROLES.includes(req.user.role)) {
      return res.status(403).json({ error: 'Başka personelin bakiyesini göremezsiniz' });
    }
    const u = await queryOne('SELECT store_id FROM users WHERE id = ?', userId);
    if (!u) return res.status(404).json({ error: 'Personel bulunamadı' });
    if (!allowsStore(req, u.store_id)) {
      return res.status(403).json({ error: 'Bu personele erişim yetkiniz yok' });
    }
  }
  res.json(await balancesOf(userId));
});

/// Talep listesi. Personel kendi taleplerini, yonetici magazasinin taleplerini.
router.get('/requests', async (req, res) => {
  const isManager = MANAGER_ROLES.includes(req.user.role);
  const params = [];
  let where = '1 = 1';

  if (!isManager) {
    where += ' AND r.user_id = ?';
    params.push(req.user.id);
  } else {
    const scope = resolveStoreScope(req, res);
    if (!scope.ok) return undefined;
    const f = storeFilter(scope, 'r.store_id');
    where += f.sql;
    params.push(...f.params);
    if (req.query.userId) { where += ' AND r.user_id = ?'; params.push(Number(req.query.userId)); }
  }
  if (req.query.status) {
    const st = String(req.query.status).toUpperCase();
    if (!['PENDING', 'APPROVED', 'REJECTED', 'CANCELLED'].includes(st)) {
      return res.status(400).json({ error: 'Geçersiz durum' });
    }
    where += ' AND r.status = ?';
    params.push(st);
  }
  if (req.query.type) {
    const ty = String(req.query.type).toUpperCase();
    if (!TYPES.includes(ty)) return res.status(400).json({ error: 'Geçersiz talep türü' });
    where += ' AND r.type = ?';
    params.push(ty);
  }

  const rows = await queryAll(`
    SELECT r.*, u.full_name, m.full_name AS manager_name, s.name AS store_name
    FROM personnel_requests r
    JOIN users u ON u.id = r.user_id
    LEFT JOIN users m ON m.id = r.manager_id
    LEFT JOIN stores s ON s.id = r.store_id
    WHERE ${where}
    ORDER BY CASE WHEN r.status = 'PENDING' THEN 0 ELSE 1 END, r.created_at DESC
    LIMIT 500`, ...params);
  res.json(rows);
});

/// Talep olustur.
router.post('/requests', async (req, res) => {
  const body = req.body || {};
  const type = String(body.type || '').toUpperCase();
  if (!TYPES.includes(type)) {
    return res.status(400).json({ error: 'Talep türü IZIN, SAATLIK_IZIN veya AVANS olmalıdır' });
  }
  const storeId = req.user.store_id;
  if (!storeId) return res.status(403).json({ error: 'Size mağaza atanmamış' });
  const reason = String(body.reason || '').trim();
  if (!reason) return res.status(400).json({ error: 'Gerekçe zorunludur' });
  if (reason.length > 500) return res.status(400).json({ error: 'Gerekçe en fazla 500 karakter' });

  const balances = await balancesOf(req.user.id);
  const profile = await profileOf(req.user.id);
  const fields = { start_at: null, end_at: null, days: null, hours: null, amount: null };

  if (type === 'AVANS') {
    const amount = Number(body.amount);
    if (!Number.isFinite(amount) || amount <= 0) {
      return res.status(400).json({ error: 'Avans tutarı 0’dan büyük olmalıdır' });
    }
    if (profile.monthly_advance_limit <= 0) {
      return res.status(400).json({ error: 'Size aylık avans limiti tanımlanmamış' });
    }
    if (amount > balances.advance.remaining) {
      return res.status(400).json({
        error: `Aylık avans limitiniz aşılıyor. Kalan: ${balances.advance.remaining} TL`,
      });
    }
    fields.amount = amount;
  } else if (type === 'IZIN') {
    const from = String(body.start_at || '');
    const to = String(body.end_at || '');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to)) {
      return res.status(400).json({ error: 'İzin tarihleri YYYY-AA-GG biçiminde olmalıdır' });
    }
    if (to < from) return res.status(400).json({ error: 'Bitiş tarihi başlangıçtan önce olamaz' });
    // Resmi tatil ve hafta tatili gunleri izin hakkindan dusulmez.
    const holidays = await holidaysFor(storeId, from, to);
    const days = bal.countLeaveDays(from, to, profile.weekly_off_days, holidays);
    if (days === null) return res.status(400).json({ error: 'Tarih aralığı geçersiz' });
    if (days === 0) {
      return res.status(400).json({
        error: 'Seçilen aralıkta çalışma günü yok (hepsi hafta tatili veya resmi tatil)',
      });
    }
    if (days > balances.leave.remaining_days) {
      return res.status(400).json({
        error: `${days} gün izin talep ettiniz, kalan hakkınız `
          + `${balances.leave.remaining_days} gün`,
      });
    }
    // Ayni gunlere ikinci talep: cift dusum ve cakisan plan olusur.
    const clash = await queryOne(`
      SELECT id, start_at, end_at, status FROM personnel_requests
      WHERE user_id = ? AND type = 'IZIN' AND status IN ('PENDING','APPROVED')
        AND start_at <= ? AND end_at >= ? LIMIT 1`, req.user.id, to, from);
    if (clash) {
      return res.status(400).json({
        error: `${clash.start_at} - ${clash.end_at} tarihlerinde zaten bir izin talebiniz var`,
      });
    }
    fields.start_at = from;
    fields.end_at = to;
    fields.days = days;
  } else {
    // SAATLIK_IZIN
    const from = String(body.start_at || '');
    const to = String(body.end_at || '');
    const hours = bal.countLeaveHours(from, to);
    if (hours === null) {
      return res.status(400).json({
        error: 'Saatlik izin geçerli bir aralık olmalı ve 12 saati geçmemelidir',
      });
    }
    if (t.localDate(from) !== t.localDate(to)) {
      return res.status(400).json({ error: 'Saatlik izin aynı gün içinde olmalıdır' });
    }
    const clash = await queryOne(`
      SELECT id FROM personnel_requests
      WHERE user_id = ? AND type = 'SAATLIK_IZIN' AND status IN ('PENDING','APPROVED')
        AND start_at < ? AND end_at > ? LIMIT 1`, req.user.id, to, from);
    if (clash) return res.status(400).json({ error: 'Bu saatlerde zaten bir talebiniz var' });
    fields.start_at = from;
    fields.end_at = to;
    fields.hours = hours;
  }

  const r = await execute(`
    INSERT INTO personnel_requests
      (user_id, store_id, type, start_at, end_at, days, hours, amount, reason)
    VALUES (?,?,?,?,?,?,?,?,?) RETURNING id`,
    req.user.id, storeId, type, fields.start_at, fields.end_at,
    fields.days, fields.hours, fields.amount, reason);

  await logActivity(req.user, 'TALEP_OLUSTUR', 'personnel_request', r.lastInsertRowid,
    `${type}: ` + (type === 'AVANS' ? `${fields.amount} TL`
      : type === 'IZIN' ? `${fields.start_at} - ${fields.end_at} (${fields.days} gün)`
      : `${fields.hours} saat`), storeId);

  res.status(201).json({ id: Number(r.lastInsertRowid), ...fields, type, status: 'PENDING' });
});

/// Onay / ret. Karar verilmis talep tekrar karara acilmaz.
async function decide(req, res, next) {
  const approve = next === 'APPROVED';
  const row = await queryOne('SELECT * FROM personnel_requests WHERE id = ?', Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Talep bulunamadı' });
  if (!allowsStore(req, row.store_id)) {
    return res.status(403).json({ error: 'Bu talebe erişim yetkiniz yok' });
  }
  if (row.status !== 'PENDING') {
    return res.status(400).json({
      error: row.status === 'APPROVED' ? 'Bu talep zaten onaylanmış'
        : row.status === 'REJECTED' ? 'Bu talep zaten reddedilmiş'
        : 'Bu talep iptal edilmiş',
    });
  }
  // Kendi talebini onaylamak yetki ayrimini anlamsiz kilar.
  if (Number(row.user_id) === Number(req.user.id)) {
    return res.status(400).json({ error: 'Kendi talebinizi onaylayamazsınız' });
  }

  const note = req.body && req.body.note !== undefined
    ? String(req.body.note).trim() || null : null;
  if (!approve && !note) return res.status(400).json({ error: 'Ret gerekçesi zorunludur' });

  // Talep olusturulduktan sonra hak degismis olabilir (yonetici izin gununu
  // dusurmus ya da baska talep onaylanmis olabilir). Onay aninda tekrar bakilir.
  if (approve) {
    const b = await balancesOf(row.user_id);
    if (row.type === 'IZIN') {
      // Bu talebin kendi bekleyen gunu zaten dusulmus; geri eklenip
      // karsilastirilir, aksi halde kendi kendini engeller.
      const available = b.leave.remaining_days + Number(row.days || 0);
      if (Number(row.days) > available) {
        return res.status(400).json({
          error: `Onaylanamaz: personelin kalan izin hakkı ${available} gün, `
            + `talep ${row.days} gün`,
        });
      }
    } else if (row.type === 'AVANS') {
      const available = b.advance.remaining + Number(row.amount || 0);
      if (Number(row.amount) > available) {
        return res.status(400).json({
          error: `Onaylanamaz: personelin kalan avans limiti ${available} TL, `
            + `talep ${row.amount} TL`,
        });
      }
    }
  }

  await execute(`
    UPDATE personnel_requests SET status=?, manager_id=?, decision_note=?,
      decided_at = to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    WHERE id = ?`, next, req.user.id, note, row.id);

  await logActivity(req.user, approve ? 'TALEP_ONAY' : 'TALEP_RET',
    'personnel_request', row.id,
    `${row.type} talebi ${approve ? 'onaylandı' : 'reddedildi'}`
    + (note ? ` (${note})` : ''), row.store_id);

  res.json({ ok: true, status: next, balances: await balancesOf(row.user_id) });
}

router.post('/requests/:id/approve', requireManager, (req, res) => decide(req, res, 'APPROVED'));
router.post('/requests/:id/reject', requireManager, (req, res) => decide(req, res, 'REJECTED'));

/// Personel bekleyen kendi talebini geri alabilir.
router.post('/requests/:id/cancel', async (req, res) => {
  const row = await queryOne('SELECT * FROM personnel_requests WHERE id = ?', Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Talep bulunamadı' });
  const isOwner = Number(row.user_id) === Number(req.user.id);
  if (!isOwner && !MANAGER_ROLES.includes(req.user.role)) {
    return res.status(403).json({ error: 'Yalnızca kendi talebinizi geri alabilirsiniz' });
  }
  if (!isOwner && !allowsStore(req, row.store_id)) {
    return res.status(403).json({ error: 'Bu talebe erişim yetkiniz yok' });
  }
  if (row.status !== 'PENDING') {
    return res.status(400).json({ error: 'Yalnızca bekleyen talep geri alınabilir' });
  }
  await execute("UPDATE personnel_requests SET status = 'CANCELLED' WHERE id = ?", row.id);
  await logActivity(req.user, 'TALEP_IPTAL', 'personnel_request', row.id,
    `${row.type} talebi geri alındı`, row.store_id);
  res.json({ ok: true });
});

module.exports = router;
module.exports.balancesOf = balancesOf;
